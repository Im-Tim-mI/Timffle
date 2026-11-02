//! Timffle: `readback.wgsl` (the synchronous WebGPU readback) must encode a
//! texture's raw bytes exactly, three per pass, for every format the player
//! reads back: 8-bit unorm bitmaps and the 32-bit float PixelBender targets.
//!
//! The browser side (webgpu_readback.rs) only exists on wasm; this test runs
//! the same shader on a native adapter, renders each pass into an
//! `Rgba8Unorm` texture standing in for the opaque canvas, and reassembles
//! the bytes the way the wasm code does. Runs on whatever adapter wgpu finds
//! (`WGPU_BACKEND`, `VK_ICD_FILENAMES`); skips when there is none.

use ruffle_render_wgpu::descriptors::Descriptors;
use std::sync::Arc;

const SHADER: &str = include_str!("../shaders/readback.wgsl");
const BYTES_PER_PASS: u32 = 3;

#[repr(C)]
#[derive(Copy, Clone, bytemuck::Pod, bytemuck::Zeroable)]
struct Params {
    origin: [i32; 2],
    pass_index: u32,
    float_texels: u32,
}

fn descriptors() -> Option<Arc<Descriptors>> {
    let backends = std::env::var("WGPU_BACKEND")
        .ok()
        .and_then(|name| wgpu::Backends::from_comma_list(&name).into())
        .unwrap_or(wgpu::Backends::all());
    let instance = wgpu::Instance::new(wgpu::InstanceDescriptor {
        backends,
        ..wgpu::InstanceDescriptor::new_without_display_handle()
    });
    let adapter =
        futures::executor::block_on(instance.request_adapter(&wgpu::RequestAdapterOptions {
            power_preference: wgpu::PowerPreference::HighPerformance,
            compatible_surface: None,
            force_fallback_adapter: false,
            apply_limit_buckets: false,
        }))
        .ok()?;
    let (device, queue) =
        futures::executor::block_on(adapter.request_device(&wgpu::DeviceDescriptor {
            required_limits: wgpu::Limits::downlevel_defaults().using_resolution(adapter.limits()),
            ..Default::default()
        }))
        .ok()?;
    eprintln!("adapter: {:?}", adapter.get_info());
    Some(Arc::new(Descriptors::new(instance, adapter, device, queue)))
}

/// Deterministic pseudo-random bytes (xorshift), so every byte value and
/// every float bit pattern class (NaN, denormal, negative zero...) shows up.
fn noise(len: usize, seed: u32) -> Vec<u8> {
    let mut state = seed | 1;
    (0..len)
        .map(|_| {
            state ^= state << 13;
            state ^= state >> 17;
            state ^= state << 5;
            (state >> 8) as u8
        })
        .collect()
}

fn read_rgba8(descriptors: &Descriptors, texture: &wgpu::Texture) -> Vec<u8> {
    let width = texture.width();
    let height = texture.height();
    let bytes_per_row = (width * 4).div_ceil(256) * 256;
    let buffer = descriptors.device.create_buffer(&wgpu::BufferDescriptor {
        label: None,
        size: u64::from(bytes_per_row * height),
        usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
        mapped_at_creation: false,
    });
    let mut encoder = descriptors
        .device
        .create_command_encoder(&Default::default());
    encoder.copy_texture_to_buffer(
        texture.as_image_copy(),
        wgpu::TexelCopyBufferInfo {
            buffer: &buffer,
            layout: wgpu::TexelCopyBufferLayout {
                offset: 0,
                bytes_per_row: Some(bytes_per_row),
                rows_per_image: None,
            },
        },
        texture.size(),
    );
    descriptors.queue.submit([encoder.finish()]);
    let slice = buffer.slice(..);
    let (tx, rx) = std::sync::mpsc::channel();
    slice.map_async(wgpu::MapMode::Read, move |r| tx.send(r).unwrap());
    descriptors
        .device
        .poll(wgpu::PollType::wait_indefinitely())
        .unwrap();
    rx.recv().unwrap().unwrap();
    let data = slice.get_mapped_range().expect("mapped range");
    let mut out = Vec::with_capacity((width * height * 4) as usize);
    for y in 0..height {
        let row = &data[(y * bytes_per_row) as usize..];
        out.extend_from_slice(&row[..(width * 4) as usize]);
    }
    out
}

/// Uploads `bytes` as a `format` texture of the given size and reads
/// `region` (x, y, w, h) back through the readback shader.
fn round_trip(
    descriptors: &Descriptors,
    format: wgpu::TextureFormat,
    size: (u32, u32),
    bytes: &[u8],
    region: (u32, u32, u32, u32),
) -> Vec<u8> {
    let device = &descriptors.device;
    let bytes_per_texel = format.block_copy_size(None).unwrap();
    let float_texels = matches!(
        format,
        wgpu::TextureFormat::R32Float
            | wgpu::TextureFormat::Rg32Float
            | wgpu::TextureFormat::Rgba32Float
    );
    let source = device.create_texture(&wgpu::TextureDescriptor {
        label: None,
        size: wgpu::Extent3d {
            width: size.0,
            height: size.1,
            depth_or_array_layers: 1,
        },
        mip_level_count: 1,
        sample_count: 1,
        dimension: wgpu::TextureDimension::D2,
        format,
        usage: wgpu::TextureUsages::TEXTURE_BINDING | wgpu::TextureUsages::COPY_DST,
        view_formats: &[],
    });
    descriptors.queue.write_texture(
        source.as_image_copy(),
        bytes,
        wgpu::TexelCopyBufferLayout {
            offset: 0,
            bytes_per_row: Some(size.0 * bytes_per_texel),
            rows_per_image: None,
        },
        source.size(),
    );

    let bind_layout = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
        label: None,
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
    let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
        label: None,
        source: wgpu::ShaderSource::Wgsl(SHADER.into()),
    });
    let layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
        label: None,
        bind_group_layouts: &[Some(&bind_layout)],
        immediate_size: 0,
    });
    let pipeline = device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
        label: None,
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
                format: wgpu::TextureFormat::Rgba8Unorm,
                blend: Some(wgpu::BlendState::REPLACE),
                write_mask: Default::default(),
            })],
            compilation_options: Default::default(),
        }),
        primitive: Default::default(),
        depth_stencil: None,
        multisample: Default::default(),
        multiview_mask: None,
        cache: None,
    });

    let (x, y, width, height) = region;
    let canvas = device.create_texture(&wgpu::TextureDescriptor {
        label: None,
        size: wgpu::Extent3d {
            width,
            height,
            depth_or_array_layers: 1,
        },
        mip_level_count: 1,
        sample_count: 1,
        dimension: wgpu::TextureDimension::D2,
        format: wgpu::TextureFormat::Rgba8Unorm,
        usage: wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::COPY_SRC,
        view_formats: &[],
    });
    let canvas_view = canvas.create_view(&Default::default());
    let source_view = source.create_view(&Default::default());
    let uniforms = device.create_buffer(&wgpu::BufferDescriptor {
        label: None,
        size: size_of::<Params>() as u64,
        usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
        mapped_at_creation: false,
    });
    let bind_group = device.create_bind_group(&wgpu::BindGroupDescriptor {
        label: None,
        layout: &bind_layout,
        entries: &[
            wgpu::BindGroupEntry {
                binding: 0,
                resource: wgpu::BindingResource::TextureView(&source_view),
            },
            wgpu::BindGroupEntry {
                binding: 1,
                resource: uniforms.as_entire_binding(),
            },
        ],
    });

    let texel_count = (width * height) as usize;
    let mut out = vec![0u8; texel_count * bytes_per_texel as usize];
    for pass_index in 0..bytes_per_texel.div_ceil(BYTES_PER_PASS) {
        descriptors.queue.write_buffer(
            &uniforms,
            0,
            bytemuck::bytes_of(&Params {
                origin: [x as i32, y as i32],
                pass_index,
                float_texels: float_texels as u32,
            }),
        );
        let mut encoder = device.create_command_encoder(&Default::default());
        {
            let mut pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: None,
                color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                    view: &canvas_view,
                    resolve_target: None,
                    ops: wgpu::Operations {
                        load: wgpu::LoadOp::Clear(wgpu::Color::BLACK),
                        store: wgpu::StoreOp::Store,
                    },
                    depth_slice: None,
                })],
                ..Default::default()
            });
            pass.set_pipeline(&pipeline);
            pass.set_bind_group(0, &bind_group, &[]);
            pass.draw(0..3, 0..1);
        }
        descriptors.queue.submit([encoder.finish()]);
        let data = read_rgba8(descriptors, &canvas);
        // Like the browser: the canvas is opaque, only R, G and B carry data.
        let first_byte = (pass_index * BYTES_PER_PASS) as usize;
        let bytes_this_pass = (bytes_per_texel as usize - first_byte).min(BYTES_PER_PASS as usize);
        for texel in 0..texel_count {
            let dst = texel * bytes_per_texel as usize + first_byte;
            out[dst..dst + bytes_this_pass]
                .copy_from_slice(&data[texel * 4..texel * 4 + bytes_this_pass]);
        }
    }
    out
}

fn expected_region(
    bytes: &[u8],
    width: u32,
    bytes_per_texel: u32,
    region: (u32, u32, u32, u32),
) -> Vec<u8> {
    let (x, y, w, h) = region;
    let mut out = Vec::with_capacity((w * h * bytes_per_texel) as usize);
    for row in y..y + h {
        let start = ((row * width + x) * bytes_per_texel) as usize;
        out.extend_from_slice(&bytes[start..start + (w * bytes_per_texel) as usize]);
    }
    out
}

fn check(descriptors: &Descriptors, format: wgpu::TextureFormat, region: (u32, u32, u32, u32)) {
    let size = (37u32, 23u32);
    let bytes_per_texel = format.block_copy_size(None).unwrap();
    let mut bytes = noise((size.0 * size.1 * bytes_per_texel) as usize, 0x9e37_79b9);
    if bytes_per_texel > 4 || format == wgpu::TextureFormat::R32Float {
        // Keep every float normal and finite: a GPU may canonicalise NaN
        // payloads or flush denormals, which is not what is being tested.
        for word in bytes.as_chunks_mut::<4>().0 {
            word[3] = (word[3] & 0xBF) | 0x20;
        }
    }
    let actual = round_trip(descriptors, format, size, &bytes, region);
    let expected = expected_region(&bytes, size.0, bytes_per_texel, region);
    assert_eq!(
        actual.len(),
        expected.len(),
        "{format:?} {region:?}: length"
    );
    let wrong = actual.iter().zip(&expected).filter(|(a, e)| a != e).count();
    eprintln!(
        "{format:?} region {region:?}: {wrong} wrong bytes of {}",
        expected.len()
    );
    assert_eq!(wrong, 0, "{format:?} {region:?}: bytes differ");
}

#[test]
fn readback_shader_reproduces_the_bytes_of_every_supported_format() {
    let Some(descriptors) = descriptors() else {
        eprintln!("no adapter: skipped");
        return;
    };
    for format in [
        wgpu::TextureFormat::Rgba8Unorm,
        wgpu::TextureFormat::R32Float,
        wgpu::TextureFormat::Rg32Float,
        wgpu::TextureFormat::Rgba32Float,
    ] {
        // The whole texture, and a sub-rectangle with an odd origin.
        check(&descriptors, format, (0, 0, 37, 23));
        check(&descriptors, format, (5, 7, 19, 11));
    }
}
