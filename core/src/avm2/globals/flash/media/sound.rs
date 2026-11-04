//! `flash.media.Sound` builtin/prototype

use crate::avm2::Avm2;
use crate::avm2::Error;
use crate::avm2::activation::Activation;
use crate::avm2::error::{
    make_error_2005, make_error_2007, make_error_2029, make_error_2037, make_error_2084,
};
use crate::avm2::function::FunctionArgs;
use crate::avm2::globals::flash::display::loader::request_from_url_request;
use crate::avm2::object::{
    EXTRACT_SAMPLE_RATE, EventObject, QueuedPlay, SoundChannelObject, SoundLoadingState,
};
use crate::avm2::parameters::ParametersExt;
use crate::avm2::value::Value;
use crate::backend::audio::swf::{AudioCompression, SoundFormat};
use crate::character::Character;
use crate::display_object::SoundTransform;
use swf::{SoundEvent, SoundInfo};

pub use crate::avm2::object::sound_allocator;

/// Implements `flash.media.Sound`'s 'init' method. which is called from the constructor.
pub fn init<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    if let Some(sound_object) = this.as_object().and_then(|o| o.as_sound_object()) {
        let class_def = this.instance_class(activation);

        if let Some((movie, symbol)) = activation
            .context
            .library
            .avm2_class_registry()
            .class_symbol(class_def)
        {
            if let Some(Character::Sound(sound)) = activation
                .context
                .library
                .library_for_movie_mut(movie)
                .character_by_id(symbol)
            {
                sound_object.set_sound(activation.context, sound);
            } else {
                tracing::warn!(
                    "Attempted to construct subclass of Sound, {}, which is associated with non-Sound character {}",
                    class_def.name().local_name(),
                    symbol
                );
            }
        }
    }

    Ok(Value::Undefined)
}

/// Implements `Sound.bytesTotal`
pub fn get_bytes_total<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(sound) = this.as_sound_object() {
        return Ok(sound.bytes_total().into());
    }

    Ok(Value::Undefined)
}

/// Implements `Sound.bytesLoaded`.
///
/// Timffle: the bytes received so far of a `load()`; the whole size for
/// library and `ByteArray` sounds.
pub fn get_bytes_loaded<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(sound) = this.as_sound_object() {
        return Ok(sound.bytes_loaded().into());
    }

    Ok(Value::Undefined)
}

/// Implements `Sound.isBuffering`
///
/// Timffle: true from `load()` on; see `SoundObjectData::is_buffering`.
pub fn get_is_buffering<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(sound) = this.as_sound_object() {
        return Ok(sound.is_buffering().into());
    }

    Ok(Value::Undefined)
}

/// Implements `Sound.isURLInaccessible`
///
/// Timffle: true when the download was redirected to an origin the loading
/// SWF does not share (Flash: "redirected, different domain, no permission");
/// `url` then only reveals that origin.
pub fn get_is_url_inaccessible<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(sound) = this.as_sound_object() {
        return Ok(sound.is_url_inaccessible().into());
    }

    Ok(Value::Undefined)
}

/// Implements `Sound.url`
pub fn get_url<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(sound) = this.as_sound_object() {
        return Ok(sound.url().map(Value::from).unwrap_or(Value::Null));
    }

    Ok(Value::Undefined)
}

/// Implements `Sound.length`
pub fn get_length<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(sound) = this.as_sound_object() {
        if let Some(sound_handle) = sound.sound_handle()
            && let Some(duration) = activation.context.audio.get_sound_duration(sound_handle)
        {
            return Ok((duration.as_millis()).into());
        }
        return Ok(0.into());
    }

    Ok(Value::Undefined)
}

/// Implements `Sound.play`
pub fn play<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(sound_object) = this.as_sound_object() {
        let position = args.get_f64(0);
        let num_loops = args.get_i32(1);
        let sound_transform = args.try_get_object(2);

        let in_sample = if position > 0.0 {
            Some((position / 1000.0 * 44100.0) as u32)
        } else {
            None
        };

        let sound_info = SoundInfo {
            event: SoundEvent::Start,
            in_sample,
            out_sample: None,
            num_loops: num_loops.max(1) as u16,
            envelope: None,
        };

        let sound_transform = if let Some(sound_transform) = sound_transform {
            Some(SoundTransform::from_avm2_object(sound_transform))
        } else {
            None
        };

        let sound_channel = SoundChannelObject::empty(activation);

        let queued_play = QueuedPlay {
            position,
            sound_info,
            sound_transform,
            sound_channel,
        };
        if sound_object.play(queued_play, activation) {
            return Ok(sound_channel.into());
        }
        // If we start playing a loaded sound with an invalid position,
        // this method returns `null`
        return Ok(Value::Null);
    }

    Ok(Value::Null)
}

/// `Sound.extract`
///
/// Timffle: writes up to `length` 44.1 kHz stereo sample frames as 32-bit
/// floats (in the ByteArray's own endianness, at its current position, which
/// advances) and returns how many were written. Measured on Flash Player 32:
/// a null target, a length below 1 or NaN, or a start past the end write
/// nothing and return 0; fractional values are truncated; a negative or NaN
/// `startPosition` continues where the previous call stopped (an explicit
/// start moves that cursor too); samples come back as the 16-bit values
/// Flash keeps internally divided by 32768.
pub fn extract<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();
    let Some(sound) = this.as_sound_object() else {
        return Ok(0.into());
    };

    let Some(target) = args.try_get_object(0) else {
        return Ok(0.into());
    };
    let length = args.get_f64(1);
    if length.is_nan() || length < 1.0 {
        return Ok(0.into());
    }
    let count = length.min(f64::from(u32::MAX)) as u32;
    let start = args.get_f64(2);
    let start = if start.is_nan() || start < 0.0 {
        None
    } else {
        Some(start.min(f64::from(u32::MAX)) as u32)
    };

    let frames = sound.extract(activation.context, start, count);
    if let Some(mut bytearray) = target.as_bytearray_mut() {
        for [left, right] in &frames {
            bytearray
                .write_float(f32::from(*left) / 32768.0)
                .map_err(|e| e.to_avm(activation))?;
            bytearray
                .write_float(f32::from(*right) / 32768.0)
                .map_err(|e| e.to_avm(activation))?;
        }
    }

    Ok((frames.len() as u32).into())
}

/// `Sound.close`
///
/// Timffle: closes the stream opened by `load()`; a download still running
/// is abandoned (no further events) and the object may be loaded again.
/// Without an open stream — a new sound, a library or ByteArray sound, or a
/// second `close()` — Flash throws `IOError #2029` (measured on Flash Player
/// 32; closing a finished download once is fine).
pub fn close<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();
    let Some(sound) = this.as_sound_object() else {
        return Ok(Value::Undefined);
    };
    if !sound.stream_open() {
        return Err(make_error_2029(activation));
    }
    sound.close_stream();
    Ok(Value::Undefined)
}

/// `Sound.load`
///
/// Timffle: the `SoundLoaderContext` is accepted without a stub: its
/// `bufferTime` (milliseconds to buffer before playback starts) is always
/// satisfied because the whole file is downloaded before it plays, and
/// `checkPolicyFile` guards data access (`id3`, `computeSpectrum`) that this
/// player never restricts (`SoundMixer.areSoundsInaccessible()` is false).
pub fn load<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this_object = this.as_object().unwrap();

    let this = this_object.as_sound_object().unwrap();
    if this.loading_state() != SoundLoadingState::New {
        return Err(make_error_2037(activation));
    }

    let url_request = match args.try_get_object(0) {
        Some(request) => request,
        // FP ignores calls of `load(null)`
        None => return Ok(Value::Undefined),
    };

    let request = request_from_url_request(activation, url_request)?;
    let caller_url = activation.caller_movie_or_root().url().to_string();

    let generation = this.begin_load();
    let future =
        crate::loader::load_sound_avm2(activation.context, this, request, caller_url, generation);
    activation.context.navigator.spawn_future(future);

    Ok(Value::Undefined)
}

/// `Sound.loadCompressedDataFromByteArray`
pub fn load_compressed_data_from_byte_array<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this_object = this.as_object().unwrap();

    let this = this_object.as_sound_object().unwrap();

    let bytearray = args.get_object(activation, 0, "bytes")?;
    let bytes_length = args.get_u32(1);
    let bytearray = bytearray.as_bytearray().unwrap();

    // Timffle: Flash checks the bytes before it looks at the loading state
    // (a second call with too few bytes left is `#2084`, not ignored).
    let bytes = if let Ok(bytes) = bytearray.read_bytes(bytes_length as usize) {
        bytes
    } else {
        // This is the error Flash throws
        return Err(make_error_2084(activation));
    };

    if this.loading_state() == SoundLoadingState::Loaded {
        return Ok(Value::Undefined);
    }

    // FIXME - determine the actual error thrown by Flash Player
    let handle = activation.context.audio.register_mp3(bytes).map_err(|e| {
        Error::rust_error(format!("Failed to register sound from bytearray: {e:?}").into())
    })?;

    let progress_evt =
        EventObject::progress_event(activation, "progress", bytes.len(), bytes.len());

    Avm2::dispatch_event(activation.context, progress_evt, this_object);

    this.read_and_call_id3_event(activation, bytes);
    this.set_bytes(bytes.len() as u32, bytes.len() as u32);
    this.set_owned_sound(activation.context, handle);

    Ok(Value::Undefined)
}

/// `Sound.loadPCMFromByteArray`
///
/// Timffle: reads `samples` sample frames from the ByteArray's position
/// ("float": 32-bit floats clamped to ±1, "short": 16-bit integers, both in
/// the ByteArray's endianness, mono or stereo at `sampleRate` Hz), converts
/// them to the 16-bit 44.1 kHz stereo data Flash keeps (floats are truncated
/// to 16 bits, other rates resampled so the sound has
/// `floor(samples * 44100 / sampleRate)` frames) and makes it this object's
/// sound. Measured on Flash Player 32: null `bytes` or `format` is
/// `TypeError #2007`, another format `ArgumentError #2005`, zero samples or
/// fewer bytes than needed `ArgumentError #2084`; `bytesTotal` is
/// `samples * channels * 2`; a sound that already has data ignores the call
/// (after the byte check); `position` advances by the bytes read.
pub fn load_pcm_from_byte_array<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this_object = this.as_object().unwrap();

    let this = this_object.as_sound_object().unwrap();

    let bytearray = args.try_get_object(0);
    let samples = args.get_u32(1);
    let format = args.try_get_string(2);
    let stereo = args.get_bool(3);
    let sample_rate = args.get_f64(4);

    let Some(bytearray) = bytearray else {
        return Err(make_error_2007(activation, "bytes"));
    };
    let Some(format) = format else {
        return Err(make_error_2007(activation, "format"));
    };
    let format = format.to_utf8_lossy();
    let is_float = if format == "float" {
        true
    } else if format == "short" {
        false
    } else {
        return Err(make_error_2005(activation, 2, "format"));
    };
    let bytearray = bytearray.as_bytearray().unwrap();

    let channels: usize = if stereo { 2 } else { 1 };
    let sample_size: usize = if is_float { 4 } else { 2 };
    let needed = samples as usize * channels * sample_size;
    if samples == 0 || bytearray.bytes_available() < needed {
        return Err(make_error_2084(activation));
    }

    // Read the frames as 16-bit values.
    let mut frames: Vec<[i16; 2]> = Vec::with_capacity(samples as usize);
    for _ in 0..samples {
        let mut frame = [0i16; 2];
        for channel in frame.iter_mut().take(channels) {
            *channel = if is_float {
                let value = bytearray.read_float().map_err(|e| e.to_avm(activation))?;
                let value = if value.is_nan() { 0.0 } else { value.clamp(-1.0, 1.0) };
                (f64::from(value) * 32768.0).clamp(-32768.0, 32767.0) as i16
            } else {
                bytearray.read_short().map_err(|e| e.to_avm(activation))?
            };
        }
        if !stereo {
            frame[1] = frame[0];
        }
        frames.push(frame);
    }

    if this.loading_state() == SoundLoadingState::Loaded {
        return Ok(Value::Undefined);
    }

    // Resample to 44.1 kHz by sample-and-hold. Assumption: a non-positive or
    // NaN rate is treated as 44100 (Flash accepts any positive rate).
    let sample_rate = if sample_rate > 0.0 && sample_rate.is_finite() {
        sample_rate
    } else {
        f64::from(EXTRACT_SAMPLE_RATE)
    };
    let out_frames: Vec<[i16; 2]> = if sample_rate == f64::from(EXTRACT_SAMPLE_RATE) {
        frames
    } else {
        let count = (f64::from(samples) * f64::from(EXTRACT_SAMPLE_RATE) / sample_rate).floor();
        let count = count.clamp(0.0, f64::from(u32::MAX)) as usize;
        (0..count)
            .map(|o| {
                let src = (o as f64 * sample_rate / f64::from(EXTRACT_SAMPLE_RATE)).floor();
                frames[(src as usize).min(frames.len() - 1)]
            })
            .collect()
    };

    let mut data = Vec::with_capacity(out_frames.len() * 4);
    for [left, right] in &out_frames {
        data.extend_from_slice(&left.to_le_bytes());
        data.extend_from_slice(&right.to_le_bytes());
    }
    let swf_sound = swf::Sound {
        id: 0,
        format: SoundFormat {
            compression: AudioCompression::Uncompressed,
            sample_rate: EXTRACT_SAMPLE_RATE as u16,
            is_stereo: true,
            is_16_bit: true,
        },
        num_samples: out_frames.len() as u32,
        data: &data,
    };
    let handle = activation
        .context
        .audio
        .register_sound(&swf_sound)
        .map_err(|e| Error::rust_error(format!("Failed to register PCM sound: {e:?}").into()))?;

    let total = (samples as usize * channels * 2) as u32;
    this.set_bytes(total, total);
    this.set_owned_sound(activation.context, handle);

    Ok(Value::Undefined)
}

/// Implements `Sound.id3`
pub fn get_id3<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(id3) = this.as_sound_object().unwrap().id3() {
        Ok(id3.into())
    } else {
        Ok(Value::Null)
    }
}
