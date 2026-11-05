//! Timffle: `flash.globalization.CurrencyFormatter` native methods.

use super::locale_data::{self, ILLEGAL_ARGUMENT_ERROR, NO_ERROR, PARSE_ERROR};
use super::number_format::{self, NumberSettings};
use crate::avm2::Error;
use crate::avm2::activation::Activation;
use crate::avm2::array::ArrayStorage;
use crate::avm2::function::FunctionArgs;
use crate::avm2::globals::slots::flash_globalization_currency_formatter as slots;
use crate::avm2::object::{ArrayObject, Object, TObject};
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

fn read_settings<'gc>(
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
        // Only the magnitude is formatted here; the sign layout comes from
        // `negativeCurrencyFormat`.
        negative_number_format: 1,
    })
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
    set_str(activation, slots::_CURRENCY_ISO_CODE, locale.currency_iso)?;
    set_str(activation, slots::_CURRENCY_SYMBOL, locale.currency_symbol)?;
    this.set_slot(slots::_DIGITS_TYPE, locale.digits_type.into(), activation)?;
    this.set_slot(
        slots::_FRACTIONAL_DIGITS,
        locale.currency_fraction_digits.into(),
        activation,
    )?;
    this.set_slot(
        slots::_POSITIVE_CURRENCY_FORMAT,
        locale.positive_currency_format.into(),
        activation,
    )?;
    this.set_slot(
        slots::_NEGATIVE_CURRENCY_FORMAT,
        locale.negative_currency_format.into(),
        activation,
    )?;
    set_status(activation, this, status)?;
    Ok(Value::Undefined)
}

/// The layouts of `positiveCurrencyFormat` (0–3), from the Adobe reference.
const POSITIVE_FORMATS: [&str; 4] = ["¤n", "n¤", "¤ n", "n ¤"];

/// The layouts of `negativeCurrencyFormat` (0–15), from the Adobe reference.
const NEGATIVE_FORMATS: [&str; 16] = [
    "(¤n)", "-¤n", "¤-n", "¤n-", "(n¤)", "-n¤", "n-¤", "n¤-", "-n ¤", "-¤ n", "n ¤-", "¤ n-",
    "¤ -n", "n- ¤", "(¤ n)", "(n ¤)",
];

/// `public native function format(value:Number, withCurrencySymbol:Boolean = false):String`
pub fn format<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();
    let value = args.get_f64(0);
    let with_symbol = args.get_bool(1);
    let settings = read_settings(activation, this)?;
    let currency = if with_symbol {
        slot_string(activation, this, slots::_CURRENCY_SYMBOL)?
    } else {
        slot_string(activation, this, slots::_CURRENCY_ISO_CODE)?
    };
    let magnitude = number_format::format_magnitude(value, &settings);

    let layout = if !value.is_nan() && value < 0.0 {
        let index = this
            .get_slot(slots::_NEGATIVE_CURRENCY_FORMAT)
            .coerce_to_u32(activation)? as usize;
        NEGATIVE_FORMATS[index.min(NEGATIVE_FORMATS.len() - 1)]
    } else {
        let index = this
            .get_slot(slots::_POSITIVE_CURRENCY_FORMAT)
            .coerce_to_u32(activation)? as usize;
        POSITIVE_FORMATS[index.min(POSITIVE_FORMATS.len() - 1)]
    };

    let mut out = String::new();
    for c in layout.chars() {
        match c {
            '¤' => out.push_str(&currency),
            'n' => out.push_str(&magnitude),
            '-' => out.push_str(&settings.negative_symbol),
            other => out.push(other),
        }
    }
    set_status(activation, this, NO_ERROR)?;
    Ok(AvmString::new_utf8(activation.gc(), &out).into())
}

/// `public native function formattingWithCurrencySymbolIsSafe(requestedISOCode:String):Boolean`
///
/// True only when the requested ISO code is the formatter's own currency.
pub fn formatting_with_currency_symbol_is_safe<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();
    let requested = args.get_string_non_null(activation, 0, "requestedISOCode")?;
    let current = this
        .get_slot(slots::_CURRENCY_ISO_CODE)
        .coerce_to_string(activation)?;
    set_status(activation, this, NO_ERROR)?;
    Ok((requested == current).into())
}

/// `public native function setCurrency(currencyISOCode:String, currencySymbol:String):void`
pub fn set_currency<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();
    let iso = args.get_string_non_null(activation, 0, "currencyISOCode")?;
    let symbol = args.get_string_non_null(activation, 1, "currencySymbol")?;
    let valid = iso.len() == 3 && iso.iter().all(|c| (b'A' as u16..=b'Z' as u16).contains(&c));
    if !valid {
        set_status(activation, this, ILLEGAL_ARGUMENT_ERROR)?;
        return Ok(Value::Undefined);
    }
    this.set_slot(slots::_CURRENCY_ISO_CODE, iso.into(), activation)?;
    this.set_slot(slots::_CURRENCY_SYMBOL, symbol.into(), activation)?;
    set_status(activation, this, NO_ERROR)?;
    Ok(Value::Undefined)
}

/// `private native function nativeParse(inputString:String):Array`
///
/// Backs `parse()`: returns `[value, currencyString]`, or `null` with
/// `lastOperationStatus` set to `parseError`.
pub fn native_parse<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();
    let input = args.get_string_non_null(activation, 0, "inputString")?;
    let input = input.to_utf8_lossy().into_owned();
    let settings = read_settings(activation, this)?;
    match number_format::parse_currency(&input, &settings) {
        Some((value, currency)) => {
            set_status(activation, this, NO_ERROR)?;
            let storage = ArrayStorage::from_args(&[
                value.into(),
                AvmString::new_utf8(activation.gc(), &currency).into(),
            ]);
            Ok(ArrayObject::from_storage(activation.context, storage).into())
        }
        None => {
            set_status(activation, this, PARSE_ERROR)?;
            Ok(Value::Null)
        }
    }
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
