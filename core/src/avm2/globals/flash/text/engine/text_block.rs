use crate::avm2::Avm2;
use crate::avm2::Avm2StrRepresentable;
use crate::avm2::Object;
use crate::avm2::activation::Activation;
use crate::avm2::error::{
    Error, Error2004Type, Error2006Type, make_error_2004, make_error_2006, make_error_2008,
    make_error_2175,
};
use crate::avm2::function::FunctionArgs;
use crate::avm2::globals::flash::display::display_object::initialize_for_allocator;
use crate::avm2::object::{ContentElementObject, ElementData, VectorObject};
use crate::avm2::parameters::ParametersExt;
use crate::avm2::value::Value;
use crate::display_object::{
    DisplayObject, EditText, LineBidi, TDisplayObject, TDisplayObjectContainer, TextLine,
};
use crate::fte::{
    TextBaselineValue, TextLineCreationResultValue, TextLineValidity, TextRotationValue,
};
use crate::html::{FormatSpans, TextFormat, TextSpan};
use crate::string::{WStr, WString};
use ruffle_render::blend::ExtendedBlendMode;
use ruffle_render::matrix::Matrix;
use swf::Twips;

pub use crate::avm2::object::text_block_allocator;

pub fn get_apply_non_linear_font_scaling<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap().as_text_block_object().unwrap();
    Ok(this.apply_non_linear_font_scaling().into())
}

pub fn set_apply_non_linear_font_scaling<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap().as_text_block_object().unwrap();

    this.set_apply_non_linear_font_scaling(args.get_bool(0));

    Ok(Value::Undefined)
}

pub fn get_baseline_font_description<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap().as_text_block_object().unwrap();
    Ok(this
        .baseline_font_description()
        .map(Value::from)
        .unwrap_or(Value::Null))
}

pub fn set_baseline_font_description<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap().as_text_block_object().unwrap();

    let value = args
        .try_get_object(0)
        .map(|v| v.as_font_description_object().unwrap());

    this.set_baseline_font_description(value, activation.gc());

    Ok(Value::Undefined)
}

pub fn get_baseline_font_size<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap().as_text_block_object().unwrap();
    Ok(this.baseline_font_size().into())
}

pub fn set_baseline_font_size<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap().as_text_block_object().unwrap();
    let value = args.get_f64(0);
    if value < 0.0 {
        return Err(make_error_2004(activation, Error2004Type::ArgumentError));
    }

    this.set_baseline_font_size(value);

    Ok(Value::Undefined)
}

pub fn get_baseline_zero<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap().as_text_block_object().unwrap();
    Ok(this.baseline_zero().as_avm2_str(activation).into())
}

pub fn set_baseline_zero<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap().as_text_block_object().unwrap();

    let value = args.get_string_non_null(activation, 0, "baselineZero")?;
    let value = TextBaselineValue::from_avm2_str(&value)
        .filter(|v| !matches!(v, TextBaselineValue::UseDominantBaseline))
        .ok_or_else(|| make_error_2008(activation, "baselineZero"))?;

    this.set_baseline_zero(value);

    Ok(Value::Undefined)
}

pub fn get_bidi_level<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap().as_text_block_object().unwrap();
    Ok(this.bidi_level().into())
}

pub fn set_bidi_level<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap().as_text_block_object().unwrap();
    let value = args.get_i32(0);
    if value < 0 {
        return Err(make_error_2004(activation, Error2004Type::ArgumentError));
    }

    // Timffle: the paragraph embedding level (UAX #9) of every line created
    // from now on; changing it invalidates all lines already broken, like
    // changing `content` does.
    if value != this.bidi_level() {
        for line in this.lines() {
            line.set_validity(TextLineValidity::Invalid, activation.gc());
        }
    }
    this.set_bidi_level(value);

    Ok(Value::Undefined)
}

pub fn get_line_rotation<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap().as_text_block_object().unwrap();
    Ok(this.line_rotation().as_avm2_str(activation).into())
}

pub fn set_line_rotation<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap().as_text_block_object().unwrap();

    let value = args.get_string_non_null(activation, 0, "lineRotation")?;
    let value = TextRotationValue::from_avm2_str(&value)
        .filter(|v| !matches!(v, TextRotationValue::Auto))
        .ok_or_else(|| make_error_2008(activation, "lineRotation"))?;

    this.set_line_rotation(value);

    Ok(Value::Undefined)
}

pub fn get_tab_stops<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap().as_text_block_object().unwrap();
    Ok(this
        .tab_stops()
        .map(|v| Value::from(VectorObject::from_vector(v.storage().clone(), activation)))
        .unwrap_or(Value::Null))
}

pub fn set_tab_stops<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap().as_text_block_object().unwrap();
    let tab_stops = args
        .try_get_object(0)
        .and_then(|v| v.as_vector_object())
        .map(|v| VectorObject::from_vector(v.storage().clone(), activation));

    this.set_tab_stops(tab_stops, activation.gc());

    Ok(Value::Undefined)
}

pub fn get_text_justifier<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap().as_text_block_object().unwrap();
    Ok(this
        .text_justifier()
        .map(Value::from)
        .unwrap_or(Value::Null))
}

pub fn set_text_justifier<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap().as_text_block_object().unwrap();

    let justifier = args.get_object(activation, 0, "textJustifier")?;

    this.set_text_justifier(justifier, activation.gc());

    Ok(Value::Undefined)
}

pub fn get_content<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap().as_text_block_object().unwrap();
    Ok(this.content().map(Value::from).unwrap_or(Value::Null))
}

pub fn set_content<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap().as_text_block_object().unwrap();

    let content = args
        .try_get_object(0)
        .map(|v| v.as_content_element_object().unwrap());

    // Flash forbids setting a `TextBlock`'s content to a user-defined subclass
    // of `ContentElement`
    let is_invalid = content.is_some_and(|c| {
        let data = c.element_data();
        matches!(&*data, ElementData::Invalid)
    });
    if is_invalid {
        return Err(make_error_2004(activation, Error2004Type::ArgumentError));
    }

    this.set_content(content, activation.gc());

    Ok(Value::Undefined)
}

pub fn get_text_line_creation_result<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap().as_text_block_object().unwrap();
    Ok(this
        .text_line_creation_result()
        .map(|v| v.as_avm2_str(activation).into())
        .unwrap_or(Value::Null))
}

// Timffle: the first line in the block's line list whose validity is not
// `valid` (lines after a released/recreated line, or after `content` changed).
pub fn get_first_invalid_line<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap().as_text_block_object().unwrap();

    let line = this
        .lines()
        .find(|l| !matches!(l.validity(), TextLineValidity::Valid))
        .and_then(|l| l.object2())
        .map(Value::from);

    Ok(line.unwrap_or(Value::Null))
}

// Timffle: `TextBlock.getTextLineAtCharIndex` — the line containing the
// character; RangeError #2006 when the index is outside the block's text.
pub fn get_text_line_at_char_index<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap().as_text_block_object().unwrap();
    let index = args.get_i32(0);
    let text_len = this.content().map(|c| c.raw_text_len()).unwrap_or(0);
    if index < 0 || index as usize >= text_len {
        return Err(make_error_2006(activation, Error2006Type::RangeError));
    }
    let index = index as u32;
    let line = this
        .lines()
        .find(|l| l.begin_index() <= index && index < l.end_index())
        .and_then(|l| l.object2())
        .map(Value::from);
    Ok(line.unwrap_or(Value::Null))
}

// Timffle: atom and word boundaries over the block's raw text. An atom is a
// grapheme cluster (UAX #29 extended grapheme cluster), a word boundary is a
// UAX #29 word boundary; both are what Flash's text engine reports for
// Latin text. RangeError #2006 when `afterCharIndex`/`beforeCharIndex` is
// outside the text.
fn block_text<'gc>(
    activation: &mut Activation<'_, 'gc>,
    block: crate::avm2::object::TextBlockObject<'gc>,
) -> String {
    block
        .content()
        .and_then(|c| c.raw_text(activation))
        .map(|s| s.to_string())
        .unwrap_or_default()
}

/// Maps a UTF-16 index to a byte index of `text` (and back) for the
/// segmentation routines.
fn utf16_to_byte(text: &str, idx: usize) -> usize {
    let mut units = 0;
    for (b, ch) in text.char_indices() {
        if units >= idx {
            return b;
        }
        units += ch.len_utf16();
    }
    text.len()
}

fn byte_to_utf16(text: &str, b: usize) -> usize {
    text[..b].encode_utf16().count()
}

fn boundary_impl<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
    forward: bool,
    word: bool,
) -> Result<Value<'gc>, Error<'gc>> {
    use unicode_segmentation::UnicodeSegmentation;

    let this = this.as_object().unwrap().as_text_block_object().unwrap();
    let index = args.get_i32(0);
    let text = block_text(activation, this);
    let len16 = text.encode_utf16().count();
    if index < 0 || index as usize >= len16 {
        return Err(make_error_2006(activation, Error2006Type::RangeError));
    }
    let at = utf16_to_byte(&text, index as usize);
    let mut boundaries: Vec<usize> = if word {
        text.split_word_bound_indices().map(|(i, _)| i).collect()
    } else {
        text.grapheme_indices(true).map(|(i, _)| i).collect()
    };
    boundaries.push(text.len());
    let result = if forward {
        boundaries.iter().copied().find(|&b| b > at)
    } else {
        boundaries.iter().rev().copied().find(|&b| b < at)
    };
    Ok(match result {
        Some(b) => Value::from_usize_lossy(byte_to_utf16(&text, b)),
        None => (-1).into(),
    })
}

pub fn find_next_atom_boundary<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    boundary_impl(activation, this, args, true, false)
}

pub fn find_previous_atom_boundary<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    boundary_impl(activation, this, args, false, false)
}

pub fn find_next_word_boundary<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    boundary_impl(activation, this, args, true, true)
}

pub fn find_previous_word_boundary<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    boundary_impl(activation, this, args, false, true)
}

pub fn get_first_line<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap().as_text_block_object().unwrap();

    let line = this
        .first_line()
        .map(|l| l.object2().expect("Already created"))
        .map(Value::from);

    Ok(line.unwrap_or(Value::Null))
}

pub fn get_last_line<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap().as_text_block_object().unwrap();

    let line = this
        .lines()
        .last()
        .map(|l| l.object2().expect("Already created"))
        .map(Value::from);

    Ok(line.unwrap_or(Value::Null))
}

pub fn release_lines<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap().as_text_block_object().unwrap();

    let line_1 = args
        .get_object(activation, 0, "firstLine")?
        .as_display_object()
        .and_then(|o| o.as_text_line())
        .expect("Guaranteed by AS signature");

    let line_2 = args
        .get_object(activation, 1, "lastLine")?
        .as_display_object()
        .and_then(|o| o.as_text_line())
        .expect("Guaranteed by AS signature");

    // Flash has some unexpected behavior for certain edge cases of this method:

    // 1. Callers can swap the order of parameters to this method without ever
    //    affecting the functionality of the method.
    // 2. If two text lines are in the same text block and are siblings to each
    //    other, this method can still fail with an error if they can't be
    //    reached by iterating forward on the linked list of lines of this text
    //    block. It's possible to enter this scenario by rebreaking a line in
    //    the middle of a block.
    // 3. This method will always throw an error if either line is from a
    //    different text block.

    // The simplest way I could reproduce this behavior was with the following
    // logic:

    // 1. Start iterating over the linked list of lines, starting at
    //    `this.first_line()`.
    // 2. When reaching a line that is either `line_1` or `line_2` for the first
    //    time, record its position in the iterator.
    // 3. When reaching a line that is either `line_1` or `line_2` for the
    //    second time, record its position in the iterator and stop iterating.
    // 4. If either iteration reached the end of the list, return an error, as
    //    that means that one of the lines was not present in the block.
    // 5. Use the two positions to release the lines between `line_1` and
    //    `line_2` in the linked list of lines.

    let matches_either_line =
        |l| DisplayObject::ptr_eq(l, line_1) || DisplayObject::ptr_eq(l, line_2);

    let Some(first_position) = this.lines().position(matches_either_line) else {
        return Err(make_error_2004(activation, Error2004Type::ArgumentError));
    };

    if DisplayObject::ptr_eq(line_1, line_2) {
        // Special case: the two lines are the same. NOTE: We only do this after
        // we ensure that the line is actually reachable from `this.first_line`.
        line_1.release(activation.gc());

        return Ok(Value::Undefined);
    }

    let lines_count = this
        .lines()
        .skip(first_position + 1)
        .position(matches_either_line)
        .map(|p| p + 2);

    let Some(lines_count) = lines_count else {
        return Err(make_error_2004(activation, Error2004Type::ArgumentError));
    };

    let lines_to_remove = this
        .lines()
        .skip(first_position)
        .take(lines_count)
        .collect::<Vec<_>>();

    // `collect` the iterator, as we're modifying the doubly-linked list at the
    // same time as we iterate over it

    for line in lines_to_remove {
        line.release(activation.gc());
    }

    Ok(Value::Undefined)
}

pub fn do_create_text_line<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this_obj = this.as_object().unwrap();
    let block = this_obj.as_text_block_object().unwrap();

    let line_to_use = args
        .try_get_object(0)
        .and_then(|o| o.as_display_object())
        .and_then(|o| o.as_text_line());

    let previous_text_line = args
        .try_get_object(1)
        .and_then(|o| o.as_display_object())
        .and_then(|o| o.as_text_line());

    let width = args.get_f64(2);
    // Timffle: `lineOffset` and `fitSomething` were previously ignored and the
    // whole paragraph went into one TextLine. Now a TextLine holds at most one
    // visual line: a paragraph wider than `width` is broken at the last break
    // opportunity that fits (the fallback EditText's word-wrap layout finds
    // it), the rest is left for the next `createTextLine` call, and
    // `textLineCreationResult` reports success/emergency/insufficientWidth/
    // complete as Flash does.
    let line_offset = args.get_f64(3);
    let fit_something = args.get_bool(4);

    let content = block.content().expect("Guaranteed by AS checks");

    let previous_position = if let Some(previous_text_line) = previous_text_line {
        previous_text_line.end_index() as usize
    } else {
        0
    };

    let spans = match get_spans_from_content(content) {
        Ok(spans) => spans,
        Err(HandleContentError::NullElementFormat) => {
            // For some reason, FP handles this error as it handles an uncaught
            // exception, and returns `null` from this method.
            let error = make_error_2175(activation);

            Avm2::uncaught_error(activation, None, error, "Error creating TextLine");

            return Ok(Value::Null);
        }
    };

    // TODO don't discard the formatting
    let text = spans.text();

    if previous_position > text.len() {
        // This can happen when the content is changed after creating a TextLine.
        block.set_text_line_creation_result(Some(TextLineCreationResultValue::Complete));
        return Ok(Value::Null);
    }

    let next_position = next_line_break(text, previous_position);

    if text.is_empty() || next_position == text.len() && previous_position == next_position {
        // No more text.
        block.set_text_line_creation_result(Some(TextLineCreationResultValue::Complete));
        return Ok(Value::Null);
    }

    let line_index = if let Some(previous_text_line) = previous_text_line {
        previous_text_line.line_index() + 1
    } else {
        0
    };

    // `do_create_text_line` is called from both `TextBlock.recreateTextLine`
    // and `TextBlock.createTextLine`. The former passes this method an existing
    // `TextLine` to reuse, while the latter expects this method to create a new
    // `TextLine`.
    // Timffle: where the recreated line was (its block and neighbours), and
    // whether it is recreated in its own place (it already follows
    // `previousLine`, or is the block's first line when there is none).
    let recreated = line_to_use.map(|line| {
        let old_block = line.text_block();
        let in_place = old_block.is_some_and(|b| Object::ptr_eq(b, block))
            && match previous_text_line {
                Some(previous) => previous
                    .next_line()
                    .is_some_and(|n| DisplayObject::ptr_eq(n, line)),
                None => block
                    .first_line()
                    .is_some_and(|f| DisplayObject::ptr_eq(f, line)),
            };
        (old_block, line.previous_line(), line.next_line(), in_place)
    });

    let text_line = if let Some(line) = line_to_use {
        // `TextLine.recreateTextLine` is the caller: completely reset the
        // properties of the passed line and use it.
        line.reset_properties(activation.gc());
        reset_recreated_line_display(activation, line);
        // Timffle: the reused line breaks at the new `width`.
        line.fallback().set_width(activation.context, width);
        line
    } else {
        // `TextLine.createTextLine` is the caller: create a new `TextLine`.
        create_text_line(activation, width)
    };

    let text_line_instance = text_line.object2().expect("Already created the object2");
    let fallback = text_line.fallback();

    let mut format = spans
        .span(0)
        .expect("Non-empty text should have at least one span")
        .get_text_format();

    // Timffle: `lineOffset` is the extra space before the first atom, i.e.
    // the first-line indent of the laid-out paragraph.
    if line_offset != 0.0 {
        format.indent = Some(line_offset);
    }

    // Timffle: `TextBlock.tabStops` positions drive the line's tab layout.
    if let Some(tab_stops) = block.tab_stops() {
        let positions = tab_stops
            .storage()
            .iter()
            .filter_map(|v| v.as_object())
            .filter_map(|o| o.as_tab_stop_object())
            .map(|t| t.position())
            .collect::<Vec<_>>();
        format.tab_stops = Some(positions);
    }

    // Timffle: lay the whole paragraph out word-wrapped at `width` and keep
    // only its first visual line. The paragraph's explicit line-break
    // characters belong to its last line.
    let paragraph = &text[previous_position..next_position];
    let body_len = paragraph.len() - line_break_len(paragraph);
    let paragraph_bidi = resolve_bidi(paragraph, block.bidi_level());

    // Timffle: measure the paragraph on one unwrapped line, then break it the way
    // Flash Player 32 does (measured, timffle/difftest/src/S5CursorLines.hx): the
    // line takes as many characters as fit (trailing spaces hang past `width`), ends
    // at the last break opportunity among them (`break_allowed`, a UAX #14 subset),
    // or, when there is none, in the middle of the word (an emergency break).
    fallback.set_width(activation.context, 1.0e6);
    fallback.set_text(&paragraph_bidi.visual, activation.context);
    apply_format(activation, fallback, format.clone(), line_index);

    let first_atom = first_atom_len(paragraph);
    let (mut line_len, insufficient_width, emergency_break) = {
        let layout = fallback.layout();
        let chars: Vec<char> = (0..body_len)
            .map(|i| {
                paragraph
                    .get(i)
                    .and_then(|u| char::from_u32(u32::from(u)))
                    .unwrap_or('\u{fffd}')
            })
            .collect();
        let bounds: Vec<Option<_>> = (0..body_len)
            .map(|i| layout.char_bounds(paragraph_bidi.to_visual[i]))
            .collect();
        let start_x = bounds
            .iter()
            .flatten()
            .map(|b| b.x_min)
            .min()
            .unwrap_or_default();
        let limit = Twips::from_pixels(width);
        // `right[k]`: the right edge of the first k characters, hanging spaces excluded.
        // Left-to-right text reads it off the layout (tabs included); with bidi runs
        // the logical prefix is the sum of the characters' advances.
        let identity = paragraph_bidi
            .to_visual
            .iter()
            .enumerate()
            .all(|(i, v)| i == *v);
        let mut right = vec![start_x; body_len + 1];
        let mut sum = start_x;
        let mut visible = start_x;
        for k in 0..body_len {
            if let Some(b) = bounds[k] {
                sum = if identity {
                    b.x_max
                } else {
                    sum + (b.x_max - b.x_min)
                };
            }
            if !is_hanging_space(chars[k]) {
                visible = sum;
            }
            right[k + 1] = visible;
        }
        let fit = (0..=body_len)
            .rev()
            .find(|&k| right[k] <= limit)
            .unwrap_or(0);
        if fit >= body_len {
            (paragraph.len(), false, false)
        } else {
            let opportunity = (1..=fit)
                .rev()
                .find(|&k| break_allowed(chars[k - 1], chars[k]));
            let (len, emergency) = match opportunity {
                Some(k) => (k, false),
                None => (fit, true),
            };
            let insufficient =
                first_atom > 0 && first_atom <= body_len && right[first_atom.min(body_len)] > limit;
            (len, insufficient, emergency)
        }
    };

    if insufficient_width && !fit_something {
        block.set_text_line_creation_result(Some(TextLineCreationResultValue::InsufficientWidth));
        return Ok(Value::Null);
    }

    if insufficient_width {
        // `fitSomething`: at least one atom goes on the line.
        line_len = line_len.max(first_atom).min(paragraph.len());
    }
    // Spaces after the break hang on this line.
    while line_len < body_len
        && paragraph
            .get(line_len)
            .and_then(|u| char::from_u32(u32::from(u)))
            .is_some_and(is_hanging_space)
    {
        line_len += 1;
    }
    if line_len >= body_len {
        line_len = paragraph.len();
    }
    fallback.set_width(activation.context, width);

    let subtext = &paragraph[..line_len];
    let line_bidi = if line_len == paragraph.len() {
        // Lay out again at the real width (the measuring pass was unwrapped).
        fallback.set_text(&paragraph_bidi.visual, activation.context);
        apply_format(activation, fallback, format, line_index);
        paragraph_bidi
    } else {
        // Re-lay out just this line's text.
        let bidi = resolve_bidi(subtext, block.bidi_level());
        fallback.set_text(&bidi.visual, activation.context);
        apply_format(activation, fallback, format, line_index);
        bidi
    };

    // An emergency break is one inside a word: no break opportunity fit.
    let emergency = line_len < paragraph.len() && (emergency_break || insufficient_width);

    text_line.set_bidi(
        LineBidi {
            logical: subtext.into(),
            to_visual: line_bidi.to_visual,
            levels: line_bidi.levels,
        },
        activation.gc(),
    );

    // Timffle: `TextBlock.lineRotation` rotates the whole line display object.
    let rotation = match block.line_rotation() {
        TextRotationValue::Rotate0 | TextRotationValue::Auto => 0.0_f64,
        TextRotationValue::Rotate90 => 90.0,
        TextRotationValue::Rotate180 => 180.0,
        TextRotationValue::Rotate270 => 270.0,
    };
    if rotation != 0.0 {
        // Only touch the transform for a real rotation: `recreateTextLine`
        // keeps upstream's reset semantics for the common `rotate0` case.
        text_line.set_rotation(crate::types::Degrees::from_radians(rotation.to_radians()));
    }

    // FIXME: This needs to use `intrinsic_bounds` to measure the width
    // of the provided text, and set the width of the EditText to that.
    // Some games depend on this (e.g. Realm Grinder).

    let line_end = previous_position + line_len;

    text_line.set_text_block(Some(block), activation.gc());
    text_line.set_specified_width(width);
    text_line.set_raw_text_length(line_len as u32);
    text_line.set_begin_index(previous_position as u32);
    text_line.set_end_index(line_end as u32);
    text_line.set_line_index(line_index);

    let mc = activation.gc();
    // Timffle: `recreateTextLine` keeps the line list linked the way Flash
    // Player 32 does (measured, `avm2/textblock_recreateline`):
    // - recreated in its own place: the links stay, the lines after it become
    //   invalid (their text may have moved);
    // - otherwise the line leaves its old list (its neighbours are joined, the
    //   line after it and all later ones become invalid, it stops being the
    //   old block's first line) and takes the place after `previousLine`: the
    //   line that was there is invalidated and unlinked (it keeps its
    //   `textBlock`), the lines after that one stay valid and follow the
    //   recreated line.
    let new_next = match recreated {
        Some((_, old_prev, old_next, true)) => {
            text_line.set_previous_line(old_prev, mc);
            for line in old_next
                .into_iter()
                .chain(old_next.into_iter().flat_map(|n| n.next_lines()))
            {
                line.set_validity(TextLineValidity::Invalid, mc);
            }
            old_next
        }
        Some((old_block, old_prev, old_next, false)) => {
            if let Some(old_block) = old_block
                && old_block
                    .first_line()
                    .is_some_and(|f| DisplayObject::ptr_eq(f, text_line))
            {
                old_block.set_first_line(old_next, mc);
            }
            if let Some(old_prev) = old_prev
                && old_prev
                    .next_line()
                    .is_some_and(|n| DisplayObject::ptr_eq(n, text_line))
            {
                old_prev.set_next_line(old_next, mc);
            }
            if let Some(old_next) = old_next
                && old_next
                    .previous_line()
                    .is_some_and(|p| DisplayObject::ptr_eq(p, text_line))
            {
                old_next.set_previous_line(old_prev, mc);
                old_next.set_validity(TextLineValidity::Invalid, mc);
                for line in old_next.next_lines() {
                    line.set_validity(TextLineValidity::Invalid, mc);
                }
            }
            let displaced = match previous_text_line {
                Some(previous) => previous.next_line(),
                None => block.first_line(),
            };
            displaced.and_then(|displaced| {
                let after = displaced.next_line();
                displaced.set_validity(TextLineValidity::Invalid, mc);
                displaced.set_previous_line(None, mc);
                displaced.set_next_line(None, mc);
                after
            })
        }
        None => None,
    };
    if recreated.is_some() {
        text_line.set_next_line(new_next, mc);
        if let Some(new_next) = new_next {
            new_next.set_previous_line(Some(text_line), mc);
        }
    }

    if let Some(previous_line) = previous_text_line {
        text_line.set_previous_line(Some(previous_line), mc);
        previous_line.set_next_line(Some(text_line), mc);
    } else {
        // If there's no previous line, then this is the first line.
        block.set_first_line(Some(text_line), mc);
    }

    block.set_text_line_creation_result(Some(if emergency {
        TextLineCreationResultValue::Emergency
    } else {
        TextLineCreationResultValue::Success
    }));

    Ok(text_line_instance.into())
}

// Timffle: characters that hang past the line end instead of taking width
// (Flash Player 32 lets a no-break space hang too, measured).
fn is_hanging_space(c: char) -> bool {
    matches!(c, ' ' | '\t' | '\u{200b}' | '\u{a0}' | '\u{3000}')
}

// Timffle: ideographic and kana characters (UAX #14 ID and the CJK forms Flash
// breaks around), which allow a break on both sides.
fn is_ideographic(c: char) -> bool {
    matches!(c as u32,
        0x2E80..=0x2FFF | 0x3001..=0x303F | 0x3040..=0x30FF | 0x3100..=0x31FF
        | 0x3200..=0x9FFF | 0xAC00..=0xD7AF | 0xF900..=0xFAFF | 0xFE30..=0xFE4F
        | 0xFF00..=0xFFEF | 0x20000..=0x3FFFF)
}

// Timffle: whether a line may break between `a` and `b`. A subset of UAX #14
// that reproduces every case measured in Flash Player 32 (spaces, ZWSP, tab,
// hyphen, slash, `?`/`!`, punctuation inside words and numbers, no-break space,
// brackets, CJK ideographs and kana with their closing punctuation, small kana
// and the prolonged sound mark).
fn break_allowed(a: char, b: char) -> bool {
    const NO_BREAK_BEFORE: &str = ")]}\u{bb},.:;!?-/'\"\u{2019}\u{201d}\u{2026}\u{2025}%\u{b0}\
        \u{3001}\u{3002}\u{ff0c}\u{ff0e}\u{ff1a}\u{ff1b}\u{ff01}\u{ff1f}\u{30fb}\u{30fc}\
        \u{300d}\u{300f}\u{3011}\u{3015}\u{3009}\u{300b}\u{ff09}\u{ff3d}\u{ff5d}\u{301c}\
        \u{3041}\u{3043}\u{3045}\u{3047}\u{3049}\u{3063}\u{3083}\u{3085}\u{3087}\u{308e}\
        \u{30a1}\u{30a3}\u{30a5}\u{30a7}\u{30a9}\u{30c3}\u{30e3}\u{30e5}\u{30e7}\u{30ee}\
        \u{30f5}\u{30f6}\u{309d}\u{309e}\u{30fd}\u{30fe}\u{3005}";
    const NO_BREAK_AFTER: &str = "([{\u{ab}'\"\u{2018}\u{201c}\u{bf}\u{a1}\
        \u{300c}\u{300e}\u{3010}\u{3014}\u{3008}\u{300a}\u{ff08}\u{ff3b}\u{ff5b}";
    const GLUE: &str = "\u{a0}\u{2060}\u{feff}\u{202f}\u{2007}";
    if is_hanging_space(b) && b != '\u{3000}' {
        return false;
    }
    if GLUE.contains(a) || GLUE.contains(b) {
        return false;
    }
    if matches!(a, ' ' | '\t' | '\u{200b}' | '\u{3000}') {
        return true;
    }
    if NO_BREAK_BEFORE.contains(b) || NO_BREAK_AFTER.contains(a) {
        return false;
    }
    if matches!(a, '-' | '/' | '!' | '?' | '\u{2010}' | '\u{2013}') {
        return !b.is_ascii_digit();
    }
    is_ideographic(a) || is_ideographic(b)
}

// Timffle: the number of trailing explicit line-break characters of a
// paragraph as `next_line_break` delimits it (0, 1, or 2 for CR LF).
fn line_break_len(paragraph: &WStr) -> usize {
    let len = paragraph.len();
    if len >= 2 && paragraph.get(len - 2) == Some(0x0D) && paragraph.get(len - 1) == Some(0x0A) {
        2
    } else if len >= 1
        && paragraph
            .get(len - 1)
            .is_some_and(|ch| matches!(ch, 0x0A | 0x0D | 0x2028 | 0x2029))
    {
        1
    } else {
        0
    }
}

// Timffle: the length in UTF-16 units of the first atom (grapheme cluster)
// of `text`.
fn first_atom_len(text: &WStr) -> usize {
    use unicode_segmentation::UnicodeSegmentation;
    let string = text.to_string();
    string
        .graphemes(true)
        .next()
        .map(|g| g.encode_utf16().count())
        .unwrap_or(0)
        .min(text.len())
}

/// Timffle: the result of resolving a line's bidirectional order.
struct ResolvedBidi {
    /// The text reordered for display (right-to-left runs reversed).
    visual: WString,
    /// Logical UTF-16 unit index -> index into `visual`.
    to_visual: Vec<usize>,
    /// Resolved embedding level per logical UTF-16 unit.
    levels: Vec<u8>,
}

// Timffle: UAX #9 resolution of `text` with `TextBlock.bidiLevel` as the
// paragraph embedding level (0 = left-to-right, 1 = right-to-left; higher
// values are explicit levels as UAX #9 allows). Runs are reordered for
// display with the Unicode bidirectional algorithm (`unicode-bidi`); text in
// which every run keeps its logical position (all left-to-right text at
// level 0) maps onto itself.
fn resolve_bidi(text: &WStr, bidi_level: i32) -> ResolvedBidi {
    use unicode_bidi::{BidiInfo, Level};

    // Timffle: Flash Player 32 only looks at the parity: an even `bidiLevel` is a
    // left-to-right paragraph at level 0 and an odd one right-to-left at level 1
    // (measured: `bidiLevel = 2` or 200 gives Latin text level 0).
    let level_number = (bidi_level.max(0) & 1) as u8;
    let identity = |levels: Vec<u8>| ResolvedBidi {
        visual: text.into(),
        to_visual: (0..text.len()).collect(),
        levels,
    };

    // `unicode-bidi` works on UTF-8; text with lone surrogates cannot be
    // mapped unit by unit, so it keeps its logical order.
    let string = text.to_string();
    if string.encode_utf16().count() != text.len() {
        return identity(vec![level_number; text.len()]);
    }
    let level = Level::new(level_number).unwrap_or_else(|_| Level::ltr());
    let info = BidiInfo::new(&string, Some(level));

    // Byte index -> logical UTF-16 unit index.
    let mut byte_to_unit = vec![0usize; string.len() + 1];
    let mut unit = 0;
    for (b, ch) in string.char_indices() {
        for k in 0..ch.len_utf8() {
            byte_to_unit[b + k] = unit;
        }
        unit += ch.len_utf16();
    }
    byte_to_unit[string.len()] = unit;

    let mut levels = vec![level.number(); text.len()];
    let mut to_visual = vec![0usize; text.len()];
    let mut visual = WString::new();
    let mut all_identity = true;

    for para in &info.paragraphs {
        let (run_levels, runs) = info.visual_runs(para, para.range.clone());
        for run in runs {
            let rtl = run_levels[run.start].is_rtl();
            let chars: Vec<(usize, char)> = string[run.clone()]
                .char_indices()
                .map(|(i, c)| (run.start + i, c))
                .collect();
            let ordered: Box<dyn Iterator<Item = &(usize, char)>> = if rtl {
                Box::new(chars.iter().rev())
            } else {
                Box::new(chars.iter())
            };
            for &(byte, ch) in ordered {
                let logical = byte_to_unit[byte];
                let lvl = run_levels[byte].number();
                let visual_index = visual.len();
                for k in 0..ch.len_utf16() {
                    levels[logical + k] = lvl;
                    to_visual[logical + k] = visual_index + k;
                    if visual_index + k != logical + k {
                        all_identity = false;
                    }
                }
                visual.push_char(ch);
            }
        }
    }

    if visual.len() != text.len() || all_identity {
        // Nothing moved (or the text could not be mapped unit by unit): keep
        // the original units.
        identity(levels)
    } else {
        ResolvedBidi {
            visual,
            to_visual,
            levels,
        }
    }
}

/// Timffle: `recreateTextLine` gives the reused line a new line's display
/// state, as Flash Player 32 does (measured, `avm2/textblock_recreateline`):
/// transform (x, y, z, scale, rotation, 3D), alpha, blend mode, mask,
/// visibility, `cacheAsBitmap` and `opaqueBackground` are reset, its children
/// are removed and its event listeners dropped. Its name and parent stay.
fn reset_recreated_line_display<'gc>(activation: &mut Activation<'_, 'gc>, line: TextLine<'gc>) {
    let mc = activation.gc();
    line.set_matrix(Matrix::IDENTITY);
    line.set_alpha(1.0);
    line.set_blend_mode(ExtendedBlendMode::Normal);
    line.set_mask(None, mc);
    line.set_visible(activation.context, true);
    line.set_bitmap_cached_preference(false);
    line.set_opaque_background(None);
    if let Some(mut container) = DisplayObject::from(line).as_container() {
        let count = container.num_children();
        container.remove_range(activation.context, 0..count);
    }
    if let Some(object) = line.object2() {
        let object: Object<'gc> = object.into();
        let _ = crate::avm2::object::TObject::set_slot(
            object,
            crate::avm2::globals::slots::flash_events_event_dispatcher::DISPATCH_LIST,
            Value::Null,
            activation,
        );
    }
}

fn create_text_line<'gc>(activation: &mut Activation<'_, 'gc>, width: f64) -> TextLine<'gc> {
    let class = activation.avm2().classes().textline;

    // TODO should we use the caller's movie instead? Does it matter?
    let movie = *activation.context.root_swf;

    let fallback = EditText::new_fte(activation.context, movie, 0.0, 0.0, width, 15.0);
    let text_line = TextLine::new(activation.context, movie, fallback);
    initialize_for_allocator(activation.context, text_line.into(), class);

    text_line
}

enum HandleContentError {
    NullElementFormat,
}

fn get_spans_from_content<'gc>(
    content: ContentElementObject<'gc>,
) -> Result<FormatSpans, HandleContentError> {
    let mut all_text = WString::new();
    let mut all_spans = Vec::new();

    handle_content_element(content, &mut all_text, &mut all_spans)?;

    let mut spans = FormatSpans::from_str_and_spans(&all_text, &all_spans);
    spans.normalize();
    Ok(spans)
}

fn handle_content_element<'gc>(
    content: ContentElementObject<'gc>,
    all_text: &mut WString,
    all_spans: &mut Vec<TextSpan>,
) -> Result<(), HandleContentError> {
    let data = content.element_data();
    let format = content.element_format();

    match &*data {
        ElementData::Text { text } => {
            // If `text` is `None`, FP just completely ignores the element. It
            // doesn't even check its `elementFormat`.
            if let Some(text) = text {
                all_text.push_str(text);

                let format = format.ok_or(HandleContentError::NullElementFormat)?;
                let text_format = format.as_text_format();

                let span = TextSpan::with_length_and_format(text.len(), &text_format);
                all_spans.push(span);
            }
        }
        ElementData::Group { elements } => {
            // TODO: The docs say GroupElement's format has some effects?
            for element in elements {
                handle_content_element(*element, all_text, all_spans)?;
            }
        }
        ElementData::Graphic { .. } => {
            // Timffle: a graphic occupies one U+FDEF character in the block's
            // text, formatted with the element's format (Flash requires one).
            all_text.push(0xFDEF);
            let format = format.ok_or(HandleContentError::NullElementFormat)?;
            let text_format = format.as_text_format();
            all_spans.push(TextSpan::with_length_and_format(1, &text_format));
        }
        ElementData::Invalid => {
            unreachable!(
                "TextBlock and GroupElement prevent holding user subclasses of ContentElement"
            )
        }
    }

    Ok(())
}

fn next_line_break(text: &WStr, start: usize) -> usize {
    let remaining_text = &text[start..];
    let len = remaining_text
        .iter()
        .position(|ch| matches!(ch, 0x0A | 0x0D | 0x2028 | 0x2029))
        // Include the separator.
        .map(|pos| {
            if remaining_text.get(pos) == Some(0x0D) && remaining_text.get(pos + 1) == Some(0x0A) {
                pos + 2
            } else {
                pos + 1
            }
        });

    if let Some(len) = len {
        start + len
    } else {
        text.len()
    }
}

fn apply_format<'gc>(
    activation: &mut Activation<'_, 'gc>,
    edit_text: EditText<'gc>,
    format: TextFormat,
    line_index: u32,
) {
    // TODO: Handle device font/non-device font properly
    edit_text.set_is_device_font(activation.context, false);
    edit_text.set_text_format(
        0,
        edit_text.text_length(),
        format.clone(),
        activation.context,
    );
    edit_text.set_new_text_format(format);

    edit_text.set_word_wrap(true, activation.context);

    let measured_text = edit_text.measure_text(activation.context);

    edit_text.set_height(activation.context, measured_text.1.to_pixels());
    edit_text.set_y(measured_text.1 * line_index as i32);
}
