//! Object representation for Context3D objects

use crate::avm2::Error;
use crate::avm2::activation::Activation;
use crate::avm2::object::TObject;
use crate::avm2::object::script_object::ScriptObjectData;
use crate::avm2::value::Value;
use crate::avm2_stub_method;
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
use ruffle_render::commands::CommandHandler;
use ruffle_render::matrix::Matrix;
use std::cell::Cell;
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

    pub fn configure_back_buffer(
        self,
        width: u32,
        height: u32,
        anti_alias: u32,
        depth_and_stencil: bool,
        wants_best_resolution: bool,
        wants_best_resolution_on_browser_zoom: bool,
    ) {
        self.with_context_3d(|ctx| {
            ctx.process_command(Context3DCommand::ConfigureBackBuffer {
                width,
                height,
                anti_alias,
                depth_and_stencil,
                wants_best_resolution,
                wants_best_resolution_on_browser_zoom,
            })
        });
        // Timffle: backBufferWidth/backBufferHeight reflect the last successful call.
        self.0.back_buffer_size.set((width, height));
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
        check_texture_stub(activation, format);
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
        enable_depth_and_stencil: bool,
        anti_alias: u32,
        surface_selector: u32,
    ) {
        self.with_context_3d(|ctx| {
            ctx.process_command(Context3DCommand::SetRenderToTexture {
                texture,
                enable_depth_and_stencil,
                anti_alias,
                surface_selector,
            })
        });
    }

    pub fn set_render_to_back_buffer(self) {
        self.with_context_3d(|ctx| ctx.process_command(Context3DCommand::SetRenderToBackBuffer));
    }

    pub fn present(self) {
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

    pub(crate) fn copy_bitmapdata_to_texture(
        self,
        source: &BitmapRawData<'gc>,
        dest: Rc<dyn Texture>,
        layer: u32,
    ) {
        // Note - Flash appears to allow a source that's larger than the destination.
        // Let's leave in this assertion to see if there any real SWFS relying on this
        // behavior.
        assert!(
            source.width() <= dest.width(),
            "Source width {:?} larger than dest width {:?}",
            source.width(),
            dest.width()
        );
        assert!(
            source.height() <= dest.height(),
            "Source height {:?} larger than dest height {:?}",
            source.height(),
            dest.height()
        );

        self.with_context_3d(|ctx| {
            ctx.process_command(Context3DCommand::CopyBitmapToTexture {
                source: source.pixels_rgba(),
                source_width: source.width(),
                source_height: source.height(),
                dest,
                layer,
            })
        });
    }

    #[cfg_attr(not(feature = "jpegxr"), allow(unused))]
    pub(crate) fn copy_pixels_to_texture(self, source: Vec<u8>, dest: Rc<dyn Texture>, layer: u32) {
        self.with_context_3d(|ctx| {
            ctx.process_command(Context3DCommand::CopyBitmapToTexture {
                source: &source,
                source_width: dest.width(),
                source_height: dest.height(),
                dest,
                layer,
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
        check_texture_stub(activation, format);
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
    ) {
        self.with_context_3d(|ctx| {
            ctx.process_command(Context3DCommand::SetSamplerStateAt {
                sampler,
                wrap,
                filter,
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

// This would ideally be placed closer to the actual usage, but
// we don't have stub support in 'render' crates
fn check_texture_stub(activation: &mut Activation<'_, '_>, format: Context3DTextureFormat) {
    match format {
        Context3DTextureFormat::BgrPacked => {
            avm2_stub_method!(
                activation,
                "flash.display3D.Context3D",
                "createTexture",
                "with BgrPacked"
            );
        }
        Context3DTextureFormat::Compressed => {
            avm2_stub_method!(
                activation,
                "flash.display3D.Context3D",
                "createTexture",
                "with Compressed"
            );
        }
        _ => {}
    }
}
