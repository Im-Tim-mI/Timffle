//! Timffle: `flash.sampler` package natives.

use crate::avm2::Error;
use crate::avm2::activation::Activation;
use crate::avm2::function::FunctionArgs;
use crate::avm2::value::Value;

/// Implements `flash.sampler.getSamples`: the release player has no sampler, and Flash
/// Player 32 returns `undefined` (measured), which an ActionScript `Object` return type
/// could not carry.
pub fn get_samples<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    Ok(Value::Undefined)
}
