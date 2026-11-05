//! Timffle: the `<flashrichtext>` format of `TextField.getXMLText` / `insertXMLText`.
//!
//! Measured in Flash Player 32 (timffle/difftest/src/S2Text.hx): `getXMLText` writes
//!
//! ```text
//! <flashrichtext version="1">
//!   <textformat font="Times New Roman" size="12" color="0" bold="false" … display="block">(Hello )</textformat>
//! </flashrichtext>
//! ```
//!
//! one `<textformat>` per format run with all 16 attributes (colour in decimal), the
//! run's text in parentheses with `<`, `>` and `&` escaped and paragraph breaks as
//! "\n". `insertXMLText` reads the same document back: every attribute is optional
//! and carries over to the next `<textformat>`, text outside parentheses is a range
//! error, and anything that is not such a document is a parse error.

use super::{FormatSpans, TextDisplay, TextFormat};
use crate::string::{WStr, WString};

/// Why `insertXMLText` refused a document.
pub enum RichTextError {
    /// Not a `<flashrichtext>` document (`Error #2138`).
    Parse,
    /// A run's text is not wrapped in parentheses (`RangeError #2006`).
    Range,
}

/// One `<textformat>` run: its text (paragraph breaks as "\r") and attributes.
pub struct RichTextRun {
    pub text: WString,
    pub attributes: Vec<(String, String)>,
}

fn number(v: f64) -> String {
    if v.fract() == 0.0 && v.abs() < 1e15 {
        format!("{}", v as i64)
    } else {
        format!("{v}")
    }
}

fn escape(text: &WStr) -> String {
    let mut out = String::new();
    for c in text.to_utf8_lossy().chars() {
        match c {
            '<' => out.push_str("&lt;"),
            '>' => out.push_str("&gt;"),
            '&' => out.push_str("&amp;"),
            '\r' => out.push('\n'),
            other => out.push(other),
        }
    }
    out
}

/// Writes `spans` (already cut to the wanted range) as a `<flashrichtext>` document.
pub fn to_flash_rich_text(spans: &FormatSpans) -> WString {
    let mut out = String::from("<flashrichtext version=\"1\">\n");
    for (start, end, text, span) in spans.iter_spans() {
        if start >= end {
            continue;
        }
        let align = match span.align {
            swf::TextAlign::Left => "left",
            swf::TextAlign::Right => "right",
            swf::TextAlign::Center => "center",
            swf::TextAlign::Justify => "justify",
        };
        let display = match span.display {
            TextDisplay::Block => "block",
            TextDisplay::Inline => "inline",
            TextDisplay::None => "none",
        };
        out.push_str(&format!(
            "  <textformat font=\"{}\" size=\"{}\" color=\"{}\" bold=\"{}\" italic=\"{}\" underline=\"{}\" url=\"{}\" target=\"{}\" align=\"{}\" leftMargin=\"{}\" rightMargin=\"{}\" indent=\"{}\" leading=\"{}\" blockIndent=\"{}\" kerning=\"{}\" letterSpacing=\"{}\" display=\"{}\">({})</textformat>\n",
            escape(&span.font.face),
            number(span.font.size),
            span.font.color.to_rgb(),
            span.style.bold,
            span.style.italic,
            span.style.underline,
            escape(&span.url),
            escape(&span.target),
            align,
            number(span.left_margin),
            number(span.right_margin),
            number(span.indent),
            number(span.leading),
            number(span.block_indent),
            span.font.kerning,
            number(span.font.letter_spacing),
            display,
            escape(text),
        ));
    }
    out.push_str("</flashrichtext>");
    WString::from_utf8(&out)
}

fn unescape(s: &str) -> String {
    s.replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&quot;", "\"")
        .replace("&apos;", "'")
        .replace("&amp;", "&")
}

/// Reads `name="value"` pairs up to the end of a start tag. Returns the
/// attributes, whether the tag is self-closing, and the rest after `>`.
fn parse_attributes(mut s: &str) -> Option<(Vec<(String, String)>, bool, &str)> {
    let mut attributes = Vec::new();
    loop {
        s = s.trim_start();
        if let Some(rest) = s.strip_prefix("/>") {
            return Some((attributes, true, rest));
        }
        if let Some(rest) = s.strip_prefix('>') {
            return Some((attributes, false, rest));
        }
        let eq = s.find('=')?;
        let name = s[..eq].trim();
        if name.is_empty() || !name.chars().all(|c| c.is_ascii_alphanumeric() || c == '_') {
            return None;
        }
        let rest = s[eq + 1..].trim_start();
        let quote = rest.chars().next().filter(|q| *q == '"' || *q == '\'')?;
        let rest = &rest[1..];
        let close = rest.find(quote)?;
        attributes.push((name.to_string(), unescape(&rest[..close])));
        s = &rest[close + 1..];
    }
}

/// Parses a `<flashrichtext>` document into its runs.
pub fn parse_flash_rich_text(xml: &WStr) -> Result<Vec<RichTextRun>, RichTextError> {
    let xml = xml.to_utf8_lossy();
    let s = xml.trim();
    let s = s
        .strip_prefix("<flashrichtext")
        .ok_or(RichTextError::Parse)?;
    let (_, self_closing, mut s) = parse_attributes(s).ok_or(RichTextError::Parse)?;
    if self_closing {
        return if s.trim().is_empty() {
            Ok(Vec::new())
        } else {
            Err(RichTextError::Parse)
        };
    }
    let mut runs = Vec::new();
    let mut range_error = false;
    loop {
        s = s.trim_start();
        if let Some(rest) = s.strip_prefix("</flashrichtext>") {
            if !rest.trim().is_empty() {
                return Err(RichTextError::Parse);
            }
            break;
        }
        let rest = s.strip_prefix("<textformat").ok_or(RichTextError::Parse)?;
        let (attributes, self_closing, rest) =
            parse_attributes(rest).ok_or(RichTextError::Parse)?;
        if self_closing {
            s = rest;
            continue;
        }
        let close = rest.find("</textformat>").ok_or(RichTextError::Parse)?;
        let content = unescape(&rest[..close]);
        s = &rest[close + "</textformat>".len()..];
        match content.strip_prefix('(').and_then(|c| c.strip_suffix(')')) {
            Some(text) => runs.push(RichTextRun {
                text: WString::from_utf8(&text.replace("\r\n", "\r").replace('\n', "\r")),
                attributes,
            }),
            None => range_error = true,
        }
    }
    if range_error {
        return Err(RichTextError::Range);
    }
    Ok(runs)
}

/// Applies one run's attributes on top of `format` (attributes carry over to the
/// next run, as in Flash Player 32).
pub fn apply_attributes(format: &mut TextFormat, attributes: &[(String, String)]) {
    let num = |v: &str| v.trim().parse::<f64>().ok();
    for (name, value) in attributes {
        match name.as_str() {
            "font" => format.font = Some(WString::from_utf8(value)),
            "size" => format.size = num(value).or(format.size),
            "color" => {
                if let Some(c) = num(value) {
                    format.color = Some(swf::Color::from_rgb(c as u32, 255));
                }
            }
            "bold" => format.bold = Some(value == "true"),
            "italic" => format.italic = Some(value == "true"),
            "underline" => format.underline = Some(value == "true"),
            "url" => format.url = Some(WString::from_utf8(value)),
            "target" => format.target = Some(WString::from_utf8(value)),
            "align" => {
                format.align = match value.as_str() {
                    "left" => Some(swf::TextAlign::Left),
                    "right" => Some(swf::TextAlign::Right),
                    "center" => Some(swf::TextAlign::Center),
                    "justify" => Some(swf::TextAlign::Justify),
                    _ => format.align,
                }
            }
            "leftMargin" => format.left_margin = num(value).or(format.left_margin),
            "rightMargin" => format.right_margin = num(value).or(format.right_margin),
            "indent" => format.indent = num(value).or(format.indent),
            "leading" => format.leading = num(value).or(format.leading),
            "blockIndent" => format.block_indent = num(value).or(format.block_indent),
            // Flash 32 reads `kerning` as a number: "false" (NaN) turns kerning on, as
            // `getXMLText` → `insertXMLText` round trips show; only "0" turns it off.
            "kerning" => format.kerning = Some(num(value) != Some(0.0)),
            "letterSpacing" => format.letter_spacing = num(value).or(format.letter_spacing),
            "display" => {
                format.display = match value.as_str() {
                    "block" => Some(TextDisplay::Block),
                    "inline" => Some(TextDisplay::Inline),
                    "none" => Some(TextDisplay::None),
                    _ => format.display,
                }
            }
            _ => {}
        }
    }
}
