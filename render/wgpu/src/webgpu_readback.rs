//! Timffle: synchronous GPU -> CPU readback on the browser's WebGPU backend.
//!
//! Flash content often draws to a `BitmapData` on the GPU and then reads the
//! pixels back on the CPU in the same frame (`getPixel`, `copyPixels`,
//! `hitTest`, `threshold`, ...). Ruffle does that with `map_async` + a
//! blocking wait, which never completes on the browser's main thread: WebGPU
//! only maps buffers asynchronously, so the tab hangs. WebGL2 has a
//! synchronous `readPixels`, which is why that path was fine.
//!
//! The browser does have one synchronous way to get GPU pixels: an
//! `OffscreenCanvas` driven by WebGPU can be snapshotted with
//! `transferToImageBitmap()`, and the bitmap drawn into a 2D canvas and read
//! with `getImageData()`. That gives 8-bit RGB with alpha forced to 1 (the
//! canvas is opaque), so `readback.wgsl` writes the texture's raw bytes three
//! per pass into the RGB channels, and this module reassembles them. The
//! result is bit-identical to a buffer readback: two passes for 8-bit
//! textures (RGB, then alpha), six for `Rgba32Float` (PixelBender output).
//!
//! Only used when `Descriptors::backend` is `BrowserWebGpu`; the WebGL and
//! native paths keep the buffer readback.

use crate::backend::ActiveFrame;
use crate::descriptors::Descriptors;
use ruffle_render::bitmap::PixelRegion;
use std::sync::Mutex;
use wasm_bindgen::{JsCast, JsValue};

/// Bytes of a texel each pass can carry (the R, G and B channels).
const BYTES_PER_PASS: u32 = 3;

struct PassCanvas {
    canvas: web_sys::OffscreenCanvas,
    surface: wgpu::Surface<'static>,
    uniforms: wgpu::Buffer,
    size: (u32, u32),
}

pub struct WebGpuReadback {
    canvas_format: wgpu::TextureFormat,
    bind_layout: wgpu::BindGroupLayout,
    pipeline: wgpu::RenderPipeline,
    passes: Vec<PassCanvas>,
    scratch: web_sys::OffscreenCanvas,
    scratch_context: web_sys::OffscreenCanvasRenderingContext2d,
    scratch_size: (u32, u32),
}

/// Marker for the `Descriptors` field; `WebGpuReadback` holds JS handles, which
/// is fine because wasm (without atomics) is single-threaded and the rest of
/// `Descriptors` is already not `Send` there.
#[derive(Default)]
pub struct WebGpuReadbackSlot(Mutex<Option<WebGpuReadback>>);

impl std::fmt::Debug for WebGpuReadbackSlot {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "WebGpuReadbackSlot")
    }
}

#[repr(C)]
#[derive(Copy, Clone, bytemuck::Pod, bytemuck::Zeroable)]
struct Params {
    origin: [i32; 2],
    pass_index: u32,
    float_texels: u32,
}

/// How a texture format's texels are turned into bytes by `readback.wgsl`:
/// the formats the player reads back (bitmaps, PixelBender targets).
fn texel_kind(format: wgpu::TextureFormat) -> Option<(u32, bool)> {
    use wgpu::TextureFormat::{R32Float, Rg32Float, Rgba8Unorm, Rgba32Float};
    let bytes_per_texel = format.block_copy_size(None)?;
    match format {
        Rgba8Unorm => Some((bytes_per_texel, false)),
        R32Float | Rg32Float | Rgba32Float => Some((bytes_per_texel, true)),
        _ => None,
    }
}

/// Reads `region` of `texture` synchronously. Returns the raw texel bytes,
/// `region.width() * bytes_per_texel` per row with no padding, together with
/// that row stride; `None` when the format is not supported or the browser
/// refused one of the canvas operations (the caller falls back to zeros rather
/// than hanging).
pub fn read_texture(
    descriptors: &Descriptors,
    frame: &mut ActiveFrame,
    texture: &wgpu::Texture,
    region: PixelRegion,
) -> Option<(Vec<u8>, u32)> {
    let (width, height) = (region.width(), region.height());
    if width == 0 || height == 0 {
        return Some((Vec::new(), 0));
    }
    let (bytes_per_texel, float_texels) = texel_kind(texture.format())?;
    let pass_count = bytes_per_texel.div_ceil(BYTES_PER_PASS);

    let mut slot = descriptors
        .webgpu_readback
        .0
        .lock()
        .expect("WebGPU readback must not be locked");
    if slot.is_none() {
        match WebGpuReadback::new(descriptors) {
            Ok(created) => *slot = Some(created),
            Err(error) => {
                log_js_error(error);
                return None;
            }
        }
    }
    let readback = slot.as_mut().expect("readback was just created");
    readback
        .read(
            descriptors,
            frame,
            texture,
            region,
            pass_count,
            bytes_per_texel,
            float_texels,
        )
        .map_err(log_js_error)
        .ok()
        .map(|bytes| (bytes, width * bytes_per_texel))
}

fn log_js_error(error: JsValue) {
    tracing::error!("WebGPU readback failed: {error:?}");
}

impl WebGpuReadback {
    fn new(descriptors: &Descriptors) -> Result<Self, JsValue> {
        let device = &descriptors.device;

        let bind_layout = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            label: create_debug_label!("Readback bind group layout").as_deref(),
            entries: &[
                wgpu::BindGroupLayoutEntry {
                    binding: 0,
                    visibility: wgpu::ShaderStages::FRAGMENT,
                    ty: wgpu::BindingType::Texture {
                        multisampled: false,
                        sample_type: wgpu::TextureSampleType::Float { filterable: false },
                        view_dimension: wgpu::TextureViewDimension::D2,
                    },
                    count: None,
                },
                wgpu::BindGroupLayoutEntry {
                    binding: 1,
                    visibility: wgpu::ShaderStages::FRAGMENT,
                    ty: wgpu::BindingType::Buffer {
                        ty: wgpu::BufferBindingType::Uniform,
                        has_dynamic_offset: false,
                        min_binding_size: wgpu::BufferSize::new(size_of::<Params>() as u64),
                    },
                    count: None,
                },
            ],
        });

        // The first canvas also tells us which canvas format the browser
        // prefers; every pass canvas uses the same one.
        let probe = web_sys::OffscreenCanvas::new(1, 1)?;
        let probe_surface = descriptors
            .wgpu_instance
            .create_surface(wgpu::SurfaceTarget::OffscreenCanvas(probe.clone()))
            .map_err(|e| JsValue::from_str(&e.to_string()))?;
        let capabilities = probe_surface.get_capabilities(&descriptors.adapter);
        let canvas_format = [
            wgpu::TextureFormat::Rgba8Unorm,
            wgpu::TextureFormat::Bgra8Unorm,
        ]
        .into_iter()
        .find(|f| capabilities.formats.contains(f))
        .ok_or_else(|| JsValue::from_str("no 8-bit canvas format"))?;

        let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: create_debug_label!("Shader readback.wgsl").as_deref(),
            source: wgpu::ShaderSource::Wgsl(include_str!("../shaders/readback.wgsl").into()),
        });
        let layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
            label: create_debug_label!("Readback pipeline layout").as_deref(),
            bind_group_layouts: &[Some(&bind_layout)],
            immediate_size: 0,
        });
        let pipeline = device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
            label: create_debug_label!("Readback pipeline").as_deref(),
            layout: Some(&layout),
            vertex: wgpu::VertexState {
                module: &shader,
                entry_point: Some("main_vertex"),
                buffers: &[],
                compilation_options: Default::default(),
            },
            fragment: Some(wgpu::FragmentState {
                module: &shader,
                entry_point: Some("main_fragment"),
                targets: &[Some(wgpu::ColorTargetState {
                    format: canvas_format,
                    blend: Some(wgpu::BlendState::REPLACE),
                    write_mask: Default::default(),
                })],
                compilation_options: Default::default(),
            }),
            primitive: wgpu::PrimitiveState {
                topology: wgpu::PrimitiveTopology::TriangleList,
                ..Default::default()
            },
            depth_stencil: None,
            multisample: wgpu::MultisampleState {
                count: 1,
                mask: !0,
                alpha_to_coverage_enabled: false,
            },
            multiview_mask: None,
            cache: None,
        });

        let scratch = web_sys::OffscreenCanvas::new(1, 1)?;
        let options = js_sys::Object::new();
        js_sys::Reflect::set(&options, &"willReadFrequently".into(), &true.into())?;
        let scratch_context = scratch
            .get_context_with_context_options("2d", &options)?
            .ok_or_else(|| JsValue::from_str("no 2d context"))?
            .dyn_into::<web_sys::OffscreenCanvasRenderingContext2d>()?;

        let mut readback = Self {
            canvas_format,
            bind_layout,
            pipeline,
            passes: Vec::new(),
            scratch,
            scratch_context,
            scratch_size: (1, 1),
        };
        readback.passes.push(PassCanvas {
            canvas: probe,
            surface: probe_surface,
            uniforms: readback.make_uniforms(device),
            size: (0, 0),
        });
        Ok(readback)
    }

    fn make_uniforms(&self, device: &wgpu::Device) -> wgpu::Buffer {
        device.create_buffer(&wgpu::BufferDescriptor {
            label: create_debug_label!("Readback params").as_deref(),
            size: size_of::<Params>() as u64,
            usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        })
    }

    fn ensure_passes(&mut self, descriptors: &Descriptors, count: usize) -> Result<(), JsValue> {
        while self.passes.len() < count {
            let canvas = web_sys::OffscreenCanvas::new(1, 1)?;
            let surface = descriptors
                .wgpu_instance
                .create_surface(wgpu::SurfaceTarget::OffscreenCanvas(canvas.clone()))
                .map_err(|e| JsValue::from_str(&e.to_string()))?;
            self.passes.push(PassCanvas {
                canvas,
                surface,
                uniforms: self.make_uniforms(&descriptors.device),
                size: (0, 0),
            });
        }
        Ok(())
    }

    #[expect(clippy::too_many_arguments)]
    fn read(
        &mut self,
        descriptors: &Descriptors,
        frame: &mut ActiveFrame,
        texture: &wgpu::Texture,
        region: PixelRegion,
        pass_count: u32,
        bytes_per_texel: u32,
        float_texels: bool,
    ) -> Result<Vec<u8>, JsValue> {
        let (width, height) = (region.width(), region.height());
        self.ensure_passes(descriptors, pass_count as usize)?;

        let source_view = texture.create_view(&Default::default());
        let mut frames = Vec::with_capacity(pass_count as usize);
        for pass_index in 0..pass_count {
            let pass = &mut self.passes[pass_index as usize];
            if pass.size != (width, height) {
                pass.surface.configure(
                    &descriptors.device,
                    &wgpu::SurfaceConfiguration {
                        usage: wgpu::TextureUsages::RENDER_ATTACHMENT,
                        format: self.canvas_format,
                        color_space: Default::default(),
                        width,
                        height,
                        present_mode: wgpu::PresentMode::Fifo,
                        desired_maximum_frame_latency: 1,
                        alpha_mode: wgpu::CompositeAlphaMode::Opaque,
                        view_formats: vec![],
                    },
                );
                pass.size = (width, height);
            }
            descriptors.queue.write_buffer(
                &pass.uniforms,
                0,
                bytemuck::bytes_of(&Params {
                    origin: [region.x_min as i32, region.y_min as i32],
                    pass_index,
                    float_texels: float_texels as u32,
                }),
            );
            let bind_group = descriptors
                .device
                .create_bind_group(&wgpu::BindGroupDescriptor {
                    label: create_debug_label!("Readback bind group").as_deref(),
                    layout: &self.bind_layout,
                    entries: &[
                        wgpu::BindGroupEntry {
                            binding: 0,
                            resource: wgpu::BindingResource::TextureView(&source_view),
                        },
                        wgpu::BindGroupEntry {
                            binding: 1,
                            resource: pass.uniforms.as_entire_binding(),
                        },
                    ],
                });
            let surface_texture = match pass.surface.get_current_texture() {
                wgpu::CurrentSurfaceTexture::Success(texture)
                | wgpu::CurrentSurfaceTexture::Suboptimal(texture) => texture,
                state => {
                    return Err(JsValue::from_str(&format!(
                        "could not acquire the readback canvas: {state:?}"
                    )));
                }
            };
            let view = surface_texture.texture.create_view(&Default::default());
            {
                let mut render_pass =
                    frame
                        .command_encoder
                        .begin_render_pass(&wgpu::RenderPassDescriptor {
                            label: create_debug_label!("Readback pass").as_deref(),
                            color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                                view: &view,
                                resolve_target: None,
                                ops: wgpu::Operations {
                                    load: wgpu::LoadOp::Clear(wgpu::Color::BLACK),
                                    store: wgpu::StoreOp::Store,
                                },
                                depth_slice: None,
                            })],
                            depth_stencil_attachment: None,
                            timestamp_writes: None,
                            occlusion_query_set: None,
                            multiview_mask: None,
                        });
                render_pass.set_pipeline(&self.pipeline);
                render_pass.set_bind_group(0, &bind_group, &[]);
                render_pass.draw(0..3, 0..1);
            }
            frames.push(surface_texture);
        }

        // Everything queued so far (including the draws that produced the
        // texture) runs before the canvases are snapshotted below.
        frame.submit_direct(descriptors);
        for surface_texture in frames {
            descriptors.queue.present(surface_texture);
        }

        if self.scratch_size != (width, height) {
            self.scratch.set_width(width);
            self.scratch.set_height(height);
            self.scratch_size = (width, height);
        }

        let texel_count = (width * height) as usize;
        let mut out = vec![0u8; texel_count * bytes_per_texel as usize];
        for pass_index in 0..pass_count {
            let pass = &self.passes[pass_index as usize];
            let bitmap = pass.canvas.transfer_to_image_bitmap()?;
            let drawn = self
                .scratch_context
                .draw_image_with_image_bitmap(&bitmap, 0.0, 0.0);
            bitmap.close();
            drawn?;
            let data = self
                .scratch_context
                .get_image_data(0, 0, width as i32, height as i32)?
                .data()
                .0;
            if data.len() < texel_count * 4 {
                return Err(JsValue::from_str("getImageData returned too few bytes"));
            }
            let first_byte = (pass_index * BYTES_PER_PASS) as usize;
            let bytes_this_pass =
                (bytes_per_texel as usize - first_byte).min(BYTES_PER_PASS as usize);
            for texel in 0..texel_count {
                let src = &data[texel * 4..texel * 4 + bytes_this_pass];
                let dst_start = texel * bytes_per_texel as usize + first_byte;
                out[dst_start..dst_start + bytes_this_pass].copy_from_slice(src);
            }
        }
        Ok(out)
    }
}
