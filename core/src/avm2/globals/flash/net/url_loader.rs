//! `flash.net.URLLoader` native function definitions

use crate::avm2::activation::Activation;
use crate::avm2::function::FunctionArgs;
use crate::avm2::globals::flash::display::loader::request_from_url_request;
use crate::avm2::parameters::ParametersExt;
use crate::avm2::value::Value;
use crate::avm2::{Error, Object};

/// Native function definition for `URLLoader._load`: starts a download whose events and `data`
/// are delivered when it finishes, unless `close()` or a later `load()` supersedes it first.
pub fn _load<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    let request = args.get_object(activation, 0, "request")?;
    let generation = args.get_u32(1);

    spawn_fetch(activation, this, request, generation)
}

fn spawn_fetch<'gc>(
    activation: &mut Activation<'_, 'gc>,
    loader_object: Object<'gc>,
    url_request: Object<'gc>,
    generation: u32,
) -> Result<Value<'gc>, Error<'gc>> {
    let request = request_from_url_request(activation, url_request)?;

    let future = crate::loader::load_data_into_url_loader(
        activation.context,
        loader_object.as_script_object().unwrap(),
        request,
        generation,
    );
    activation.context.navigator.spawn_future(future);
    Ok(Value::Undefined)
}
