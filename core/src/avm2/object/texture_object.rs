//! Object representation for Texture3D objects

use crate::avm2::Error;
use crate::avm2::activation::Activation;
use crate::avm2::object::script_object::ScriptObjectData;
use crate::avm2::object::{Object, TObject};
use gc_arena::{Collect, Gc, GcWeak};
use ruffle_common::utils::HasPrefixField;
use ruffle_render::backend::{Context3DTextureFormat, Texture};
use std::cell::RefCell;
use std::rc::Rc;

use super::{ClassObject, Context3DObject};

#[derive(Clone, Collect, Copy)]
#[collect(no_drop)]
pub struct TextureObject<'gc>(pub Gc<'gc, TextureObjectData<'gc>>);

#[derive(Clone, Collect, Copy, Debug)]
#[collect(no_drop)]
pub struct TextureObjectWeak<'gc>(pub GcWeak<'gc, TextureObjectData<'gc>>);

impl<'gc> TextureObject<'gc> {
    pub fn from_handle(
        activation: &mut Activation<'_, 'gc>,
        context3d: Context3DObject<'gc>,
        handle: Rc<dyn Texture>,
        original_format: Context3DTextureFormat,
        class: ClassObject<'gc>,
        gpu_size: u64,
    ) -> Object<'gc> {
        TextureObject(Gc::new(
            activation.gc(),
            TextureObjectData {
                base: ScriptObjectData::new(class),
                context3d,
                original_format,
                handle: RefCell::new(Some(handle)),
                gpu_size,
            },
        ))
        .into()
    }

    pub fn original_format(self) -> Context3DTextureFormat {
        self.0.original_format
    }

    pub fn handle(self) -> Rc<dyn Texture> {
        self.0
            .handle
            .borrow()
            .clone()
            .expect("Texture was disposed")
    }

    // Timffle: dispose() drops the GPU texture; later calls throw Error #3694.
    pub fn is_disposed(self) -> bool {
        self.0.handle.borrow().is_none()
    }

    pub fn check_disposed(self, activation: &mut Activation<'_, 'gc>) -> Result<(), Error<'gc>> {
        if self.is_disposed() {
            Err(crate::avm2::error::make_error_3694(activation))
        } else {
            Ok(())
        }
    }

    pub fn dispose(self) {
        if self.0.handle.take().is_some() {
            self.0.context3d.sub_gpu_memory(self.0.gpu_size);
        }
    }

    pub fn context3d(self) -> Context3DObject<'gc> {
        self.0.context3d
    }
}

#[derive(Collect, HasPrefixField)]
#[collect(no_drop)]
#[repr(C, align(8))]
pub struct TextureObjectData<'gc> {
    /// Base script object
    base: ScriptObjectData<'gc>,

    context3d: Context3DObject<'gc>,

    #[collect(require_static)]
    original_format: Context3DTextureFormat,

    #[collect(require_static)]
    handle: RefCell<Option<Rc<dyn Texture>>>,

    // Timffle: bytes counted in Context3D.totalGPUMemory.
    gpu_size: u64,
}

impl<'gc> TObject<'gc> for TextureObject<'gc> {
    fn gc_base(&self) -> Gc<'gc, ScriptObjectData<'gc>> {
        HasPrefixField::as_prefix_gc(self.0)
    }
}

impl std::fmt::Debug for TextureObject<'_> {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "Texture3D")
    }
}
