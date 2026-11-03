//! Timffle: the sub-rectangle resolve (`resolve.wgsl`) must give the same
//! pixels as the GPU's own multisample resolve, and must not touch anything
//! outside the rectangle it was asked for.
//!
//! Runs on whatever adapter wgpu finds (set `WGPU_BACKEND`, and e.g.
//! `VK_ICD_FILENAMES` for lavapipe or a real GPU); skips when there is none.

use ruffle_render_wgpu::descriptors::Descriptors;
use std::sync::Arc;

const WIDTH: u32 = 64;
const HEIGHT: u32 = 48;
const SAMPLES: u32 = 4;
const FORMAT: wgpu::TextureFormat = wgpu::TextureFormat::Rgba8Unorm;

/// Draws two overlapping triangles with a gradient, so that edge pixels have
/// samples of different colours.
const CONTENT_SHADER: &str = r#"
struct Out { @builtin(position) pos: vec4<f32>, @location(0) col: vec4<f32> };
@vertex
fn vs(@builtin(vertex_index) i: u32) -> Out {
    var p = array<vec2<f32>, 6>(
        vec2(-0.9, -0.8), vec2(0.7, -0.6), vec2(-0.3, 0.9),
        vec2(-0.5, 0.2), vec2(0.95, 0.1), vec2(0.4, -0.95),
    );
    var c = array<vec4<f32>, 6>(
        vec4(1.0, 0.0, 0.0, 1.0), vec4(0.0, 1.0, 0.0, 1.0), vec4(0.0, 0.0, 1.0, 1.0),
        vec4(1.0, 1.0, 0.0, 0.5), vec4(0.0, 1.0, 1.0, 0.5), vec4(1.0, 0.0, 1.0, 0.5),
    );
    return Out(vec4(p[i], 0.0, 1.0), c[i]);
}
@fragment
fn fs(in: Out) -> @location(0) vec4<f32> { return in.col; }
"#;

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
    if adapter.get_info().backend == wgpu::Backend::Gl {
        // Multisampled textures cannot be sampled on GL; the player keeps the
        // whole-texture resolve there.
        eprintln!("GL adapter: nothing to test");
        return None;
    }
    let (device, queue) =
        futures::executor::block_on(adapter.request_device(&wgpu::DeviceDescriptor {
            required_limits: wgpu::Limits::downlevel_defaults().using_resolution(adapter.limits()),
            ..Default::default()
        }))
        .ok()?;
    eprintln!("adapter: {:?}", adapter.get_info());
    Some(Arc::new(Descriptors::new(instance, adapter, device, queue)))
}

fn texture(device: &wgpu::Device, samples: u32, usage: wgpu::TextureUsages) -> wgpu::Texture {
    device.create_texture(&wgpu::TextureDescriptor {
        label: None,
        size: wgpu::Extent3d {
            width: WIDTH,
            height: HEIGHT,
            depth_or_array_layers: 1,
        },
        mip_level_count: 1,
        sample_count: samples,
        dimension: wgpu::TextureDimension::D2,
        format: FORMAT,
        usage,
        view_formats: &[],
    })
}

fn read_back(descriptors: &Descriptors, texture: &wgpu::Texture) -> Vec<[u8; 4]> {
    let bytes_per_row = (WIDTH * 4).div_ceil(256) * 256;
    let buffer = descriptors.device.create_buffer(&wgpu::BufferDescriptor {
        label: None,
        size: u64::from(bytes_per_row * HEIGHT),
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
    let mut out = Vec::with_capacity((WIDTH * HEIGHT) as usize);
    for y in 0..HEIGHT {
        let row = &data[(y * bytes_per_row) as usize..];
        for x in 0..WIDTH {
            let i = (x * 4) as usize;
            out.push([row[i], row[i + 1], row[i + 2], row[i + 3]]);
        }
    }
    out
}

/// Draws the content into the multisampled texture; with `resolve` the GPU
/// resolves it into that texture at the end of the pass.
fn draw_content(
    descriptors: &Descriptors,
    msaa: &wgpu::TextureView,
    resolve: Option<&wgpu::TextureView>,
) {
    let shader = descriptors
        .device
        .create_shader_module(wgpu::ShaderModuleDescriptor {
            label: None,
            source: wgpu::ShaderSource::Wgsl(CONTENT_SHADER.into()),
        });
    let pipeline = descriptors
        .device
        .create_render_pipeline(&wgpu::RenderPipelineDescriptor {
            label: None,
            layout: None,
            vertex: wgpu::VertexState {
                module: &shader,
                entry_point: Some("vs"),
                buffers: &[],
                compilation_options: Default::default(),
            },
            fragment: Some(wgpu::FragmentState {
                module: &shader,
                entry_point: Some("fs"),
                targets: &[Some(wgpu::ColorTargetState {
                    format: FORMAT,
                    blend: Some(wgpu::BlendState::ALPHA_BLENDING),
                    write_mask: Default::default(),
                })],
                compilation_options: Default::default(),
            }),
            primitive: Default::default(),
            depth_stencil: None,
            multisample: wgpu::MultisampleState {
                count: SAMPLES,
                mask: !0,
                alpha_to_coverage_enabled: false,
            },
            multiview_mask: None,
            cache: None,
        });
    let mut encoder = descriptors
        .device
        .create_command_encoder(&Default::default());
    {
        let mut pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
            label: None,
            color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                view: msaa,
                resolve_target: resolve,
                ops: wgpu::Operations {
                    load: wgpu::LoadOp::Clear(wgpu::Color {
                        r: 0.2,
                        g: 0.3,
                        b: 0.4,
                        a: 1.0,
                    }),
                    store: wgpu::StoreOp::Store,
                },
                depth_slice: None,
            })],
            ..Default::default()
        });
        pass.set_pipeline(&pipeline);
        pass.draw(0..6, 0..1);
    }
    descriptors.queue.submit([encoder.finish()]);
}

fn shader_resolve(
    descriptors: &Descriptors,
    msaa: &wgpu::TextureView,
    target: &wgpu::TextureView,
    scissor: (u32, u32, u32, u32),
) {
    shader_resolve_rects(descriptors, msaa, target, &[scissor]);
}

/// One render pass, one scissored draw per rectangle (what the player does for
/// a group of blends that wait together).
fn shader_resolve_rects(
    descriptors: &Descriptors,
    msaa: &wgpu::TextureView,
    target: &wgpu::TextureView,
    scissors: &[(u32, u32, u32, u32)],
) {
    let bind_group = descriptors
        .device
        .create_bind_group(&wgpu::BindGroupDescriptor {
            label: None,
            layout: &descriptors.bind_layouts.resolve,
            entries: &[wgpu::BindGroupEntry {
                binding: 0,
                resource: wgpu::BindingResource::TextureView(msaa),
            }],
        });
    let pipeline = descriptors.resolve_pipeline(FORMAT, SAMPLES);
    let mut encoder = descriptors
        .device
        .create_command_encoder(&Default::default());
    {
        let mut pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
            label: None,
            color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                view: target,
                resolve_target: None,
                ops: wgpu::Operations {
                    load: wgpu::LoadOp::Load,
                    store: wgpu::StoreOp::Store,
                },
                depth_slice: None,
            })],
            ..Default::default()
        });
        pass.set_pipeline(&pipeline);
        pass.set_bind_group(0, &bind_group, &[]);
        for scissor in scissors {
            pass.set_scissor_rect(scissor.0, scissor.1, scissor.2, scissor.3);
            pass.draw(0..3, 0..1);
        }
    }
    descriptors.queue.submit([encoder.finish()]);
}

#[test]
fn shader_resolve_of_several_rectangles_in_one_pass() {
    let Some(descriptors) = descriptors() else {
        return;
    };
    let msaa = texture(
        &descriptors.device,
        SAMPLES,
        wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::TEXTURE_BINDING,
    );
    let hardware = texture(
        &descriptors.device,
        1,
        wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::COPY_SRC,
    );
    let shader = texture(
        &descriptors.device,
        1,
        wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::COPY_SRC,
    );
    let msaa_view = msaa.create_view(&Default::default());
    let shader_view = shader.create_view(&Default::default());
    draw_content(
        &descriptors,
        &msaa_view,
        Some(&hardware.create_view(&Default::default())),
    );
    let sentinel = wgpu::Color {
        r: 0.0,
        g: 1.0,
        b: 0.0,
        a: 1.0,
    };
    clear(&descriptors, &shader_view, sentinel);
    let rects = [(3u32, 4u32, 12u32, 9u32), (30, 2, 20, 15), (8, 30, 50, 10)];
    shader_resolve_rects(&descriptors, &msaa_view, &shader_view, &rects);
    let expected = read_back(&descriptors, &hardware);
    let actual = read_back(&descriptors, &shader);
    let mut max_diff = 0u8;
    for y in 0..HEIGHT {
        for x in 0..WIDTH {
            let i = (y * WIDTH + x) as usize;
            let inside = rects
                .iter()
                .any(|r| x >= r.0 && x < r.0 + r.2 && y >= r.1 && y < r.1 + r.3);
            if inside {
                for c in 0..4 {
                    max_diff = max_diff.max(expected[i][c].abs_diff(actual[i][c]));
                }
            } else {
                assert_eq!(
                    actual[i],
                    [0u8, 255, 0, 255],
                    "pixel ({x},{y}) outside every rectangle was written"
                );
            }
        }
    }
    assert!(max_diff <= 1, "max channel diff {max_diff}");
}

fn clear(descriptors: &Descriptors, view: &wgpu::TextureView, color: wgpu::Color) {
    let mut encoder = descriptors
        .device
        .create_command_encoder(&Default::default());
    encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
        label: None,
        color_attachments: &[Some(wgpu::RenderPassColorAttachment {
            view,
            resolve_target: None,
            ops: wgpu::Operations {
                load: wgpu::LoadOp::Clear(color),
                store: wgpu::StoreOp::Store,
            },
            depth_slice: None,
        })],
        ..Default::default()
    });
    descriptors.queue.submit([encoder.finish()]);
}

#[test]
fn shader_resolve_matches_hardware_resolve_inside_the_rectangle_only() {
    let Some(descriptors) = descriptors() else {
        eprintln!("no adapter: skipped");
        return;
    };
    let msaa = texture(
        &descriptors.device,
        SAMPLES,
        wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::TEXTURE_BINDING,
    );
    let hardware = texture(
        &descriptors.device,
        1,
        wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::COPY_SRC,
    );
    let shader = texture(
        &descriptors.device,
        1,
        wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::COPY_SRC,
    );
    let msaa_view = msaa.create_view(&Default::default());
    let hardware_view = hardware.create_view(&Default::default());
    let shader_view = shader.create_view(&Default::default());

    draw_content(&descriptors, &msaa_view, Some(&hardware_view));
    // Exactly representable, so the clear colour cannot round differently
    // between drivers.
    let sentinel = wgpu::Color {
        r: 0.0,
        g: 1.0,
        b: 0.0,
        a: 1.0,
    };
    clear(&descriptors, &shader_view, sentinel);
    let rect = (10u32, 5u32, 30u32, 20u32);
    shader_resolve(&descriptors, &msaa_view, &shader_view, rect);

    let expected = read_back(&descriptors, &hardware);
    let actual = read_back(&descriptors, &shader);
    let sentinel_px = [0u8, 255, 0, 255];
    let mut max_diff = 0u8;
    let mut edge_pixels = 0;
    for y in 0..HEIGHT {
        for x in 0..WIDTH {
            let i = (y * WIDTH + x) as usize;
            let inside = x >= rect.0 && x < rect.0 + rect.2 && y >= rect.1 && y < rect.1 + rect.3;
            if inside {
                for c in 0..4 {
                    max_diff = max_diff.max(expected[i][c].abs_diff(actual[i][c]));
                }
                if expected[i] != actual[i] {
                    edge_pixels += 1;
                }
            } else {
                assert_eq!(
                    actual[i], sentinel_px,
                    "pixel ({x},{y}) outside the rectangle was written"
                );
            }
        }
    }
    // The content really has mixed samples somewhere inside the rectangle.
    let distinct: std::collections::HashSet<[u8; 4]> = (rect.1..rect.1 + rect.3)
        .flat_map(|y| (rect.0..rect.0 + rect.2).map(move |x| (y * WIDTH + x) as usize))
        .map(|i| expected[i])
        .collect();
    assert!(
        distinct.len() > 8,
        "test content is not varied enough: {distinct:?}"
    );
    eprintln!(
        "pixels differing from the hardware resolve: {edge_pixels}, max channel diff {max_diff}"
    );
    // Averaging order may round differently from the hardware by one step.
    assert!(
        max_diff <= 1,
        "shader resolve differs from the hardware resolve by {max_diff}"
    );
}

#[test]
fn shader_resolve_of_everything_matches_hardware_resolve() {
    let Some(descriptors) = descriptors() else {
        return;
    };
    let msaa = texture(
        &descriptors.device,
        SAMPLES,
        wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::TEXTURE_BINDING,
    );
    let hardware = texture(
        &descriptors.device,
        1,
        wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::COPY_SRC,
    );
    let shader = texture(
        &descriptors.device,
        1,
        wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::COPY_SRC,
    );
    let msaa_view = msaa.create_view(&Default::default());
    draw_content(
        &descriptors,
        &msaa_view,
        Some(&hardware.create_view(&Default::default())),
    );
    shader_resolve(
        &descriptors,
        &msaa_view,
        &shader.create_view(&Default::default()),
        (0, 0, WIDTH, HEIGHT),
    );
    let expected = read_back(&descriptors, &hardware);
    let actual = read_back(&descriptors, &shader);
    let max_diff = expected
        .iter()
        .zip(&actual)
        .flat_map(|(e, a)| e.iter().zip(a).map(|(e, a)| e.abs_diff(*a)))
        .max()
        .unwrap();
    assert!(max_diff <= 1, "max channel diff {max_diff}");
}
