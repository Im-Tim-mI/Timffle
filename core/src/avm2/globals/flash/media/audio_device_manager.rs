//! Timffle: `flash.media.AudioDeviceManager` natives.

use crate::avm2::function::FunctionArgs;
use crate::avm2::{Activation, Error, Value};

/// Whether a user event (mouse, keyboard) is being handled right now: the
/// reference puts `selectedDeviceIndex` under the user-invoked-action
/// restriction (`IllegalOperationError #2176` otherwise), the same flag
/// `System.setClipboard` and `Clipboard` use.
pub fn is_user_invoked<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    Ok(activation.avm2().in_user_interaction.into())
}
