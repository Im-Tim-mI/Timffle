//! `flash.net.drm.DRMManager` natives

use crate::avm2::function::FunctionArgs;
use crate::avm2::object::construct_abstract_class;
use crate::avm2::{Activation, Error, Value};

/// Timffle: makes the `DRMManager` singleton. The class is abstract to
/// ActionScript (`new DRMManager()` is #2012 before any constructor runs,
/// as in Flash Player), so `getDRMManager()` asks for its instance here.
pub fn create_instance<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let class = this
        .as_object()
        .and_then(|this| this.as_class_object())
        .expect("DRMManager.createInstance is called on the class");

    Ok(construct_abstract_class(activation, class, &[])?.into())
}
