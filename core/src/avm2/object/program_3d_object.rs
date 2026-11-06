//! Object representation for VertexBuffer3D objects

use crate::avm2::Error;
use crate::avm2::activation::Activation;
use crate::avm2::object::script_object::ScriptObjectData;
use crate::avm2::object::{Object, TObject};
use gc_arena::{Collect, Gc, GcWeak};
use ruffle_common::utils::HasPrefixField;
use ruffle_render::backend::ShaderModule;
use std::cell::{Cell, RefCell};
use std::rc::Rc;

use super::Context3DObject;

#[derive(Clone, Collect, Copy)]
#[collect(no_drop)]
pub struct Program3DObject<'gc>(pub Gc<'gc, Program3DObjectData<'gc>>);

#[derive(Clone, Collect, Copy, Debug)]
#[collect(no_drop)]
pub struct Program3DObjectWeak<'gc>(pub GcWeak<'gc, Program3DObjectData<'gc>>);

impl<'gc> Program3DObject<'gc> {
    pub fn from_context(
        activation: &mut Activation<'_, 'gc>,
        context3d: Context3DObject<'gc>,
    ) -> Object<'gc> {
        let class = activation.avm2().classes().program3d;
        let base = ScriptObjectData::new(class);

        Program3DObject(Gc::new(
            activation.gc(),
            Program3DObjectData {
                base,
                context3d,
                shader_module_handle: RefCell::new(None),
                disposed: Cell::new(false),
                gpu_size: Cell::new(0),
            },
        ))
        .into()
    }

    pub fn shader_module_handle(&self) -> &RefCell<Option<Rc<dyn ShaderModule>>> {
        &self.0.shader_module_handle
    }

    pub fn context3d(self) -> Context3DObject<'gc> {
        self.0.context3d
    }

    // Timffle: dispose() drops the shader module; later calls throw Error #3694.
    pub fn check_disposed(self, activation: &mut Activation<'_, 'gc>) -> Result<(), Error<'gc>> {
        if self.0.disposed.get() {
            Err(crate::avm2::error::make_error_3694(activation))
        } else {
            Ok(())
        }
    }

    pub fn dispose(self) {
        self.0.disposed.set(true);
        self.0.shader_module_handle.replace(None);
        self.0.context3d.sub_gpu_memory(self.0.gpu_size.replace(0));
    }

    /// Records the uploaded program size for Context3D.totalGPUMemory.
    pub fn set_gpu_size(self, bytes: u64) {
        let old = self.0.gpu_size.replace(bytes);
        self.0.context3d.sub_gpu_memory(old);
        self.0.context3d.add_gpu_memory(bytes);
    }
}

#[derive(Collect, HasPrefixField)]
#[collect(no_drop)]
#[repr(C, align(8))]
pub struct Program3DObjectData<'gc> {
    /// Base script object
    base: ScriptObjectData<'gc>,

    context3d: Context3DObject<'gc>,

    shader_module_handle: RefCell<Option<Rc<dyn ShaderModule>>>,

    // Timffle: see `dispose`.
    disposed: Cell<bool>,
    gpu_size: Cell<u64>,
}

impl<'gc> TObject<'gc> for Program3DObject<'gc> {
    fn gc_base(&self) -> Gc<'gc, ScriptObjectData<'gc>> {
        HasPrefixField::as_prefix_gc(self.0)
    }
}

impl std::fmt::Debug for Program3DObject<'_> {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "Program3D")
    }
}
