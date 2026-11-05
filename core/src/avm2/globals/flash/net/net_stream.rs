use crate::avm2::error::{Error2004Type, make_error_2004};
use crate::avm2::function::FunctionArgs;
use crate::avm2::object::{EventObject, NetStreamObjectWeak};
use crate::avm2::parameters::ParametersExt;
use crate::avm2::{Activation, Avm2, Error, Object, Value};
use crate::string::AvmString;
use gc_arena::Gc;

pub use crate::avm2::object::netstream_allocator as net_stream_allocator;

/// Timffle: the end of the `NetStream` constructor: list the stream for
/// `NetMonitor.listStreams()` and send every live `NetMonitor` a `netStreamCreate`
/// (synchronously, like Flash Player 32).
pub fn register_with_monitors<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();
    let Some(ns) = this.as_netstream_object() else {
        return Ok(Value::Undefined);
    };
    let mc = activation.gc();

    let avm2 = activation.avm2();
    avm2.net_streams.retain(|s| s.0.upgrade(mc).is_some());
    avm2.net_streams.push(NetStreamObjectWeak(Gc::downgrade(ns.0)));
    let monitors: Vec<Object<'gc>> = avm2
        .net_monitors
        .iter()
        .filter_map(|m| m.upgrade(mc))
        .collect();

    if !monitors.is_empty() {
        let event_class = activation.avm2().classes().netmonitorevent;
        let event_type = AvmString::new_utf8(mc, "netStreamCreate");
        for monitor in monitors {
            let event = EventObject::from_class_and_args(
                activation,
                event_class,
                &[event_type.into(), false.into(), false.into(), this.into()],
            );
            Avm2::dispatch_event(activation.context, event, monitor);
        }
    }

    Ok(Value::Undefined)
}

pub fn get_bytes_loaded<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(ns) = this.as_netstream() {
        return Ok(Value::from_usize_lossy(ns.bytes_loaded()));
    }

    Ok(Value::Undefined)
}

pub fn get_bytes_total<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(ns) = this.as_netstream() {
        return Ok(Value::from_usize_lossy(ns.bytes_total()));
    }

    Ok(Value::Undefined)
}

pub fn play<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(ns) = this.as_netstream() {
        let name = args
            .get_optional(0)
            .filter(|v| !matches!(v, Value::Null))
            .map(|v| v.coerce_to_string(activation))
            .transpose()?;

        ns.play(activation.context, name);
    }

    Ok(Value::Undefined)
}

pub fn pause<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(ns) = this.as_netstream() {
        ns.pause(activation.context, true);
    }

    Ok(Value::Undefined)
}

pub fn resume<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(ns) = this.as_netstream() {
        ns.resume(activation.context);
    }

    Ok(Value::Undefined)
}

pub fn toggle_pause<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(ns) = this.as_netstream() {
        ns.toggle_paused(activation.context);
    }

    Ok(Value::Undefined)
}

pub fn get_client<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(ns) = this.as_netstream() {
        return Ok(ns.client().expect("NetStream client should be set").into());
    }

    Ok(Value::Undefined)
}

pub fn set_client<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    let client = args.get_value(0).as_object();

    if let Some(client) = client {
        if let Some(ns) = this.as_netstream() {
            ns.set_client(activation.gc(), client);
        }
    } else {
        return Err(make_error_2004(activation, Error2004Type::TypeError));
    }

    Ok(Value::Undefined)
}

pub fn seek<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(ns) = this.as_netstream() {
        let offset = args.get_f64(0);
        ns.seek(activation.context, offset * 1000.0, true);
    }

    Ok(Value::Undefined)
}

pub fn get_time<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(ns) = this.as_netstream() {
        return Ok((ns.time() / 1000.0).into());
    }

    Ok(Value::Undefined)
}
