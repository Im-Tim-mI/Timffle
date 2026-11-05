use crate::avm2::Avm2StrRepresentable;
use crate::avm2::Error;
use crate::avm2::activation::Activation;
use crate::avm2::error::make_error_2008;
use crate::avm2::function::FunctionArgs;
use crate::avm2::parameters::ParametersExt;
use crate::avm2::value::Value;
use crate::fte::TextRotationValue;

pub use crate::avm2::object::content_element_allocator;

pub fn get_text<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this
        .as_object()
        .unwrap()
        .as_content_element_object()
        .unwrap();

    let text = this.text(activation);

    Ok(match text {
        Some(s) => s.into(),
        None => Value::Null,
    })
}

pub fn get_element_format<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this
        .as_object()
        .unwrap()
        .as_content_element_object()
        .unwrap();
    Ok(match this.element_format() {
        Some(ef) => ef.into(),
        None => Value::Null,
    })
}

pub fn set_element_format<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this
        .as_object()
        .unwrap()
        .as_content_element_object()
        .unwrap();
    let ef = args
        .try_get_object(0)
        .and_then(|o| o.as_element_format_object());
    this.set_element_format(ef, activation.gc());
    Ok(Value::Undefined)
}

// Timffle: `textBlock`, `textBlockBeginIndex` and `groupElement` are real
// bookkeeping now: `GroupElement.setElements`/`replaceElements` and
// `TextBlock.content` record the owner on each element.
pub fn get_text_block<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this
        .as_object()
        .unwrap()
        .as_content_element_object()
        .unwrap();
    Ok(this.text_block().map(Value::from).unwrap_or(Value::Null))
}

pub fn get_text_block_begin_index<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this
        .as_object()
        .unwrap()
        .as_content_element_object()
        .unwrap();
    Ok(this
        .text_block_begin_index()
        .map(Value::from_usize_lossy)
        .unwrap_or((-1).into()))
}

pub fn get_group_element<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this
        .as_object()
        .unwrap()
        .as_content_element_object()
        .unwrap();
    Ok(this.group_element().map(Value::from).unwrap_or(Value::Null))
}

// Timffle: `eventMirror` is stored on the element and used by
// `TextLine.mirrorRegions`; the mirroring of events dispatched to the line is
// done by `TextLine` in ActionScript.
pub fn get_event_mirror<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this
        .as_object()
        .unwrap()
        .as_content_element_object()
        .unwrap();
    Ok(this.event_mirror().map(|v| v.into()).unwrap_or(Value::Null))
}

pub fn set_event_mirror<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this
        .as_object()
        .unwrap()
        .as_content_element_object()
        .unwrap();
    this.set_event_mirror(args.try_get_object(0), activation.gc());
    Ok(Value::Undefined)
}

// Timffle: `textRotation` is validated, stored and reported through
// `TextLine.getAtomTextRotation`; glyphs are not drawn rotated yet.
pub fn get_text_rotation<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this
        .as_object()
        .unwrap()
        .as_content_element_object()
        .unwrap();
    Ok(this.text_rotation().as_avm2_str(activation).into())
}

pub fn set_text_rotation<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this
        .as_object()
        .unwrap()
        .as_content_element_object()
        .unwrap();
    let s = args.get_string_non_null(activation, 0, "textRotation")?;
    this.set_text_rotation(
        TextRotationValue::from_avm2_str(&s)
            .filter(|&v| v != TextRotationValue::Auto)
            .ok_or_else(|| make_error_2008(activation, "textRotation"))?,
    );
    Ok(Value::Undefined)
}

// Timffle: `rawText` includes the U+FDEF placeholder of each `GraphicElement`.
pub fn get_raw_text<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this
        .as_object()
        .unwrap()
        .as_content_element_object()
        .unwrap();
    Ok(match this.raw_text(activation) {
        Some(s) => s.into(),
        None => Value::Null,
    })
}

// Timffle: helper for `GroupElement.getElementAtCharIndex` and the atom
// queries of `TextLine`.
pub fn leaf_at_char_index<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this
        .as_object()
        .unwrap()
        .as_content_element_object()
        .unwrap();
    let index = args.get_i32(0);
    let Ok(index) = usize::try_from(index) else {
        return Ok(Value::Null);
    };
    Ok(this
        .leaf_at_char_index(index)
        .map(|(e, _)| Value::from(e))
        .unwrap_or(Value::Null))
}
