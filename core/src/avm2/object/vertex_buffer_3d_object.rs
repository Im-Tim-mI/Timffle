//! Object representation for VertexBuffer3D objects

use crate::avm2::Error;
use crate::avm2::activation::Activation;
use crate::avm2::object::script_object::ScriptObjectData;
use crate::avm2::object::{Object, TObject};
use gc_arena::{Collect, Gc, GcWeak};
use ruffle_common::utils::HasPrefixField;
use ruffle_render::backend::VertexBuffer;
use std::cell::RefCell;
use std::rc::Rc;

use super::Context3DObject;

#[derive(Clone, Collect, Copy)]
#[collect(no_drop)]
pub struct VertexBuffer3DObject<'gc>(pub Gc<'gc, VertexBuffer3DObjectData<'gc>>);

#[derive(Clone, Collect, Copy, Debug)]
#[collect(no_drop)]
pub struct VertexBuffer3DObjectWeak<'gc>(pub GcWeak<'gc, VertexBuffer3DObjectData<'gc>>);

impl<'gc> VertexBuffer3DObject<'gc> {
    pub fn from_handle(
        activation: &mut Activation<'_, 'gc>,
        context3d: Context3DObject<'gc>,
        handle: Rc<dyn VertexBuffer>,
        data32_per_vertex: u8,
        gpu_size: u64,
    ) -> Object<'gc> {
        let class = activation.avm2().classes().vertexbuffer3d;

        VertexBuffer3DObject(Gc::new(
            activation.gc(),
            VertexBuffer3DObjectData {
                base: ScriptObjectData::new(class),
                context3d,
                handle: RefCell::new(Some(handle)),
                data32_per_vertex,
                gpu_size,
            },
        ))
        .into()
    }

    pub fn handle(self) -> Rc<dyn VertexBuffer> {
        self.0
            .handle
            .borrow()
            .clone()
            .expect("VertexBuffer3D was disposed")
    }

    // Timffle: dispose() drops the GPU buffer; later calls throw Error #3694.
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

    pub fn data32_per_vertex(self) -> u8 {
        self.0.data32_per_vertex
    }
}

#[derive(Collect, HasPrefixField)]
#[collect(no_drop)]
#[repr(C, align(8))]
pub struct VertexBuffer3DObjectData<'gc> {
    /// Base script object
    base: ScriptObjectData<'gc>,

    context3d: Context3DObject<'gc>,

    #[collect(require_static)]
    handle: RefCell<Option<Rc<dyn VertexBuffer>>>,

    // Timffle: bytes counted in Context3D.totalGPUMemory.
    gpu_size: u64,

    /// The 'data32PerVertex' value that this object was created with.
    /// This is the number of 32-bit values associated with each vertex,
    /// and is at most 64
    data32_per_vertex: u8,
}

impl<'gc> TObject<'gc> for VertexBuffer3DObject<'gc> {
    fn gc_base(&self) -> Gc<'gc, ScriptObjectData<'gc>> {
        HasPrefixField::as_prefix_gc(self.0)
    }
}

impl std::fmt::Debug for VertexBuffer3DObject<'_> {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "VertexBuffer3D")
    }
}
