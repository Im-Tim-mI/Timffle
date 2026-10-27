use crate::avm2::Error;
use crate::avm2::activation::Activation;
use crate::avm2::object::script_object::ScriptObjectData;
use crate::avm2::object::{ClassObject, Object, TObject};
use crate::context::UpdateContext;
use crate::display_object::{DisplayObject, TDisplayObject};
use core::fmt;
use gc_arena::barrier::unlock;
use gc_arena::lock::Lock;
use gc_arena::{Collect, Gc, GcWeak};
use ruffle_common::utils::HasPrefixField;
use ruffle_render::matrix3d::Matrix3D;
use std::cell::{Ref, RefCell, RefMut};
use std::ops::{Deref, DerefMut};

/// A class instance allocator that allocates Matrix3D objects.
pub fn matrix_3d_allocator<'gc>(
    class: ClassObject<'gc>,
    activation: &mut Activation<'_, 'gc>,
) -> Result<Object<'gc>, Error<'gc>> {
    let base = ScriptObjectData::new(class);

    Ok(Matrix3DObject(Gc::new(
        activation.gc(),
        Matrix3DObjectData {
            base,
            matrix: RefCell::new(Matrix3D::IDENTITY),
            owner: Lock::new(None),
        },
    ))
    .into())
}

#[derive(Clone, Collect, Copy)]
#[collect(no_drop)]
pub struct Matrix3DObject<'gc>(pub Gc<'gc, Matrix3DObjectData<'gc>>);

#[derive(Clone, Collect, Copy, Debug)]
#[collect(no_drop)]
pub struct Matrix3DObjectWeak<'gc>(pub GcWeak<'gc, Matrix3DObjectData<'gc>>);

impl fmt::Debug for Matrix3DObject<'_> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("Matrix3DObject")
            .field("ptr", &Gc::as_ptr(self.0))
            .finish()
    }
}

#[derive(Collect, HasPrefixField)]
#[collect(no_drop)]
#[repr(C, align(8))]
pub struct Matrix3DObjectData<'gc> {
    /// Base script object.
    base: ScriptObjectData<'gc>,

    matrix: RefCell<Matrix3D>,

    /// The display object whose `transform.matrix3D` this is. Like in Flash Player, such a matrix is a live view
    /// of the object's own: changing it moves the object, and the object's changes show in it. While the owner
    /// is not 3D (any more), `matrix` is used on its own.
    owner: Lock<Option<DisplayObject<'gc>>>,
}

impl<'gc> Matrix3DObject<'gc> {
    pub fn new(context: &mut UpdateContext<'gc>, matrix: Matrix3D) -> Matrix3DObject<'gc> {
        let class = context.avm2.classes().matrix3d;
        let base = ScriptObjectData::new(class);
        Matrix3DObject(Gc::new(
            context.gc(),
            Matrix3DObjectData {
                base,
                matrix: RefCell::new(matrix),
                owner: Lock::new(None),
            },
        ))
    }

    /// The display object that this matrix is the live `transform.matrix3D` of, if any.
    pub fn owner(self) -> Option<DisplayObject<'gc>> {
        self.0.owner.get()
    }

    /// Makes this matrix the live `transform.matrix3D` of `owner`.
    pub fn bind_to(self, context: &UpdateContext<'gc>, owner: DisplayObject<'gc>) {
        let write = Gc::write(context.gc(), self.0);
        unlock!(write, Matrix3DObjectData, owner).set(Some(owner));
    }

    /// Takes the owner's current 3D matrix, if the object is still 3D.
    fn refresh_from_owner(&self) {
        if let Some(owner) = self.0.owner.get()
            && let Some(matrix) = owner.base().matrix3d()
            && let Ok(mut current) = self.0.matrix.try_borrow_mut()
        {
            // A live borrow (a method whose argument is this very matrix, like `m.append(m)`) was taken
            // right after a refresh and nothing has moved the owner since, so it is already current.
            *current = matrix;
        }
    }

    /// Gives the owner (if it is still 3D) the matrix that this object now holds.
    fn push_to_owner(&self, matrix: Matrix3D) {
        if let Some(owner) = self.0.owner.get()
            && owner.base().has_matrix3d()
        {
            owner.base().set_matrix3d(Some(matrix));
            if let Some(parent) = owner.parent() {
                parent.invalidate_cached_bitmap();
            }
        }
    }

    pub fn matrix_ref(&self) -> Ref<'_, Matrix3D> {
        self.refresh_from_owner();
        self.0.matrix.borrow()
    }

    /// Mutable access to the matrix; what it holds when the guard goes away is passed on to the owner.
    pub fn matrix_mut(&self) -> Matrix3DGuard<'_, 'gc> {
        self.refresh_from_owner();
        Matrix3DGuard {
            object: self,
            matrix: Some(self.0.matrix.borrow_mut()),
        }
    }

    pub fn matrix(self) -> Matrix3D {
        *self.matrix_ref()
    }

    pub fn replace_matrix(self, matrix: Matrix3D) -> Matrix3D {
        self.refresh_from_owner();
        let old = self.0.matrix.replace(matrix);
        self.push_to_owner(matrix);
        old
    }
}

/// A mutable borrow of a [`Matrix3DObject`]'s matrix that updates the display object it belongs to when it ends.
pub struct Matrix3DGuard<'a, 'gc> {
    object: &'a Matrix3DObject<'gc>,
    matrix: Option<RefMut<'a, Matrix3D>>,
}

impl Deref for Matrix3DGuard<'_, '_> {
    type Target = Matrix3D;

    fn deref(&self) -> &Matrix3D {
        self.matrix.as_deref().expect("guard is alive")
    }
}

impl DerefMut for Matrix3DGuard<'_, '_> {
    fn deref_mut(&mut self) -> &mut Matrix3D {
        self.matrix.as_deref_mut().expect("guard is alive")
    }
}

impl Drop for Matrix3DGuard<'_, '_> {
    fn drop(&mut self) {
        if let Some(matrix) = self.matrix.take() {
            let value = *matrix;
            drop(matrix);
            self.object.push_to_owner(value);
        }
    }
}

impl<'gc> TObject<'gc> for Matrix3DObject<'gc> {
    fn gc_base(&self) -> Gc<'gc, ScriptObjectData<'gc>> {
        HasPrefixField::as_prefix_gc(self.0)
    }
}
