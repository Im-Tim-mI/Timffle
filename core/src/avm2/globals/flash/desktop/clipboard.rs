//! Timffle: `flash.desktop.Clipboard` native methods.
//!
//! Flash Player (not AIR) has exactly one clipboard, `Clipboard.generalClipboard`,
//! which is the operating-system clipboard. Its contents live in
//! [`Avm2::clipboard`](crate::avm2::Avm2) as a list of `(format, data | handler)`
//! entries in insertion order; the `air:text` format is mirrored to the host
//! clipboard through [`UiBackend`](crate::backend::ui::UiBackend) so that other
//! programs see it, and a text put on the host clipboard by another program shows
//! up as `air:text`. The rules below were measured on the standalone Flash Player
//! 32.0.0.465 (`timffle/difftest/src/D50ClipAcc.hx`):
//!
//! * `new Clipboard()` throws `IllegalOperationError #2178` (done in `Clipboard.as`).
//! * `getData()` is only allowed while an `Event.PASTE` is being dispatched,
//!   anywhere else it throws `SecurityError #2179` (even for formats that are not
//!   there, and even inside a mouse click); a null format is `TypeError #1009`
//!   before that check.
//! * `setData()` accepts `air:text` (coerced to a string), `air:html`, `air:rtf`
//!   and application-defined formats and answers `true`; the AIR-only formats
//!   `air:url`, `air:bitmap`, `air:file list` and `air:file promise list` answer
//!   `false` and store nothing. A null format or data is `TypeError #2007`.
//! * `setDataHandler()` stores the function and lists the format; the function
//!   runs when that format is read. Null format or handler is `TypeError #2007`.
//! * `clearData(null)` is `TypeError #2007`; `hasFormat(null)` is `false`.
//! * `formats` is a new Array every time.
//!
//! In the browser plugin `clear()`, `clearData()`, `setData()` and
//! `setDataHandler()` are only allowed as the result of user interaction (a mouse
//! click or key press), otherwise `SecurityError #2191`; the standalone player
//! has no such rule, so the check is only compiled for the web target (the same
//! split upstream uses for `System.setClipboard`).

use crate::avm2::Error;
use crate::avm2::activation::Activation;
use crate::avm2::amf::{deserialize_value, serialize_value};
use crate::avm2::error::{make_error_2007, make_error_2008, make_null_or_undefined_error};
use crate::avm2::function::FunctionArgs;
use crate::avm2::object::{ArrayObject, EventObject, Object};
use crate::avm2::parameters::ParametersExt;
use crate::avm2::value::Value;
use crate::avm2::{ArrayStorage, Avm2};
use crate::context::UpdateContext;
use crate::string::{AvmString, WStr};
use flash_lso::types::AMFVersion;
use gc_arena::Collect;

const TEXT_FORMAT: &[u8] = b"air:text";
const HTML_FORMAT: &[u8] = b"air:html";
const RICH_TEXT_FORMAT: &[u8] = b"air:rtf";
const URL_FORMAT: &[u8] = b"air:url";
const BITMAP_FORMAT: &[u8] = b"air:bitmap";
const FILE_LIST_FORMAT: &[u8] = b"air:file list";
const FILE_PROMISE_LIST_FORMAT: &[u8] = b"air:file promise list";

fn is(format: &WStr, name: &'static [u8]) -> bool {
    format == WStr::from_units(name)
}

/// What a clipboard format holds: a value put there by `setData`, or the
/// function given to `setDataHandler` that makes the value on demand.
#[derive(Clone, Copy, Collect)]
#[collect(no_drop)]
pub enum ClipboardData<'gc> {
    Value(Value<'gc>),
    Handler(Object<'gc>),
}

/// One format of `Clipboard.generalClipboard`.
#[derive(Clone, Copy, Collect)]
#[collect(no_drop)]
pub struct ClipboardEntry<'gc> {
    pub format: AvmString<'gc>,
    pub data: ClipboardData<'gc>,
    /// The `serializable` argument of `setData`/`setDataHandler`: whether a
    /// clone (an AMF copy) may be handed out for the clone transfer modes.
    pub serializable: bool,
}

/// Formats that only AIR can put on the clipboard; Flash Player's `setData`
/// returns `false` for them.
fn is_air_only_format(format: &WStr) -> bool {
    is(format, URL_FORMAT)
        || is(format, BITMAP_FORMAT)
        || is(format, FILE_LIST_FORMAT)
        || is(format, FILE_PROMISE_LIST_FORMAT)
}

/// Flash Player's browser plugin only lets a SWF write the clipboard while it is
/// handling a user event (`SecurityError #2191`); the standalone player does not
/// care. Mirrors the `target_family = "wasm"` split of `System.setClipboard`.
fn check_write_allowed<'gc>(activation: &mut Activation<'_, 'gc>) -> Result<(), Error<'gc>> {
    #[cfg(target_family = "wasm")]
    if !activation.avm2().in_user_interaction {
        return Err(crate::avm2::error::make_error_2191(activation));
    }
    let _ = activation;
    Ok(())
}

fn find_entry<'gc>(avm2: &Avm2<'gc>, format: &WStr) -> Option<usize> {
    avm2.clipboard.iter().position(|e| e.format == format)
}

/// The format names in order, with `air:text` added in front when the host
/// clipboard holds text that did not come from `setData` (text copied in another
/// program).
fn format_names<'gc>(activation: &mut Activation<'_, 'gc>) -> Vec<AvmString<'gc>> {
    let mut names: Vec<AvmString<'gc>> = activation
        .avm2()
        .clipboard
        .iter()
        .map(|e| e.format)
        .collect();
    if !names.iter().any(|n| is(n, TEXT_FORMAT))
        && !activation.context.ui.clipboard_content().is_empty()
    {
        names.insert(0, AvmString::new_utf8(activation.gc(), "air:text"));
    }
    names
}

/// Stores a format, replacing an earlier entry of the same name in place.
fn store<'gc>(activation: &mut Activation<'_, 'gc>, entry: ClipboardEntry<'gc>) {
    let avm2 = activation.avm2();
    if let Some(i) = find_entry(avm2, &entry.format) {
        avm2.clipboard[i] = entry;
    } else {
        avm2.clipboard.push(entry);
    }
}

/// Dispatches Flash's `Event.PASTE` (bubbles, not cancelable) to the focused
/// object; `Clipboard.getData()` is allowed only while this runs. Called from the
/// paste text-control path, before the text is inserted into a text field.
pub fn dispatch_paste_event<'gc>(context: &mut UpdateContext<'gc>, target: Object<'gc>) {
    let event = EventObject::bare_event(context, "paste", true, false);
    let was_in_paste = std::mem::replace(&mut context.avm2.in_paste_event, true);
    Avm2::dispatch_event(context, event, target);
    context.avm2.in_paste_event = was_in_paste;
}

/// Implements `Clipboard.formats`
pub fn get_formats<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let names = format_names(activation);
    let storage = ArrayStorage::from_storage(names.into_iter().map(|n| Some(n.into())).collect());
    Ok(ArrayObject::from_storage(activation.context, storage).into())
}

/// Implements `Clipboard.hasFormat`
pub fn has_format<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let Some(format) = args.try_get_string(0) else {
        return Ok(false.into());
    };
    Ok(format_names(activation).contains(&format).into())
}

/// Implements `Clipboard.clear`
pub fn clear<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    check_write_allowed(activation)?;
    activation.avm2().clipboard.clear();
    activation.context.ui.set_clipboard_content(String::new());
    Ok(Value::Undefined)
}

/// Implements `Clipboard.clearData`
pub fn clear_data<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let format = args.get_string_non_null(activation, 0, "format")?;
    check_write_allowed(activation)?;
    if let Some(i) = find_entry(activation.avm2(), &format) {
        activation.avm2().clipboard.remove(i);
    }
    if is(&format, TEXT_FORMAT) {
        activation.context.ui.set_clipboard_content(String::new());
    }
    Ok(Value::Undefined)
}

/// Implements `Clipboard.setData`
pub fn set_data<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let format = args.get_string_non_null(activation, 0, "format")?;
    let data = args.get_value(1);
    if matches!(data, Value::Null | Value::Undefined) {
        return Err(make_error_2007(activation, "data"));
    }
    let serializable = args.get_bool(2);
    check_write_allowed(activation)?;
    if is_air_only_format(&format) {
        return Ok(false.into());
    }
    let data = if is(&format, TEXT_FORMAT) {
        let text = data.coerce_to_string(activation)?;
        activation
            .context
            .ui
            .set_clipboard_content(text.to_string());
        text.into()
    } else {
        data
    };
    store(
        activation,
        ClipboardEntry {
            format,
            data: ClipboardData::Value(data),
            serializable,
        },
    );
    Ok(true.into())
}

/// Implements `Clipboard.setDataHandler`
pub fn set_data_handler<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let format = args.get_string_non_null(activation, 0, "format")?;
    let handler = args.get_object(activation, 1, "handler")?;
    let serializable = args.get_bool(2);
    check_write_allowed(activation)?;
    if is_air_only_format(&format) {
        return Ok(false.into());
    }
    store(
        activation,
        ClipboardEntry {
            format,
            data: ClipboardData::Handler(handler),
            serializable,
        },
    );
    Ok(true.into())
}

/// An AMF3 round trip: the "serialized copy" Flash hands out for the clone
/// transfer modes.
fn clone_value<'gc>(
    activation: &mut Activation<'_, 'gc>,
    value: Value<'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let amf = serialize_value(activation, value, AMFVersion::AMF3, &mut Default::default());
    deserialize_value(activation, &amf)
}

/// Implements `Clipboard.getData`
pub fn get_data<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    // A null format fails inside the player before the security check (#1009).
    let Some(format) = args.try_get_string(0) else {
        return Err(make_null_or_undefined_error(activation, Value::Null, None));
    };
    if !activation.avm2().in_paste_event {
        return Err(crate::avm2::error::make_error_2179(activation));
    }
    let transfer_mode = args.get_string(activation, 1);
    let (prefer_clone, only) = match transfer_mode.to_utf8_lossy().as_ref() {
        "originalPreferred" => (false, false),
        "clonePreferred" => (true, false),
        "originalOnly" => (false, true),
        "cloneOnly" => (true, true),
        _ => return Err(make_error_2008(activation, "transferMode")),
    };

    if is(&format, TEXT_FORMAT) {
        // The host clipboard is the truth for text: it holds what `setData`
        // wrote unless another program copied something since.
        let text = activation.context.ui.clipboard_content();
        if !text.is_empty() {
            return Ok(AvmString::new_utf8(activation.gc(), text).into());
        }
    }
    let Some(i) = find_entry(activation.avm2(), &format) else {
        return Ok(Value::Null);
    };
    let entry = activation.avm2().clipboard[i];
    let value = match entry.data {
        ClipboardData::Value(v) => v,
        ClipboardData::Handler(handler) => {
            let Some(handler) = handler.as_function_object() else {
                return Ok(Value::Null);
            };
            let args = [format.into()];
            let v = handler.call(activation, Value::Null, FunctionArgs::from_slice(&args))?;
            if is(&format, TEXT_FORMAT) && !matches!(v, Value::Null | Value::Undefined) {
                v.coerce_to_string(activation)?.into()
            } else {
                v
            }
        }
    };
    if matches!(value, Value::Null | Value::Undefined) {
        return Ok(Value::Null);
    }

    // Standard formats always come back as a copy (strings are immutable, so
    // only the rich-text ByteArray needs cloning); application-defined formats
    // follow the transfer mode.
    let standard =
        is(&format, TEXT_FORMAT) || is(&format, HTML_FORMAT) || is(&format, RICH_TEXT_FORMAT);
    if standard {
        return if value.as_object().is_some() {
            clone_value(activation, value)
        } else {
            Ok(value)
        };
    }
    if prefer_clone {
        if entry.serializable {
            clone_value(activation, value)
        } else if only {
            Ok(Value::Null)
        } else {
            Ok(value)
        }
    } else {
        Ok(value)
    }
}
