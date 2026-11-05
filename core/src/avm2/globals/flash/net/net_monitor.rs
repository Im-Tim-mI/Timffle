//! Timffle: `flash.net.NetMonitor` natives (the list of live `NetStream`s lives in `Avm2`).

use crate::avm2::function::FunctionArgs;
use crate::avm2::object::{NetStreamObject, VectorObject};
use crate::avm2::vector::VectorStorage;
use crate::avm2::{Activation, Error, Object, Value};

/// `NetMonitor` constructor: remember the monitor (weakly) so `NetStream` constructors can
/// send it `netStreamCreate`.
pub fn register<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();
    let mc = activation.gc();

    let avm2 = activation.avm2();
    avm2.net_monitors.retain(|m| m.upgrade(mc).is_some());
    avm2.net_monitors.push(this.downgrade());

    Ok(Value::Undefined)
}

/// `NetMonitor.listStreams()`: a new `Vector.<NetStream>` of every NetStream still alive.
pub fn list_streams<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let mc = activation.gc();

    let avm2 = activation.avm2();
    avm2.net_streams.retain(|s| s.0.upgrade(mc).is_some());
    let streams: Vec<Value<'gc>> = avm2
        .net_streams
        .iter()
        .filter_map(|s| s.0.upgrade(mc))
        .map(|gc| Object::from(NetStreamObject(gc)).into())
        .collect();

    let net_stream_class = activation
        .avm2()
        .classes()
        .netstream
        .inner_class_definition();
    let storage = VectorStorage::from_values(streams, false, Some(net_stream_class));
    Ok(VectorObject::from_vector(storage, activation).into())
}
