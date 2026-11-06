//! Timffle: `flash.globalization.DateTimeFormatter` native methods.
//!
//! Implements the Unicode LDML pattern letters the Adobe reference lists
//! (`G y M d E Q w W D F a h H K k m s S z Z v`, quoted literals), the
//! `DateTimeStyle` patterns of each locale in `locale_data`, and the month and
//! weekday name tables. Like Flash Player 32 on Windows (measured), the letters the
//! operating system's formatter has no field for (`Q w D F S z Z v`) are accepted
//! with `unsupportedError` and format as nothing, and `medium` uses the long patterns.

use super::locale_data::{
    self, ILLEGAL_ARGUMENT_ERROR, LocaleData, NO_ERROR, PATTERN_SYNTAX_ERROR, UNSUPPORTED_ERROR,
};
use crate::avm2::Error;
use crate::avm2::activation::Activation;
use crate::avm2::error::make_error_2008;
use crate::avm2::function::FunctionArgs;
use crate::avm2::globals::slots::flash_globalization_date_time_formatter as slots;
use crate::avm2::object::{Object, TObject, VectorObject};
use crate::avm2::parameters::ParametersExt;
use crate::avm2::value::Value;
use crate::avm2::vector::VectorStorage;
use crate::string::AvmString;
use chrono::{DateTime, Datelike, FixedOffset, Offset, Timelike, Utc};

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

fn set_str<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Object<'gc>,
    id: usize,
    s: &str,
) -> Result<(), Error<'gc>> {
    this.set_slot(
        id,
        AvmString::new_utf8(activation.gc(), s).into(),
        activation,
    )
}

fn locale_of<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Object<'gc>,
) -> Result<&'static LocaleData, Error<'gc>> {
    let actual = this
        .get_slot(slots::_ACTUAL_LOCALE_ID_NAME)
        .coerce_to_string(activation)?
        .to_utf8_lossy()
        .into_owned();
    Ok(locale_data::resolve(activation, &actual).0)
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
    set_str(activation, this, slots::_ACTUAL_LOCALE_ID_NAME, locale.id)?;
    set_status(activation, this, status)?;
    Ok(Value::Undefined)
}

fn style_index(style: &str) -> Option<Option<usize>> {
    match style {
        "long" => Some(Some(0)),
        // Timffle: Windows has only long and short date/time formats; Flash 32 gives
        // `medium` the long patterns (measured for en-US, zh-TW, zh-CN, ja-JP, de-DE).
        "medium" => Some(Some(0)),
        "short" => Some(Some(2)),
        "none" => Some(None),
        _ => None,
    }
}

/// `public native function setDateTimeStyles(dateStyle:String, timeStyle:String):void`
pub fn native_set_date_time_styles<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();
    let date_style = args.get_string_non_null(activation, 0, "dateStyle")?;
    let time_style = args.get_string_non_null(activation, 1, "timeStyle")?;
    let date_style = date_style.to_utf8_lossy().into_owned();
    let time_style = time_style.to_utf8_lossy().into_owned();
    let Some(date_index) = style_index(&date_style) else {
        return Err(make_error_2008(activation, "dateStyle"));
    };
    let Some(time_index) = style_index(&time_style) else {
        return Err(make_error_2008(activation, "timeStyle"));
    };

    let locale = locale_of(activation, this)?;
    let mut pattern = String::new();
    if let Some(i) = date_index {
        pattern.push_str(locale.date_patterns[i]);
    }
    if let Some(i) = time_index {
        if !pattern.is_empty() {
            pattern.push(' ');
        }
        pattern.push_str(locale.time_patterns[i]);
    }
    set_str(activation, this, slots::_DATE_STYLE, &date_style)?;
    set_str(activation, this, slots::_TIME_STYLE, &time_style)?;
    set_str(activation, this, slots::_DATE_TIME_PATTERN, &pattern)?;
    set_status(activation, this, NO_ERROR)?;
    Ok(Value::Undefined)
}

const PATTERN_LETTERS: &str = "GyMdEQwWDFahHKkmsSzZv";

/// Checks the syntax of a pattern: unquoted ASCII letters must be pattern
/// letters, and the pattern may hold at most 255 characters.
fn pattern_is_valid(pattern: &str) -> bool {
    if pattern.chars().count() > 255 {
        return false;
    }
    let mut in_quote = false;
    for c in pattern.chars() {
        if c == '\'' {
            in_quote = !in_quote;
        } else if !in_quote && c.is_ascii_alphabetic() && !PATTERN_LETTERS.contains(c) {
            return false;
        }
    }
    true
}

/// Timffle: pattern letters Flash 32 on Windows cannot render — the operating system's
/// date formatter has no quarter, week, day-of-year, time zone or fraction-of-second
/// fields. `setDateTimePattern` keeps the pattern but reports `unsupportedError`, and
/// they format as nothing (measured).
const UNSUPPORTED_LETTERS: &str = "QwDFSzZv";

fn pattern_uses_unsupported_letters(pattern: &str) -> bool {
    let mut in_quote = false;
    pattern.chars().any(|c| {
        if c == '\'' {
            in_quote = !in_quote;
            false
        } else {
            !in_quote && UNSUPPORTED_LETTERS.contains(c)
        }
    })
}

/// `public native function setDateTimePattern(pattern:String):void`
pub fn native_set_date_time_pattern<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();
    let pattern = args.get_string_non_null(activation, 0, "pattern")?;
    let pattern = pattern.to_utf8_lossy().into_owned();
    if !pattern_is_valid(&pattern) {
        set_status(activation, this, PATTERN_SYNTAX_ERROR)?;
        return Ok(Value::Undefined);
    }
    set_str(activation, this, slots::_DATE_STYLE, "custom")?;
    set_str(activation, this, slots::_TIME_STYLE, "custom")?;
    set_str(activation, this, slots::_DATE_TIME_PATTERN, &pattern)?;
    let status = if pattern_uses_unsupported_letters(&pattern) {
        UNSUPPORTED_ERROR
    } else {
        NO_ERROR
    };
    set_status(activation, this, status)?;
    Ok(Value::Undefined)
}

fn pad(value: impl std::fmt::Display, width: usize) -> String {
    format!("{value:0>width$}")
}

/// Renders `date` with an LDML `pattern` and the names of `locale`.
pub fn render_pattern(pattern: &str, date: &DateTime<FixedOffset>, locale: &LocaleData) -> String {
    let names = locale.names;
    let chars: Vec<char> = pattern.chars().collect();
    let mut out = String::new();
    let mut i = 0;
    while i < chars.len() {
        let c = chars[i];
        if c == '\'' {
            if chars.get(i + 1) == Some(&'\'') {
                out.push('\'');
                i += 2;
                continue;
            }
            // Quoted literal, up to the closing quote ('' inside is one quote).
            i += 1;
            while i < chars.len() {
                if chars[i] == '\'' {
                    if chars.get(i + 1) == Some(&'\'') {
                        out.push('\'');
                        i += 2;
                        continue;
                    }
                    i += 1;
                    break;
                }
                out.push(chars[i]);
                i += 1;
            }
            continue;
        }
        if !c.is_ascii_alphabetic() {
            out.push(c);
            i += 1;
            continue;
        }
        let mut count = 1;
        while chars.get(i + count) == Some(&c) {
            count += 1;
        }
        i += count;

        if UNSUPPORTED_LETTERS.contains(c) {
            continue;
        }
        let month = date.month() as usize;
        let weekday = date.weekday().num_days_from_sunday() as usize;
        let hour = date.hour();
        match c {
            'G' => out.push_str(match (date.year() > 0, count) {
                (true, 4) => "Anno Domini",
                (false, 4) => "Before Christ",
                (true, 5) => "A",
                (false, 5) => "B",
                (true, _) => "AD",
                (false, _) => "BC",
            }),
            'y' => {
                let year = date.year();
                if count == 2 {
                    out.push_str(&pad(year.rem_euclid(100), 2));
                } else {
                    // Timffle: Flash 32 writes `yyyyy` like `yyyy` (no fifth digit).
                    out.push_str(&pad(year, count.min(4)));
                }
            }
            'M' => match count {
                1 => out.push_str(&month.to_string()),
                2 => out.push_str(&pad(month, 2)),
                // Timffle: Flash 32 writes `MMMMM` as the full name, like `MMMM`.
                4.. => out.push_str(
                    names
                        .months_format
                        .as_ref()
                        .map_or(names.months[month - 1], |m| m[month - 1]),
                ),
                _ => out.push_str(names.months_abbr[month - 1]),
            },
            'd' => out.push_str(&pad(date.day(), count.min(2))),
            'E' => match count {
                // Timffle: `EEEEE` is the full name too in Flash 32.
                4.. => out.push_str(names.weekdays[weekday]),
                _ => out.push_str(names.weekdays_abbr[weekday]),
            },
            'W' => {
                let first = locale.first_weekday as u32;
                let day1 = date.with_day(1).unwrap_or(*date);
                let day1_wd = (day1.weekday().num_days_from_sunday() + 7 - first) % 7;
                let week = (date.day0() + day1_wd) / 7 + 1;
                out.push_str(&week.to_string());
            }
            'a' => out.push_str(names.am_pm[if hour >= 12 { 1 } else { 0 }]),
            'h' => {
                let h = if hour.is_multiple_of(12) {
                    12
                } else {
                    hour % 12
                };
                out.push_str(&pad(h, count.min(2)));
            }
            'H' => out.push_str(&pad(hour, count.min(2))),
            'K' => out.push_str(&pad(hour % 12, count.min(2))),
            'k' => out.push_str(&pad(if hour == 0 { 24 } else { hour }, count.min(2))),
            'm' => out.push_str(&pad(date.minute(), count.min(2))),
            's' => out.push_str(&pad(date.second(), count.min(2))),
            other => {
                for _ in 0..count {
                    out.push(other);
                }
            }
        }
    }
    out
}

fn format_date<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
    utc: bool,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();
    let date = args.get_object(activation, 0, "dateTime")?;
    let Some(date_time) = date.as_date_object().and_then(|d| d.date_time()) else {
        set_status(activation, this, ILLEGAL_ARGUMENT_ERROR)?;
        return Ok(AvmString::new_utf8(activation.gc(), "").into());
    };
    let offset = if utc {
        Utc.fix()
    } else {
        activation.context.locale.get_timezone()
    };
    let local = date_time.with_timezone(&offset);
    let locale = locale_of(activation, this)?;
    let pattern = this
        .get_slot(slots::_DATE_TIME_PATTERN)
        .coerce_to_string(activation)?
        .to_utf8_lossy()
        .into_owned();
    let result = render_pattern(&pattern, &local, locale);
    set_status(activation, this, NO_ERROR)?;
    Ok(AvmString::new_utf8(activation.gc(), &result).into())
}

pub fn native_format<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    format_date(activation, this, args, false)
}

pub fn native_format_utc<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    format_date(activation, this, args, true)
}

fn names_vector<'gc>(activation: &mut Activation<'_, 'gc>, names: &[&str]) -> Value<'gc> {
    let values = names
        .iter()
        .map(|name| AvmString::new_utf8(activation.gc(), *name).into())
        .collect();
    let storage =
        VectorStorage::from_values(values, false, Some(activation.avm2().class_defs().string));
    VectorObject::from_vector(storage, activation).into()
}

fn name_args<'gc>(
    activation: &mut Activation<'_, 'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<(bool, bool), Error<'gc>> {
    let style = args.get_string_non_null(activation, 0, "nameStyle")?;
    let context = args.get_string_non_null(activation, 1, "context")?;
    let full = match style.to_utf8_lossy().as_ref() {
        "full" => true,
        "longAbbreviation" | "shortAbbreviation" => false,
        _ => return Err(make_error_2008(activation, "nameStyle")),
    };
    let format_context = match context.to_utf8_lossy().as_ref() {
        "format" => true,
        "standalone" => false,
        _ => return Err(make_error_2008(activation, "context")),
    };
    Ok((full, format_context))
}

pub fn native_get_month_names<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();
    let (full, format_context) = name_args(activation, args)?;
    let names = locale_of(activation, this)?.names;
    let list: &[&str] = match (full, format_context, names.months_format.as_ref()) {
        (true, true, Some(format)) => format,
        (true, _, _) => &names.months,
        _ => &names.months_abbr,
    };
    set_status(activation, this, NO_ERROR)?;
    Ok(names_vector(activation, list))
}

pub fn native_get_weekday_names<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();
    let (full, _) = name_args(activation, args)?;
    let names = locale_of(activation, this)?.names;
    let list: &[&str] = if full {
        &names.weekdays
    } else {
        &names.weekdays_abbr
    };
    set_status(activation, this, NO_ERROR)?;
    Ok(names_vector(activation, list))
}

pub fn get_first_weekday<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();
    let locale = locale_of(activation, this)?;
    set_status(activation, this, NO_ERROR)?;
    Ok(locale.first_weekday.into())
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
