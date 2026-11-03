use crate::backend::RenderTargetMode;
use crate::buffer_pool::{AlwaysCompatible, PoolEntry, TexturePool};
use crate::descriptors::Descriptors;
use crate::globals::Globals;
use crate::surface::bounds::{SurfaceRect, Touched};
use crate::utils::run_copy_pipeline;
use std::cell::{OnceCell, RefCell};
use std::sync::Arc;

/// Timffle: which pixels of the multisampled frame buffer have been drawn
/// since the resolve buffer was last brought up to date.
///
/// Upstream resolves the whole multisampled frame buffer at the end of every
/// render pass. A frame with hundreds of blended objects therefore resolves the
/// whole stage hundreds of times, although each blend only needs the parent's
/// pixels under its own rectangle. Passes started through `draw_attachments`
/// do not resolve; the resolve happens on demand, only when something reads a
/// part of the resolve buffer that is out of date, and once at the end.
#[derive(Debug)]
enum Dirty {
    Clean,
    Rects(Vec<SurfaceRect>),
    All,
}

/// More dirty rectangles than this are folded into `Dirty::All`.
const MAX_DIRTY_RECTS: usize = 64;

impl Dirty {
    fn mark(&mut self, touched: Touched) {
        match touched {
            Touched::None => {}
            Touched::All => *self = Dirty::All,
            Touched::Rect(rect) => match self {
                Dirty::Clean => *self = Dirty::Rects(vec![rect]),
                Dirty::Rects(rects) => {
                    if rects.len() >= MAX_DIRTY_RECTS {
                        *self = Dirty::All;
                    } else {
                        rects.push(rect);
                    }
                }
                Dirty::All => {}
            },
        }
    }

    fn needs_resolve(&self, rect: Option<SurfaceRect>) -> bool {
        match (self, rect) {
            (Dirty::Clean, _) => false,
            (Dirty::All, _) => true,
            (Dirty::Rects(_), None) => true,
            (Dirty::Rects(rects), Some(rect)) => rects.iter().any(|r| r.intersects(&rect)),
        }
    }

    /// Records that `resolved` were resolved: dirty rectangles that lie
    /// completely inside one of them are clean again. (A rectangle that only
    /// partly overlaps stays dirty; resolving its pixels again is harmless.)
    fn resolved(&mut self, resolved: &[SurfaceRect]) {
        if let Dirty::Rects(rects) = self {
            rects.retain(|dirty| !resolved.iter().any(|r| r.contains(dirty)));
            if rects.is_empty() {
                *self = Dirty::Clean;
            }
        }
    }
}

#[derive(Debug)]
pub struct ResolveBuffer {
    texture: PoolOrArcTexture,
}

impl ResolveBuffer {
    pub fn new(
        descriptors: &Descriptors,
        size: wgpu::Extent3d,
        format: wgpu::TextureFormat,
        usage: wgpu::TextureUsages,
        pool: &mut TexturePool,
    ) -> Self {
        let texture = pool.get_texture(descriptors, size, usage, format, 1);
        Self {
            texture: PoolOrArcTexture::Pool(texture),
        }
    }

    pub fn new_manual(texture: wgpu::Texture) -> Self {
        Self {
            texture: PoolOrArcTexture::Manual((
                texture.clone(),
                texture.create_view(&Default::default()),
            )),
        }
    }

    pub fn view(&self) -> &wgpu::TextureView {
        match self.texture {
            PoolOrArcTexture::Pool(ref texture) => &texture.1,
            PoolOrArcTexture::Manual(ref texture) => &texture.1,
        }
    }

    pub fn texture(&self) -> &wgpu::Texture {
        match self.texture {
            PoolOrArcTexture::Pool(ref texture) => &texture.0,
            PoolOrArcTexture::Manual(ref texture) => &texture.0,
        }
    }

    pub fn take_texture(self) -> PoolOrArcTexture {
        self.texture
    }
}

#[derive(Debug)]
pub struct FrameBuffer {
    texture: PoolOrArcTexture,
    size: wgpu::Extent3d,
}

#[derive(Debug)]
/// Holds either a `PoolEntry` texture, or an `Arc`-wrapped texture.
/// This is used to select between using a texture pool for our framebuffer/resolve-buffer
/// (when rendering to the main screen), or rendering to a non-pooled `Texture`
/// (when doing an offscreen render to a BitmapData texture)
pub enum PoolOrArcTexture {
    Pool(PoolEntry<(wgpu::Texture, wgpu::TextureView), AlwaysCompatible>),
    Manual((wgpu::Texture, wgpu::TextureView)),
}

impl PoolOrArcTexture {
    pub fn texture(&self) -> &wgpu::Texture {
        match self {
            PoolOrArcTexture::Pool(texture) => &texture.0,
            PoolOrArcTexture::Manual(texture) => &texture.0,
        }
    }
    pub fn view(&self) -> &wgpu::TextureView {
        match self {
            PoolOrArcTexture::Pool(texture) => &texture.1,
            PoolOrArcTexture::Manual(texture) => &texture.1,
        }
    }
}

impl FrameBuffer {
    pub fn new(
        descriptors: &Descriptors,
        sample_count: u32,
        size: wgpu::Extent3d,
        format: wgpu::TextureFormat,
        usage: wgpu::TextureUsages,
        pool: &mut TexturePool,
    ) -> Self {
        let texture = pool.get_texture(descriptors, size, usage, format, sample_count);

        Self {
            texture: PoolOrArcTexture::Pool(texture),
            size,
        }
    }

    pub fn new_manual(texture: wgpu::Texture, size: wgpu::Extent3d) -> Self {
        Self {
            texture: PoolOrArcTexture::Manual((
                texture.clone(),
                texture.create_view(&Default::default()),
            )),
            size,
        }
    }

    pub fn view(&self) -> &wgpu::TextureView {
        match self.texture {
            PoolOrArcTexture::Pool(ref texture) => &texture.1,
            PoolOrArcTexture::Manual(ref texture) => &texture.1,
        }
    }

    pub fn texture(&self) -> &wgpu::Texture {
        match self.texture {
            PoolOrArcTexture::Pool(ref texture) => &texture.0,
            PoolOrArcTexture::Manual(ref texture) => &texture.0,
        }
    }

    pub fn take_texture(self) -> PoolOrArcTexture {
        self.texture
    }

    pub fn size(&self) -> wgpu::Extent3d {
        self.size
    }
}

#[derive(Debug)]
pub struct BlendBuffer {
    texture: PoolEntry<(wgpu::Texture, wgpu::TextureView), AlwaysCompatible>,
}

impl BlendBuffer {
    pub fn new(
        descriptors: &Descriptors,
        size: wgpu::Extent3d,
        format: wgpu::TextureFormat,
        usage: wgpu::TextureUsages,
        pool: &mut TexturePool,
    ) -> Self {
        let texture = pool.get_texture(descriptors, size, usage, format, 1);

        Self { texture }
    }

    pub fn view(&self) -> &wgpu::TextureView {
        &self.texture.1
    }

    pub fn texture(&self) -> &wgpu::Texture {
        &self.texture.0
    }
}

#[derive(Debug)]
pub struct StencilBuffer {
    texture: PoolEntry<(wgpu::Texture, wgpu::TextureView), AlwaysCompatible>,
}

impl StencilBuffer {
    pub fn new(
        descriptors: &Descriptors,
        msaa_sample_count: u32,
        size: wgpu::Extent3d,
        pool: &mut TexturePool,
    ) -> Self {
        let texture = pool.get_texture(
            descriptors,
            size,
            wgpu::TextureUsages::RENDER_ATTACHMENT,
            wgpu::TextureFormat::Stencil8,
            msaa_sample_count,
        );

        Self { texture }
    }

    pub fn view(&self) -> &wgpu::TextureView {
        &self.texture.1
    }
}

pub struct CommandTarget {
    frame_buffer: FrameBuffer,
    blend_buffer: OnceCell<BlendBuffer>,
    resolve_buffer: Option<ResolveBuffer>,
    depth: OnceCell<StencilBuffer>,
    globals: Arc<Globals>,
    size: wgpu::Extent3d,
    format: wgpu::TextureFormat,
    sample_count: u32,
    color_needs_clear: OnceCell<bool>,
    render_target_mode: RenderTargetMode,
    /// Timffle: see [`Dirty`]. Only meaningful when there is a resolve buffer.
    dirty: RefCell<Dirty>,
}

impl CommandTarget {
    pub fn new(
        descriptors: &Descriptors,
        pool: &mut TexturePool,
        size: wgpu::Extent3d,
        format: wgpu::TextureFormat,
        sample_count: u32,
        render_target_mode: RenderTargetMode,
        encoder: &mut wgpu::CommandEncoder,
    ) -> Self {
        let globals = pool.get_globals(descriptors, size.width, size.height);

        let mut make_pooled_frame_buffer = || {
            FrameBuffer::new(
                descriptors,
                sample_count,
                size,
                format,
                if sample_count > 1 {
                    // Timffle: the sub-rectangle resolve reads the multisampled
                    // texture from a shader (not possible on WebGL).
                    if descriptors.backend == wgpu::Backend::Gl {
                        wgpu::TextureUsages::RENDER_ATTACHMENT
                    } else {
                        wgpu::TextureUsages::RENDER_ATTACHMENT
                            | wgpu::TextureUsages::TEXTURE_BINDING
                    }
                } else {
                    wgpu::TextureUsages::RENDER_ATTACHMENT
                        | wgpu::TextureUsages::COPY_SRC
                        | wgpu::TextureUsages::COPY_DST
                        | wgpu::TextureUsages::TEXTURE_BINDING
                },
                pool,
            )
        };

        let (frame_buffer, resolve_buffer) =
            if let RenderTargetMode::ExistingWithColor(texture, _) = &render_target_mode {
                if sample_count > 1 {
                    (
                        make_pooled_frame_buffer(),
                        Some(ResolveBuffer::new_manual(texture.clone())),
                    )
                } else {
                    (
                        FrameBuffer::new_manual(texture.clone(), texture.size()),
                        None,
                    )
                }
            } else if sample_count > 1 {
                (
                    make_pooled_frame_buffer(),
                    Some(ResolveBuffer::new(
                        descriptors,
                        size,
                        format,
                        wgpu::TextureUsages::COPY_SRC
                            | wgpu::TextureUsages::COPY_DST
                            | wgpu::TextureUsages::TEXTURE_BINDING
                            | wgpu::TextureUsages::RENDER_ATTACHMENT,
                        pool,
                    )),
                )
            } else {
                (make_pooled_frame_buffer(), None)
            };

        if let RenderTargetMode::FreshWithTexture(texture) = &render_target_mode {
            if let Some(resolve_buffer) = &resolve_buffer {
                encoder.copy_texture_to_texture(
                    texture.as_image_copy(),
                    resolve_buffer.texture().as_image_copy(),
                    size,
                );
            }

            if sample_count > 1 {
                // Both our frame buffer and resolve buffer need to start out
                // in the same state, so copy our existing texture to the freshly
                // allocated frame buffer. We cannot use `copy_texture_to_texture`,
                // since the sample counts are different.
                run_copy_pipeline(
                    descriptors,
                    format,
                    frame_buffer.texture.view(),
                    &texture.create_view(&Default::default()),
                    &globals,
                    sample_count,
                    encoder,
                );
            } else {
                encoder.copy_texture_to_texture(
                    texture.as_image_copy(),
                    frame_buffer.texture().as_image_copy(),
                    size,
                );
            }
        }

        // A fresh copy of a texture starts out equal in both buffers; anything
        // else has nothing valid in the resolve buffer until the first resolve.
        let dirty = if matches!(render_target_mode, RenderTargetMode::FreshWithTexture(_)) {
            Dirty::Clean
        } else {
            Dirty::All
        };

        Self {
            frame_buffer,
            blend_buffer: OnceCell::new(),
            resolve_buffer,
            depth: OnceCell::new(),
            globals,
            size,
            format,
            sample_count,
            color_needs_clear: OnceCell::new(),
            render_target_mode,
            dirty: RefCell::new(dirty),
        }
    }

    pub fn width(&self) -> u32 {
        self.size.width
    }

    pub fn height(&self) -> u32 {
        self.size.height
    }

    pub fn ensure_cleared(&self, encoder: &mut wgpu::CommandEncoder) {
        if self.color_needs_clear.get().is_some() {
            return;
        }
        // If we aren't clearing with a color (eg a texture instead)
        // the there's no point in creating a new render pass that does nothing.
        if self.render_target_mode.color().is_some() {
            encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: create_debug_label!("Clearing command target").as_deref(),
                color_attachments: &[self.color_attachments()],
                ..Default::default()
            });
        }
    }

    pub fn take_color_texture(self) -> PoolOrArcTexture {
        self.resolve_buffer
            .map(|b| b.take_texture())
            .unwrap_or_else(|| self.frame_buffer.take_texture())
    }

    pub fn globals(&self) -> &Globals {
        &self.globals
    }

    /// The color attachment for a render pass that leaves the resolve buffer
    /// up to date (the whole multisampled frame buffer is resolved when the
    /// pass ends).
    pub fn color_attachments(&self) -> Option<wgpu::RenderPassColorAttachment<'_>> {
        *self.dirty.borrow_mut() = Dirty::Clean;
        self.attachments(true)
    }

    /// Timffle: the color attachment for a render pass that does not resolve.
    /// The caller must report what the pass drew with [`Self::mark_drawn`];
    /// the resolve buffer is brought up to date by [`Self::ensure_resolved`].
    pub fn draw_attachments(&self) -> Option<wgpu::RenderPassColorAttachment<'_>> {
        self.attachments(false)
    }

    fn attachments(&self, resolve: bool) -> Option<wgpu::RenderPassColorAttachment<'_>> {
        let mut load = wgpu::LoadOp::Load;
        if self.color_needs_clear.set(false).is_ok()
            && let Some(clear_color) = self.render_target_mode.color()
        {
            load = wgpu::LoadOp::Clear(clear_color);
        }
        Some(wgpu::RenderPassColorAttachment {
            view: self.frame_buffer.view(),
            resolve_target: if resolve {
                self.resolve_buffer.as_ref().map(|b| b.view())
            } else {
                None
            },
            ops: wgpu::Operations {
                load,
                store: wgpu::StoreOp::Store,
            },
            depth_slice: None,
        })
    }

    /// Timffle: records that a pass started with [`Self::draw_attachments`]
    /// may have changed these pixels.
    pub fn mark_drawn(&self, touched: Touched) {
        if self.resolve_buffer.is_some() {
            self.dirty.borrow_mut().mark(touched);
        }
    }

    /// Timffle: makes sure the resolve buffer is current inside `rect` (or
    /// everywhere, for `None`). Resolves the whole multisampled frame buffer
    /// only when something drawn since the last resolve overlaps it.
    pub fn ensure_resolved(
        &self,
        descriptors: &Descriptors,
        encoder: &mut wgpu::CommandEncoder,
        rect: Option<SurfaceRect>,
    ) {
        self.ensure_cleared(encoder);
        let Some(resolve_buffer) = &self.resolve_buffer else {
            return;
        };
        if let Some(rect) = rect {
            self.ensure_resolved_rects(descriptors, encoder, &[rect]);
            return;
        }
        if !self.dirty.borrow().needs_resolve(None) {
            return;
        }
        self.resolve_all(encoder, resolve_buffer);
    }

    /// Timffle: makes sure the resolve buffer is current inside each of
    /// `rects`.
    ///
    /// When everything is dirty (the first time after a draw that could have
    /// touched anything, such as a full-screen background), the whole frame
    /// buffer is resolved once with the GPU's own resolve, so that the many
    /// blends that usually follow find their rectangles clean and need no
    /// pass at all. Otherwise, where the resolve shader can read the
    /// multisampled texture, only the rectangles that overlap something
    /// drawn since are resolved, all in one render pass (one scissored draw
    /// each), and the dirty rectangles they cover are clean again.
    pub fn ensure_resolved_rects(
        &self,
        descriptors: &Descriptors,
        encoder: &mut wgpu::CommandEncoder,
        rects: &[SurfaceRect],
    ) {
        self.ensure_cleared(encoder);
        let Some(resolve_buffer) = &self.resolve_buffer else {
            return;
        };
        let needed: Vec<SurfaceRect> = {
            let dirty = self.dirty.borrow();
            if matches!(*dirty, Dirty::All) {
                drop(dirty);
                self.resolve_all(encoder, resolve_buffer);
                return;
            }
            rects
                .iter()
                .copied()
                .filter(|rect| dirty.needs_resolve(Some(*rect)))
                .collect()
        };
        if needed.is_empty() {
            return;
        }
        if self.can_resolve_partially(descriptors) {
            self.resolve_rects(descriptors, encoder, resolve_buffer, &needed);
            self.dirty.borrow_mut().resolved(&needed);
        } else {
            self.resolve_all(encoder, resolve_buffer);
        }
    }

    /// Whether `resolve.wgsl` can read this target's multisampled frame buffer.
    fn can_resolve_partially(&self, descriptors: &Descriptors) -> bool {
        descriptors.backend != wgpu::Backend::Gl
            && self
                .frame_buffer
                .texture()
                .usage()
                .contains(wgpu::TextureUsages::TEXTURE_BINDING)
    }

    /// One render pass that resolves each of `rects` with the resolve shader.
    /// The dirty state is left as it is.
    fn resolve_rects(
        &self,
        descriptors: &Descriptors,
        encoder: &mut wgpu::CommandEncoder,
        resolve_buffer: &ResolveBuffer,
        rects: &[SurfaceRect],
    ) {
        let bind_group = descriptors
            .device
            .create_bind_group(&wgpu::BindGroupDescriptor {
                label: create_debug_label!("Resolve bind group").as_deref(),
                layout: &descriptors.bind_layouts.resolve,
                entries: &[wgpu::BindGroupEntry {
                    binding: 0,
                    resource: wgpu::BindingResource::TextureView(self.frame_buffer.view()),
                }],
            });
        let pipeline = descriptors.resolve_pipeline(self.format, self.sample_count);
        let mut render_pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
            label: create_debug_label!("Resolving part of command target").as_deref(),
            color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                view: resolve_buffer.view(),
                resolve_target: None,
                ops: wgpu::Operations {
                    load: wgpu::LoadOp::Load,
                    store: wgpu::StoreOp::Store,
                },
                depth_slice: None,
            })],
            ..Default::default()
        });
        render_pass.set_pipeline(&pipeline);
        render_pass.set_bind_group(0, &bind_group, &[]);
        for rect in rects {
            render_pass.set_scissor_rect(rect.x, rect.y, rect.width, rect.height);
            render_pass.draw(0..3, 0..1);
        }
    }

    /// Resolves the whole frame buffer with the GPU's own resolve.
    fn resolve_all(&self, encoder: &mut wgpu::CommandEncoder, resolve_buffer: &ResolveBuffer) {
        encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
            label: create_debug_label!("Resolving command target").as_deref(),
            color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                view: self.frame_buffer.view(),
                resolve_target: Some(resolve_buffer.view()),
                ops: wgpu::Operations {
                    load: wgpu::LoadOp::Load,
                    store: wgpu::StoreOp::Store,
                },
                depth_slice: None,
            })],
            ..Default::default()
        });
        *self.dirty.borrow_mut() = Dirty::Clean;
    }

    pub fn sample_count(&self) -> u32 {
        self.sample_count
    }

    pub fn stencil_attachment(
        &self,
        descriptors: &Descriptors,
        pool: &mut TexturePool,
    ) -> Option<wgpu::RenderPassDepthStencilAttachment<'_>> {
        let new_buffer = self.depth.get().is_none();
        let stencil = self
            .depth
            .get_or_init(|| StencilBuffer::new(descriptors, self.sample_count, self.size, pool));
        Some(wgpu::RenderPassDepthStencilAttachment {
            view: stencil.view(),
            depth_ops: None,
            stencil_ops: Some(wgpu::Operations {
                load: if new_buffer {
                    wgpu::LoadOp::Clear(0)
                } else {
                    wgpu::LoadOp::Load
                },
                store: wgpu::StoreOp::Store,
            }),
        })
    }

    pub fn update_blend_buffer(
        &self,
        descriptors: &Descriptors,
        pool: &mut TexturePool,
        encoder: &mut wgpu::CommandEncoder,
    ) -> &BlendBuffer {
        let blend_buffer = self.blend_buffer.get_or_init(|| {
            BlendBuffer::new(
                descriptors,
                self.size,
                self.format,
                wgpu::TextureUsages::TEXTURE_BINDING
                    | wgpu::TextureUsages::COPY_DST
                    | wgpu::TextureUsages::COPY_SRC,
                pool,
            )
        });
        self.ensure_resolved(descriptors, encoder, None);
        encoder.copy_texture_to_texture(
            wgpu::TexelCopyTextureInfo {
                texture: self
                    .resolve_buffer
                    .as_ref()
                    .map(|b| b.texture())
                    .unwrap_or_else(|| self.frame_buffer.texture()),
                mip_level: 0,
                origin: Default::default(),
                aspect: Default::default(),
            },
            wgpu::TexelCopyTextureInfo {
                texture: blend_buffer.texture(),
                mip_level: 0,
                origin: Default::default(),
                aspect: Default::default(),
            },
            self.frame_buffer.size(),
        );
        blend_buffer
    }

    /// Timffle: whether a render pass that draws into this target (without
    /// resolving) may read [`Self::color_view`] at the same time — true when
    /// the colour is read from the resolve buffer, a different texture from
    /// the multisampled frame buffer being drawn.
    pub fn readable_while_drawn(&self) -> bool {
        self.resolve_buffer.is_some()
    }

    pub fn color_view(&self) -> &wgpu::TextureView {
        self.resolve_buffer
            .as_ref()
            .map(|b| b.view())
            .unwrap_or_else(|| self.frame_buffer.view())
    }

    pub fn color_texture(&self) -> &wgpu::Texture {
        self.resolve_buffer
            .as_ref()
            .map(|b| b.texture())
            .unwrap_or_else(|| self.frame_buffer.texture())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn r(x: u32, y: u32, w: u32, h: u32) -> SurfaceRect {
        SurfaceRect {
            x,
            y,
            width: w,
            height: h,
        }
    }

    #[test]
    fn dirty_rects_only_resolve_when_overlapping() {
        let mut d = Dirty::Clean;
        assert!(!d.needs_resolve(None));
        d.mark(Touched::None);
        assert!(!d.needs_resolve(None));
        d.mark(Touched::Rect(r(0, 0, 10, 10)));
        d.mark(Touched::Rect(r(100, 100, 10, 10)));
        assert!(d.needs_resolve(None));
        assert!(d.needs_resolve(Some(r(5, 5, 1, 1))));
        assert!(!d.needs_resolve(Some(r(10, 10, 50, 50))));
        assert!(d.needs_resolve(Some(r(90, 90, 20, 20))));
        d.mark(Touched::All);
        assert!(d.needs_resolve(Some(r(500, 500, 1, 1))));
    }

    #[test]
    fn resolved_rectangles_become_clean() {
        let mut d = Dirty::Clean;
        d.mark(Touched::Rect(r(10, 10, 20, 20)));
        d.mark(Touched::Rect(r(100, 100, 5, 5)));
        d.resolved(&[r(0, 0, 50, 50)]);
        assert!(!d.needs_resolve(Some(r(10, 10, 20, 20))));
        assert!(d.needs_resolve(Some(r(100, 100, 5, 5))));
        d.resolved(&[r(100, 100, 5, 5)]);
        assert!(matches!(d, Dirty::Clean));
        // A rectangle that is only partly covered stays dirty.
        d.mark(Touched::Rect(r(10, 10, 20, 20)));
        d.resolved(&[r(0, 0, 15, 15)]);
        assert!(d.needs_resolve(Some(r(10, 10, 1, 1))));
        // Everything dirty is never cleaned by a partial resolve.
        let mut all = Dirty::All;
        all.resolved(&[r(0, 0, 1000, 1000)]);
        assert!(all.needs_resolve(Some(r(1, 1, 1, 1))));
    }

    #[test]
    fn too_many_rects_fold_into_all() {
        let mut d = Dirty::Clean;
        for i in 0..MAX_DIRTY_RECTS as u32 + 1 {
            d.mark(Touched::Rect(r(i * 2, 0, 1, 1)));
        }
        assert!(matches!(d, Dirty::All));
    }
}
