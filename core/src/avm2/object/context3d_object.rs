//! Object representation for Context3D objects

use crate::avm2::Error;
use crate::avm2::activation::Activation;
use crate::avm2::object::TObject;
use crate::avm2::object::script_object::ScriptObjectData;
use crate::avm2::value::Value;
use crate::bitmap::bitmap_data::BitmapRawData;
use crate::context::{RenderContext, UpdateContext};
use gc_arena::{Collect, Gc, GcWeak};
use naga_agal::AgalError;
use ruffle_common::utils::HasPrefixField;
use ruffle_render::backend::{
    BufferUsage, Context3D, Context3DBlendFactor, Context3DCommand, Context3DCompareMode,
    Context3DStencilAction, Context3DTextureFormat, Context3DTriangleFace,
    Context3DVertexBufferFormat, ProgramType, Texture,
};
use ruffle_render::bitmap::BitmapHandle;
use ruffle_render::commands::CommandHandler;
use ruffle_render::matrix::Matrix;
use std::cell::{Cell, RefCell};
use std::rc::Rc;
use swf::{Rectangle, Twips};

use super::program_3d_object::Program3DObject;
use super::texture_object::TextureObject;
use super::{ClassObject, IndexBuffer3DObject, Stage3DObject, VertexBuffer3DObject};

#[derive(Clone, Collect, Copy)]
#[collect(no_drop)]
pub struct Context3DObject<'gc>(pub Gc<'gc, Context3DData<'gc>>);

#[derive(Clone, Collect, Copy, Debug)]
#[collect(no_drop)]
pub struct Context3DObjectWeak<'gc>(pub GcWeak<'gc, Context3DData<'gc>>);

impl<'gc> Context3DObject<'gc> {
    pub fn from_context(
        context: &mut UpdateContext<'gc>,
        context3d: Box<dyn Context3D>,
        stage3d: Stage3DObject<'gc>,
    ) -> Self {
        let class = context.avm2.classes().context3d;

        Context3DObject(Gc::new(
            context.gc(),
            Context3DData {
                base: ScriptObjectData::new(class),
                render_context: Cell::new(Some(context3d)),
                stage3d,
                disposed: Cell::new(false),
                back_buffer_size: Cell::new((0, 0)),
                max_back_buffer: Cell::new((16384, 16384)),
                gpu_memory: Cell::new(0),
                back_buffer_config: Cell::new(None),
                back_buffer_scale: Cell::new((1.0, 1.0)),
                render_target_0: RefCell::new(None),
            },
        ))
    }

    pub fn stage3d(self) -> Stage3DObject<'gc> {
        self.0.stage3d
    }

    // Timffle: dispose() semantics (Flash Error #3694 on later use) and the
    // backBuffer*/maxBackBuffer*/totalGPUMemory/driverInfo bookkeeping.
    pub fn is_disposed(self) -> bool {
        self.0.disposed.get()
    }

    pub fn check_disposed(self, activation: &mut Activation<'_, 'gc>) -> Result<(), Error<'gc>> {
        if self.0.disposed.get() {
            Err(crate::avm2::error::make_error_3694(activation))
        } else {
            Ok(())
        }
    }

    /// Releases the renderer-side Context3D (all its wgpu buffers, textures and
    /// pipelines go with it) and marks the object as disposed.
    pub fn dispose(self) {
        self.0.disposed.set(true);
        self.0.gpu_memory.set(0);
        drop(self.0.render_context.take());
    }

    pub fn back_buffer_size(self) -> (u32, u32) {
        self.0.back_buffer_size.get()
    }

    pub fn max_back_buffer(self) -> (u32, u32) {
        self.0.max_back_buffer.get()
    }

    pub fn set_max_back_buffer(self, size: (u32, u32)) {
        self.0.max_back_buffer.set(size);
    }

    pub fn total_gpu_memory(self) -> u64 {
        self.0.gpu_memory.get()
    }

    pub fn add_gpu_memory(self, bytes: u64) {
        self.0.gpu_memory.set(self.0.gpu_memory.get() + bytes);
    }

    pub fn sub_gpu_memory(self, bytes: u64) {
        self.0
            .gpu_memory
            .set(self.0.gpu_memory.get().saturating_sub(bytes));
    }

    pub fn driver_info(self) -> String {
        if self.0.disposed.get() {
            return "Disposed".to_string();
        }
        self.with_context_3d(|ctx| ctx.driver_info())
    }

    pub fn with_context_3d<R>(self, f: impl FnOnce(&mut dyn Context3D) -> R) -> R {
        // Temporarily take ownership of the Context3D instance.
        let cell = &self.0.render_context;
        let mut guard = scopeguard::guard(cell.take(), |stolen| cell.set(stolen));
        f(guard
            .as_deref_mut()
            .expect("Context3D is missing or already in use"))
    }

    /// Timffle: `configureBackBuffer()`. `scale_factor` is the viewport's
    /// device pixel ratio (what `Stage.contentsScaleFactor` reports).
    ///
    /// * `wantsBestResolution`: "if the device supports HiDPI screens it will
    ///   attempt to allocate a larger back buffer than indicated by the width
    ///   and height" — the buffer is `width×scale` by `height×scale` device
    ///   pixels and is presented into the same `width×height` logical area.
    /// * `wantsBestResolutionOnBrowserZoom`: "the size of the back buffer
    ///   should increase in proportion to the increase in the browser zoom
    ///   factor" — the buffer grows (or shrinks) with the ratio between the
    ///   current scale factor and the one in effect at this call, and is
    ///   reconfigured when that ratio changes (`refresh_best_resolution`).
    ///
    /// The scaled size is capped at `maxBackBufferWidth`/`Height` ("the
    /// maximum size of the back buffer ... can also be set by the user");
    /// `backBufferWidth`/`backBufferHeight` report the buffer actually
    /// allocated.
    #[expect(clippy::too_many_arguments)]
    pub fn configure_back_buffer(
        self,
        width: u32,
        height: u32,
        anti_alias: u32,
        depth_and_stencil: bool,
        wants_best_resolution: bool,
        wants_best_resolution_on_browser_zoom: bool,
        scale_factor: f64,
    ) {
        let config = BackBufferConfig {
            width,
            height,
            anti_alias,
            depth_and_stencil,
            wants_best_resolution,
            wants_best_resolution_on_browser_zoom,
            base_scale_factor: scale_factor,
            applied_scale_factor: scale_factor,
        };
        self.0.back_buffer_config.set(Some(config));
        self.apply_back_buffer_config(config);
    }

    fn apply_back_buffer_config(self, config: BackBufferConfig) {
        let scale = config.effective_scale();
        let (max_w, max_h) = self.max_back_buffer();
        let scaled = |logical: u32, max: u32| -> u32 {
            ((logical as f64 * scale).round() as u32)
                .max(32)
                .min(max)
                .min(16384)
        };
        let (width, height) = (scaled(config.width, max_w), scaled(config.height, max_h));
        self.with_context_3d(|ctx| {
            ctx.process_command(Context3DCommand::ConfigureBackBuffer {
                width,
                height,
                anti_alias: config.anti_alias,
                depth_and_stencil: config.depth_and_stencil,
                wants_best_resolution: config.wants_best_resolution,
                wants_best_resolution_on_browser_zoom: config.wants_best_resolution_on_browser_zoom,
            })
        });
        // backBufferWidth/backBufferHeight reflect the last successful call.
        self.0.back_buffer_size.set((width, height));
        self.0.back_buffer_scale.set((
            width as f64 / config.width as f64,
            height as f64 / config.height as f64,
        ));
        *self.0.render_target_0.borrow_mut() = None;
    }

    /// Timffle: called once per frame — re-applies `configureBackBuffer()`
    /// when `wantsBestResolutionOnBrowserZoom` was set and the viewport scale
    /// factor (browser zoom × device pixel ratio) has changed since.
    pub fn refresh_best_resolution(self, context: &mut UpdateContext<'gc>) {
        if self.0.disposed.get() {
            return;
        }
        let Some(mut config) = self.0.back_buffer_config.get() else {
            return;
        };
        if !config.wants_best_resolution_on_browser_zoom {
            return;
        }
        let scale_factor = context.renderer.viewport_dimensions().scale_factor;
        if scale_factor <= 0.0 || (scale_factor - config.applied_scale_factor).abs() < 1e-6 {
            return;
        }
        config.applied_scale_factor = scale_factor;
        self.0.back_buffer_config.set(Some(config));
        self.apply_back_buffer_config(config);
    }

    /// Timffle: the back buffer (device pixels) read by `drawToBitmapData`.
    pub fn back_buffer_handle(self) -> Option<BitmapHandle> {
        self.with_context_3d(|ctx| ctx.back_buffer_bitmap_handle())
    }

    /// Timffle: the texture bound as colour output 0 (`None` = back buffer).
    pub fn render_target_0(self) -> Option<(Rc<dyn Texture>, Context3DTextureFormat)> {
        self.0.render_target_0.borrow().clone()
    }

    pub fn create_index_buffer(
        self,
        num_indices: u32,
        activation: &mut Activation<'_, 'gc>,
    ) -> Value<'gc> {
        let index_buffer = self
            .with_context_3d(|ctx| ctx.create_index_buffer(BufferUsage::StaticDraw, num_indices));

        // Timffle: 16-bit indices, counted towards totalGPUMemory.
        let gpu_size = num_indices as u64 * 2;
        self.add_gpu_memory(gpu_size);
        Value::Object(IndexBuffer3DObject::from_handle(
            activation,
            self,
            index_buffer,
            gpu_size,
        ))
    }

    #[expect(clippy::too_many_arguments)]
    pub fn create_texture(
        self,
        width: u32,
        height: u32,
        format: Context3DTextureFormat,
        optimize_for_render_to_texture: bool,
        streaming_levels: u32,
        class: ClassObject<'gc>,
        activation: &mut Activation<'_, 'gc>,
    ) -> Result<Value<'gc>, Error<'gc>> {
        let texture = self.with_context_3d(|ctx| {
            ctx.create_texture(
                width,
                height,
                format,
                optimize_for_render_to_texture,
                streaming_levels,
            )
        })?;

        // Timffle: counted towards totalGPUMemory (full mip chain when streaming is requested).
        let gpu_size = texture_gpu_size(width, height, format, streaming_levels, 1);
        self.add_gpu_memory(gpu_size);
        Ok(Value::Object(TextureObject::from_handle(
            activation, self, texture, format, class, gpu_size,
        )))
    }

    pub fn create_vertex_buffer(
        self,
        num_vertices: u32,
        data_32_per_vertex: u8,
        usage: BufferUsage,
        activation: &mut Activation<'_, 'gc>,
    ) -> Value<'gc> {
        let handle = self.with_context_3d(|ctx| {
            ctx.create_vertex_buffer(usage, num_vertices, data_32_per_vertex)
        });

        // Timffle: counted towards totalGPUMemory.
        let gpu_size = num_vertices as u64 * data_32_per_vertex as u64 * 4;
        self.add_gpu_memory(gpu_size);
        Value::Object(VertexBuffer3DObject::from_handle(
            activation,
            self,
            handle,
            data_32_per_vertex,
            gpu_size,
        ))
    }

    pub fn upload_vertex_buffer_data(
        self,
        buffer: VertexBuffer3DObject<'gc>,
        data: &[u8],
        start_vertex: usize,
        data32_per_vertex: u8,
    ) {
        self.with_context_3d(|ctx| {
            ctx.process_command(Context3DCommand::UploadToVertexBuffer {
                buffer: buffer.handle(),
                data,
                start_vertex,
                data32_per_vertex,
            })
        });
    }

    pub fn upload_index_buffer_data(
        self,
        buffer: IndexBuffer3DObject<'gc>,
        data: &[u8],
        start_offset: usize,
    ) {
        let mut handle = buffer.handle();
        self.with_context_3d(|ctx| {
            ctx.process_command(Context3DCommand::UploadToIndexBuffer {
                buffer: &mut *handle,
                data,
                start_offset,
            })
        });
    }

    pub fn set_vertex_buffer_at(
        self,
        index: u32,
        buffer: Option<(VertexBuffer3DObject<'gc>, Context3DVertexBufferFormat)>,
        buffer_offset: u32,
    ) {
        self.with_context_3d(|ctx| {
            ctx.process_command(Context3DCommand::SetVertexBufferAt {
                index,
                buffer: buffer.map(|(b, format)| (b.handle(), format)),
                buffer_offset,
            })
        });
    }

    pub fn create_program(self, activation: &mut Activation<'_, 'gc>) -> Value<'gc> {
        Value::Object(Program3DObject::from_context(activation, self))
    }

    pub fn upload_shaders(
        self,
        program: Program3DObject<'gc>,
        vertex_shader_agal: Vec<u8>,
        fragment_shader_agal: Vec<u8>,
    ) -> Result<(), AgalError> {
        self.with_context_3d(|ctx| {
            ctx.upload_shaders(
                program.shader_module_handle(),
                vertex_shader_agal,
                fragment_shader_agal,
            )
        })
    }

    pub fn set_program(self, program: Option<Program3DObject<'gc>>) {
        let module = program.and_then(|p| p.shader_module_handle().borrow().clone());

        self.with_context_3d(|ctx| ctx.process_command(Context3DCommand::SetShaders { module }));
    }

    pub fn draw_triangles(
        self,
        index_buffer: IndexBuffer3DObject<'gc>,
        first_index: u32,
        mut num_triangles: i32,
    ) {
        if num_triangles == -1 {
            // FIXME - should we error if the number of indices isn't a multiple of 3?
            num_triangles = (index_buffer.count() / 3) as i32;
        }
        let handle = index_buffer.handle();

        self.with_context_3d(|ctx| {
            ctx.process_command(Context3DCommand::DrawTriangles {
                index_buffer: &*handle,
                first_index: first_index as usize,
                num_triangles: num_triangles as isize,
            })
        });
    }

    pub fn set_program_constants(
        self,
        program_type: ProgramType,
        first_register: u32,
        matrix_raw_data_column_major: &[[u8; 4]],
    ) {
        self.with_context_3d(|ctx| {
            ctx.process_command(Context3DCommand::SetProgramConstants {
                program_type,
                first_register,
                matrix_raw_data_column_major,
            })
        });
    }

    pub fn set_culling(self, face: Context3DTriangleFace) {
        self.with_context_3d(|ctx| ctx.process_command(Context3DCommand::SetCulling { face }));
    }

    pub fn set_blend_factors(
        self,
        source_factor: Context3DBlendFactor,
        destination_factor: Context3DBlendFactor,
    ) {
        self.with_context_3d(|ctx| {
            ctx.process_command(Context3DCommand::SetBlendFactors {
                source_factor,
                destination_factor,
            })
        });
    }

    pub fn set_render_to_texture(
        self,
        texture: Rc<dyn Texture>,
        format: Context3DTextureFormat,
        enable_depth_and_stencil: bool,
        anti_alias: u32,
        surface_selector: u32,
        color_output_index: u32, // Timffle: multiple render targets
    ) {
        if color_output_index == 0 {
            *self.0.render_target_0.borrow_mut() = Some((texture.clone(), format));
        }
        self.with_context_3d(|ctx| {
            ctx.process_command(Context3DCommand::SetRenderToTexture {
                texture,
                enable_depth_and_stencil,
                anti_alias,
                surface_selector,
                color_output_index,
            })
        });
    }

    pub fn set_render_to_back_buffer(self) {
        *self.0.render_target_0.borrow_mut() = None; // Timffle
        self.with_context_3d(|ctx| ctx.process_command(Context3DCommand::SetRenderToBackBuffer));
    }

    pub fn present(self) {
        // Timffle: "Calling present() resets the target to the back buffer".
        *self.0.render_target_0.borrow_mut() = None;
        self.with_context_3d(|ctx| ctx.present())
    }

    // Renders our finalized frame to the screen, as part of the Ruffle rendering process.
    pub fn render(self, context: &mut RenderContext<'_, 'gc>) {
        // Timffle: a disposed context has no renderer-side state any more.
        if self.0.disposed.get() {
            return;
        }
        self.with_context_3d(|context3d| {
            if context3d.should_render() {
                let handle = context3d.bitmap_handle();

                // FIXME - The Stage3D should not be scaled
                // when resizing the player window.
                let mut transform = context.transform_stack.transform();
                transform.matrix *= Matrix::translate(
                    Twips::from_pixels(self.stage3d().x()),
                    Twips::from_pixels(self.stage3d().y()),
                );
                // Timffle: a HiDPI back buffer (wantsBestResolution*) is drawn
                // into the logical width×height area it was configured for.
                let (scale_x, scale_y) = self.0.back_buffer_scale.get();
                if scale_x != 1.0 || scale_y != 1.0 {
                    transform.matrix *= Matrix::scale(1.0 / scale_x as f32, 1.0 / scale_y as f32);
                }

                context.commands.render_stage3d(handle, transform);
            }
        });
    }

    #[expect(clippy::too_many_arguments)]
    pub fn set_clear(
        self,
        red: f64,
        green: f64,
        blue: f64,
        alpha: f64,
        depth: f64,
        stencil: u32,
        mask: u32,
    ) {
        self.with_context_3d(|ctx| {
            ctx.process_command(Context3DCommand::Clear {
                red,
                green,
                blue,
                alpha,
                depth,
                stencil,
                mask,
            })
        });
    }

    // Timffle: `mip_level` selects the level written; the source must fit that
    // level (`dest size >> mip_level`), partial (smaller) uploads are allowed as
    // in Flash. Returns false when the level does not exist or the source does
    // not fit.
    pub(crate) fn copy_bitmapdata_to_texture(
        self,
        source: &BitmapRawData<'gc>,
        dest: Rc<dyn Texture>,
        layer: u32,
        mip_level: u32,
    ) -> bool {
        if mip_level >= dest.mip_level_count() {
            return false;
        }
        let (level_w, level_h) = (
            (dest.width() >> mip_level).max(1),
            (dest.height() >> mip_level).max(1),
        );
        if source.width() > level_w || source.height() > level_h {
            tracing::warn!(
                "Texture upload of {}x{} does not fit mip level {} ({}x{})",
                source.width(),
                source.height(),
                mip_level,
                level_w,
                level_h
            );
            return false;
        }

        self.with_context_3d(|ctx| {
            ctx.process_command(Context3DCommand::CopyBitmapToTexture {
                source: source.pixels_rgba(),
                source_width: source.width(),
                source_height: source.height(),
                dest,
                layer,
                mip_level,
            })
        });
        true
    }

    // Timffle: raw bytes in the texture's own storage layout (RGBA8 pixels or
    // DXT/ETC2 blocks) for a `source_width` x `source_height` area of a level.
    pub(crate) fn copy_pixels_to_texture(
        self,
        source: &[u8],
        source_width: u32,
        source_height: u32,
        dest: Rc<dyn Texture>,
        layer: u32,
        mip_level: u32,
    ) {
        self.with_context_3d(|ctx| {
            ctx.process_command(Context3DCommand::CopyBitmapToTexture {
                source,
                source_width,
                source_height,
                dest,
                layer,
                mip_level,
            })
        });
    }

    pub(crate) fn set_texture_at(self, sampler: u32, texture: Option<Rc<dyn Texture>>, cube: bool) {
        self.with_context_3d(|ctx| {
            ctx.process_command(Context3DCommand::SetTextureAt {
                sampler,
                texture,
                cube,
            })
        });
    }

    pub(crate) fn set_color_mask(self, red: bool, green: bool, blue: bool, alpha: bool) {
        self.with_context_3d(|ctx| {
            ctx.process_command(Context3DCommand::SetColorMask {
                red,
                green,
                blue,
                alpha,
            })
        });
    }

    pub(crate) fn set_depth_test(self, depth_mask: bool, pass_compare_mode: Context3DCompareMode) {
        self.with_context_3d(|ctx| {
            ctx.process_command(Context3DCommand::SetDepthTest {
                depth_mask,
                pass_compare_mode,
            })
        });
    }

    pub(crate) fn create_cube_texture(
        self,
        size: u32,
        format: Context3DTextureFormat,
        optimize_for_render_to_texture: bool,
        streaming_levels: u32,
        activation: &mut Activation<'_, 'gc>,
    ) -> Result<Value<'gc>, Error<'gc>> {
        let texture = self.with_context_3d(|ctx| {
            ctx.create_cube_texture(
                size,
                format,
                optimize_for_render_to_texture,
                streaming_levels,
            )
        })?;

        let class = activation.avm2().classes().cubetexture;

        // Timffle: six faces, counted towards totalGPUMemory.
        let gpu_size = texture_gpu_size(size, size, format, streaming_levels, 6);
        self.add_gpu_memory(gpu_size);
        Ok(Value::Object(TextureObject::from_handle(
            activation, self, texture, format, class, gpu_size,
        )))
    }

    pub(crate) fn set_sampler_state_at(
        self,
        sampler: u32,
        wrap: ruffle_render::backend::Context3DWrapMode,
        filter: ruffle_render::backend::Context3DTextureFilter,
        mip_filter: ruffle_render::backend::Context3DMipFilter,
    ) {
        self.with_context_3d(|ctx| {
            ctx.process_command(Context3DCommand::SetSamplerStateAt {
                sampler,
                wrap,
                filter,
                mip_filter, // Timffle
            })
        });
    }

    pub(crate) fn set_scissor_rectangle(self, rect: Option<Rectangle<Twips>>) {
        self.with_context_3d(|ctx| {
            ctx.process_command(Context3DCommand::SetScissorRectangle { rect })
        });
    }

    pub(crate) fn set_stencil_actions(
        self,
        triangle_face: Context3DTriangleFace,
        compare_mode: Context3DCompareMode,
        on_both_pass: Context3DStencilAction,
        on_depth_fail: Context3DStencilAction,
        on_depth_pass_stencil_fail: Context3DStencilAction,
    ) {
        self.with_context_3d(|ctx| {
            ctx.process_command(Context3DCommand::SetStencilActions {
                triangle_face,
                compare_mode,
                on_both_pass,
                on_depth_fail,
                on_depth_pass_stencil_fail,
            })
        });
    }

    pub(crate) fn set_stencil_reference_value(
        self,
        reference_value: u32,
        read_mask: u32,
        write_mask: u32,
    ) {
        self.with_context_3d(|ctx| {
            ctx.process_command(Context3DCommand::SetStencilReferenceValue {
                reference_value,
                read_mask,
                write_mask,
            })
        });
    }
}

#[derive(Collect, HasPrefixField)]
#[collect(no_drop)]
#[repr(C, align(8))]
pub struct Context3DData<'gc> {
    /// Base script object
    base: ScriptObjectData<'gc>,

    #[collect(require_static)]
    render_context: Cell<Option<Box<dyn Context3D>>>,

    stage3d: Stage3DObject<'gc>,

    // Timffle: see `Context3DObject::dispose`.
    disposed: Cell<bool>,
    back_buffer_size: Cell<(u32, u32)>,
    max_back_buffer: Cell<(u32, u32)>,
    gpu_memory: Cell<u64>,

    // Timffle: the last successful configureBackBuffer() call, re-applied
    // on browser zoom changes (`wantsBestResolutionOnBrowserZoom`).
    back_buffer_config: Cell<Option<BackBufferConfig>>,
    // Timffle: device pixels per logical pixel of the back buffer
    // (1.0 unless `wantsBestResolution*` enlarged it).
    back_buffer_scale: Cell<(f64, f64)>,
    // Timffle: the texture bound as colour output 0 by setRenderToTexture()
    // (`None` while rendering to the back buffer); the extra outputs of a
    // multiple-render-target setup are checked against it.
    #[collect(require_static)]
    render_target_0: RefCell<Option<(Rc<dyn Texture>, Context3DTextureFormat)>>,
}

// Timffle: see `Context3DObject::configure_back_buffer`.
#[derive(Clone, Copy, Debug)]
struct BackBufferConfig {
    width: u32,
    height: u32,
    anti_alias: u32,
    depth_and_stencil: bool,
    wants_best_resolution: bool,
    wants_best_resolution_on_browser_zoom: bool,
    /// Viewport scale factor when configureBackBuffer() was called.
    base_scale_factor: f64,
    /// Viewport scale factor the buffer was last sized for.
    applied_scale_factor: f64,
}

impl BackBufferConfig {
    /// Device pixels per requested pixel.
    fn effective_scale(&self) -> f64 {
        let scale = if self.wants_best_resolution {
            // The full device pixel ratio.
            self.applied_scale_factor
        } else if self.wants_best_resolution_on_browser_zoom {
            // Only the zoom applied since the call.
            self.applied_scale_factor / self.base_scale_factor
        } else {
            1.0
        };
        if scale.is_finite() && scale > 0.0 {
            scale
        } else {
            1.0
        }
    }
}

// Timffle: bytes a texture of this size/format occupies on the GPU. Flash's
// totalGPUMemory counts index buffers, vertex buffers, textures and programs.
fn texture_gpu_size(
    width: u32,
    height: u32,
    format: Context3DTextureFormat,
    streaming_levels: u32,
    layers: u64,
) -> u64 {
    let (num, den) = match format {
        Context3DTextureFormat::Bgra => (4, 1),
        Context3DTextureFormat::BgraPacked | Context3DTextureFormat::BgrPacked => (2, 1),
        Context3DTextureFormat::Compressed => (1, 2),
        Context3DTextureFormat::CompressedAlpha => (1, 1),
        Context3DTextureFormat::RgbaHalfFloat => (8, 1),
    };
    let mut total = 0u64;
    let (mut w, mut h) = (width.max(1) as u64, height.max(1) as u64);
    loop {
        total += (w * h * num).div_ceil(den);
        if streaming_levels == 0 || (w == 1 && h == 1) {
            break;
        }
        w = (w / 2).max(1);
        h = (h / 2).max(1);
    }
    total * layers
}

impl<'gc> TObject<'gc> for Context3DObject<'gc> {
    fn gc_base(&self) -> Gc<'gc, ScriptObjectData<'gc>> {
        HasPrefixField::as_prefix_gc(self.0)
    }
}

impl std::fmt::Debug for Context3DObject<'_> {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "Context3D")
    }
}
