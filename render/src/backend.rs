pub mod null;

use crate::bitmap::{Bitmap, BitmapHandle, BitmapSource, PixelRegion, RgbaBufRead, SyncHandle};
use crate::commands::CommandList;
use crate::error::Error;
use crate::filters::Filter;
use crate::pixel_bender::{PixelBenderShader, PixelBenderShaderHandle};
use crate::pixel_bender_support::PixelBenderShaderArgument;
use crate::quality::StageQuality;
use crate::shape_utils::DistilledShape;
use ruffle_wstr::{FromWStr, WStr};
use std::any::Any;
use std::borrow::Cow;
use std::cell::RefCell;
use std::fmt::Debug;
use std::num::NonZeroU32;
use std::rc::Rc;
use std::sync::Arc;
use swf::{Color, Rectangle, Twips};

pub struct BitmapCacheEntry {
    pub handle: BitmapHandle,
    pub commands: CommandList,
    pub clear: Color,
    pub filters: Vec<Filter>,
}

pub trait RenderBackend: Any {
    fn viewport_dimensions(&self) -> ViewportDimensions;
    // Do not call this method directly - use `player.set_viewport_dimensions`,
    // which will ensure that the stage is properly updated as well.
    fn set_viewport_dimensions(&mut self, dimensions: ViewportDimensions);
    fn register_shape(
        &mut self,
        shape: DistilledShape,
        bitmap_source: &dyn BitmapSource,
    ) -> ShapeHandle;

    fn register_shape_with_scale(
        &mut self,
        shape: DistilledShape,
        bitmap_source: &dyn BitmapSource,
        _scale: f32,
    ) -> ShapeHandle {
        // Default implementation ignores scale
        self.register_shape(shape, bitmap_source)
    }

    fn render_offscreen(
        &mut self,
        handle: BitmapHandle,
        commands: CommandList,
        quality: StageQuality,
        bounds: PixelRegion,
    ) -> Option<Box<dyn SyncHandle>>;

    /// Timffle: whether `render_offscreen_with_cache` draws the cacheAsBitmap pictures
    /// (and so the filters) that `BitmapData.draw` of a filtered object needs. Backends
    /// that do not keep drawing such objects without their filters.
    fn supports_offscreen_bitmap_cache(&self) -> bool {
        false
    }

    /// Timffle: `render_offscreen` after drawing (and filtering) the given
    /// cacheAsBitmap pictures, which the commands may sample.
    fn render_offscreen_with_cache(
        &mut self,
        handle: BitmapHandle,
        commands: CommandList,
        quality: StageQuality,
        bounds: PixelRegion,
        _cache_entries: Vec<BitmapCacheEntry>,
    ) -> Option<Box<dyn SyncHandle>> {
        self.render_offscreen(handle, commands, quality, bounds)
    }

    /// Applies the given filter with a `BitmapHandle` source onto a destination `BitmapHandle`.
    /// The `destination_rect` must be calculated by the caller and is assumed to be correct.
    /// Both `source_rect` and `destination_rect` must be valid (`BoundingBox::valid`).
    /// `source` may equal `destination`, in which case a temporary buffer is used internally.
    ///
    /// Returns None if the backend does not support this filter.
    fn apply_filter(
        &mut self,
        _source: BitmapHandle,
        _source_point: (u32, u32),
        _source_size: (u32, u32),
        _destination: BitmapHandle,
        _dest_point: (i32, i32),
        _filter: Filter,
    ) -> Option<Box<dyn SyncHandle>> {
        None
    }

    fn is_filter_supported(&self, _filter: &Filter) -> bool {
        false
    }

    fn is_offscreen_supported(&self) -> bool {
        false
    }

    fn submit_frame(
        &mut self,
        clear: swf::Color,
        commands: CommandList,
        cache_entries: Vec<BitmapCacheEntry>,
    );

    fn create_empty_texture(
        &mut self,
        width: NonZeroU32,
        height: NonZeroU32,
    ) -> Result<BitmapHandle, Error>;

    fn register_bitmap(&mut self, bitmap: Bitmap<'_>) -> Result<BitmapHandle, Error>;
    fn update_texture(
        &mut self,
        handle: &BitmapHandle,
        bitmap: Bitmap<'_>,
        region: PixelRegion,
    ) -> Result<(), Error>;

    fn create_context3d(&mut self, profile: Context3DProfile) -> Result<Box<dyn Context3D>, Error>;

    fn debug_info(&self) -> Cow<'static, str>;
    /// An internal name that is used to identify the render-backend.
    fn name(&self) -> &'static str;

    fn set_quality(&mut self, quality: StageQuality);

    fn compile_pixelbender_shader(
        &mut self,
        shader: PixelBenderShader,
    ) -> Result<PixelBenderShaderHandle, Error>;

    fn run_pixelbender_shader(
        &mut self,
        handle: PixelBenderShaderHandle,
        arguments: &[PixelBenderShaderArgument],
        target: &PixelBenderTarget,
    ) -> Result<PixelBenderOutput, Error>;

    fn resolve_sync_handle(
        &mut self,
        handle: Box<dyn SyncHandle>,
        with_rgba: RgbaBufRead,
    ) -> Result<(), Error>;

    /// Timffle: `Context3D.drawToBitmapData` — copies the `source_region` of a
    /// Stage3D buffer (`source`, a texture owned by a `Context3D`) into the
    /// bitmap `destination` at `dest_point`, pixel for pixel (no scaling, no
    /// blending; the colours are taken as premultiplied, as Flash does).
    /// The caller has clipped the region to both textures. Returns the handle
    /// that syncs the new GPU pixels back to the CPU, or `None` when the
    /// backend cannot copy.
    fn copy_stage3d_to_bitmap(
        &mut self,
        _source: BitmapHandle,
        _source_region: PixelRegion,
        _destination: BitmapHandle,
        _dest_point: (u32, u32),
    ) -> Option<Box<dyn SyncHandle>> {
        None
    }
}

pub enum PixelBenderTarget {
    // The shader will write to the provided bitmap texture,
    // producing a `PixelBenderOutput::Bitmap` with the corresponding
    // `SyncHandle`
    Bitmap(BitmapHandle),
    // The shader will write to a temporary texture, which will then
    // be immediately read back as bytes (in `PixelBenderOutput::Bytes`)
    Bytes { width: u32, height: u32 },
}

pub enum PixelBenderOutput {
    Bitmap(Box<dyn SyncHandle>),
    Bytes(Vec<u8>),
}

pub trait IndexBuffer: Any {}
pub trait VertexBuffer: Any {}

pub trait ShaderModule: Any {}

pub trait Texture: Any + Debug {
    fn width(&self) -> u32;
    fn height(&self) -> u32;
    // Timffle: number of mip levels the GPU texture holds (1 when the texture
    // has no mip chain, e.g. a RectangleTexture).
    fn mip_level_count(&self) -> u32 {
        1
    }
    // Timffle: the block format the GPU texture stores natively when the
    // backend could honour a COMPRESSED / COMPRESSED_ALPHA request with a
    // compressed format (None: RGBA8 storage, uploads are decoded on the CPU).
    fn compressed_format(&self) -> Option<crate::compressed::CompressedFormat> {
        None
    }
}

pub trait RawTexture: Any + Debug {
    fn equals(&self, other: &dyn RawTexture) -> bool;
}

#[cfg(feature = "wgpu")]
impl RawTexture for wgpu::Texture {
    fn equals(&self, other: &dyn RawTexture) -> bool {
        if let Some(other_texture) = (other as &dyn Any).downcast_ref::<wgpu::Texture>() {
            std::ptr::eq(self, other_texture)
        } else {
            false
        }
    }
}

#[derive(Debug, Copy, Clone)]
pub enum Context3DTextureFormat {
    Bgra,
    BgraPacked,
    BgrPacked,
    Compressed,
    CompressedAlpha,
    RgbaHalfFloat,
}

impl FromWStr for Context3DTextureFormat {
    type Err = ();

    fn from_wstr(s: &WStr) -> Result<Self, Self::Err> {
        if s == b"bgra" {
            Ok(Context3DTextureFormat::Bgra)
        } else if s == b"bgraPacked4444" {
            Ok(Context3DTextureFormat::BgraPacked)
        } else if s == b"bgrPacked565" {
            Ok(Context3DTextureFormat::BgrPacked)
        } else if s == b"compressed" {
            Ok(Context3DTextureFormat::Compressed)
        } else if s == b"compressedAlpha" {
            Ok(Context3DTextureFormat::CompressedAlpha)
        } else if s == b"rgbaHalfFloat" {
            Ok(Context3DTextureFormat::RgbaHalfFloat)
        } else {
            Err(())
        }
    }
}

#[derive(Debug, Copy, Clone)]
pub enum Context3DBlendFactor {
    DestinationAlpha,
    DestinationColor,
    One,
    OneMinusDestinationAlpha,
    OneMinusDestinationColor,
    OneMinusSourceAlpha,
    OneMinusSourceColor,
    SourceAlpha,
    SourceColor,
    Zero,
}

impl FromWStr for Context3DBlendFactor {
    type Err = ();

    fn from_wstr(s: &WStr) -> Result<Self, Self::Err> {
        if s == b"destinationAlpha" {
            Ok(Context3DBlendFactor::DestinationAlpha)
        } else if s == b"destinationColor" {
            Ok(Context3DBlendFactor::DestinationColor)
        } else if s == b"one" {
            Ok(Context3DBlendFactor::One)
        } else if s == b"oneMinusDestinationAlpha" {
            Ok(Context3DBlendFactor::OneMinusDestinationAlpha)
        } else if s == b"oneMinusDestinationColor" {
            Ok(Context3DBlendFactor::OneMinusDestinationColor)
        } else if s == b"oneMinusSourceAlpha" {
            Ok(Context3DBlendFactor::OneMinusSourceAlpha)
        } else if s == b"oneMinusSourceColor" {
            Ok(Context3DBlendFactor::OneMinusSourceColor)
        } else if s == b"sourceAlpha" {
            Ok(Context3DBlendFactor::SourceAlpha)
        } else if s == b"sourceColor" {
            Ok(Context3DBlendFactor::SourceColor)
        } else if s == b"zero" {
            Ok(Context3DBlendFactor::Zero)
        } else {
            Err(())
        }
    }
}

pub enum BufferUsage {
    DynamicDraw,
    StaticDraw,
}

pub enum ProgramType {
    Vertex,
    Fragment,
}

impl FromWStr for ProgramType {
    type Err = ();

    fn from_wstr(s: &WStr) -> Result<Self, Self::Err> {
        if s == b"vertex" {
            Ok(ProgramType::Vertex)
        } else if s == b"fragment" {
            Ok(ProgramType::Fragment)
        } else {
            Err(())
        }
    }
}

pub trait Context3D: Any {
    fn profile(&self) -> Context3DProfile;
    // The BitmapHandle for the texture we're rendering to
    fn bitmap_handle(&self) -> BitmapHandle;
    // Timffle: the back buffer (the one drawTriangles() writes until the next
    // present()), read by `Context3D.drawToBitmapData`; `None` before
    // configureBackBuffer().
    fn back_buffer_bitmap_handle(&mut self) -> Option<BitmapHandle>;
    // Whether or not we should actually render the texture
    // as part of stage rendering
    fn should_render(&self) -> bool;

    // Get a 'disposed' handle - this is what we store in all IndexBuffer3D
    // objects after dispose() has been called.
    fn disposed_index_buffer_handle(&self) -> Rc<dyn IndexBuffer>;

    // Get a 'disposed' handle - this is what we store in all VertexBuffer3D
    // objects after dispose() has been called.
    fn disposed_vertex_buffer_handle(&self) -> Rc<dyn VertexBuffer>;

    fn create_index_buffer(&mut self, usage: BufferUsage, num_indices: u32)
    -> Box<dyn IndexBuffer>;
    fn create_vertex_buffer(
        &mut self,
        usage: BufferUsage,
        num_vertices: u32,
        data_32_per_vertex: u8,
    ) -> Rc<dyn VertexBuffer>;

    fn create_texture(
        &mut self,
        width: u32,
        height: u32,
        format: Context3DTextureFormat,
        optimize_for_render_to_texture: bool,
        streaming_levels: u32,
    ) -> Result<Rc<dyn Texture>, Error>;
    fn create_cube_texture(
        &mut self,
        size: u32,
        format: Context3DTextureFormat,
        optimize_for_render_to_texture: bool,
        streaming_levels: u32,
    ) -> Result<Rc<dyn Texture>, Error>;

    fn upload_shaders(
        &mut self,
        module: &RefCell<Option<Rc<dyn ShaderModule>>>,
        vertex_shader_agal: Vec<u8>,
        fragment_shader_agal: Vec<u8>,
    ) -> Result<(), naga_agal::AgalError>;

    fn process_command(&mut self, command: Context3DCommand<'_>);

    fn present(&mut self);

    // Timffle: the string Flash exposes as Context3D.driverInfo, composed from the
    // graphics adapter actually in use.
    fn driver_info(&self) -> String;
}

#[derive(Copy, Clone, Debug)]
pub enum Context3DVertexBufferFormat {
    Float1,
    Float2,
    Float3,
    Float4,
    Bytes4,
}

impl FromWStr for Context3DVertexBufferFormat {
    type Err = ();

    fn from_wstr(s: &WStr) -> Result<Self, Self::Err> {
        if s == b"float1" {
            Ok(Context3DVertexBufferFormat::Float1)
        } else if s == b"float2" {
            Ok(Context3DVertexBufferFormat::Float2)
        } else if s == b"float3" {
            Ok(Context3DVertexBufferFormat::Float3)
        } else if s == b"float4" {
            Ok(Context3DVertexBufferFormat::Float4)
        } else if s == b"bytes4" {
            Ok(Context3DVertexBufferFormat::Bytes4)
        } else {
            Err(())
        }
    }
}

#[derive(Copy, Clone, Debug)]
pub enum Context3DTriangleFace {
    None,
    Back,
    Front,
    FrontAndBack,
}

impl FromWStr for Context3DTriangleFace {
    type Err = ();

    fn from_wstr(s: &WStr) -> Result<Self, Self::Err> {
        if s == b"none" {
            Ok(Context3DTriangleFace::None)
        } else if s == b"back" {
            Ok(Context3DTriangleFace::Back)
        } else if s == b"front" {
            Ok(Context3DTriangleFace::Front)
        } else if s == b"frontAndBack" {
            Ok(Context3DTriangleFace::FrontAndBack)
        } else {
            Err(())
        }
    }
}

#[derive(Copy, Clone, Debug)]
pub enum Context3DProfile {
    Baseline,
    BaselineConstrained,
    BaselineExtended,
    Standard,
    StandardConstrained,
    StandardExtended,
}

#[derive(Copy, Clone, Debug)]
pub enum Context3DCompareMode {
    Never,
    Less,
    Equal,
    LessEqual,
    Greater,
    NotEqual,
    GreaterEqual,
    Always,
}

impl FromWStr for Context3DCompareMode {
    type Err = ();

    fn from_wstr(s: &WStr) -> Result<Self, Self::Err> {
        if s == b"never" {
            Ok(Context3DCompareMode::Never)
        } else if s == b"less" {
            Ok(Context3DCompareMode::Less)
        } else if s == b"equal" {
            Ok(Context3DCompareMode::Equal)
        } else if s == b"lessEqual" {
            Ok(Context3DCompareMode::LessEqual)
        } else if s == b"greater" {
            Ok(Context3DCompareMode::Greater)
        } else if s == b"notEqual" {
            Ok(Context3DCompareMode::NotEqual)
        } else if s == b"greaterEqual" {
            Ok(Context3DCompareMode::GreaterEqual)
        } else if s == b"always" {
            Ok(Context3DCompareMode::Always)
        } else {
            Err(())
        }
    }
}

#[derive(Copy, Clone, Debug)]
pub enum Context3DStencilAction {
    DecrementSaturate,
    DecrementWrap,
    IncrementSaturate,
    IncrementWrap,
    Invert,
    Keep,
    Set,
    Zero,
}

impl FromWStr for Context3DStencilAction {
    type Err = ();

    fn from_wstr(s: &WStr) -> Result<Self, Self::Err> {
        if s == b"decrementSaturate" {
            Ok(Context3DStencilAction::DecrementSaturate)
        } else if s == b"decrementWrap" {
            Ok(Context3DStencilAction::DecrementWrap)
        } else if s == b"incrementSaturate" {
            Ok(Context3DStencilAction::IncrementSaturate)
        } else if s == b"incrementWrap" {
            Ok(Context3DStencilAction::IncrementWrap)
        } else if s == b"invert" {
            Ok(Context3DStencilAction::Invert)
        } else if s == b"keep" {
            Ok(Context3DStencilAction::Keep)
        } else if s == b"set" {
            Ok(Context3DStencilAction::Set)
        } else if s == b"zero" {
            Ok(Context3DStencilAction::Zero)
        } else {
            Err(())
        }
    }
}

#[derive(Copy, Clone, Debug)]
pub enum Context3DWrapMode {
    Clamp,
    ClampURepeatV,
    Repeat,
    RepeatUClampV,
}

impl FromWStr for Context3DWrapMode {
    type Err = ();

    fn from_wstr(s: &WStr) -> Result<Self, Self::Err> {
        if s == b"clamp" {
            Ok(Context3DWrapMode::Clamp)
        } else if s == b"clamp_u_repeat_v" {
            Ok(Context3DWrapMode::ClampURepeatV)
        } else if s == b"repeat" {
            Ok(Context3DWrapMode::Repeat)
        } else if s == b"repeat_u_clamp_v" {
            Ok(Context3DWrapMode::RepeatUClampV)
        } else {
            Err(())
        }
    }
}

#[derive(Copy, Clone, Debug)]
pub enum Context3DTextureFilter {
    Anisotropic16X,
    Anisotropic2X,
    Anisotropic4X,
    Anisotropic8X,
    Linear,
    Nearest,
}

impl FromWStr for Context3DTextureFilter {
    type Err = ();

    fn from_wstr(s: &WStr) -> Result<Self, Self::Err> {
        if s == b"anisotropic16x" {
            Ok(Context3DTextureFilter::Anisotropic16X)
        } else if s == b"anisotropic2x" {
            Ok(Context3DTextureFilter::Anisotropic2X)
        } else if s == b"anisotropic4x" {
            Ok(Context3DTextureFilter::Anisotropic4X)
        } else if s == b"anisotropic8x" {
            Ok(Context3DTextureFilter::Anisotropic8X)
        } else if s == b"linear" {
            Ok(Context3DTextureFilter::Linear)
        } else if s == b"nearest" {
            Ok(Context3DTextureFilter::Nearest)
        } else {
            Err(())
        }
    }
}
// Timffle: `Context3D.setSamplerStateAt` mipfilter ("mipnone" / "mipnearest" /
// "miplinear"). Textures carry a full mip chain, so the filter is real.
#[derive(Copy, Clone, Debug, PartialEq, Eq)]
pub enum Context3DMipFilter {
    None,
    Nearest,
    Linear,
}

impl FromWStr for Context3DMipFilter {
    type Err = ();

    fn from_wstr(s: &WStr) -> Result<Self, Self::Err> {
        if s == b"mipnone" {
            Ok(Context3DMipFilter::None)
        } else if s == b"mipnearest" {
            Ok(Context3DMipFilter::Nearest)
        } else if s == b"miplinear" {
            Ok(Context3DMipFilter::Linear)
        } else {
            Err(())
        }
    }
}

pub enum Context3DCommand<'a> {
    Clear {
        red: f64,
        green: f64,
        blue: f64,
        alpha: f64,
        depth: f64,
        stencil: u32,
        mask: u32,
    },
    ConfigureBackBuffer {
        width: u32,
        height: u32,
        anti_alias: u32,
        depth_and_stencil: bool,
        wants_best_resolution: bool,
        wants_best_resolution_on_browser_zoom: bool,
    },
    SetRenderToTexture {
        texture: Rc<dyn Texture>,
        enable_depth_and_stencil: bool,
        anti_alias: u32,
        surface_selector: u32,
        // Timffle: colour output 0..3 (multiple render targets); the caller
        // has checked the range, the profile and that the sizes match.
        color_output_index: u32,
    },
    SetRenderToBackBuffer,

    UploadToIndexBuffer {
        buffer: &'a mut dyn IndexBuffer,
        start_offset: usize,
        data: &'a [u8],
    },

    UploadToVertexBuffer {
        buffer: Rc<dyn VertexBuffer>,
        start_vertex: usize,
        data32_per_vertex: u8,
        data: &'a [u8],
    },

    DrawTriangles {
        index_buffer: &'a dyn IndexBuffer,
        first_index: usize,
        num_triangles: isize,
    },

    SetVertexBufferAt {
        index: u32,
        buffer: Option<(Rc<dyn VertexBuffer>, Context3DVertexBufferFormat)>,
        buffer_offset: u32,
    },

    SetShaders {
        module: Option<Rc<dyn ShaderModule>>,
    },
    SetProgramConstants {
        program_type: ProgramType,
        first_register: u32,
        matrix_raw_data_column_major: &'a [[u8; 4]],
    },
    SetCulling {
        face: Context3DTriangleFace,
    },
    CopyBitmapToTexture {
        source: &'a [u8],
        source_width: u32,
        source_height: u32,
        dest: Rc<dyn Texture>,
        layer: u32,
        // Timffle: the mip level written (`miplevel` of the upload* methods).
        mip_level: u32,
    },
    SetTextureAt {
        sampler: u32,
        texture: Option<Rc<dyn Texture>>,
        cube: bool,
    },
    SetColorMask {
        red: bool,
        green: bool,
        blue: bool,
        alpha: bool,
    },
    SetDepthTest {
        depth_mask: bool,
        pass_compare_mode: Context3DCompareMode,
    },
    SetBlendFactors {
        source_factor: Context3DBlendFactor,
        destination_factor: Context3DBlendFactor,
    },
    SetSamplerStateAt {
        sampler: u32,
        wrap: Context3DWrapMode,
        filter: Context3DTextureFilter,
        // Timffle
        mip_filter: Context3DMipFilter,
    },
    SetScissorRectangle {
        rect: Option<Rectangle<Twips>>,
    },
    SetStencilActions {
        triangle_face: Context3DTriangleFace,
        compare_mode: Context3DCompareMode,
        on_both_pass: Context3DStencilAction,
        on_depth_fail: Context3DStencilAction,
        on_depth_pass_stencil_fail: Context3DStencilAction,
    },
    SetStencilReferenceValue {
        reference_value: u32,
        read_mask: u32,
        write_mask: u32,
    },
}

#[derive(Clone, Debug)]
pub struct ShapeHandle(pub Arc<dyn ShapeHandleImpl>);

pub trait ShapeHandleImpl: Any + Debug {}

#[derive(Copy, Clone, Debug)]
#[cfg_attr(feature = "serde", derive(serde::Serialize, serde::Deserialize))]
#[cfg_attr(feature = "serde", serde(deny_unknown_fields))]
pub struct ViewportDimensions {
    /// The dimensions of the stage's containing viewport.
    pub width: u32,
    pub height: u32,

    /// The scale factor of the containing viewport from standard-size pixels
    /// to device-scale pixels.
    pub scale_factor: f64,
}
