use crate::avm2::activation::Activation;
use crate::avm2::error::{Error, make_error_2008};
use crate::avm2::function::FunctionArgs;
use crate::avm2::parameters::ParametersExt;
use crate::avm2::value::Value;
use crate::display_object::TDisplayObject;
use crate::fte::TextLineValidity;
use ruffle_macros::istr;

pub fn get_text_width<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();
    let display_object = this.as_display_object().unwrap();
    let Some(text_line) = display_object.as_text_line() else {
        return Ok(0.0.into());
    };

    let measured_text = text_line.measure_text(activation.context);
    Ok(measured_text.0.to_pixels().into())
}

pub fn get_has_tabs<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this
        .as_object()
        .unwrap()
        .as_display_object()
        .unwrap()
        .as_text_line()
        .unwrap();

    Ok(this.has_tabs().into())
}

pub fn get_ascent<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();
    let display_object = this.as_display_object().unwrap();
    let text_line = display_object.as_text_line().unwrap();

    Ok(text_line.metrics().0.into())
}

pub fn get_descent<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();
    let display_object = this.as_display_object().unwrap();
    let text_line = display_object.as_text_line().unwrap();

    Ok(text_line.metrics().1.into())
}

pub fn get_validity<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();
    let display_object = this.as_display_object().unwrap();
    let Some(text_line) = display_object.as_text_line() else {
        return Ok(Value::Undefined);
    };

    let validity = match text_line.validity() {
        TextLineValidity::Valid => istr!("valid"),
        TextLineValidity::Invalid => istr!("invalid"),
        TextLineValidity::Static => istr!("static"),
        TextLineValidity::PossiblyInvalid => istr!("possiblyInvalid"),
        TextLineValidity::UserInvalid(string) => string,
    };

    Ok(validity.into())
}

pub fn set_validity<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();
    let display_object = this.as_display_object().unwrap();
    let Some(text_line) = display_object.as_text_line() else {
        return Ok(Value::Undefined);
    };

    let value = args.get_string_non_null(activation, 0, "validity")?;

    let previous_value = text_line.validity();
    let new_value = TextLineValidity::parse(value);

    let transition_allowed = match (previous_value, new_value) {
        (a, b) if a == b => true,
        (_, TextLineValidity::PossiblyInvalid) => false,
        (_, TextLineValidity::Static) => true,
        (TextLineValidity::Static, _) => false,
        (TextLineValidity::Invalid, _) => false,
        _ => true,
    };

    if !transition_allowed {
        return Err(make_error_2008(activation, "validity"));
    }

    text_line.set_validity(new_value, activation.gc());
    Ok(Value::Undefined)
}

pub fn get_text_block<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this
        .as_object()
        .unwrap()
        .as_display_object()
        .unwrap()
        .as_text_line()
        .unwrap();

    let block = this.text_block_from_script();

    Ok(block.map(Value::from).unwrap_or(Value::Null))
}

pub fn get_specified_width<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this
        .as_object()
        .unwrap()
        .as_display_object()
        .unwrap()
        .as_text_line()
        .unwrap();

    Ok(this.specified_width().into())
}

pub fn get_raw_text_length<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this
        .as_object()
        .unwrap()
        .as_display_object()
        .unwrap()
        .as_text_line()
        .unwrap();

    Ok(this.raw_text_length().into())
}

pub fn get_text_block_begin_index<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this
        .as_object()
        .unwrap()
        .as_display_object()
        .unwrap()
        .as_text_line()
        .unwrap();

    Ok(this.begin_index().into())
}

pub fn get_previous_line<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this
        .as_object()
        .unwrap()
        .as_display_object()
        .unwrap()
        .as_text_line()
        .unwrap();

    Ok(this
        .previous_line()
        .and_then(|line| line.object2())
        .map(Value::from)
        .unwrap_or(Value::Null))
}

pub fn get_next_line<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this
        .as_object()
        .unwrap()
        .as_display_object()
        .unwrap()
        .as_text_line()
        .unwrap();

    Ok(this
        .next_line()
        .and_then(|line| line.object2())
        .map(Value::from)
        .unwrap_or(Value::Null))
}

pub fn get_text_height<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();
    let display_object = this.as_display_object().unwrap();
    let Some(text_line) = display_object.as_text_line() else {
        return Ok(0.0.into());
    };

    let measured_text = text_line.measure_text(activation.context);
    Ok(measured_text.1.to_pixels().into())
}

// Timffle: atom queries. An atom is a grapheme cluster (UAX #29) of the
// line's text, or a single U+FDEF graphic placeholder; bounds come from the
// laid-out glyph positions of the line.
fn line_atoms(text: &str) -> Vec<(usize, usize)> {
    use unicode_segmentation::UnicodeSegmentation;
    let mut atoms = Vec::new();
    let mut unit = 0;
    for g in text.graphemes(true) {
        let len = g.encode_utf16().count();
        atoms.push((unit, unit + len));
        unit += len;
    }
    atoms
}

fn this_line<'gc>(this: Value<'gc>) -> crate::display_object::TextLine<'gc> {
    this.as_object()
        .unwrap()
        .as_display_object()
        .unwrap()
        .as_text_line()
        .unwrap()
}

fn atom_at<'gc>(
    activation: &mut Activation<'_, 'gc>,
    line: crate::display_object::TextLine<'gc>,
    index: i32,
) -> Result<(usize, usize), Error<'gc>> {
    let text = line.fallback().text().to_string();
    let atoms = line_atoms(&text);
    usize::try_from(index)
        .ok()
        .and_then(|i| atoms.get(i).copied())
        .ok_or_else(|| {
            crate::avm2::error::make_error_2006(
                activation,
                crate::avm2::error::Error2006Type::RangeError,
            )
        })
}

pub fn get_atom_count<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let line = this_line(this);
    let text = line.fallback().text().to_string();
    Ok(Value::from_usize_lossy(line_atoms(&text).len()))
}

pub fn get_atom_index_at_char_index<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let line = this_line(this);
    let char_index = args.get_i32(0);
    let Ok(char_index) = usize::try_from(char_index) else {
        return Ok((-1).into());
    };
    let begin = line.begin_index() as usize;
    if char_index < begin {
        return Ok((-1).into());
    }
    let local = char_index - begin;
    let text = line.fallback().text().to_string();
    let found = line_atoms(&text)
        .iter()
        .position(|&(s, e)| s <= local && local < e);
    Ok(found.map(Value::from_usize_lossy).unwrap_or((-1).into()))
}

pub fn get_atom_text_block_begin_index<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let line = this_line(this);
    let (start, _) = atom_at(activation, line, args.get_i32(0))?;
    Ok(Value::from_usize_lossy(line.begin_index() as usize + start))
}

pub fn get_atom_text_block_end_index<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let line = this_line(this);
    let (_, end) = atom_at(activation, line, args.get_i32(0))?;
    Ok(Value::from_usize_lossy(line.begin_index() as usize + end))
}

pub fn get_atom_word_boundary_on_left<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    use unicode_segmentation::UnicodeSegmentation;
    let line = this_line(this);
    let (start, _) = atom_at(activation, line, args.get_i32(0))?;
    let text = line.fallback().text().to_string();
    let mut unit = 0;
    for (_, word) in text.split_word_bound_indices() {
        if unit == start {
            return Ok(true.into());
        }
        unit += word.encode_utf16().count();
    }
    Ok(false.into())
}

fn atom_bounds<'gc>(
    line: crate::display_object::TextLine<'gc>,
    (start, end): (usize, usize),
) -> Option<swf::Rectangle<swf::Twips>> {
    let mut result: Option<swf::Rectangle<swf::Twips>> = None;
    for i in start..end {
        if let Some(b) = line.fallback().char_bounds(i) {
            result = Some(match result {
                Some(r) => r.union(&b),
                None => b,
            });
        }
    }
    result
}

pub fn get_atom_bounds<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let line = this_line(this);
    let atom = atom_at(activation, line, args.get_i32(0))?;
    let bounds = atom_bounds(line, atom).unwrap_or_default();
    let rect = activation.avm2().classes().rectangle.construct(
        activation,
        &[
            bounds.x_min.to_pixels().into(),
            bounds.y_min.to_pixels().into(),
            bounds.width().to_pixels().into(),
            bounds.height().to_pixels().into(),
        ],
    )?;
    Ok(rect)
}

pub fn get_atom_center<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let line = this_line(this);
    let atom = atom_at(activation, line, args.get_i32(0))?;
    let bounds = atom_bounds(line, atom).unwrap_or_default();
    Ok(((bounds.x_min.to_pixels() + bounds.x_max.to_pixels()) / 2.0).into())
}

pub fn get_atom_index_at_point<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    use crate::display_object::TDisplayObject;
    let line = this_line(this);
    let stage = swf::Point::from_pixels(args.get_f64(0), args.get_f64(1));
    let Some(local) = line.global_to_local(stage) else {
        return Ok((-1).into());
    };
    let text = line.fallback().text().to_string();
    for (i, atom) in line_atoms(&text).into_iter().enumerate() {
        if let Some(b) = atom_bounds(line, atom)
            && b.x_min <= local.x
            && local.x < b.x_max
            && b.y_min <= local.y
            && local.y < b.y_max
        {
            return Ok(Value::from_usize_lossy(i));
        }
    }
    Ok((-1).into())
}
