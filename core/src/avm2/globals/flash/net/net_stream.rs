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
    avm2.net_streams
        .push(NetStreamObjectWeak(Gc::downgrade(ns.0)));
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

// Timffle: natives backing the `NetStream` members implemented on this
// player's FLV playback (see `crate::streams::NetStream`).

fn with_netstream<'gc, T>(
    this: Value<'gc>,
    f: impl FnOnce(crate::streams::NetStream<'gc>) -> T,
) -> Option<T> {
    this.as_object().and_then(|o| o.as_netstream()).map(f)
}

pub fn get_audio_codec<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    Ok(with_netstream(this, |ns| ns.audio_codec())
        .unwrap_or(0)
        .into())
}

pub fn get_video_codec<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    Ok(with_netstream(this, |ns| ns.video_codec())
        .unwrap_or(0)
        .into())
}

pub fn get_decoded_frames<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    Ok(with_netstream(this, |ns| ns.decoded_frames())
        .unwrap_or(0)
        .into())
}

pub fn get_current_fps<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    Ok(with_netstream(this, |ns| ns.current_fps())
        .unwrap_or(0.0)
        .into())
}

pub fn get_buffer_length<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    Ok(with_netstream(this, |ns| ns.buffer_length())
        .unwrap_or(0.0)
        .into())
}

pub fn get_buffer_time<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    Ok(with_netstream(this, |ns| ns.buffer_time())
        .unwrap_or(0.0)
        .into())
}

pub fn set_buffer_time<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let time = args.get_f64(0);
    with_netstream(this, |ns| ns.set_buffer_time(time));
    Ok(Value::Undefined)
}

pub fn get_back_buffer_length<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    Ok(with_netstream(this, |ns| ns.back_buffer_length())
        .unwrap_or(0.0)
        .into())
}

pub fn get_back_buffer_time<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    Ok(with_netstream(this, |ns| ns.back_buffer_time())
        .unwrap_or(30.0)
        .into())
}

pub fn set_back_buffer_time<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let time = args.get_f64(0);
    let time = if time.is_nan() { 0.0 } else { time.max(0.0) };
    with_netstream(this, |ns| ns.set_back_buffer_time(time));
    Ok(Value::Undefined)
}

pub fn get_in_buffer_seek<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    Ok(with_netstream(this, |ns| ns.in_buffer_seek())
        .unwrap_or(false)
        .into())
}

pub fn set_in_buffer_seek<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let value = args.get_bool(0);
    with_netstream(this, |ns| ns.set_in_buffer_seek(value));
    Ok(Value::Undefined)
}

pub fn get_sound_transform<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let transform = with_netstream(this, |ns| ns.sound_transform()).unwrap_or_default();
    Ok(transform.into_avm2_object(activation)?.into())
}

pub fn set_sound_transform<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let as3_st = args.get_object(activation, 0, "soundTransform")?;
    let transform = crate::display_object::SoundTransform::from_avm2_object(as3_st);
    if let Some(ns) = this.as_object().and_then(|o| o.as_netstream()) {
        ns.set_sound_transform(activation.context, transform);
    }
    Ok(Value::Undefined)
}

pub fn close<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    if let Some(ns) = this.as_object().and_then(|o| o.as_netstream()) {
        ns.close(activation.context);
    }
    Ok(Value::Undefined)
}

pub fn dispose<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    if let Some(ns) = this.as_object().and_then(|o| o.as_netstream()) {
        ns.dispose(activation.context);
    }
    Ok(Value::Undefined)
}

/// `step(frames)`: true when the frame was shown (the AS side then sends
/// `NetStream.Step.Notify`).
pub fn step_internal<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let frames = args.get_i32(0);
    if let Some(ns) = this.as_object().and_then(|o| o.as_netstream()) {
        return Ok(ns.step(activation.context, frames).into());
    }
    Ok(false.into())
}

pub fn append_bytes_internal<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let bytes = args.get_object(activation, 0, "bytes")?;
    let data: Vec<u8> = bytes
        .as_bytearray()
        .map(|b| b.bytes().to_vec())
        .unwrap_or_default();
    if let Some(ns) = this.as_object().and_then(|o| o.as_netstream()) {
        return Ok(ns.append_bytes(activation.context, &data).into());
    }
    Ok(false.into())
}

pub fn append_bytes_action_internal<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let action = args.get_string_non_null(activation, 0, "action")?;
    let action = action.to_string();
    if let Some(ns) = this.as_object().and_then(|o| o.as_netstream()) {
        return Ok(ns.append_bytes_action(activation.context, &action).into());
    }
    Ok(false.into())
}

/// The numbers and objects behind `NetStream.info` (see `NetStream.info` in
/// NetStream.as for how they reach the `NetStreamInfo` constructor):
/// [currentBytesPerSecond, byteCount, maxBytesPerSecond, audioBytesPerSecond,
///  audioByteCount, videoBytesPerSecond, videoByteCount, dataBytesPerSecond,
///  dataByteCount, playbackBytesPerSecond, droppedFrames, audioBufferLength,
///  videoBufferLength, dataBufferLength, audioBufferByteLength,
///  videoBufferByteLength, dataBufferByteLength, metaData, xmpData, resourceName].
///
/// Timffle: the transfer counters and rates are what Flash Player 32 reports
/// for a progressive download, which is the only kind of stream here: 0 for
/// every byte count and every per-second rate except `playbackBytesPerSecond`,
/// even after the whole file arrived (measured over HTTP on Flash Player 32;
/// those fields describe RTMP traffic).
pub fn info_values<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    use crate::avm2::ArrayStorage;
    use crate::avm2::object::ArrayObject;

    let Some(ns) = this.as_object().and_then(|o| o.as_netstream()) else {
        return Ok(Value::Null);
    };
    let stats = ns.buffer_stats();
    let (_, _, playback_bps) = ns.rates();
    let time = ns.time();
    let ahead = |end: Option<i32>| end.map_or(0.0, |e| ((e as f64 - time) / 1000.0).max(0.0));
    let mc = activation.gc();
    let values: Vec<Value<'gc>> = vec![
        0.into(),
        0.into(),
        0.into(),
        0.into(),
        0.into(),
        0.into(),
        0.into(),
        0.into(),
        0.into(),
        playback_bps.into(),
        (ns.dropped_frames() as f64).into(),
        ahead(stats.audio_end).into(),
        ahead(stats.video_end).into(),
        ahead(stats.data_end).into(),
        (stats.audio_ahead_bytes as f64).into(),
        (stats.video_ahead_bytes as f64).into(),
        (stats.data_ahead_bytes as f64).into(),
        ns.metadata().map_or(Value::Null, Value::from),
        ns.xmp_data().map_or(Value::Null, Value::from),
        ns.url()
            .map_or(Value::Null, |u| AvmString::new_utf8(mc, u).into()),
    ];
    Ok(ArrayObject::from_storage(activation.context, ArrayStorage::from_args(&values)).into())
}
