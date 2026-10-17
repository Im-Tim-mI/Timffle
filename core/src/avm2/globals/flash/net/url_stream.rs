//! `flash.net.URLStream` native function definitions

use crate::avm2::Error;
use crate::avm2::activation::Activation;
use crate::avm2::function::FunctionArgs;
use crate::avm2::globals::flash::display::loader::request_from_url_request;
use crate::avm2::parameters::ParametersExt;
use crate::avm2::value::Value;

/// Native function definition for `URLStream._load`: starts a streaming
/// download whose data and events are delivered as chunks arrive.
pub fn _load<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    let request = args.get_object(activation, 0, "request")?;
    let generation = args.get_u32(1);
    let mut request = request_from_url_request(activation, request)?;
    request.preserve_error_body = true;

    let future = crate::loader::load_url_stream(
        activation.context,
        this.as_script_object().unwrap(),
        request,
        generation,
    );
    activation.context.navigator.spawn_future(future);
    Ok(Value::Undefined)
}
