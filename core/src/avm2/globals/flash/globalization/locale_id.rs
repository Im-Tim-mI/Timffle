//! Timffle: `flash.globalization.LocaleID` native methods.
//!
//! Parses locale ID names (UTS #35 / BCP 47: language, script, region,
//! variants, `-u-` extension keys and the `@key=value;…` suffix) without any
//! OS service, and guesses the script and region of a bare language from a
//! likely-subtags table, reporting `usingFallbackWarning` as Flash does.

use super::locale_data::{self, NO_ERROR, UNEXPECTED_TOKEN, USING_FALLBACK_WARNING};
use crate::avm2::Error;
use crate::avm2::activation::Activation;
use crate::avm2::function::FunctionArgs;
use crate::avm2::globals::slots::flash_globalization_locale_id as slots;
use crate::avm2::object::{Object, ScriptObject, TObject, VectorObject};
use crate::avm2::parameters::ParametersExt;
use crate::avm2::value::Value;
use crate::avm2::vector::VectorStorage;
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

fn parsed<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Object<'gc>,
) -> Result<locale_data::ParsedLocale, Error<'gc>> {
    let name = this.get_slot(slots::_NAME).coerce_to_string(activation)?;
    Ok(locale_data::parse_locale(&name.to_utf8_lossy()))
}

fn string_result<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Object<'gc>,
    value: &str,
    status: &str,
) -> Result<Value<'gc>, Error<'gc>> {
    set_status(activation, this, status)?;
    Ok(AvmString::new_utf8(activation.gc(), value).into())
}

/// `private native function init(name:String):void`
///
/// Stores the canonical form of the name (proper casing, `-` separators).
pub fn init<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();
    let name = args.get_string_non_null(activation, 0, "name")?;
    let name = name.to_utf8_lossy().into_owned();
    let canonical = if name == "i-default" {
        locale_data::default_locale_id(activation).to_string()
    } else {
        locale_data::canonical_name(&name)
    };
    this.set_slot(
        slots::_NAME,
        AvmString::new_utf8(activation.gc(), &canonical).into(),
        activation,
    )?;
    let parsed = locale_data::parse_locale(&canonical);
    let status = if parsed.unexpected_token {
        UNEXPECTED_TOKEN
    } else {
        NO_ERROR
    };
    set_status(activation, this, status)?;
    Ok(Value::Undefined)
}

pub fn get_language<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();
    let parsed = parsed(activation, this)?;
    string_result(activation, this, &parsed.language, NO_ERROR)
}

pub fn get_region<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();
    let parsed = parsed(activation, this)?;
    if !parsed.region.is_empty() {
        return string_result(activation, this, &parsed.region, NO_ERROR);
    }
    let guessed = locale_data::default_region(&parsed.language, &parsed.script);
    let status = if guessed.is_empty() {
        NO_ERROR
    } else {
        USING_FALLBACK_WARNING
    };
    string_result(activation, this, guessed, status)
}

pub fn get_script<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();
    let parsed = parsed(activation, this)?;
    if !parsed.script.is_empty() {
        return string_result(activation, this, &parsed.script, NO_ERROR);
    }
    let guessed = locale_data::default_script(&parsed.language, &parsed.region);
    let status = if guessed.is_empty() {
        NO_ERROR
    } else {
        USING_FALLBACK_WARNING
    };
    string_result(activation, this, guessed, status)
}

pub fn get_variant<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();
    let parsed = parsed(activation, this)?;
    let variant = parsed.variants.join("-");
    string_result(activation, this, &variant, NO_ERROR)
}

pub fn is_right_to_left<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();
    let parsed = parsed(activation, this)?;
    set_status(activation, this, NO_ERROR)?;
    Ok(locale_data::is_right_to_left(&parsed).into())
}

/// `public native function getKeysAndValues():Object`
pub fn get_keys_and_values<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();
    let parsed = parsed(activation, this)?;
    let object = ScriptObject::new_object(activation.context);
    for (key, value) in &parsed.keys {
        let key = AvmString::new_utf8(activation.gc(), key);
        let value = AvmString::new_utf8(activation.gc(), value);
        object.set_dynamic_property(key, value.into(), activation.gc());
    }
    let status = if parsed.unexpected_token {
        UNEXPECTED_TOKEN
    } else {
        NO_ERROR
    };
    set_status(activation, this, status)?;
    Ok(object.into())
}

fn vector_strings<'gc>(
    activation: &mut Activation<'_, 'gc>,
    object: Object<'gc>,
) -> Result<Vec<String>, Error<'gc>> {
    let values: Vec<Value<'gc>> = match object.as_vector_storage() {
        Some(storage) => storage.iter().collect(),
        None => Vec::new(),
    };
    let mut out = Vec::with_capacity(values.len());
    for value in values {
        if matches!(value, Value::Null | Value::Undefined) {
            continue;
        }
        out.push(
            value
                .coerce_to_string(activation)?
                .to_utf8_lossy()
                .into_owned(),
        );
    }
    Ok(out)
}

/// How well an available locale satisfies a wanted one: 3 = identical,
/// 2 = one is a prefix of the other (`en` / `en-US`), 1 = same language.
fn match_score(want: &locale_data::ParsedLocale, have: &locale_data::ParsedLocale) -> u8 {
    if want.language != have.language {
        return 0;
    }
    let script_ok = want.script.is_empty() || have.script.is_empty() || want.script == have.script;
    let region_ok = want.region.is_empty() || have.region.is_empty() || want.region == have.region;
    if want.script == have.script && want.region == have.region && want.variants == have.variants {
        3
    } else if script_ok && region_ok {
        2
    } else {
        1
    }
}

/// `public static native function determinePreferredLocales(want, have, keyword):Vector.<String>`
///
/// Returns the subset of `have` that matches the locales in `want`, ordered
/// by the user's preference: for each wanted locale, exact matches first,
/// then prefix matches (`en` ↔ `en-US`), then other locales of the same
/// language. The `keyword` ("userinterface" by default) only selects the
/// OS preference list in Flash Player; with no OS list it has no effect.
pub fn determine_preferred_locales<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let want = args.get_object(activation, 0, "want")?;
    let have = args.get_object(activation, 1, "have")?;
    let _keyword = args.get_string_non_null(activation, 2, "keyword")?;

    let want: Vec<locale_data::ParsedLocale> = vector_strings(activation, want)?
        .iter()
        .map(|s| locale_data::parse_locale(s))
        .collect();
    let have_names = vector_strings(activation, have)?;
    let have: Vec<locale_data::ParsedLocale> = have_names
        .iter()
        .map(|s| locale_data::parse_locale(s))
        .collect();

    let mut chosen: Vec<usize> = Vec::new();
    for wanted in &want {
        for score in (1..=3).rev() {
            for (i, available) in have.iter().enumerate() {
                if !chosen.contains(&i) && match_score(wanted, available) == score {
                    chosen.push(i);
                }
            }
        }
    }

    let values = chosen
        .into_iter()
        .map(|i| AvmString::new_utf8(activation.gc(), &have_names[i]).into())
        .collect();
    let storage =
        VectorStorage::from_values(values, false, Some(activation.avm2().class_defs().string));
    Ok(VectorObject::from_vector(storage, activation).into())
}
