//! `flash.globalization.Collator` native methods
//!
//! Timffle: the comparison is a real multi-level collation modelled on the
//! Unicode Collation Algorithm instead of a case-folded code point compare:
//! strings are decomposed (NFKD), the primary level compares base letters
//! (whitespace < punctuation < symbols < digits < letters), the secondary
//! level compares diacritics, the tertiary level compares case (lowercase
//! first), then character width and kana type. Each `ignore*` option drops the
//! matching level, `ignoreSymbols` drops whitespace/punctuation/symbols from
//! the key, and `numericComparison` compares runs of digits by value. Locale
//! tailorings carried: the Swedish/Finnish and Danish/Norwegian letters after
//! `z`, and `@collation=phonebook` for German. Flash Player reads all of this
//! from the OS collator; the locale fallback follows the documented rules
//! (`usingFallbackWarning` / `usingDefaultWarning`).

use super::locale_data::{self, USING_DEFAULT_WARNING, USING_FALLBACK_WARNING};
use super::number_format::digit_value;
use crate::avm2::activation::Activation;
use crate::avm2::error::make_error_1508;
use crate::avm2::function::FunctionArgs;
pub use crate::avm2::object::collator_allocator;
use crate::avm2::object::{CollatorOptions, LastOperationStatus};
use crate::avm2::parameters::ParametersExt;
use crate::avm2::value::Value;
use crate::avm2::{Avm2StrRepresentable, Error};
use crate::string::AvmString;
use std::cmp::Ordering;
use unicode_normalization::UnicodeNormalization;
use unicode_normalization::char::is_combining_mark;

pub fn ctor<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();
    let collator = this.as_collator().unwrap();

    let requested_locale_id_name =
        args.get_string_non_null(activation, 0, "requestedLocaleIDName")?;
    let initial_mode = args.get_string_non_null(activation, 1, "initialMode")?;

    if &initial_mode != b"sorting" && &initial_mode != b"matching" {
        return Err(make_error_1508(activation, "initialMode"));
    }

    // Timffle: resolve the locale against the compiled-in locale table.
    let requested = requested_locale_id_name.to_utf8_lossy().into_owned();
    let (locale, status) = locale_data::resolve(activation, &requested);
    let parsed = locale_data::parse_locale(&requested);
    let mut actual = locale.id.to_string();
    for (key, value) in &parsed.keys {
        if key == "collation" {
            actual.push_str(&format!("@collation={value}"));
        }
    }
    let actual = AvmString::new_utf8(activation.gc(), &actual);

    collator.set_requested_locale_id_name(requested_locale_id_name, activation.gc());
    collator.set_actual_locale_id_name(actual, activation.gc());
    if &initial_mode == b"matching" {
        collator.set_options(CollatorOptions::matching());
    }
    collator.set_last_operation_status(match status {
        USING_FALLBACK_WARNING => LastOperationStatus::UsingFallbackWarning,
        USING_DEFAULT_WARNING => LastOperationStatus::UsingDefaultWarning,
        _ => LastOperationStatus::NoError,
    });

    Ok(Value::Undefined)
}

pub fn get_actual_locale_id_name<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();
    let collator = this.as_collator().unwrap();

    Ok(collator.actual_locale_id_name().into())
}

pub fn get_requested_locale_id_name<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();
    let collator = this.as_collator().unwrap();

    Ok(collator.requested_locale_id_name().into())
}

macro_rules! option_accessors {
    ($getter:ident, $setter:ident, $flag:ident) => {
        pub fn $getter<'gc>(
            _activation: &mut Activation<'_, 'gc>,
            this: Value<'gc>,
            _args: FunctionArgs<'_, 'gc>,
        ) -> Result<Value<'gc>, Error<'gc>> {
            let this = this.as_object().unwrap();
            let collator = this.as_collator().unwrap();

            Ok(collator.options().contains(CollatorOptions::$flag).into())
        }

        pub fn $setter<'gc>(
            _activation: &mut Activation<'_, 'gc>,
            this: Value<'gc>,
            args: FunctionArgs<'_, 'gc>,
        ) -> Result<Value<'gc>, Error<'gc>> {
            let this = this.as_object().unwrap();
            let collator = this.as_collator().unwrap();

            collator.set_option(CollatorOptions::$flag, args.get_bool(0));
            // Timffle: every option is honoured by the collation below.
            collator.set_last_operation_status(LastOperationStatus::NoError);

            Ok(Value::Undefined)
        }
    };
}

option_accessors!(get_ignore_case, set_ignore_case, IGNORE_CASE);
option_accessors!(
    get_ignore_character_width,
    set_ignore_character_width,
    IGNORE_CHARACTER_WIDTH
);
option_accessors!(
    get_ignore_diacritics,
    set_ignore_diacritics,
    IGNORE_DIACRITICS
);
option_accessors!(get_ignore_kana_type, set_ignore_kana_type, IGNORE_KANA_TYPE);
option_accessors!(get_ignore_symbols, set_ignore_symbols, IGNORE_SYMBOLS);
option_accessors!(
    get_numeric_comparison,
    set_numeric_comparison,
    NUMERIC_COMPARISON
);

pub fn get_last_operation_status<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();
    let collator = this.as_collator().unwrap();

    Ok(collator
        .last_operation_status()
        .as_avm2_str(activation)
        .into())
}

/// The tailoring derived from the actual locale ID name.
#[derive(Clone, Copy, PartialEq, Eq)]
enum Tailoring {
    Default,
    /// Swedish/Finnish: å ä ö after z.
    Swedish,
    /// Danish/Norwegian: æ ø å after z.
    Danish,
    /// German `@collation=phonebook`: ä → ae, ö → oe, ü → ue.
    Phonebook,
}

fn tailoring_of(actual: &str) -> Tailoring {
    let parsed = locale_data::parse_locale(actual);
    let phonebook = parsed
        .keys
        .iter()
        .any(|(k, v)| k == "collation" && v == "phonebook");
    match parsed.language.as_str() {
        "sv" | "fi" => Tailoring::Swedish,
        "da" | "nb" | "nn" | "no" => Tailoring::Danish,
        "de" if phonebook => Tailoring::Phonebook,
        _ => Tailoring::Default,
    }
}

fn compare_strings<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Ordering, Error<'gc>> {
    let this = this.as_object().unwrap();
    let collator = this.as_collator().unwrap();

    let string1 = args.get_string_non_null(activation, 0, "string1")?;
    let string2 = args.get_string_non_null(activation, 1, "string2")?;
    let tailoring = tailoring_of(&collator.actual_locale_id_name().to_utf8_lossy());
    collator.set_last_operation_status(LastOperationStatus::NoError);

    Ok(collate(
        collator.options(),
        tailoring,
        &string1.to_utf8_lossy(),
        &string2.to_utf8_lossy(),
    ))
}

pub fn compare<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    Ok((compare_strings(activation, this, args)? as i32).into())
}

pub fn equals<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    Ok((compare_strings(activation, this, args)? == Ordering::Equal).into())
}

/// A run of digits, compared by numeric value when `numericComparison` is on.
#[derive(PartialEq, Eq)]
struct DigitRun(String);

impl Ord for DigitRun {
    fn cmp(&self, other: &Self) -> Ordering {
        let a = self.0.trim_start_matches('0');
        let b = other.0.trim_start_matches('0');
        a.len().cmp(&b.len()).then_with(|| a.cmp(b))
    }
}

impl PartialOrd for DigitRun {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

/// Primary collation weight. The variant order is the UCA order of the
/// character groups: whitespace, punctuation, symbols, digits, letters.
#[derive(PartialEq, Eq, PartialOrd, Ord)]
enum Primary {
    Space(u32),
    Punct(u32),
    Symbol(u32),
    Digits(DigitRun),
    Latin(u8),
    Other(u32),
}

struct Element {
    primary: Primary,
    secondary: Vec<u32>,
    case: u8,
    width: u8,
    kana: u8,
}

/// UCA order of the ASCII punctuation and symbols.
const PUNCTUATION_ORDER: &str = "_-,;:!?.'\"()[]{}@*/\\&#%`^+<=>|~$";

fn is_variable(c: char) -> bool {
    !(c.is_alphanumeric() || is_combining_mark(c))
}

fn classify(c: char) -> Primary {
    if c.is_whitespace() {
        return Primary::Space(0);
    }
    if let Some(d) = digit_value(c) {
        return Primary::Digits(DigitRun(d.to_string()));
    }
    if let Some(idx) = PUNCTUATION_ORDER.find(c) {
        return Primary::Punct(idx as u32);
    }
    if c.is_ascii_lowercase() {
        return Primary::Latin(c as u8 - b'a');
    }
    if c.is_alphabetic() {
        return Primary::Other(c as u32);
    }
    Primary::Symbol(c as u32)
}

/// Pseudo-diacritic weights for letters that NFKD does not decompose.
const STROKE: u32 = 0x338;
/// Marks the first half of an expansion (`æ` → a+e, `ß` → s+s). Timffle: Flash 32
/// (Windows) compares an expansion equal to its letters (`æ` = `ae`, `ß` = `ss`,
/// measured for en-US, zh-TW, zh-CN, ja-JP, de-DE and sv-SE), so this mark only
/// identifies the letter for the Danish tailoring and is not compared.
const LIGATURE: u32 = 0x1;
/// Secondary weight of the German phonebook `ä` → a+e expansion (compared).
const PHONEBOOK_UMLAUT: u32 = 0x2;

fn push_letter(
    elements: &mut Vec<Element>,
    c: char,
    case: u8,
    width: u8,
    kana_type: u8,
    tailoring: Tailoring,
) {
    let mut push = |base: char, extra_secondary: Option<u32>, kana: u8| {
        let mut secondary = Vec::new();
        if let Some(mark) = extra_secondary {
            secondary.push(mark);
        }
        elements.push(Element {
            primary: classify(base),
            secondary,
            case,
            width,
            kana,
        });
    };
    match c {
        'æ' => {
            push('a', Some(LIGATURE), 0);
            push('e', None, 0);
        }
        'œ' => {
            push('o', Some(LIGATURE), 0);
            push('e', None, 0);
        }
        'ß' => {
            push('s', Some(LIGATURE), 0);
            push('s', None, 0);
        }
        'ø' => push('o', Some(STROKE), 0),
        'đ' | 'ð' => push('d', Some(STROKE), 0),
        'ł' => push('l', Some(STROKE), 0),
        'ħ' => push('h', Some(STROKE), 0),
        'ı' => push('i', Some(STROKE), 0),
        'þ' => {
            push('t', Some(LIGATURE), 0);
            push('h', None, 0);
        }
        '\u{30a1}'..='\u{30fa}' => {
            // Katakana → the hiragana of the same syllable at the primary level.
            let hiragana = char::from_u32(c as u32 - 0x60).unwrap_or(c);
            push(hiragana, None, 1);
        }
        _ => push(c, None, kana_type),
    }
    let _ = tailoring;
}

/// Applies the locale tailoring to an element whose base letter and
/// diacritics are known.
fn tailor(element: &mut Element, tailoring: Tailoring) -> Option<Element> {
    let Primary::Latin(letter) = element.primary else {
        return None;
    };
    let base = (b'a' + letter) as char;
    let marks = element.secondary.clone();
    let has = |m: u32| marks.contains(&m);
    match tailoring {
        Tailoring::Swedish => {
            let index = match base {
                'a' if has(0x30A) => Some(27),
                'a' if has(0x308) => Some(28),
                'o' if has(0x308) || has(STROKE) => Some(29),
                _ => None,
            };
            if let Some(i) = index {
                element.primary = Primary::Latin(i);
                element.secondary.clear();
            }
            None
        }
        Tailoring::Danish => {
            let index = match base {
                'a' if has(LIGATURE) || has(0x308) => Some(27),
                'o' if has(STROKE) || has(0x308) => Some(28),
                'a' if has(0x30A) => Some(29),
                _ => None,
            };
            if let Some(i) = index {
                element.primary = Primary::Latin(i);
                element.secondary.clear();
            }
            None
        }
        Tailoring::Phonebook => {
            if matches!(base, 'a' | 'o' | 'u') && has(0x308) {
                element.secondary.retain(|m| *m != 0x308);
                element.secondary.push(PHONEBOOK_UMLAUT);
                return Some(Element {
                    primary: Primary::Latin(b'e' - b'a'),
                    secondary: Vec::new(),
                    case: element.case,
                    width: element.width,
                    kana: element.kana,
                });
            }
            None
        }
        Tailoring::Default => None,
    }
}

/// Timffle: Windows "word sort", which Flash 32 uses: the hyphen and the apostrophe have
/// no weight of their own (`a-b` and `O'Brian` sort next to `ab` and `OBrian`); on an
/// otherwise equal comparison the string that has them sorts after (measured).
fn is_word_sort_ignorable(c: char) -> bool {
    matches!(c, '-' | '\'')
}

fn elements(s: &str, options: CollatorOptions, tailoring: Tailoring) -> Vec<Element> {
    let mut elements: Vec<Element> = Vec::new();
    for c in s.chars() {
        if is_word_sort_ignorable(c) {
            continue;
        }
        let width = match c as u32 {
            0xFF01..=0xFF60 | 0xFFE0..=0xFFE6 => 1,
            0xFF61..=0xFFDC | 0xFFE8..=0xFFEE => 2,
            _ => 0,
        };
        let start = elements.len();
        for d in c.nfkd() {
            if is_combining_mark(d) {
                if let Some(last) = elements.last_mut() {
                    last.secondary.push(d as u32);
                }
                continue;
            }
            let case = u8::from(d.is_uppercase());
            for lower in d.to_lowercase() {
                if is_combining_mark(lower) {
                    if let Some(last) = elements.last_mut() {
                        last.secondary.push(lower as u32);
                    }
                    continue;
                }
                push_letter(&mut elements, lower, case, width, 0, tailoring);
            }
        }
        if tailoring != Tailoring::Default {
            let mut extra = Vec::new();
            for (i, element) in elements[start..].iter_mut().enumerate() {
                if let Some(e) = tailor(element, tailoring) {
                    extra.push((start + i + 1, e));
                }
            }
            for (i, e) in extra.into_iter().rev() {
                elements.insert(i, e);
            }
        }
    }

    if options.contains(CollatorOptions::IGNORE_SYMBOLS) {
        elements.retain(|e| {
            !matches!(
                e.primary,
                Primary::Space(_) | Primary::Punct(_) | Primary::Symbol(_)
            )
        });
    }

    if options.contains(CollatorOptions::NUMERIC_COMPARISON) {
        let mut merged: Vec<Element> = Vec::with_capacity(elements.len());
        for element in elements {
            if let (
                Some(Element {
                    primary: Primary::Digits(run),
                    ..
                }),
                Primary::Digits(next),
            ) = (merged.last_mut(), &element.primary)
            {
                run.0.push_str(&next.0);
                continue;
            }
            merged.push(element);
        }
        return merged;
    }
    elements
}

/// Compares two strings with the given options and tailoring.
fn collate(options: CollatorOptions, tailoring: Tailoring, s1: &str, s2: &str) -> Ordering {
    let e1 = elements(s1, options, tailoring);
    let e2 = elements(s2, options, tailoring);

    let primary = e1
        .iter()
        .map(|e| &e.primary)
        .cmp(e2.iter().map(|e| &e.primary));
    if primary != Ordering::Equal {
        return primary;
    }
    if !options.contains(CollatorOptions::IGNORE_DIACRITICS) {
        let marks = |e: &Element| -> Vec<u32> {
            e.secondary
                .iter()
                .copied()
                .filter(|m| *m != LIGATURE)
                .collect()
        };
        let secondary = e1.iter().map(marks).cmp(e2.iter().map(marks));
        if secondary != Ordering::Equal {
            return secondary;
        }
    }
    if !options.contains(CollatorOptions::IGNORE_CASE) {
        let tertiary = e1.iter().map(|e| e.case).cmp(e2.iter().map(|e| e.case));
        if tertiary != Ordering::Equal {
            return tertiary;
        }
    }
    if !options.contains(CollatorOptions::IGNORE_CHARACTER_WIDTH) {
        let width = e1.iter().map(|e| e.width).cmp(e2.iter().map(|e| e.width));
        if width != Ordering::Equal {
            return width;
        }
    }
    if !options.contains(CollatorOptions::IGNORE_KANA_TYPE) {
        let kana = e1.iter().map(|e| e.kana).cmp(e2.iter().map(|e| e.kana));
        if kana != Ordering::Equal {
            return kana;
        }
    }
    let _ = is_variable;
    if !options.contains(CollatorOptions::IGNORE_SYMBOLS) {
        let ignorable = |s: &str| s.chars().filter(|c| is_word_sort_ignorable(*c)).count();
        return ignorable(s1).cmp(&ignorable(s2));
    }
    Ordering::Equal
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
