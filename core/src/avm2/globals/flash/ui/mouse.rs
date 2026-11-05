//! `flash.ui.Mouse` builtin

use std::rc::Rc;

use crate::avm2::activation::Activation;
use crate::avm2::error::{Error2004Type, make_error_2004, make_error_2008};
use crate::avm2::function::FunctionArgs;
use crate::avm2::globals::slots::flash_geom_point as point_slots;
use crate::avm2::object::TObject;
use crate::avm2::parameters::ParametersExt;
use crate::avm2::value::Value;
use crate::avm2::{Avm2StrRepresentable, Error};
use crate::backend::ui::{CustomCursor, MouseCursor, RgbaFrame};
use crate::bitmap::bitmap_data::BitmapData;
use crate::player::RegisteredCursor;
use crate::string::AvmString;
use ruffle_macros::istr;
use ruffle_render::bitmap::PixelRegion;

pub fn hide<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    activation.context.ui.set_mouse_visible(false);
    Ok(Value::Undefined)
}

pub fn get_cursor<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    if let Some(cursor) = activation.context.mouse_data.current_custom_cursor {
        return Ok(cursor.into());
    }

    let cursor = activation.context.mouse_data.forced_cursor;
    Ok(cursor
        .map(|cursor| cursor.as_avm2_str(activation))
        .unwrap_or_else(|| istr!("auto"))
        .into())
}

pub fn set_cursor<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let value = args.get_string_non_null(activation, 0, "cursor")?;

    let forced = if &value == b"auto" {
        None
    } else if let Some(custom) = activation.context.mouse_data.custom_cursors.get(&value) {
        // Timffle: a registered name shows that bitmap cursor on the host; the
        // built-in cursor underneath stays automatic, like `auto`.
        let custom = CustomCursor::clone(&custom.0);
        activation.context.mouse_data.current_custom_cursor = Some(value);
        activation.context.mouse_data.forced_cursor = None;
        activation.context.ui.set_custom_cursor(Some(custom));
        return Ok(Value::Undefined);
    } else {
        Some(
            MouseCursor::from_avm2_str(&value)
                .ok_or_else(|| make_error_2008(activation, "cursor"))?,
        )
    };

    // Set the custom cursor to None now that we know that the cursor
    // is one of the enum values. This needs to be done here
    // so that we don't do this before potentially throwing an error.
    clear_custom_cursor(activation);
    activation.context.mouse_data.forced_cursor = forced;
    Ok(Value::Undefined)
}

/// Timffle: returns the host to the built-in cursor if a registered one is shown.
fn clear_custom_cursor<'gc>(activation: &mut Activation<'_, 'gc>) {
    if activation
        .context
        .mouse_data
        .current_custom_cursor
        .take()
        .is_some()
    {
        activation.context.ui.set_custom_cursor(None);
    }
}

pub fn show<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    activation.context.ui.set_mouse_visible(true);
    Ok(Value::Undefined)
}

/// Timffle: `Mouse.supportsNativeCursor`, whether the host can show the bitmap cursors
/// of `registerCursor()` (web: CSS `cursor: url()`, desktop: a winit custom cursor; the
/// test harness cannot). The registry and `Mouse.cursor` work either way.
pub fn get_supports_native_cursor<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    Ok(activation.context.ui.supports_native_cursor().into())
}

/// Timffle: `Mouse.registerCursor(name, cursor)`: copies the frames of the
/// `MouseCursorData` into the player's cursor registry under `name`.
///
/// Validation (the reference documents no errors; the codes are Flash Player's generic
/// ones for these argument faults): a null `name` or `cursor` is a TypeError #2007;
/// a `data` that is null or empty, a frame that is disposed, or a frame larger than
/// 32x32 pixels (the limit the `MouseCursorData` reference states) is an ArgumentError
/// #2004; so is one of the built-in names (`auto`, `arrow`, `button`, `hand`, `ibeam`),
/// which `Mouse.cursor` keeps for the built-in cursors. Registering a name again replaces
/// its cursor; if that cursor is being shown, the host shows the new one.
pub fn register_cursor<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let name = args.get_string_non_null(activation, 0, "name")?;
    let data = args.get_object(activation, 1, "cursor")?;

    if &name == b"auto" || MouseCursor::from_avm2_str(&name).is_some() {
        return Err(make_error_2004(activation, Error2004Type::ArgumentError));
    }

    let data_name = AvmString::new_utf8(activation.gc(), "data");
    let frames = Value::from(data).get_public_property(data_name, activation)?;
    let frames = frames
        .as_object()
        .and_then(|frames| {
            let storage = frames.as_vector_storage()?;
            Some(storage.iter().collect::<Vec<_>>())
        })
        .unwrap_or_default();
    if frames.is_empty() {
        return Err(make_error_2004(activation, Error2004Type::ArgumentError));
    }
    let frames = frames
        .into_iter()
        .map(|frame| {
            let bitmap = frame
                .as_object()
                .and_then(|frame| frame.as_bitmap_data())
                .ok_or_else(|| make_error_2004(activation, Error2004Type::ArgumentError))?;
            read_frame(activation, bitmap)
        })
        .collect::<Result<Vec<_>, _>>()?;

    let hot_spot_name = AvmString::new_utf8(activation.gc(), "hotSpot");
    let hot_spot = Value::from(data).get_public_property(hot_spot_name, activation)?;
    let hot_spot = match hot_spot.as_object() {
        Some(point) => {
            let x = point
                .get_slot(point_slots::X)
                .coerce_to_number(activation)?;
            let y = point
                .get_slot(point_slots::Y)
                .coerce_to_number(activation)?;
            (x.max(0.0) as u32, y.max(0.0) as u32)
        }
        None => (0, 0),
    };

    let frame_rate_name = AvmString::new_utf8(activation.gc(), "frameRate");
    let frame_rate = Value::from(data)
        .get_public_property(frame_rate_name, activation)?
        .coerce_to_number(activation)?;

    let cursor = Rc::new(CustomCursor {
        frames,
        hot_spot,
        frame_rate,
    });
    activation
        .context
        .mouse_data
        .custom_cursors
        .insert(name, RegisteredCursor(Rc::clone(&cursor)));
    if activation.context.mouse_data.current_custom_cursor == Some(name) {
        activation
            .context
            .ui
            .set_custom_cursor(Some(CustomCursor::clone(&cursor)));
    }
    Ok(Value::Undefined)
}

/// Timffle: the straight-alpha RGBA pixels of one cursor frame.
fn read_frame<'gc>(
    activation: &mut Activation<'_, 'gc>,
    bitmap: BitmapData<'gc>,
) -> Result<RgbaFrame, Error<'gc>> {
    bitmap.check_valid(activation)?;
    let (width, height) = (bitmap.width(), bitmap.height());
    if width > CustomCursor::MAX_SIZE || height > CustomCursor::MAX_SIZE {
        return Err(make_error_2004(activation, Error2004Type::ArgumentError));
    }
    let read = bitmap.read_area(
        PixelRegion::for_whole_size(width, height),
        activation.context.renderer,
    );
    let mut rgba = Vec::with_capacity((width * height * 4) as usize);
    for pixel in read.pixels() {
        let pixel = pixel.to_un_multiplied_alpha();
        rgba.extend_from_slice(&[pixel.red(), pixel.green(), pixel.blue(), pixel.alpha()]);
    }
    Ok(RgbaFrame {
        width,
        height,
        rgba,
    })
}

/// Timffle: `Mouse.unregisterCursor(name)`: forgets the cursor; if it is the one being
/// shown, `Mouse.cursor` falls back to `auto` (the built-in cursor returns).
pub fn unregister_cursor<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let name = args.get_string_non_null(activation, 0, "name")?;
    activation.context.mouse_data.custom_cursors.remove(&name);
    if activation.context.mouse_data.current_custom_cursor == Some(name) {
        clear_custom_cursor(activation);
    }
    Ok(Value::Undefined)
}
