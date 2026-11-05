//! Timffle: `flash.globalization.NumberFormatter` native methods.

use super::locale_data::{self, NO_ERROR, PARSE_ERROR};
use super::number_format::{self, NumberSettings};
use crate::avm2::Error;
use crate::avm2::activation::Activation;
use crate::avm2::array::ArrayStorage;
use crate::avm2::function::FunctionArgs;
use crate::avm2::globals::slots::flash_globalization_number_formatter as slots;
use crate::avm2::object::{ArrayObject, Object, TObject, VectorObject};
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

fn slot_string<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Object<'gc>,
    id: usize,
) -> Result<String, Error<'gc>> {
    Ok(this
        .get_slot(id)
        .coerce_to_string(activation)?
        .to_utf8_lossy()
        .into_owned())
}

pub fn read_settings<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Object<'gc>,
) -> Result<NumberSettings, Error<'gc>> {
    Ok(NumberSettings {
        decimal_separator: slot_string(activation, this, slots::_DECIMAL_SEPARATOR)?,
        grouping_separator: slot_string(activation, this, slots::_GROUPING_SEPARATOR)?,
        digits_type: this
            .get_slot(slots::_DIGITS_TYPE)
            .coerce_to_u32(activation)?,
        fractional_digits: this
            .get_slot(slots::_FRACTIONAL_DIGITS)
            .coerce_to_i32(activation)?,
        grouping_pattern: slot_string(activation, this, slots::_GROUPING_PATTERN)?,
        leading_zero: this.get_slot(slots::_LEADING_ZERO).coerce_to_boolean(),
        trailing_zeros: this.get_slot(slots::_TRAILING_ZEROS).coerce_to_boolean(),
        use_grouping: this.get_slot(slots::_USE_GROUPING).coerce_to_boolean(),
        negative_symbol: slot_string(activation, this, slots::_NEGATIVE_SYMBOL)?,
        negative_number_format: this
            .get_slot(slots::_NEGATIVE_NUMBER_FORMAT)
            .coerce_to_u32(activation)?,
    })
}

/// `private native function init(requestedLocaleIDName:String):void`
///
/// Resolves the requested locale and loads its number conventions.
pub fn init<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();
    let requested = args.get_string_non_null(activation, 0, "requestedLocaleIDName")?;
    let requested = requested.to_utf8_lossy().into_owned();
    let (locale, status) = locale_data::resolve(activation, &requested);

    let set_str = |activation: &mut Activation<'_, 'gc>, id: usize, s: &str| {
        this.set_slot(
            id,
            AvmString::new_utf8(activation.gc(), s).into(),
            activation,
        )
    };
    set_str(activation, slots::_ACTUAL_LOCALE_ID_NAME, locale.id)?;
    set_str(
        activation,
        slots::_DECIMAL_SEPARATOR,
        locale.decimal_separator,
    )?;
    set_str(
        activation,
        slots::_GROUPING_SEPARATOR,
        locale.grouping_separator,
    )?;
    this.set_slot(slots::_DIGITS_TYPE, locale.digits_type.into(), activation)?;
    this.set_slot(
        slots::_NEGATIVE_NUMBER_FORMAT,
        locale.negative_number_format.into(),
        activation,
    )?;
    set_status(activation, this, status)?;
    Ok(Value::Undefined)
}

fn format_value<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    value: f64,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();
    let settings = read_settings(activation, this)?;
    let result = number_format::format_number(value, &settings);
    set_status(activation, this, NO_ERROR)?;
    Ok(AvmString::new_utf8(activation.gc(), &result).into())
}

pub fn format_number<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    format_value(activation, this, args.get_f64(0))
}

pub fn format_int<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    format_value(activation, this, args.get_i32(0) as f64)
}

pub fn format_uint<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    format_value(activation, this, args.get_u32(0) as f64)
}

/// `private native function nativeParse(parseString:String):Array`
///
/// Backs `parse()`: returns `[value, startIndex, endIndex]` for the first
/// number in the string, or `null` (with `lastOperationStatus` set to
/// `parseError`) when there is none.
pub fn native_parse<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();
    let input = args.get_string_non_null(activation, 0, "parseString")?;
    let input = input.to_utf8_lossy().into_owned();
    let settings = read_settings(activation, this)?;

    match number_format::parse_first_number(&input, &settings) {
        Some((value, start, end)) => {
            set_status(activation, this, NO_ERROR)?;
            let storage = ArrayStorage::from_args(&[
                value.into(),
                (start as i32).into(),
                (end as i32).into(),
            ]);
            Ok(ArrayObject::from_storage(activation.context, storage).into())
        }
        None => {
            set_status(activation, this, PARSE_ERROR)?;
            Ok(Value::Null)
        }
    }
}

/// `public native function parseNumber(parseString:String):Number`
pub fn parse_number<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();
    let input = args.get_string_non_null(activation, 0, "parseString")?;
    let input = input.to_utf8_lossy().into_owned();
    let settings = read_settings(activation, this)?;
    match number_format::parse_whole_number(&input, &settings) {
        Some(value) => {
            set_status(activation, this, NO_ERROR)?;
            Ok(value.into())
        }
        None => {
            set_status(activation, this, PARSE_ERROR)?;
            Ok(f64::NAN.into())
        }
    }
}

/// Builds the `Vector.<String>` of locale ID names for `getAvailableLocaleIDNames()`.
pub fn available_locale_id_names_vector<'gc>(activation: &mut Activation<'_, 'gc>) -> Value<'gc> {
    let values = locale_data::available_locale_id_names()
        .into_iter()
        .map(|name| AvmString::new_utf8(activation.gc(), name).into())
        .collect();
    let storage =
        VectorStorage::from_values(values, false, Some(activation.avm2().class_defs().string));
    VectorObject::from_vector(storage, activation).into()
}

pub fn get_available_locale_id_names<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    Ok(available_locale_id_names_vector(activation))
}
