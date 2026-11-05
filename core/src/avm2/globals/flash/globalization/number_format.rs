//! Timffle: number formatting and parsing shared by
//! `flash.globalization.NumberFormatter` and `CurrencyFormatter`.
//!
//! Flash Player hands these operations to the OS (`GetNumberFormatEx` on
//! Windows, ICU elsewhere). Here they are implemented directly, following the
//! Adobe reference: grouping patterns (`"3;*"`, `"3;2;*"`, `"3"`), the
//! `leadingZero`/`trailingZeros` table, the five `negativeNumberFormat`
//! layouts, national digit sets, and the `parse()` rules (first number in the
//! string, grouping separators accepted anywhere in the integer part, one
//! optional space before a minus sign or closing parenthesis).

/// Formatting settings read from a formatter object.
pub struct NumberSettings {
    pub decimal_separator: String,
    pub grouping_separator: String,
    pub digits_type: u32,
    pub fractional_digits: i32,
    pub grouping_pattern: String,
    pub leading_zero: bool,
    pub trailing_zeros: bool,
    pub use_grouping: bool,
    pub negative_symbol: String,
    pub negative_number_format: u32,
}

/// Parses a grouping pattern such as `"3;*"`. Returns the group sizes (nearest
/// the decimal separator first) and whether the last size repeats.
pub fn parse_grouping_pattern(pattern: &str) -> Option<(Vec<usize>, bool)> {
    let mut sizes = Vec::new();
    let mut repeat = false;
    let parts: Vec<&str> = pattern.split(';').collect();
    for (i, part) in parts.iter().enumerate() {
        let part = part.trim();
        if part == "*" {
            if i != parts.len() - 1 || sizes.is_empty() {
                return None;
            }
            repeat = true;
        } else {
            let size: usize = part.parse().ok()?;
            if size == 0 {
                return None;
            }
            sizes.push(size);
        }
    }
    if sizes.is_empty() {
        return None;
    }
    Some((sizes, repeat))
}

/// Exact decimal expansion of `value` (finite, non-negative) rounded half away
/// from zero to `fractional_digits` places, as `(integer digits, fraction digits)`.
fn round_decimal(value: f64, fractional_digits: usize) -> (String, String) {
    // Rust prints the exact decimal expansion for a fixed precision.
    const EXTRA: usize = 40;
    let expanded = format!("{:.*}", EXTRA, value);
    let (int_part, frac_part) = expanded.split_once('.').unwrap_or((&expanded, ""));
    let frac: Vec<u8> = frac_part.bytes().collect();
    let mut digits: Vec<u8> = int_part
        .bytes()
        .chain(frac[..fractional_digits.min(frac.len())].iter().copied())
        .collect();
    let round_up = frac.get(fractional_digits).is_some_and(|d| *d >= b'5');
    if round_up {
        let mut i = digits.len();
        loop {
            if i == 0 {
                digits.insert(0, b'1');
                break;
            }
            i -= 1;
            if digits[i] == b'9' {
                digits[i] = b'0';
            } else {
                digits[i] += 1;
                break;
            }
        }
    }
    let split = digits.len() - fractional_digits.min(frac.len());
    let int_digits = String::from_utf8_lossy(&digits[..split]).into_owned();
    let mut frac_digits = String::from_utf8_lossy(&digits[split..]).into_owned();
    while frac_digits.len() < fractional_digits {
        frac_digits.push('0');
    }
    (int_digits, frac_digits)
}

fn apply_grouping(int_digits: &str, settings: &NumberSettings) -> String {
    let Some((sizes, repeat)) = parse_grouping_pattern(&settings.grouping_pattern) else {
        return int_digits.to_string();
    };
    let digits: Vec<char> = int_digits.chars().collect();
    let mut groups: Vec<String> = Vec::new();
    let mut end = digits.len();
    let mut idx = 0;
    while end > 0 {
        let size = if idx < sizes.len() {
            sizes[idx]
        } else if repeat {
            sizes[sizes.len() - 1]
        } else {
            end
        };
        let start = end.saturating_sub(size);
        groups.push(digits[start..end].iter().collect());
        end = start;
        idx += 1;
    }
    groups.reverse();
    groups.join(&settings.grouping_separator)
}

fn substitute_digits(s: &str, digits_type: u32) -> String {
    if digits_type == 0x30 {
        return s.to_string();
    }
    s.chars()
        .map(|c| {
            if c.is_ascii_digit() {
                char::from_u32(digits_type + (c as u32 - '0' as u32)).unwrap_or(c)
            } else {
                c
            }
        })
        .collect()
}

/// Formats the magnitude of `value` (no sign) with the given settings.
pub fn format_magnitude(value: f64, settings: &NumberSettings) -> String {
    if value.is_nan() {
        return "NaN".to_string();
    }
    if value.is_infinite() {
        return "Infinity".to_string();
    }
    let fractional_digits = settings.fractional_digits.clamp(0, 30) as usize;
    let (int_digits, mut frac_digits) = round_decimal(value.abs(), fractional_digits);

    if !settings.trailing_zeros {
        while frac_digits.ends_with('0') {
            frac_digits.pop();
        }
    }

    let mut out = if settings.use_grouping {
        apply_grouping(&int_digits, settings)
    } else {
        int_digits.clone()
    };
    if !settings.leading_zero && int_digits == "0" && !frac_digits.is_empty() {
        out.clear();
    }
    if !frac_digits.is_empty() {
        out.push_str(&settings.decimal_separator);
        out.push_str(&frac_digits);
    }
    substitute_digits(&out, settings.digits_type)
}

/// Formats `value` with the sign laid out per `negativeNumberFormat`.
pub fn format_number(value: f64, settings: &NumberSettings) -> String {
    let magnitude = format_magnitude(value, settings);
    if value.is_nan() || value >= 0.0 {
        return magnitude;
    }
    let minus = &settings.negative_symbol;
    match settings.negative_number_format {
        0 => format!("({magnitude})"),
        2 => format!("{minus} {magnitude}"),
        3 => format!("{magnitude}{minus}"),
        4 => format!("{magnitude} {minus}"),
        _ => format!("{minus}{magnitude}"),
    }
}

/// Zero code points of the digit sets in `NationalDigitsType`.
const DIGIT_ZEROS: &[u32] = &[
    0x0030, 0x0660, 0x06F0, 0x07C0, 0x0966, 0x09E6, 0x0A66, 0x0AE6, 0x0B66, 0x0BE6, 0x0C66, 0x0CE6,
    0x0D66, 0x0E50, 0x0ED0, 0x0F20, 0x1040, 0x1090, 0x17E0, 0x1810, 0x1946, 0x19D0, 0x1B50, 0x1BB0,
    0x1C40, 0x1C50, 0xA620, 0xA8D0, 0xA900, 0xAA50, 0xFF10, 0x104A0,
];

pub fn digit_value(c: char) -> Option<u32> {
    let cp = c as u32;
    DIGIT_ZEROS
        .iter()
        .find(|zero| cp >= **zero && cp < **zero + 10)
        .map(|zero| cp - zero)
}

/// Unicode `Zs` (space separator) characters, the whitespace `parseNumber()` ignores.
pub fn is_space_separator(c: char) -> bool {
    matches!(
        c,
        ' ' | '\u{a0}' | '\u{1680}' | '\u{2000}'
            ..='\u{200a}' | '\u{202f}' | '\u{205f}' | '\u{3000}'
    )
}

fn starts_with_at(chars: &[char], at: usize, s: &str) -> bool {
    if s.is_empty() {
        return false;
    }
    let needle: Vec<char> = s.chars().collect();
    chars.len() >= at + needle.len() && chars[at..at + needle.len()] == needle[..]
}

/// Tries to read the digits of a number (integer part with grouping
/// separators, optional decimal separator and fraction) at `at`.
/// Returns the value and the index after the number.
fn match_digits(chars: &[char], at: usize, settings: &NumberSettings) -> Option<(f64, usize)> {
    let group_len = settings.grouping_separator.chars().count();
    let decimal_len = settings.decimal_separator.chars().count();
    let mut i = at;
    let mut text = String::new();
    let mut int_digits = 0;
    while i < chars.len() {
        if let Some(d) = digit_value(chars[i]) {
            text.push(char::from_digit(d, 10).unwrap_or('0'));
            int_digits += 1;
            i += 1;
        } else if int_digits > 0
            && starts_with_at(chars, i, &settings.grouping_separator)
            && chars
                .get(i + group_len)
                .is_some_and(|c| digit_value(*c).is_some())
        {
            i += group_len;
        } else {
            break;
        }
    }
    let mut frac_digits = 0;
    if starts_with_at(chars, i, &settings.decimal_separator)
        && chars
            .get(i + decimal_len)
            .is_some_and(|c| digit_value(*c).is_some())
    {
        i += decimal_len;
        text.push('.');
        while let Some(d) = chars.get(i).and_then(|c| digit_value(*c)) {
            text.push(char::from_digit(d, 10).unwrap_or('0'));
            frac_digits += 1;
            i += 1;
        }
    }
    if int_digits == 0 && frac_digits == 0 {
        return None;
    }
    if int_digits == 0 {
        text.insert(0, '0');
    }
    let value: f64 = text.parse().ok()?;
    Some((value, i))
}

/// Tries to match a number, with the negative layout of
/// `negativeNumberFormat`, starting exactly at `at`.
fn match_number_at(chars: &[char], at: usize, settings: &NumberSettings) -> Option<(f64, usize)> {
    let minus_len = settings.negative_symbol.chars().count();
    let format = settings.negative_number_format;
    let mut i = at;
    let mut negative = false;

    match format {
        0 if chars.get(i) == Some(&'(') => {
            negative = true;
            i += 1;
            if chars.get(i) == Some(&' ') {
                i += 1;
            }
        }
        1 | 2 if starts_with_at(chars, i, &settings.negative_symbol) => {
            negative = true;
            i += minus_len;
            if chars.get(i) == Some(&' ') {
                i += 1;
            }
        }
        _ => {}
    }

    let (value, mut end) = match match_digits(chars, i, settings) {
        Some(found) => found,
        None if negative => return match_digits(chars, at, settings),
        None => return None,
    };

    match format {
        0 if negative => {
            let mut j = end;
            if chars.get(j) == Some(&' ') {
                j += 1;
            }
            if chars.get(j) == Some(&')') {
                end = j + 1;
            } else {
                // "(123" without the closing parenthesis: not a negative number.
                return None;
            }
        }
        3 | 4 => {
            let mut j = end;
            if chars.get(j) == Some(&' ') {
                j += 1;
            }
            if starts_with_at(chars, j, &settings.negative_symbol) {
                negative = true;
                end = j + minus_len;
            }
        }
        _ => {}
    }

    Some((if negative { -value } else { value }, end))
}

/// Finds the first number in `input` (`NumberFormatter.parse()`).
/// Returns `(value, startIndex, endIndex)`.
pub fn parse_first_number(input: &str, settings: &NumberSettings) -> Option<(f64, usize, usize)> {
    let chars: Vec<char> = input.chars().collect();
    for start in 0..chars.len() {
        if let Some((value, end)) = match_number_at(&chars, start, settings) {
            return Some((value, start, end));
        }
    }
    None
}

/// Parses a string that must contain only a number and `Zs` whitespace
/// (`NumberFormatter.parseNumber()`).
pub fn parse_whole_number(input: &str, settings: &NumberSettings) -> Option<f64> {
    let trimmed = input.trim_matches(is_space_separator);
    let chars: Vec<char> = trimmed.chars().collect();
    if chars.is_empty() {
        return None;
    }
    match match_number_at(&chars, 0, settings) {
        Some((value, end)) if end == chars.len() => Some(value),
        _ => None,
    }
}

/// What `CurrencyFormatter.parse()` found.
pub enum CurrencyParse {
    /// The value and the currency string.
    Found(f64, String),
    /// The input has nothing but whitespace (`illegalArgumentError`).
    Empty,
    /// No layout matched (`parseError`).
    NoMatch,
}

/// Matches the text on one side of the number against that side of a
/// currency layout (`¤` currency text, `-` the negative symbol, `(`/`)`
/// literals, ` ` an optional space). `before` is true for the text in front
/// of the number. Returns the currency text the `¤` covered.
fn match_currency_side(
    text: &[char],
    pattern: &str,
    before: bool,
    minus: &[char],
) -> Option<String> {
    let pattern: Vec<char> = pattern.chars().filter(|c| *c != ' ').collect();
    let mut text = text;
    let cur_at = pattern.iter().position(|c| *c == '¤');
    let (outer, inner): (&[char], &[char]) = match cur_at {
        Some(i) => (&pattern[..i], &pattern[i + 1..]),
        None => (&pattern[..], &[]),
    };
    let lit = |c: char| -> Vec<char> { if c == '-' { minus.to_vec() } else { vec![c] } };
    // Literals on the outer side of the currency text (string edge).
    let (edge, near): (&[char], &[char]) = if before { (outer, inner) } else { (inner, outer) };
    let take_front = |t: &mut &[char], c: char| -> bool {
        let l = lit(c);
        if t.len() >= l.len() && t[..l.len()] == l[..] {
            *t = &t[l.len()..];
            true
        } else {
            false
        }
    };
    let take_back = |t: &mut &[char], c: char| -> bool {
        let l = lit(c);
        if t.len() >= l.len() && t[t.len() - l.len()..] == l[..] {
            *t = &t[..t.len() - l.len()];
            true
        } else {
            false
        }
    };
    if before {
        for c in edge {
            if !take_front(&mut text, *c) {
                return None;
            }
        }
        for c in near.iter().rev() {
            if !take_back(&mut text, *c) {
                return None;
            }
        }
    } else {
        for c in near {
            if !take_front(&mut text, *c) {
                return None;
            }
        }
        for c in edge.iter().rev() {
            if !take_back(&mut text, *c) {
                return None;
            }
        }
    }
    if cur_at.is_none() {
        return if text.iter().all(|c| is_space_separator(*c)) && text.len() <= 1 {
            Some(String::new())
        } else {
            None
        };
    }
    // One space next to the number belongs to the layout (Flash 32: "$  5" -> "$ ", "5  €" -> " €").
    let mut cur: Vec<char> = text.to_vec();
    if before {
        if cur.last().is_some_and(|c| is_space_separator(*c)) {
            cur.pop();
        }
    } else if cur.first().is_some_and(|c| is_space_separator(*c)) {
        cur.remove(0);
    }
    let contains_minus = !minus.is_empty() && cur.windows(minus.len()).any(|w| w == minus);
    if contains_minus || cur.iter().any(|c| matches!(c, '(' | ')') || digit_value(*c).is_some()) {
        return None;
    }
    Some(cur.into_iter().collect())
}

/// `CurrencyFormatter.parse()`, measured in Flash Player 32: the input is trimmed, the
/// number (grouping separators anywhere in the integer part, an optional decimal part)
/// splits it into the text before and after, and that text has to fit the positive or
/// the negative currency layout exactly — the currency text on the layout's side, the
/// sign as the layout writes it (`-` = `negativeSymbol`, or parentheses). The currency
/// string is whatever text stands where the layout's `¤` is.
pub fn parse_currency(
    input: &str,
    settings: &NumberSettings,
    positive_layout: &str,
    negative_layout: &str,
) -> CurrencyParse {
    let trimmed = input.trim_matches(is_space_separator);
    if trimmed.is_empty() {
        return CurrencyParse::Empty;
    }
    let chars: Vec<char> = trimmed.chars().collect();
    let decimal: Vec<char> = settings.decimal_separator.chars().collect();
    let starts_number = |i: usize| -> bool {
        digit_value(chars[i]).is_some()
            || (!decimal.is_empty()
                && chars.len() > i + decimal.len()
                && chars[i..i + decimal.len()] == decimal[..]
                && digit_value(chars[i + decimal.len()]).is_some())
    };
    let Some(start) = (0..chars.len()).find(|i| starts_number(*i)) else {
        return CurrencyParse::NoMatch;
    };
    let Some((value, mut end)) = match_digits(&chars, start, settings) else {
        return CurrencyParse::NoMatch;
    };
    // "$5." — a decimal separator with no digits after it still belongs to the number.
    if !decimal.is_empty()
        && chars.len() >= end + decimal.len()
        && chars[end..end + decimal.len()] == decimal[..]
    {
        end += decimal.len();
    }
    let prefix = &chars[..start];
    let suffix = &chars[end..];
    let minus: Vec<char> = settings.negative_symbol.chars().collect();
    for (layout, negative) in [(positive_layout, false), (negative_layout, true)] {
        let Some((before, after)) = layout.split_once('n') else {
            continue;
        };
        let lead = match_currency_side(prefix, before, true, &minus);
        let trail = match_currency_side(suffix, after, false, &minus);
        if let (Some(lead), Some(trail)) = (lead, trail) {
            let currency = if before.contains('¤') { lead } else { trail };
            return CurrencyParse::Found(if negative { -value } else { value }, currency);
        }
    }
    CurrencyParse::NoMatch
}
