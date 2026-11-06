//! Timffle: the AVM2 object behind `flash.text.TextSnapshot`.

use crate::avm2::Error;
use crate::avm2::activation::Activation;
use crate::avm2::object::script_object::ScriptObjectData;
use crate::avm2::object::{ClassObject, Object, TObject};
use crate::display_object::{DisplayObjectContainer, TextSnapshot};
use core::fmt;
use gc_arena::barrier::unlock;
use gc_arena::lock::Lock;
use gc_arena::{Collect, Gc, GcWeak};
use ruffle_common::utils::HasPrefixField;

/// A class instance allocator that allocates TextSnapshot objects.
///
/// `new TextSnapshot()` from ActionScript makes an empty snapshot (no text);
/// `DisplayObjectContainer.textSnapshot` fills one in through
/// [`TextSnapshotObject::set_target`].
pub fn text_snapshot_allocator<'gc>(
    class: ClassObject<'gc>,
    activation: &mut Activation<'_, 'gc>,
) -> Result<Object<'gc>, Error<'gc>> {
    let base = ScriptObjectData::new(class);

    Ok(TextSnapshotObject(Gc::new(
        activation.gc(),
        TextSnapshotObjectData {
            base,
            snapshot: Lock::new(None),
        },
    ))
    .into())
}

#[derive(Clone, Collect, Copy)]
#[collect(no_drop)]
pub struct TextSnapshotObject<'gc>(pub Gc<'gc, TextSnapshotObjectData<'gc>>);

#[derive(Clone, Collect, Copy, Debug)]
#[collect(no_drop)]
pub struct TextSnapshotObjectWeak<'gc>(pub GcWeak<'gc, TextSnapshotObjectData<'gc>>);

impl fmt::Debug for TextSnapshotObject<'_> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("TextSnapshotObject")
            .field("ptr", &Gc::as_ptr(self.0))
            .finish()
    }
}

#[derive(Collect, HasPrefixField)]
#[collect(no_drop)]
#[repr(C, align(8))]
pub struct TextSnapshotObjectData<'gc> {
    /// Base script object
    base: ScriptObjectData<'gc>,

    /// The static texts this snapshot covers; `None` for `new TextSnapshot()`.
    snapshot: Lock<Option<TextSnapshot<'gc>>>,
}

impl<'gc> TObject<'gc> for TextSnapshotObject<'gc> {
    fn gc_base(&self) -> Gc<'gc, ScriptObjectData<'gc>> {
        HasPrefixField::as_prefix_gc(self.0)
    }
}

impl<'gc> TextSnapshotObject<'gc> {
    /// Points this snapshot at the static texts that are children of `target`
    /// right now.
    pub fn set_target(
        self,
        activation: &mut Activation<'_, 'gc>,
        target: DisplayObjectContainer<'gc>,
    ) {
        let snapshot = TextSnapshot::new(activation.context, target);
        unlock!(
            Gc::write(activation.gc(), self.0),
            TextSnapshotObjectData,
            snapshot
        )
        .set(Some(snapshot));
    }

    pub fn snapshot(self) -> Option<TextSnapshot<'gc>> {
        self.0.snapshot.get()
    }
}
