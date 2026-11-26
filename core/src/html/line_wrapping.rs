use crate::font::{EvalParameters, FontLike};
use crate::prelude::*;
use crate::string::WStr;
use ruffle_wstr::utils::{swf_is_cjk_like, swf_is_closing, swf_is_opening};

use itertools::Itertools;

// FP line wrapping behavior summary.
// NOTE: this is derived from experiment and is not guaranteed to fully match FP.
// SWF >= 8:
// - In ASCII, only allowed wrapping points are after '-' and after (runs of) spaces.
// - Given "aaa    bbb", the splitting (observed by getLineLength()) works as if
//   the text was split into "aaa    " and "bbb",
//   but for the purposes of width measurement, they behave like "aaa" and "    bbb".
//   (this behaves as-if spaces were "collapsed")
// - Break is allowed on any side of CJK characters
// - BUT if CJK has a matching opening/closing character on its side, don't break.
//   the opening/closing character doesn't need to be CJK, can be just '('.
// - Fallback when even 1st slice doesn't fit: break on last fitting char.
// - Final fallback:
//   if nothing fits, fit one character per line (it'll get cut off visually).

// SWF <= 7 differences:
// - Breaks are allowed on both sides of '-'.
// - Any space is a valid break point.
// - Spaces are not collapsed; only the final space of the slice (if present)
//   is dropped for measurements.
//   (this means we can never split "a " apart, since its space never counts)
// - Final fallback:
//   if resulting length has <=1 char, yield entire line without wrapping.

/// Given a line of text, find the first breakpoint within the text.
/// This assumes the input doesn't contain any mandatory breaks (newlines).
///
/// The given `offset` determines the start of the initial line, while the
/// `width` indicates how long the line is supposed to be. Be careful to
/// note that it is possible for this function to return `0`; that
/// indicates that the string itself cannot fit on the line and should
/// break onto the next one.
/// If is_start_of_line, the function is guaranteed to not return 0.
///
/// This function yields `None` if the line is not broken.
pub fn wrap_line<'gc, T: FontLike<'gc>>(
    font: &T,
    text: &WStr,
    params: EvalParameters,
    width: Twips,
    offset: Twips,
    mut is_start_of_line: bool,
    swf_version: u8,
) -> Option<usize> {
    let swf8 = swf_version >= 8;

    if text.is_empty() {
        return None;
    }

    let mut remaining_width = width - offset;
    if remaining_width < Twips::ZERO {
        if swf8 {
            // If even 1st char doesn't fit, let's write _anything_.
            return Some(1);
        } else {
            // If even 1st char doesn't fit, give up on wrapping.
            return None;
        }
    }

    let mut line_end = 0;

    let allowed_breaks = find_allowed_breaks(text, swf8);

    let mut last_stop = 0;
    for (i, word_end) in allowed_breaks.into_iter().enumerate() {
        let word_start = last_stop;

        let word = &text[word_start..word_end];

        debug_assert!(!word.is_empty());
        if word.is_empty() {
            tracing::error!("Tried to fit an empty span during line breaking");
            continue;
        }

        let trimmed_word = if swf8 {
            // Given "aaa      bbb",
            //  the allowed break "splits" the text to "aaa     " and "bbb".
            //  but we want to measure "aaa", then check if "     bbb" still fits.
            // The way we do it is, when measuring "aaa     ", we pretend it's "aaa"
            //  and when measuring "bbb", we pretend it's "     bbb".
            // So given "a  b ", the checked words are:
            // - word: "a  ", trimmed_word: "a",
            // - word: "  b ", trimmed_word: "  b",
            // Timffle: no-break spaces join that trailing run when it holds a
            // real space, and also hang at the start of a line (see
            // `trim_hanging`).
            trim_hanging(word, is_start_of_line)
        } else {
            // The swf7 difference is that every space is a break point
            //  and we only trim the final space,
            // So given "a  b ", the checked words are:
            // - word: "a ", trimmed_word: "a",
            // - word: "  ", trimmed_word: " ",
            // - word: " b ", trimmed_word: " b",

            if word.get(word.len() - 1) == Some(b' ' as u16) {
                &word[..word.len() - 1]
            } else {
                word
            }
        };

        let trimmed_word_end = word_start + trimmed_word.len();
        last_stop = trimmed_word_end;

        let measure = font.measure(trimmed_word, params);

        if measure <= remaining_width {
            //Space remains for our current word, move up the word pointer.
            line_end = word_end;

            is_start_of_line = false;

            remaining_width -= measure;
        } else {
            if is_start_of_line {
                //Failsafe: we get a word wider than the field, break anywhere.

                assert_eq!(i, 0);
                assert_eq!(word_start, 0);

                let mut last_fitting_end = 0;
                for (frag_end, _) in trimmed_word.char_indices() {
                    let fragment = &trimmed_word[..frag_end];
                    // Timffle: trailing no-break spaces of a fragment hang.
                    let fragment = if swf8 {
                        trim_hanging(fragment, true)
                    } else {
                        fragment
                    };
                    let width = font.measure(fragment, params);
                    if width > remaining_width {
                        break;
                    }
                    last_fitting_end = frag_end;
                }
                line_end = last_fitting_end;

                if swf8 {
                    // If even 1st char doesn't fit, let's write _anything_.
                    line_end = line_end.max(1);
                } else {
                    // If result has <= 1 char, give up on wrapping.
                    if line_end <= 1 {
                        return None;
                    };
                }
            }
            return Some(line_end);
        }
    }

    None
}

/// U+00A0 NO-BREAK SPACE.
const NBSP: u16 = 0xA0;

/// Timffle: the part of a word (SWF 8+) that counts for line width.
///
/// Measured in Flash Player 32 with SimSun (where U+00A0 is a full em wide)
/// and Arial: the trailing whitespace of a line hangs past the margin, and a
/// trailing run of no-break spaces hangs with it when the run also holds a
/// real space ("投 " followed by twenty U+00A0 stays on its line). A run of
/// no-break spaces alone right after a glyph counts ("投" followed by twenty
/// U+00A0 moves to the next line as a whole), except at the start of a line,
/// where it hangs too (`nbsp_hangs`), and so a word wider than the line is
/// split after its no-break spaces rather than inside them.
fn trim_hanging(word: &WStr, nbsp_hangs: bool) -> &WStr {
    let is_space = |c: u16| ruffle_wstr::utils::swf_is_whitespace(c) || c == NBSP;
    let mut end = word.len();
    let mut has_real_space = false;
    while end > 0 {
        let c = word.at(end - 1);
        if !is_space(c) {
            break;
        }
        has_real_space |= c != NBSP;
        end -= 1;
    }
    if has_real_space || nbsp_hangs {
        &word[..end]
    } else {
        word
    }
}

/// Find the text indices delimiting (ending) non-breakable spans of text.
// IMO way more readable the way it is rn
#[allow(clippy::if_same_then_else)]
#[allow(clippy::collapsible_if)]
fn find_allowed_breaks(text: &WStr, swf8: bool) -> Vec<usize> {
    // note: FP probably handles bad utf16 in some universal way
    const FALLBACK: char = char::REPLACEMENT_CHARACTER;

    let mut ret = vec![];
    if text.is_empty() {
        return ret;
    };
    for ((_, prev), (i, curr)) in text.char_indices().tuple_windows() {
        let prev = prev.unwrap_or(FALLBACK);
        let curr = curr.unwrap_or(FALLBACK);
        if swf8 && curr == ' ' {
            // in swf>=8, only last space is a break
            continue;
        }
        if swf8 && curr == '\u{A0}' {
            // Timffle: Flash Player never breaks before a no-break space,
            // not even after a space or a CJK character. After one, only the
            // CJK rule below allows a break.
            continue;
        }
        if prev == ' ' {
            ret.push(i);
        } else if prev == '-' || (!swf8 && curr == '-') {
            ret.push(i);
        } else if swf_is_cjk_like(prev) || swf_is_cjk_like(curr) {
            if !swf_is_opening(prev) && !swf_is_closing(curr) {
                ret.push(i);
            }
        }
    }
    ret.push(text.len());
    ret
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::font::*;
    use crate::string::WStr;
    use flate2::read::DeflateDecoder;
    use gc_arena::{Mutation, arena::rootless_mutate};
    use std::io::Read;
    use swf::Twips;

    const DEVICE_FONT: &[u8] = include_bytes!("../../assets/notosans.subset.ttf.gz");

    /// Construct eval parameters from their individual parts.
    fn eval_parameters_from_parts(
        height: Twips,
        letter_spacing: Twips,
        kerning: bool,
    ) -> EvalParameters {
        EvalParameters {
            height,
            letter_spacing,
            kerning,
            color: swf::Color::BLACK,
            opentype: None,
            fte_grid: None,
            device_run: crate::font::DeviceRun::FromText,
        }
    }

    fn with_device_font<F>(callback: F)
    where
        F: for<'gc> FnOnce(&Mutation<'gc>, Font<'gc>),
    {
        rootless_mutate(|mc| {
            let mut data = Vec::new();
            let mut decoder = DeflateDecoder::new(DEVICE_FONT);
            decoder
                .read_to_end(&mut data)
                .expect("default font decompression must succeed");

            let descriptor = FontDescriptor::from_parts("Noto Sans", false, false);
            let device_font =
                Font::from_font_file(mc, descriptor, FontFileData::new(data), 0, FontType::Device)
                    .unwrap();
            callback(mc, device_font);
        })
    }

    #[test]
    fn wrap_line_no_breakpoint() {
        with_device_font(|_mc, df| {
            let params = eval_parameters_from_parts(Twips::from_pixels(12.0), Twips::ZERO, true);
            let string = WStr::from_units(b"abcdefghijklmnopqrstuv");
            let breakpoint = wrap_line(
                &df,
                string,
                params,
                Twips::from_pixels(200.0),
                Twips::ZERO,
                true,
                // TODO: parametrize tests on swf7/8
                8,
            );

            assert_eq!(None, breakpoint);
        });
    }

    #[test]
    fn wrap_line_breakpoint_every_word() {
        with_device_font(|_mc, df| {
            let params = eval_parameters_from_parts(Twips::from_pixels(12.0), Twips::ZERO, true);
            let string = WStr::from_units(b"abcd efgh ijkl mnop");
            let mut last_bp = 0;
            let breakpoint = wrap_line(
                &df,
                string,
                params,
                Twips::from_pixels(35.0),
                Twips::ZERO,
                true,
                8,
            );

            assert_eq!(Some(5), breakpoint);

            last_bp += breakpoint.unwrap();

            let breakpoint2 = wrap_line(
                &df,
                &string[last_bp..],
                params,
                Twips::from_pixels(35.0),
                Twips::ZERO,
                true,
                8,
            );

            assert_eq!(Some(5), breakpoint2);

            last_bp += breakpoint2.unwrap();

            let breakpoint3 = wrap_line(
                &df,
                &string[last_bp..],
                params,
                Twips::from_pixels(35.0),
                Twips::ZERO,
                true,
                8,
            );

            assert_eq!(Some(5), breakpoint3);

            last_bp += breakpoint3.unwrap();

            let breakpoint4 = wrap_line(
                &df,
                &string[last_bp..],
                params,
                Twips::from_pixels(35.0),
                Twips::ZERO,
                true,
                8,
            );

            assert_eq!(None, breakpoint4);
        });
    }

    #[test]
    fn wrap_line_breakpoint_no_room() {
        with_device_font(|_mc, df| {
            let params = eval_parameters_from_parts(Twips::from_pixels(12.0), Twips::ZERO, true);
            let string = WStr::from_units(b"abcd efgh ijkl mnop");
            let breakpoint = wrap_line(
                &df,
                string,
                params,
                Twips::from_pixels(30.0),
                Twips::from_pixels(29.0),
                false,
                8,
            );

            assert_eq!(Some(0), breakpoint);
        });
    }

    #[test]
    fn wrap_line_breakpoint_irregular_sized_words() {
        with_device_font(|_mc, df| {
            let params = eval_parameters_from_parts(Twips::from_pixels(12.0), Twips::ZERO, true);
            let string = WStr::from_units(b"abcdi j kl mnop q rstuv");
            let mut last_bp = 0;
            let breakpoint = wrap_line(
                &df,
                string,
                params,
                Twips::from_pixels(35.0),
                Twips::ZERO,
                true,
                8,
            );

            assert_eq!(Some(6), breakpoint);

            last_bp += breakpoint.unwrap();

            let breakpoint2 = wrap_line(
                &df,
                &string[last_bp..],
                params,
                Twips::from_pixels(37.0),
                Twips::ZERO,
                true,
                8,
            );

            assert_eq!(Some(5), breakpoint2);

            last_bp += breakpoint2.unwrap();

            let breakpoint3 = wrap_line(
                &df,
                &string[last_bp..],
                params,
                Twips::from_pixels(37.0),
                Twips::ZERO,
                true,
                8,
            );

            assert_eq!(Some(5), breakpoint3);

            last_bp += breakpoint3.unwrap();

            let breakpoint4 = wrap_line(
                &df,
                &string[last_bp..],
                params,
                Twips::from_pixels(37.0),
                Twips::ZERO,
                true,
                8,
            );

            assert_eq!(Some(2), breakpoint4);

            last_bp += breakpoint4.unwrap();

            let breakpoint5 = wrap_line(
                &df,
                &string[last_bp..],
                params,
                Twips::from_pixels(37.0),
                Twips::ZERO,
                true,
                8,
            );

            assert_eq!(None, breakpoint5);
        });
    }

    /// Timffle: no-break space rules measured in Flash Player 32 (SimSun and
    /// Arial, `timffle-work/drag-pick-probe/nbspwrap`).
    fn units(s: &str) -> Vec<u16> {
        s.encode_utf16().collect()
    }

    #[test]
    fn nbsp_is_never_a_break_before() {
        // "投" then three no-break spaces then "個": no break between the CJK
        // character and the no-break space, one before "個".
        let text = units("\u{6295}\u{A0}\u{A0}\u{A0}\u{500B}");
        assert_eq!(
            find_allowed_breaks(WStr::from_units(&text[..]), true),
            vec![4, 5]
        );
        // "a b" with the space replaced: "ab", space, no-break spaces, "cd".
        let text = units("ab \u{A0}\u{A0}cd");
        assert_eq!(
            find_allowed_breaks(WStr::from_units(&text[..]), true),
            vec![7]
        );
        // Latin after a no-break space stays glued.
        let text = units("ab\u{A0}cd");
        assert_eq!(
            find_allowed_breaks(WStr::from_units(&text[..]), true),
            vec![5]
        );
    }

    #[test]
    fn nbsp_hangs_with_a_real_space_or_at_line_start() {
        let with_space = units("\u{6295} \u{A0}\u{A0}");
        let word = WStr::from_units(&with_space[..]);
        assert_eq!(trim_hanging(word, false).len(), 1);
        let alone = units("\u{6295}\u{A0}\u{A0}");
        let word = WStr::from_units(&alone[..]);
        assert_eq!(trim_hanging(word, false).len(), 3);
        assert_eq!(trim_hanging(word, true).len(), 1);
        let plain = units("ab  ");
        assert_eq!(trim_hanging(WStr::from_units(&plain[..]), false).len(), 2);
    }
}
