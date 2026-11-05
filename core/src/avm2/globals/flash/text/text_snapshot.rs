//! Timffle: `flash.text.TextSnapshot` natives.
//!
//! A snapshot covers the static texts (`DefineText` objects) that are direct
//! children of one container, in display-list order, and reads their glyphs,
//! colours and positions straight from the `DefineText` records
//! (`crate::display_object::text`). Selection (`setSelected`/`setSelectColor`)
//! is kept on the static text objects, so it survives taking a new snapshot
//! and is drawn as a filled rectangle behind each selected glyph, the way
//! Flash draws it.

use crate::avm2::activation::Activation;
use crate::avm2::function::FunctionArgs;
use crate::avm2::object::{ArrayObject, ScriptObject, TObject as _};
use crate::avm2::parameters::ParametersExt;
use crate::avm2::value::Value;
use crate::avm2::{ArrayStorage, Error};
use crate::display_object::TextSnapshot;
use crate::string::AvmString;
use swf::Point;

pub use crate::avm2::object::text_snapshot_allocator;

fn snapshot<'gc>(this: Value<'gc>) -> Option<TextSnapshot<'gc>> {
    this.as_object()
        .and_then(|this| this.as_text_snapshot_object())
        .and_then(|this| this.snapshot())
}

/// Implements `TextSnapshot.charCount`
pub fn get_char_count<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let count = snapshot(this).map(|s| s.count()).unwrap_or_default();
    Ok(Value::from_usize_lossy(count))
}

/// Implements `TextSnapshot.findText`
pub fn find_text<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let from = args.get_i32(0);
    let text = args.get_string(activation, 1);
    let case_sensitive = args.get_bool(2);
    let index = snapshot(this)
        .map(|s| s.find_text(from, &text, case_sensitive))
        .unwrap_or(-1);
    Ok(index.into())
}

/// Implements `TextSnapshot.getSelected`
pub fn get_selected<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let from = args.get_i32(0);
    let to = args.get_i32(1);
    let selected = snapshot(this).is_some_and(|s| s.get_selected(from, to));
    Ok(selected.into())
}

/// Implements `TextSnapshot.getSelectedText`
pub fn get_selected_text<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let include_line_endings = args.get_bool(0);
    let text = snapshot(this)
        .map(|s| s.get_selected_text(include_line_endings))
        .unwrap_or_default();
    Ok(AvmString::new(activation.gc(), text).into())
}

/// Implements `TextSnapshot.getText`
pub fn get_text<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let from = args.get_i32(0);
    let to = args.get_i32(1);
    let include_line_endings = args.get_bool(2);
    let text = snapshot(this)
        .map(|s| s.get_text(from, to, include_line_endings))
        .unwrap_or_default();
    Ok(AvmString::new(activation.gc(), text).into())
}

/// Implements `TextSnapshot.getTextRunInfo`
///
/// One plain object per character with the properties the Adobe reference
/// lists: `indexInRun`, `selected`, `font`, `color` (alpha in the top byte),
/// `height` (pixels), `matrix_a`…`matrix_ty` (the character's position in the
/// parent container, `[1 0 0 1 x y]` for upright text) and `corner0x`…
/// `corner3y` (the bounding box in the parent container, top-left, top-right,
/// bottom-right, bottom-left).
pub fn get_text_run_info<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let from = args.get_i32(0);
    let to = args.get_i32(1);
    let runs = snapshot(this)
        .map(|s| s.text_run_info(activation.context, from, to))
        .unwrap_or_default();

    let mut storage = ArrayStorage::new(0);
    for run in runs {
        let object = ScriptObject::new_object(activation.context);
        let set = |name: &'static str, value: Value<'gc>| {
            object.set_dynamic_property(
                AvmString::new_utf8(activation.gc(), name),
                value,
                activation.gc(),
            );
        };
        let glyph = run.glyph;
        let position = run.matrix * Point::new(glyph.x, glyph.baseline);
        let color = (u32::from(glyph.color.a) << 24) | glyph.color.to_rgb();
        set("indexInRun", Value::from_usize_lossy(run.index));
        set("selected", run.selected.into());
        set(
            "font",
            AvmString::new_utf8(activation.gc(), glyph.font.descriptor().name()).into(),
        );
        set("color", Value::Number(color as f64));
        set("height", Value::Number(glyph.height.to_pixels()));
        set("matrix_a", Value::Number(run.matrix.a as f64));
        set("matrix_b", Value::Number(run.matrix.b as f64));
        set("matrix_c", Value::Number(run.matrix.c as f64));
        set("matrix_d", Value::Number(run.matrix.d as f64));
        set("matrix_tx", Value::Number(position.x.to_pixels()));
        set("matrix_ty", Value::Number(position.y.to_pixels()));
        let bounds = glyph.bounds();
        let corners = [
            Point::new(bounds.x_min, bounds.y_min),
            Point::new(bounds.x_max, bounds.y_min),
            Point::new(bounds.x_max, bounds.y_max),
            Point::new(bounds.x_min, bounds.y_max),
        ];
        let names = [
            ("corner0x", "corner0y"),
            ("corner1x", "corner1y"),
            ("corner2x", "corner2y"),
            ("corner3x", "corner3y"),
        ];
        for (corner, (x_name, y_name)) in corners.into_iter().zip(names) {
            let corner = run.matrix * corner;
            set(x_name, Value::Number(corner.x.to_pixels()));
            set(y_name, Value::Number(corner.y.to_pixels()));
        }
        storage.push(object.into());
    }
    Ok(ArrayObject::from_storage(activation.context, storage).into())
}

/// Implements `TextSnapshot.hitTestTextNearPos`
pub fn hit_test_text_near_pos<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let x = args.get_f64(0);
    let y = args.get_f64(1);
    let max_distance = args.get_f64(2);
    let index = snapshot(this)
        .map(|s| s.hit_test_text_near_pos(activation.context, x, y, max_distance))
        .unwrap_or(-1);
    Ok(Value::Number(index as f64))
}

/// Implements `TextSnapshot.setSelectColor`
pub fn set_select_color<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let color = args.get_u32(0);
    if let Some(snapshot) = snapshot(this) {
        snapshot.set_select_color(color);
    }
    Ok(Value::Undefined)
}

/// Implements `TextSnapshot.setSelected`
pub fn set_selected<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let from = args.get_i32(0);
    let to = args.get_i32(1);
    let select = args.get_bool(2);
    if let Some(snapshot) = snapshot(this) {
        snapshot.set_selected(from, to, select);
    }
    Ok(Value::Undefined)
}
