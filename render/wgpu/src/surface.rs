mod bounds;
mod commands;
pub mod target;

use crate::backend::RenderTargetMode;
use crate::blend::ComplexBlend;
use crate::buffer_pool::TexturePool;
use crate::dynamic_transforms::DynamicTransforms;
use crate::filters::FilterSource;
use crate::mesh::Mesh;
use crate::pixel_bender::{ShaderMode, run_pixelbender_shader_impl};
use crate::surface::bounds::{BlendRects, Touched};
use crate::surface::commands::{Chunk, CommandRenderer, chunk_blends};
use crate::surface::target::PoolOrArcTexture;
use crate::utils::run_copy_pipeline;
use crate::utils::supported_sample_count;
use crate::{Descriptors, MaskState, Pipelines};
use ruffle_render::commands::CommandList;
use ruffle_render::pixel_bender_support::{ImageInputTexture, PixelBenderShaderArgument};
use ruffle_render::quality::StageQuality;
use std::sync::Arc;
use target::CommandTarget;
use tracing::instrument;
use wgpu_profiler::Scope;

pub use crate::surface::commands::LayerRef;

use self::commands::ChunkBlendMode;

#[derive(Debug)]
pub struct Surface {
    size: wgpu::Extent3d,
    quality: StageQuality,
    sample_count: u32,
    pipelines: Arc<Pipelines>,
    format: wgpu::TextureFormat,
}

impl Surface {
    pub fn new(
        descriptors: &Descriptors,
        quality: StageQuality,
        width: u32,
        height: u32,
        frame_buffer_format: wgpu::TextureFormat,
    ) -> Self {
        let size = wgpu::Extent3d {
            width,
            height,
            depth_or_array_layers: 1,
        };

        let sample_count = supported_sample_count(
            &descriptors.adapter,
            quality.sample_count(),
            frame_buffer_format,
        );
        let pipelines = descriptors.pipelines(sample_count, frame_buffer_format);
        Self {
            size,
            quality,
            sample_count,
            pipelines,
            format: frame_buffer_format,
        }
    }

    #[expect(clippy::too_many_arguments)]
    #[instrument(level = "debug", skip_all)]
    pub fn draw_commands_and_copy_to<'encoder, 'global: 'encoder>(
        &self,
        frame_view: &wgpu::TextureView,
        render_target_mode: RenderTargetMode,
        descriptors: &'global Descriptors,
        staging_belt: &'global mut wgpu::util::StagingBelt,
        dynamic_transforms: &'global DynamicTransforms,
        draw_encoder: &'encoder mut Scope<'global, wgpu::CommandEncoder>,
        meshes: &'global Vec<Mesh>,
        commands: CommandList,
        layer: LayerRef<'encoder>,
        texture_pool: &'global mut TexturePool,
    ) {
        let target = self.draw_commands(
            render_target_mode,
            descriptors,
            meshes,
            commands,
            staging_belt,
            dynamic_transforms,
            draw_encoder,
            (0, 0),
            layer,
            texture_pool,
        );

        run_copy_pipeline(
            descriptors,
            self.format,
            frame_view,
            target.color_view(),
            target.globals(),
            1,
            draw_encoder,
        );
    }

    #[expect(clippy::too_many_arguments)]
    #[instrument(level = "debug", skip_all)]
    pub fn draw_commands<'encoder, 'global: 'encoder>(
        &self,
        render_target_mode: RenderTargetMode,
        descriptors: &'encoder Descriptors,
        meshes: &'encoder Vec<Mesh>,
        commands: CommandList,
        staging_belt: &'encoder mut wgpu::util::StagingBelt,
        dynamic_transforms: &'encoder DynamicTransforms,
        draw_encoder: &'encoder mut Scope<'global, wgpu::CommandEncoder>,
        origin: (i32, i32),
        nearest_layer: LayerRef<'encoder>,
        texture_pool: &'encoder mut TexturePool,
    ) -> CommandTarget {
        let target = CommandTarget::new(
            descriptors,
            texture_pool,
            self.size,
            self.format,
            self.sample_count,
            render_target_mode,
            draw_encoder,
        );

        let mut num_masks = 0;
        let mut mask_state = MaskState::NoMask;
        let chunks = chunk_blends(
            commands,
            descriptors,
            staging_belt,
            dynamic_transforms,
            draw_encoder,
            meshes,
            self.quality,
            target.width(),
            target.height(),
            origin,
            match nearest_layer {
                LayerRef::Current => LayerRef::Parent(&target),
                layer => layer,
            },
            texture_pool,
        );

        // Timffle: complex blends waiting to be composited (see below).
        let mut deferred: Vec<(PoolOrArcTexture, ComplexBlend, BlendRects)> = Vec::new();
        for chunk in chunks {
            match chunk {
                Chunk::Draw {
                    chunk,
                    needs_stencil,
                    transforms,
                    vertices,
                    touched,
                } => {
                    // Draws that overlap a waiting blend (or change the mask state
                    // it would be drawn under) must not get ahead of it.
                    let overlaps = needs_stencil
                        || match touched {
                            Touched::None => false,
                            Touched::All => true,
                            Touched::Rect(rect) => {
                                deferred.iter().any(|(_, _, r)| r.tight.intersects(&rect))
                            }
                        };
                    if overlaps {
                        self.flush_deferred(
                            &mut deferred,
                            &target,
                            descriptors,
                            texture_pool,
                            draw_encoder,
                            nearest_layer,
                            num_masks,
                            mask_state,
                        );
                    }
                    transforms.copy_to(staging_belt, draw_encoder, &dynamic_transforms.buffer);
                    vertices.copy_to(
                        staging_belt,
                        draw_encoder,
                        &dynamic_transforms.vertex_buffer,
                    );
                    let mut render_pass = draw_encoder.scoped_render_pass(
                        format!(
                            "Chunked draw calls {}",
                            if needs_stencil {
                                "(with stencil)"
                            } else {
                                "(Stencilless)"
                            }
                        ),
                        wgpu::RenderPassDescriptor {
                            // Timffle: no resolve here; see CommandTarget::ensure_resolved.
                            color_attachments: &[target.draw_attachments()],
                            depth_stencil_attachment: if needs_stencil {
                                target.stencil_attachment(descriptors, texture_pool)
                            } else {
                                None
                            },
                            ..Default::default()
                        },
                    );
                    target.mark_drawn(touched);
                    render_pass.set_bind_group(0, target.globals().bind_group(), &[]);
                    render_pass.set_bind_group(1, &dynamic_transforms.bind_group, &[]);
                    let mut renderer = CommandRenderer::new(
                        &self.pipelines,
                        descriptors,
                        &dynamic_transforms.vertex_buffer,
                        num_masks,
                        mask_state,
                        needs_stencil,
                    );

                    for command in &chunk {
                        renderer.execute(&mut render_pass.scope(command.name()), command);
                    }

                    num_masks = renderer.num_masks();
                    mask_state = renderer.mask_state();
                }
                Chunk::Blend {
                    texture,
                    blend_mode: ChunkBlendMode::Shader(shader),
                    needs_stencil,
                    rect,
                } => {
                    assert!(!needs_stencil, "Shader blend mode not implemented in masks");
                    assert!(
                        rect.is_none(),
                        "Shader blends always use a full-size surface"
                    );
                    self.flush_deferred(
                        &mut deferred,
                        &target,
                        descriptors,
                        texture_pool,
                        draw_encoder,
                        nearest_layer,
                        num_masks,
                        mask_state,
                    );
                    let parent_blend_buffer =
                        target.update_blend_buffer(descriptors, texture_pool, draw_encoder);
                    run_pixelbender_shader_impl(
                        descriptors,
                        shader,
                        ShaderMode::Filter,
                        &[
                            PixelBenderShaderArgument::ImageInput {
                                index: 0,
                                channels: 0xFF,
                                name: "background".to_string(),
                                texture: Some(ImageInputTexture::TextureRef(
                                    parent_blend_buffer.texture(),
                                )),
                            },
                            PixelBenderShaderArgument::ImageInput {
                                index: 1,
                                channels: 0xff,
                                name: "foreground".to_string(),
                                texture: Some(ImageInputTexture::TextureRef(texture.texture())),
                            },
                        ],
                        parent_blend_buffer.texture(),
                        draw_encoder,
                        target.color_attachments(),
                        target.sample_count(),
                        &FilterSource::for_entire_texture(texture.texture()),
                    )
                    .expect("Failed to run PixelBender blend mode");
                }
                Chunk::Blend {
                    texture,
                    blend_mode: ChunkBlendMode::Complex(blend_mode),
                    needs_stencil,
                    rect,
                } => {
                    // Timffle: a blend that reads only its own rectangle of this
                    // target, and no stencil, can wait until something overlaps
                    // it; neighbouring blends then share one resolve.
                    if let Some(rect) = rect
                        && !needs_stencil
                        && !matches!(blend_mode, ComplexBlend::Alpha | ComplexBlend::Erase)
                    {
                        deferred.push((texture, blend_mode, rect));
                        continue;
                    }
                    self.flush_deferred(
                        &mut deferred,
                        &target,
                        descriptors,
                        texture_pool,
                        draw_encoder,
                        nearest_layer,
                        num_masks,
                        mask_state,
                    );
                    self.draw_complex_blend(
                        &target,
                        descriptors,
                        texture_pool,
                        draw_encoder,
                        nearest_layer,
                        texture,
                        blend_mode,
                        needs_stencil,
                        rect,
                        num_masks,
                        mask_state,
                    );
                }
            }
        }
        self.flush_deferred(
            &mut deferred,
            &target,
            descriptors,
            texture_pool,
            draw_encoder,
            nearest_layer,
            num_masks,
            mask_state,
        );

        // If nothing happened, ensure it's cleared so we don't operate on garbage data,
        // and (Timffle) bring the resolve buffer up to date once, so that whoever
        // reads the target's color texture sees everything that was drawn.
        target.ensure_resolved(draw_encoder, None);

        target
    }

    /// Timffle: composites the blends that were waiting, in their original order.
    #[expect(clippy::too_many_arguments)]
    fn flush_deferred<'encoder, 'global: 'encoder>(
        &self,
        deferred: &mut Vec<(PoolOrArcTexture, ComplexBlend, BlendRects)>,
        target: &CommandTarget,
        descriptors: &'encoder Descriptors,
        texture_pool: &'encoder mut TexturePool,
        draw_encoder: &'encoder mut Scope<'global, wgpu::CommandEncoder>,
        nearest_layer: LayerRef<'encoder>,
        num_masks: u32,
        mask_state: MaskState,
    ) {
        for (texture, blend_mode, rect) in deferred.drain(..) {
            self.draw_complex_blend(
                target,
                descriptors,
                texture_pool,
                draw_encoder,
                nearest_layer,
                texture,
                blend_mode,
                false,
                Some(rect),
                num_masks,
                mask_state,
            );
        }
    }

    #[expect(clippy::too_many_arguments)]
    fn draw_complex_blend<'encoder, 'global: 'encoder>(
        &self,
        target: &CommandTarget,
        descriptors: &'encoder Descriptors,
        texture_pool: &'encoder mut TexturePool,
        draw_encoder: &'encoder mut Scope<'global, wgpu::CommandEncoder>,
        nearest_layer: LayerRef<'encoder>,
        texture: PoolOrArcTexture,
        blend_mode: ComplexBlend,
        needs_stencil: bool,
        rect: Option<BlendRects>,
        num_masks: u32,
        mask_state: MaskState,
    ) {
        let parent = match blend_mode {
            ComplexBlend::Alpha | ComplexBlend::Erase => {
                match nearest_layer {
                    LayerRef::None => {
                        // An Alpha or Erase with no Layer above it should be ignored
                        return;
                    }
                    LayerRef::Current => target,
                    LayerRef::Parent(layer) => layer,
                }
            }
            _ => target,
        };

        // Timffle: a blend surface smaller than the parent is paired with a
        // copy of just that part of the parent, and drawn with the viewport
        // set to that part, so the blend shaders stay unchanged. (Alpha and
        // Erase never get a smaller surface, so `parent` is `target` here.)
        let region_buffer;
        let parent_blend_view = if let Some(rect) = rect {
            region_buffer = parent.copy_region(
                descriptors,
                texture_pool,
                draw_encoder,
                rect.surface,
                rect.tight,
            );
            region_buffer.view()
        } else {
            parent
                .update_blend_buffer(descriptors, texture_pool, draw_encoder)
                .view()
        };

        let blend_bind_group = descriptors
            .device
            .create_bind_group(&wgpu::BindGroupDescriptor {
                label: create_debug_label!(
                    "Complex blend binds {:?} {}",
                    blend_mode,
                    if needs_stencil {
                        "(with stencil)"
                    } else {
                        "(Stencilless)"
                    }
                )
                .as_deref(),
                layout: &descriptors.bind_layouts.blend,
                entries: &[
                    wgpu::BindGroupEntry {
                        binding: 0,
                        resource: wgpu::BindingResource::TextureView(parent_blend_view),
                    },
                    wgpu::BindGroupEntry {
                        binding: 1,
                        resource: wgpu::BindingResource::TextureView(texture.view()),
                    },
                    wgpu::BindGroupEntry {
                        binding: 2,
                        resource: wgpu::BindingResource::Sampler(
                            descriptors.bitmap_samplers.get_sampler(false, false),
                        ),
                    },
                ],
            });

        let mut render_pass = draw_encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
            label: create_debug_label!(
                "Complex blend {:?} {}",
                blend_mode,
                if needs_stencil {
                    "(with stencil)"
                } else {
                    "(Stencilless)"
                }
            )
            .as_deref(),
            // Timffle: no resolve here; see CommandTarget::ensure_resolved.
            color_attachments: &[target.draw_attachments()],
            depth_stencil_attachment: if needs_stencil {
                target.stencil_attachment(descriptors, texture_pool)
            } else {
                None
            },
            ..Default::default()
        });
        target.mark_drawn(match rect {
            Some(rect) => Touched::Rect(rect.tight),
            None => Touched::All,
        });
        render_pass.set_bind_group(0, target.globals().bind_group(), &[]);
        if let Some(rect) = rect {
            render_pass.set_viewport(
                rect.surface.x as f32,
                rect.surface.y as f32,
                rect.surface.width as f32,
                rect.surface.height as f32,
                0.0,
                1.0,
            );
            // Only the pixels the blend can change are written; the rest of
            // the surface rectangle may hold stale parent pixels.
            render_pass.set_scissor_rect(
                rect.tight.x,
                rect.tight.y,
                rect.tight.width,
                rect.tight.height,
            );
        }

        if needs_stencil {
            match mask_state {
                MaskState::NoMask => {}
                MaskState::DrawMaskStencil => {
                    render_pass.set_stencil_reference(num_masks - 1);
                }
                MaskState::DrawMaskedContent => {
                    render_pass.set_stencil_reference(num_masks);
                }
                MaskState::ClearMaskStencil => {
                    render_pass.set_stencil_reference(num_masks);
                }
            }
            render_pass
                .set_pipeline(self.pipelines.complex_blends[blend_mode].pipeline_for(mask_state));
        } else {
            render_pass
                .set_pipeline(self.pipelines.complex_blends[blend_mode].stencilless_pipeline());
        }

        render_pass.set_bind_group(2, &blend_bind_group, &[]);

        render_pass.set_vertex_buffer(0, descriptors.quad.vertices_pos.slice(..));
        render_pass.set_index_buffer(
            descriptors.quad.indices.slice(..),
            wgpu::IndexFormat::Uint32,
        );

        render_pass.draw_indexed(0..6, 0, 0..1);
    }

    pub fn quality(&self) -> StageQuality {
        self.quality
    }

    pub fn sample_count(&self) -> u32 {
        self.sample_count
    }

    pub fn size(&self) -> wgpu::Extent3d {
        self.size
    }
}
