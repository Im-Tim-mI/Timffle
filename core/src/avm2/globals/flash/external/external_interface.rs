use crate::avm2::error::make_error_2067;
use crate::avm2::function::FunctionArgs;
use crate::avm2::parameters::ParametersExt;
use crate::avm2::{Activation, Error, Value};
use crate::external::{Callback, ExternalInterface, Value as ExternalValue};
use crate::string::AvmString;

pub fn call<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let name = args.get_string(activation, 0);
    check_available(activation)?;

    let external_args = args
        .iter()
        .skip(1)
        .map(|arg| ExternalValue::from_avm2(activation, arg.to_owned()))
        .collect::<Result<Vec<ExternalValue>, Error>>()?;

    let name = name.to_utf8_lossy();
    let result = if activation.context.external_interface.marshall_exceptions() {
        // Timffle: a container exception is rethrown here as an Error.
        match ExternalInterface::call_method_checked(activation.context, &name, &external_args) {
            Ok(result) => result,
            Err(message) => {
                let message = AvmString::new_utf8(activation.gc(), message);
                let error = activation
                    .avm2()
                    .classes()
                    .error
                    .construct(activation, &[message.into(), 0.into()])?;
                return Err(Error::from_value(activation, error));
            }
        }
    } else {
        ExternalInterface::call_method(activation.context, &name, &external_args)
    };

    Ok(result.into_avm2(activation.context))
}

/// Timffle: `ExternalInterface.marshallExceptions` getter.
pub fn get_marshall_exceptions<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    Ok(activation
        .context
        .external_interface
        .marshall_exceptions()
        .into())
}

/// Timffle: `ExternalInterface.marshallExceptions` setter.
pub fn set_marshall_exceptions<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let value = args.get_bool(0);
    activation
        .context
        .external_interface
        .set_marshall_exceptions(value);
    Ok(Value::Undefined)
}

fn check_available<'gc>(activation: &mut Activation<'_, 'gc>) -> Result<(), Error<'gc>> {
    if !activation.context.external_interface.available() {
        return Err(make_error_2067(activation));
    }
    Ok(())
}

pub fn get_available<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    Ok(activation.context.external_interface.available().into())
}

pub fn add_callback<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let name = args.get_string(activation, 0);
    let callback = args.try_get_function(1);

    check_available(activation)?;

    if let Some(method) = callback {
        activation
            .context
            .external_interface
            .add_callback(name.to_string(), Callback::Avm2 { method });
    } else {
        activation
            .context
            .external_interface
            .remove_callback(name.to_string());
    }

    Ok(Value::Undefined)
}

pub fn get_object_id<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    if let Some(id) = activation.context.external_interface.get_id() {
        Ok(AvmString::new_utf8(activation.gc(), id).into())
    } else {
        Ok(Value::Null)
    }
}
