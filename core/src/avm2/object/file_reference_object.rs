use crate::avm2::object::script_object::ScriptObjectData;
use crate::avm2::object::{ClassObject, Object, TObject};
use crate::avm2::{Activation, Error};
use crate::backend::ui::FileDialogSelection;
use crate::context::UpdateContext;
use gc_arena::{Collect, DynamicRoot, Gc, GcWeak, Rootable};
use ruffle_common::utils::HasPrefixField;
use std::cell::{Cell, Ref, RefCell};
use std::fmt;

pub fn file_reference_allocator<'gc>(
    class: ClassObject<'gc>,
    activation: &mut Activation<'_, 'gc>,
) -> Result<Object<'gc>, Error<'gc>> {
    let base = ScriptObjectData::new(class);

    Ok(FileReferenceObject(Gc::new(
        activation.gc(),
        FileReferenceObjectData {
            base,
            reference: RefCell::new(FileReference::None),
            loaded: Cell::new(false),
            generation: Cell::new(0),
        },
    ))
    .into())
}

#[derive(Clone, Collect, Copy)]
#[collect(no_drop)]
pub struct FileReferenceObject<'gc>(pub Gc<'gc, FileReferenceObjectData<'gc>>);

#[derive(Clone, Collect, Copy, Debug)]
#[collect(no_drop)]
pub struct FileReferenceObjectWeak<'gc>(pub GcWeak<'gc, FileReferenceObjectData<'gc>>);

#[derive(Clone)]
pub struct FileReferenceObjectHandle(DynamicRoot<Rootable![FileReferenceObjectData<'_>]>);

impl FileReferenceObjectHandle {
    pub fn stash<'gc>(context: &UpdateContext<'gc>, this: FileReferenceObject<'gc>) -> Self {
        Self(context.dynamic_root.stash(context.gc(), this.0))
    }

    pub fn fetch<'gc>(&self, context: &UpdateContext<'gc>) -> FileReferenceObject<'gc> {
        FileReferenceObject(context.dynamic_root.fetch(&self.0))
    }
}

impl<'gc> TObject<'gc> for FileReferenceObject<'gc> {
    fn gc_base(&self) -> Gc<'gc, ScriptObjectData<'gc>> {
        HasPrefixField::as_prefix_gc(self.0)
    }
}

impl FileReferenceObject<'_> {
    pub fn init_from_file_selection(
        self,
        selection: Box<dyn FileDialogSelection>,
    ) -> FileReference {
        self.0
            .reference
            .replace(FileReference::FileDialogSelection(selection))
    }

    pub fn file_reference(&self) -> Ref<'_, FileReference> {
        self.0.reference.borrow()
    }

    /// Timffle: takes the selection out (leaving `None`), e.g. to write downloaded data into it.
    pub fn take_file_reference(self) -> FileReference {
        self.0.reference.replace(FileReference::None)
    }

    /// Timffle: the current operation number; `cancel()` bumps it so a running download or
    /// upload stops reporting (see `loader::download_file_dialog_avm2`).
    pub fn generation(self) -> u32 {
        self.0.generation.get()
    }

    pub fn cancel_operations(self) {
        self.0
            .generation
            .set(self.0.generation.get().wrapping_add(1));
    }

    pub fn set_loaded(self, value: bool) {
        self.0.loaded.set(value)
    }

    pub fn loaded(self) -> bool {
        self.0.loaded.get()
    }
}

pub enum FileReference {
    None,
    FileDialogSelection(Box<dyn FileDialogSelection>),
}

#[derive(Collect, HasPrefixField)]
#[collect(no_drop)]
#[repr(C, align(8))]
pub struct FileReferenceObjectData<'gc> {
    /// Base script object
    base: ScriptObjectData<'gc>,

    reference: RefCell<FileReference>,

    loaded: Cell<bool>,

    /// Timffle: see [`FileReferenceObject::generation`].
    generation: Cell<u32>,
}

impl fmt::Debug for FileReferenceObject<'_> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "FileReferenceObject")
    }
}
