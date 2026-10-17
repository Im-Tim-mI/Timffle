use crate::avm2::amf::{amf3_values_len, serialize_value};
use crate::avm2::error::{
    Error2004Type, make_error_2004, make_error_2082, make_error_2083, make_error_2084,
    make_error_2085,
};
use crate::avm2::function::FunctionArgs;
use crate::avm2::parameters::ParametersExt;
use crate::avm2::{Activation, Error, Value};
use crate::string::AvmString;
use flash_lso::types::AMFVersion;
use std::rc::Rc;

pub use crate::avm2::object::local_connection_allocator;
use crate::local_connection::LocalConnections;

/// Implements `domain` getter
pub fn get_domain<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let movie = &activation.context.root_swf;
    let domain = LocalConnections::get_domain(movie.url());

    Ok(Value::String(AvmString::new_utf8(activation.gc(), domain)))
}

/// `send()` rejects messages larger than this with ArgumentError #2084.
/// Measured on Flash Player 32 as: length of the qualified connection name
/// (e.g. `127.0.0.1:name`) + length of the method name + size of the
/// arguments encoded as AMF3. The limit is 32 bytes lower when something is
/// listening on the name.
const MAX_MESSAGE_SIZE: usize = 40943;
const LISTENER_OVERHEAD: usize = 32;

/// Implements `LocalConnection.send`
pub fn send<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    let connection_name = args.get_string_non_null(activation, 0, "connectionName")?;
    let method_name = args.get_string_non_null(activation, 1, "methodName")?;

    if connection_name.is_empty() {
        return Err(make_error_2085(activation, "connectionName"));
    }
    if method_name.is_empty() {
        return Err(make_error_2085(activation, "methodName"));
    }
    if &method_name == b"send"
        || &method_name == b"connect"
        || &method_name == b"close"
        || &method_name == b"allowDomain"
        || &method_name == b"allowInsecureDomain"
        || &method_name == b"domain"
    {
        return Err(make_error_2004(activation, Error2004Type::ArgumentError));
    }

    let domain = LocalConnections::get_domain(activation.context.root_swf.url());
    let qualified_name = LocalConnections::qualified_name(&domain, &connection_name);
    let mut size_table = Default::default();
    let mut amf3_arguments = Vec::with_capacity(args.len() - 2);
    for arg in args.get_slice_from(2..) {
        let value = serialize_value(activation, arg, AMFVersion::AMF3, &mut size_table);
        amf3_arguments.push(Rc::new(value));
    }
    let mut limit = MAX_MESSAGE_SIZE;
    if activation
        .context
        .local_connections
        .has_listener(&qualified_name)
    {
        limit -= LISTENER_OVERHEAD;
    }
    let size = qualified_name
        .to_utf8_lossy()
        .len()
        .saturating_add(method_name.to_utf8_lossy().len())
        .saturating_add(amf3_values_len(&amf3_arguments));
    if size > limit {
        return Err(make_error_2084(activation));
    }

    let mut amf_arguments = Vec::with_capacity(args.len() - 2);
    // One table for all arguments, so shared and cyclic references survive
    // across arguments too.
    let mut object_table = Default::default();
    for arg in args.get_slice_from(2..) {
        let value = serialize_value(activation, arg, AMFVersion::AMF0, &mut object_table);
        amf_arguments.push(value);
    }

    if let Some(local_connection) = this.as_local_connection_object() {
        activation.context.local_connections.send(
            &domain,
            (activation.domain(), local_connection),
            connection_name,
            method_name,
            amf_arguments,
        );
    }

    Ok(Value::Undefined)
}

/// Implements `LocalConnection.connect`
pub fn connect<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    let connection_name = args.get_string_non_null(activation, 0, "connectionName")?;
    if connection_name.is_empty() {
        return Err(make_error_2085(activation, "connectionName"));
    }
    if connection_name.contains(b':') {
        return Err(make_error_2004(activation, Error2004Type::ArgumentError));
    }

    if let Some(local_connection) = this.as_local_connection_object()
        && !local_connection.connect(activation, connection_name)
    {
        // This triggers both if this object is already connected, OR there's something else taking the name
        // (The error message is misleading, in that case!)
        return Err(make_error_2082(activation));
    }

    Ok(Value::Undefined)
}

/// Implements `LocalConnection.close`
pub fn close<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(local_connection) = this.as_local_connection_object() {
        if !local_connection.is_connected() {
            return Err(make_error_2083(activation));
        }

        local_connection.disconnect(activation);
    }

    Ok(Value::Undefined)
}

pub fn get_client<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(local_connection) = this.as_local_connection_object() {
        Ok(local_connection.client().into())
    } else {
        Ok(Value::Undefined)
    }
}

pub fn set_client<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(local_connection) = this.as_local_connection_object() {
        // The parameter is typed `Object`, so primitives (e.g. `5`, `"str"`) reach
        // us uncoerced; Flash rejects them, and null, with TypeError #2004.
        let client_obj = args.get_value(0).as_object();

        if let Some(client_obj) = client_obj {
            local_connection.set_client(activation.gc(), client_obj);
        } else {
            return Err(make_error_2004(activation, Error2004Type::TypeError));
        }
    }

    Ok(Value::Undefined)
}
