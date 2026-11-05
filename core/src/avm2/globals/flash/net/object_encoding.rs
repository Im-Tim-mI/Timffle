use crate::avm2::Error;
use crate::avm2::activation::Activation;
use crate::avm2::function::FunctionArgs;
use crate::avm2::parameters::ParametersExt;
use crate::avm2::value::Value;

/// Timffle: `ObjectEncoding.dynamicPropertyWriter` (null until set); see
/// `crate::avm2::amf` for where the serializer consults it.
pub fn get_dynamic_property_writer<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    Ok(activation
        .avm2()
        .dynamic_property_writer
        .map_or(Value::Null, Value::from))
}

pub fn set_dynamic_property_writer<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    // The AS3 signature already rejects non-IDynamicPropertyWriter values (#1034).
    let writer = args.try_get_object(0);
    activation.avm2().dynamic_property_writer = writer;
    Ok(Value::Undefined)
}
