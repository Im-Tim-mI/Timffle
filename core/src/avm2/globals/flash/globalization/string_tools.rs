//! Timffle: `flash.globalization.StringTools` native methods.
//!
//! Flash Player delegates case conversion to the OS. Here the full Unicode
//! case mappings of the Rust standard library are used (they already cover
//! `ß` → `SS` and the Greek final sigma), plus the language-specific rules of
//! Unicode `SpecialCasing.txt`: the Turkish/Azeri dotted and dotless I, and
//! the Lithuanian rules for `i` with accents.

use super::locale_data::{self, NO_ERROR};
use crate::avm2::Error;
use crate::avm2::activation::Activation;
use crate::avm2::function::FunctionArgs;
use crate::avm2::globals::slots::flash_globalization_string_tools as slots;
use crate::avm2::object::{Object, TObject};
use crate::avm2::parameters::ParametersExt;
use crate::avm2::value::Value;
use crate::string::AvmString;

fn set_status<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Object<'gc>,
    status: &str,
) -> Result<(), Error<'gc>> {
    this.set_slot(
        slots::_LAST_OPERATION_STATUS,
        AvmString::new_utf8(activation.gc(), status).into(),
        activation,
    )
}

/// `private native function init(requestedLocaleIDName:String):void`
pub fn init<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();
    let requested = args.get_string_non_null(activation, 0, "requestedLocaleIDName")?;
    let requested = requested.to_utf8_lossy().into_owned();
    let (locale, status) = locale_data::resolve(activation, &requested);
    this.set_slot(
        slots::_ACTUAL_LOCALE_ID_NAME,
        AvmString::new_utf8(activation.gc(), locale.id).into(),
        activation,
    )?;
    set_status(activation, this, status)?;
    Ok(Value::Undefined)
}

fn is_mark_above(c: char) -> bool {
    // Combining marks with canonical combining class 230 that are relevant to
    // the Lithuanian rules (grave, acute, tilde, ogonek is below and excluded).
    matches!(c, '\u{300}' | '\u{301}' | '\u{303}' | '\u{307}')
}

/// Locale-aware lowercase mapping.
pub fn to_lowercase(s: &str, language: &str) -> String {
    match language {
        "tr" | "az" => {
            let mut out = String::with_capacity(s.len());
            let mut chars = s.chars().peekable();
            while let Some(c) = chars.next() {
                match c {
                    'I' => {
                        // I + COMBINING DOT ABOVE → i
                        if chars.peek() == Some(&'\u{307}') {
                            chars.next();
                            out.push('i');
                        } else {
                            out.push('ı');
                        }
                    }
                    'İ' => out.push('i'),
                    other => out.extend(other.to_lowercase()),
                }
            }
            out
        }
        "lt" => {
            let mut out = String::with_capacity(s.len());
            let mut chars = s.chars().peekable();
            while let Some(c) = chars.next() {
                match c {
                    'I' | 'J' | 'Į' if chars.peek().is_some_and(|n| is_mark_above(*n)) => {
                        out.extend(c.to_lowercase());
                        out.push('\u{307}');
                    }
                    'Ì' => out.push_str("i\u{307}\u{300}"),
                    'Í' => out.push_str("i\u{307}\u{301}"),
                    'Ĩ' => out.push_str("i\u{307}\u{303}"),
                    other => out.extend(other.to_lowercase()),
                }
            }
            out
        }
        _ => s.to_lowercase(),
    }
}

/// Locale-aware uppercase mapping.
pub fn to_uppercase(s: &str, language: &str) -> String {
    match language {
        "tr" | "az" => s
            .chars()
            .flat_map(|c| match c {
                'i' => vec!['İ'],
                'ı' => vec!['I'],
                other => other.to_uppercase().collect(),
            })
            .collect(),
        "lt" => {
            // Remove the dot above an `i`/`j` that was kept in lowercase.
            let mut out = String::with_capacity(s.len());
            let mut chars = s.chars().peekable();
            while let Some(c) = chars.next() {
                if matches!(c, 'i' | 'j' | 'į') && chars.peek() == Some(&'\u{307}') {
                    chars.next();
                }
                out.extend(c.to_uppercase());
            }
            out
        }
        _ => s.to_uppercase(),
    }
}

fn language_of<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Object<'gc>,
) -> Result<String, Error<'gc>> {
    let actual = this
        .get_slot(slots::_ACTUAL_LOCALE_ID_NAME)
        .coerce_to_string(activation)?;
    Ok(locale_data::parse_locale(&actual.to_utf8_lossy()).language)
}

pub fn native_to_lower_case<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();
    let s = args.get_string_non_null(activation, 0, "s")?;
    let language = language_of(activation, this)?;
    let result = to_lowercase(&s.to_utf8_lossy(), &language);
    set_status(activation, this, NO_ERROR)?;
    Ok(AvmString::new_utf8(activation.gc(), &result).into())
}

pub fn native_to_upper_case<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();
    let s = args.get_string_non_null(activation, 0, "s")?;
    let language = language_of(activation, this)?;
    let result = to_uppercase(&s.to_utf8_lossy(), &language);
    set_status(activation, this, NO_ERROR)?;
    Ok(AvmString::new_utf8(activation.gc(), &result).into())
}

pub fn get_available_locale_id_names<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    Ok(super::number_formatter::available_locale_id_names_vector(
        activation,
    ))
}
