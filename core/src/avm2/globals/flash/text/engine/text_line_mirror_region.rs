//! `flash.text.engine.TextLineMirrorRegion` natives

use crate::avm2::function::FunctionArgs;
use crate::avm2::object::construct_abstract_class;
use crate::avm2::{Activation, Error, Value};

/// Timffle: makes a region for `TextLine.mirrorRegions`. The class is
/// abstract to ActionScript (`new TextLineMirrorRegion()` is #2012 before any
/// constructor runs, as in Flash Player).
pub fn create<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let class = this
        .as_object()
        .and_then(|this| this.as_class_object())
        .expect("TextLineMirrorRegion.create is called on the class");

    Ok(construct_abstract_class(activation, class, &[])?.into())
}
