//! `flash.system.Worker` native methods

use crate::avm2::Error;
use crate::avm2::activation::Activation;
use crate::avm2::function::FunctionArgs;
use crate::avm2::object::{MessageChannelObject, WorkerObject};
use crate::avm2::value::Value;

/// Timffle: `Worker.createMessageChannel` is written in Worker.as; this
/// makes the bare `MessageChannel` object for it (the class is abstract),
/// which the AS side then initialises.
pub fn instantiate_message_channel<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let message_channel = MessageChannelObject::new(activation);

    Ok(message_channel.into())
}

pub fn instantiate_internal<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let worker = WorkerObject::new(activation);

    Ok(worker.into())
}
