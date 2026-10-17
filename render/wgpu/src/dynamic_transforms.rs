use crate::descriptors::Descriptors;
use crate::{PosUvVertex, Transforms};
use std::mem;
use std::sync::atomic::{AtomicU64, Ordering};

const ESTIMATED_OBJECTS_PER_CHUNK: u64 = 200;

/// Vertex uniform vectors kept for everything but the transforms array
/// (globals, texture and gradient uniforms).
const RESERVED_VERTEX_UNIFORM_VECTORS: u64 = 64;

static MAX_VERTEX_UNIFORM_VECTORS: AtomicU64 = AtomicU64::new(u64::MAX);

/// Reports the device's `GL_MAX_VERTEX_UNIFORM_VECTORS` (timffle).
///
/// WebGL implementations can count the transforms uniform block against that
/// limit, and wgpu's limits do not include it: with the WebGL 2 minimum of 256
/// (the Android emulator, many phone GPUs) the full array fails pipeline
/// validation. Applies to backends created afterwards.
pub fn set_max_vertex_uniform_vectors(vectors: u64) {
    MAX_VERTEX_UNIFORM_VECTORS.store(vectors, Ordering::Relaxed);
}

pub struct DynamicTransforms {
    pub buffer: wgpu::Buffer,
    pub vertex_buffer: wgpu::Buffer,
    pub bind_group: wgpu::BindGroup,
}

pub fn transforms_per_draw(limits: &wgpu::Limits) -> u64 {
    let maximum = limits.max_uniform_buffer_binding_size / size_of::<Transforms>() as u64;
    let vectors_per_transform = size_of::<Transforms>() as u64 / 16;
    let by_vectors = MAX_VERTEX_UNIFORM_VECTORS
        .load(Ordering::Relaxed)
        .saturating_sub(RESERVED_VERTEX_UNIFORM_VECTORS)
        / vectors_per_transform;
    maximum
        .min(by_vectors)
        .clamp(1, ESTIMATED_OBJECTS_PER_CHUNK)
}

impl DynamicTransforms {
    pub fn new(descriptors: &Descriptors) -> Self {
        let buffer = descriptors.device.create_buffer(&wgpu::BufferDescriptor {
            label: None,
            size: transforms_per_draw(&descriptors.limits) * size_of::<Transforms>() as u64,
            usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });
        let vertex_buffer = descriptors.device.create_buffer(&wgpu::BufferDescriptor {
            label: None,
            size: (mem::size_of::<PosUvVertex>() as u64 * 4 * ESTIMATED_OBJECTS_PER_CHUNK)
                .min(descriptors.limits.max_buffer_size),
            usage: wgpu::BufferUsages::VERTEX | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });
        let bind_group = descriptors
            .device
            .create_bind_group(&wgpu::BindGroupDescriptor {
                label: None,
                layout: &descriptors.bind_layouts.transforms,
                entries: &[wgpu::BindGroupEntry {
                    binding: 0,
                    resource: buffer.as_entire_binding(),
                }],
            });
        Self {
            buffer,
            bind_group,
            vertex_buffer,
        }
    }
}
