//! `flash.ui.Keyboard` builtin/prototype

use crate::avm2::Error;
use crate::avm2::activation::Activation;
use crate::avm2::function::FunctionArgs;
use crate::avm2::value::Value;
use crate::avm2_stub_getter;
use crate::events::KeyCode;
use crate::string::AvmString;
use crate::system_properties::TouchscreenType;

// Timffle: the lock state the player tracks from the key events it receives (the lock keys
// toggle it, typed letters and numpad keys correct it; see `InputManager::infer_lock_state`).
// This is the same state AVM1's `Key.isToggled(Key.CAPSLOCK)` reports.
pub fn get_caps_lock<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    Ok(activation
        .context
        .input
        .is_key_toggled(KeyCode::CAPS_LOCK)
        .into())
}

// Timffle: a virtual (on-screen) keyboard is a property of touch devices; this player reports
// `Capabilities.touchscreenType` "none" on every host it runs on (no touch input reaches it as
// touch), and a host without a touchscreen has no virtual keyboard, exactly like desktop Flash
// Player. Derived from the same system property so the two can never disagree.
pub fn get_has_virtual_keyboard<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let touchscreen = !matches!(
        activation.context.system.touchscreen_type,
        TouchscreenType::None
    );
    Ok(touchscreen.into())
}

// Timffle: see `get_caps_lock`.
pub fn get_num_lock<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    Ok(activation
        .context
        .input
        .is_key_toggled(KeyCode::NUM_LOCK)
        .into())
}

// Timffle: `KeyboardType.ALPHANUMERIC` on a host without a touchscreen (a desktop or browser
// with a physical keyboard, what desktop Flash Player reports); a touch-only host (the
// `touchscreenType` "finger" case, never reported by this player today) has no physical
// keyboard, `KeyboardType.NONE`.
pub fn get_physical_keyboard_type<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let keyboard_type: &'static [u8] = match activation.context.system.touchscreen_type {
        TouchscreenType::None | TouchscreenType::Stylus => b"alphanumeric",
        TouchscreenType::Finger => b"none",
    };
    Ok(AvmString::new_ascii_static(activation.gc(), keyboard_type).into())
}

pub fn is_accessible<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    avm2_stub_getter!(activation, "flash.ui.Keyboard", "isAccessible");
    Ok(true.into())
}
