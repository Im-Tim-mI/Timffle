//! `flash.display.BitmapData` builtin/prototype

use crate::avm2::Error;
use crate::avm2::activation::Activation;
use crate::avm2::bytearray::ByteArrayStorage;
use crate::avm2::error::{
    Error2004Type, Error2006Type, make_error_2004, make_error_2005, make_error_2006,
    make_error_2007, make_error_2008, make_error_2015, make_error_2027, make_error_3699,
};
use crate::avm2::filters::FilterAvm2Ext;
use crate::avm2::function::FunctionArgs;
use crate::avm2::globals::flash::display::display_object::object_to_rectangle;
use crate::avm2::globals::flash::geom::transform::object_to_color_transform;
use crate::avm2::globals::flash::geom::transform::object_to_matrix;
use crate::avm2::globals::slots::{
    flash_geom_point as point_slots, flash_geom_rectangle as rectangle_slots,
};
pub use crate::avm2::object::bitmap_data_allocator;
use crate::avm2::object::{BitmapDataObject, ByteArrayObject, Object, TObject, VectorObject};
use crate::avm2::parameters::ParametersExt;
use crate::avm2::value::Value;
use crate::avm2::vector::VectorStorage;
use crate::bitmap::bitmap_data::{BitmapData, ChannelOptions, ThresholdOperation};
use crate::bitmap::bitmap_data::{BitmapDataDrawError, IBitmapDrawable};
use crate::bitmap::{is_size_valid, operations};
use crate::character::{Character, CompressedBitmap};
use crate::ecma_conversions::round_to_even;
use crate::swf::BlendMode;
use ruffle_render::filters::Filter;
use ruffle_render::transform::Transform;
use std::str::FromStr;

// Timffle: JPEG XR encoder for encode(..., JPEGXREncoderOptions)
mod jpegxr_encode;
#[cfg(all(test, feature = "jpegxr"))]
mod jpegxr_flash_samples;
use swf::{Rectangle, Twips};

// Computes the integer x,y,width,height values from
// the given `Rectangle`. This method performs `x + width`
// and `y + height` as floating point operations before
// `round_to_even`, which is needed to match Flash Player's
// rounding behavior.
fn get_rectangle_x_y_width_height<'gc>(
    activation: &mut Activation<'_, 'gc>,
    rectangle: Object<'gc>,
) -> Result<(i32, i32, i32, i32), Error<'gc>> {
    let x = rectangle
        .get_slot(rectangle_slots::X)
        .coerce_to_number(activation)?;
    let y = rectangle
        .get_slot(rectangle_slots::Y)
        .coerce_to_number(activation)?;
    let width = rectangle
        .get_slot(rectangle_slots::WIDTH)
        .coerce_to_number(activation)?;
    let height = rectangle
        .get_slot(rectangle_slots::HEIGHT)
        .coerce_to_number(activation)?;

    let x_max = round_to_even(x + width);
    let y_max = round_to_even(y + height);

    let x_int = round_to_even(x);
    let y_int = round_to_even(y);

    let width_int = x_max - x_int;
    let height_int = y_max - y_int;

    Ok((x_int, y_int, width_int, height_int))
}

/// Copy the static data from a given Bitmap into a new BitmapData.
///
/// `bd` is assumed to be an uninstantiated library symbol, associated with the
/// class named by `name`.
pub fn fill_bitmap_data_from_symbol<'gc>(
    activation: &mut Activation<'_, 'gc>,
    bd: &CompressedBitmap,
) -> BitmapData<'gc> {
    let bitmap = bd.decode().expect("Failed to decode BitmapData");
    BitmapData::new_with_pixels(
        activation.context.gc_context,
        bitmap.width(),
        bitmap.height(),
        true,
        bitmap
            .as_colors()
            .map(crate::bitmap::bitmap_data::Color::from)
            .collect(),
    )
}

/// Implements `flash.display.BitmapData`'s 'init' method (invoked from the AS3 constructor)
pub fn init<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();
    let bitmap_data_obj = this.as_bitmap_data_object().unwrap();

    // We set the underlying BitmapData instance - we start out with a dummy BitmapData,
    // which makes custom classes see a disposed BitmapData before they call super()
    let name = this.instance_class().name();
    let character = activation
        .context
        .library
        .avm2_class_registry()
        .class_symbol(this.instance_class())
        .and_then(|(movie, chara_id)| {
            activation
                .context
                .library
                .library_for_movie_mut(movie)
                .character_by_id(chara_id)
        });

    let new_bitmap_data = if let Some(Character::Bitmap(bitmap)) = character {
        // Instantiating BitmapData from an Animate-style bitmap asset
        fill_bitmap_data_from_symbol(activation, bitmap.compressed())
    } else {
        if character.is_some() {
            //TODO: Determine if mismatched symbols will still work as a
            //regular BitmapData subclass, or if this should throw
            tracing::warn!(
                "BitmapData subclass {:?} is associated with a non-bitmap symbol",
                name
            );
        }

        let width = args.get_u32(0);
        let height = args.get_u32(1);
        let transparency = args.get_bool(2);
        let fill_color = args.get_u32(3);

        if !is_size_valid(activation.context.root_swf.version(), width, height) {
            return Err(make_error_2015(activation));
        }

        BitmapData::new(
            activation.context.gc_context,
            width,
            height,
            transparency,
            fill_color,
        )
    };

    new_bitmap_data.init_object2(activation.gc(), bitmap_data_obj);
    bitmap_data_obj.init_bitmap_data(activation.gc(), new_bitmap_data);

    Ok(Value::Undefined)
}

/// Implements `BitmapData.width`'s getter.
pub fn get_width<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(bitmap_data) = this.as_bitmap_data() {
        bitmap_data.check_valid(activation)?;
        return Ok((bitmap_data.width() as i32).into());
    }

    Ok(Value::Undefined)
}

/// Implements `BitmapData.height`'s getter.
pub fn get_height<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(bitmap_data) = this.as_bitmap_data() {
        bitmap_data.check_valid(activation)?;
        return Ok((bitmap_data.height() as i32).into());
    }

    Ok(Value::Undefined)
}

/// Implements `BitmapData.transparent`'s getter.
pub fn get_transparent<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(bitmap_data) = this.as_bitmap_data() {
        bitmap_data.check_valid(activation)?;
        return Ok(bitmap_data.transparency().into());
    }

    Ok(Value::Undefined)
}

/// Implements `BitmapData.scroll`.
pub fn scroll<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(bitmap_data) = this.as_bitmap_data() {
        bitmap_data.check_valid(activation)?;
        let x = args.get_i32(0);
        let y = args.get_i32(1);

        operations::scroll(
            activation.gc(),
            activation.context.renderer,
            bitmap_data,
            x,
            y,
        );
    }

    Ok(Value::Undefined)
}

/// Implements `BitmapData.copyPixels`.
pub fn copy_pixels<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(bitmap_data) = this.as_bitmap_data() {
        bitmap_data.check_valid(activation)?;
        let source_bitmap = args.get_object(activation, 0, "sourceBitmapData")?;

        let source_rect = args.get_object(activation, 1, "sourceRect")?;

        let (src_min_x, src_min_y, src_width, src_height) =
            get_rectangle_x_y_width_height(activation, source_rect)?;

        let dest_point = args.get_object(activation, 2, "destPoint")?;

        let dest_x = dest_point
            .get_slot(point_slots::X)
            .coerce_to_i32(activation)?;
        let dest_y = dest_point
            .get_slot(point_slots::Y)
            .coerce_to_i32(activation)?;

        if let Some(src_bitmap) = source_bitmap.as_bitmap_data() {
            src_bitmap.check_valid(activation)?;

            let mut alpha_source = None;

            if let Some(alpha_bitmap) = args.try_get_object(3).and_then(|o| o.as_bitmap_data()) {
                // Testing shows that a null/undefined 'alphaPoint' parameter is treated
                // as 'new Point(0, 0)'
                let mut x = 0;
                let mut y = 0;

                if let Some(alpha_point) = args.try_get_object(4) {
                    x = alpha_point
                        .get_slot(point_slots::X)
                        .coerce_to_i32(activation)?;
                    y = alpha_point
                        .get_slot(point_slots::Y)
                        .coerce_to_i32(activation)?;
                }

                alpha_source = Some((alpha_bitmap, (x, y)));
            }

            let merge_alpha = args.get_bool(5);

            if let Some((alpha_bitmap, alpha_point)) = alpha_source {
                operations::copy_pixels_with_alpha_source(
                    activation.context,
                    bitmap_data,
                    src_bitmap,
                    (src_min_x, src_min_y, src_width, src_height),
                    (dest_x, dest_y),
                    alpha_bitmap,
                    alpha_point,
                    merge_alpha,
                );
            } else {
                operations::copy_pixels(
                    activation.context,
                    bitmap_data,
                    src_bitmap,
                    (src_min_x, src_min_y, src_width, src_height),
                    (dest_x, dest_y),
                    merge_alpha,
                );
            }
        }
    }

    Ok(Value::Undefined)
}

/// Implements `BitmapData.getPixels`.
pub fn get_pixels<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(bitmap_data) = this.as_bitmap_data() {
        bitmap_data.check_valid(activation)?;
        let rectangle = args.get_object(activation, 0, "rect")?;
        let (x, y, width, height) = get_rectangle_x_y_width_height(activation, rectangle)?;
        let mut storage = ByteArrayStorage::new(activation.context);

        operations::get_pixels_as_byte_array(
            activation,
            bitmap_data,
            x,
            y,
            width,
            height,
            &mut storage,
        )?;

        let bytearray = ByteArrayObject::from_storage(activation.context, storage);
        return Ok(bytearray.into());
    }

    Ok(Value::Undefined)
}

/// Implements `BitmapData.copyPixelsToByteArray`.
pub fn copy_pixels_to_byte_array<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(bitmap_data) = this.as_bitmap_data() {
        bitmap_data.check_valid(activation)?;
        let rectangle = args.get_object(activation, 0, "rect")?;
        let storage = args.get_object(activation, 1, "data")?;
        let mut storage = storage.as_bytearray_mut().unwrap();
        let (x, y, width, height) = get_rectangle_x_y_width_height(activation, rectangle)?;
        operations::get_pixels_as_byte_array(
            activation,
            bitmap_data,
            x,
            y,
            width,
            height,
            &mut storage,
        )?;
    }

    Ok(Value::Undefined)
}

pub fn get_vector<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(bitmap_data) = this.as_bitmap_data() {
        bitmap_data.check_valid(activation)?;
        let rectangle = args.get_object(activation, 0, "rect")?;
        let (x, y, width, height) = get_rectangle_x_y_width_height(activation, rectangle)?;

        let pixels = operations::get_vector(
            bitmap_data,
            activation.context.renderer,
            x,
            y,
            width,
            height,
        );

        let value_type = activation.avm2().class_defs().uint;
        let new_storage = VectorStorage::from_values(pixels, false, Some(value_type));

        return Ok(VectorObject::from_vector(new_storage, activation).into());
    }

    Ok(Value::Undefined)
}

/// Implements `BitmapData.getPixel`.
pub fn get_pixel<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(bitmap_data) = this.as_bitmap_data() {
        bitmap_data.check_valid(activation)?;
        let x = args.get_u32(0);
        let y = args.get_u32(1);
        let col = operations::get_pixel(bitmap_data, activation.context.renderer, x, y);
        return Ok(col.into());
    }

    Ok(Value::Undefined)
}

/// Implements `BitmapData.getPixel32`.
pub fn get_pixel32<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(bitmap_data) = this.as_bitmap_data() {
        bitmap_data.check_valid(activation)?;
        let x = args.get_u32(0);
        let y = args.get_u32(1);
        let pixel = operations::get_pixel32(bitmap_data, activation.context.renderer, x, y);
        return Ok(pixel.into());
    }

    Ok(Value::Undefined)
}

/// Implements `BitmapData.setPixel`.
pub fn set_pixel<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(bitmap_data) = this.as_bitmap_data() {
        let x = args.get_u32(0);
        let y = args.get_u32(1);
        let color = args.get_u32(2);
        operations::set_pixel(
            activation.gc(),
            activation.context.renderer,
            bitmap_data,
            x,
            y,
            color.into(),
        );
    }

    Ok(Value::Undefined)
}

/// Implements `BitmapData.setPixel32`.
pub fn set_pixel32<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(bitmap_data) = this.as_bitmap_data() {
        bitmap_data.check_valid(activation)?;

        let x = args.get_u32(0);
        let y = args.get_u32(1);
        let color = args.get_u32(2);

        operations::set_pixel32(
            activation.gc(),
            activation.context.renderer,
            bitmap_data,
            x,
            y,
            color,
        );
    }

    Ok(Value::Undefined)
}

/// Implements `BitmapData.setPixels`.
pub fn set_pixels<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    let rectangle = args.get_object(activation, 0, "rect")?;
    let bytearray = args.get_object(activation, 1, "inputByteArray")?;

    if let Some(bitmap_data) = this.as_bitmap_data() {
        let (x, y, width, height) = get_rectangle_x_y_width_height(activation, rectangle)?;

        let mut ba_write = bytearray
            .as_bytearray_mut()
            .expect("Parameter must be a bytearray");

        operations::set_pixels_from_byte_array(
            activation.gc(),
            activation.context.renderer,
            bitmap_data,
            x,
            y,
            width,
            height,
            &mut ba_write,
        )
        .map_err(|e| e.to_avm(activation))?;
    }

    Ok(Value::Undefined)
}

/// Implements `BitmapData.setVector`.
pub fn set_vector<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    let rectangle = args.get_object(activation, 0, "rect")?;
    // Note - flash player misspells this as 'imputVector'.
    let vec = args.get_object(activation, 1, "imputVector")?;
    if let Some(bitmap_data) = this.as_bitmap_data() {
        let x = rectangle
            .get_slot(rectangle_slots::X)
            .coerce_to_number(activation)?;
        let y = rectangle
            .get_slot(rectangle_slots::Y)
            .coerce_to_number(activation)?;
        let width = rectangle
            .get_slot(rectangle_slots::WIDTH)
            .coerce_to_number(activation)?;
        let height = rectangle
            .get_slot(rectangle_slots::HEIGHT)
            .coerce_to_number(activation)?;

        // Clamp to bitmap rect.
        let bitmap_width = f64::from(bitmap_data.width());
        let bitmap_height = f64::from(bitmap_data.height());
        let x_min = x.clamp(0.0, bitmap_width);
        let y_min = y.clamp(0.0, bitmap_height);
        let x_max = (x + width).clamp(x_min, bitmap_width);
        let y_max = (y + height).clamp(y_min, bitmap_height);

        let x_min = x_min as u32;
        let x_max = x_max as u32;
        let y_min = y_min as u32;
        let y_max = y_max as u32;

        let vec_read = vec
            .as_vector_storage()
            .expect("BitmapData.setVector: Expected vector");

        operations::set_vector(
            activation,
            bitmap_data,
            x_min,
            y_min,
            x_max,
            y_max,
            &vec_read,
        )?;
    }

    Ok(Value::Undefined)
}

/// Implements `BitmapData.copyChannel`.
pub fn copy_channel<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(bitmap_data) = this.as_bitmap_data() {
        bitmap_data.check_valid(activation)?;

        let source_bitmap = args.get_object(activation, 0, "sourceBitmapData")?;
        let source_rect = args.get_object(activation, 1, "sourceRect")?;
        let dest_point = args.get_object(activation, 2, "destPoint")?;

        let dest_x = dest_point
            .get_slot(point_slots::X)
            .coerce_to_i32(activation)?;
        let dest_y = dest_point
            .get_slot(point_slots::Y)
            .coerce_to_i32(activation)?;

        let source_channel = args.get_i32(3);

        let dest_channel = args.get_i32(4);

        if let Some(source_bitmap) = source_bitmap.as_bitmap_data() {
            //TODO: what if source is disposed

            let (src_min_x, src_min_y, src_width, src_height) =
                get_rectangle_x_y_width_height(activation, source_rect)?;

            operations::copy_channel(
                activation.gc(),
                activation.context.renderer,
                bitmap_data,
                (dest_x, dest_y),
                (src_min_x, src_min_y, src_width, src_height),
                source_bitmap,
                source_channel,
                dest_channel,
            );
        }
    }
    Ok(Value::Undefined)
}

pub fn flood_fill<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(bitmap_data) = this.as_bitmap_data()
        && !bitmap_data.disposed()
    {
        let x = args.get_u32(0);
        let y = args.get_u32(1);
        let color = args.get_u32(2);

        operations::flood_fill(
            activation.gc(),
            activation.context.renderer,
            bitmap_data,
            x,
            y,
            color,
        );
    }

    Ok(Value::Undefined)
}

pub fn noise<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    let low = args.get_u32(1) as u8;

    let high = args.get_u32(2) as u8;

    let channel_options = ChannelOptions::from_bits_truncate(args.get_u32(3) as u8);

    let gray_scale = args.get_bool(4);

    if let Some(bitmap_data) = this.as_bitmap_data() {
        bitmap_data.check_valid(activation)?;
        let random_seed = args.get_i32(0);
        operations::noise(
            activation.gc(),
            bitmap_data,
            random_seed,
            low,
            high.max(low),
            channel_options,
            gray_scale,
        );
    }
    Ok(Value::Undefined)
}

pub fn color_transform<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(bitmap_data) = this.as_bitmap_data()
        && !bitmap_data.disposed()
    {
        // TODO: Re-use `object_to_rectangle` in `movie_clip.rs`.
        let rectangle = args.get_object(activation, 0, "rect")?;
        let (x, y, width, height) = get_rectangle_x_y_width_height(activation, rectangle)?;

        let x_min = x.max(0) as u32;
        let x_max = (x + width) as u32;
        let y_min = y.max(0) as u32;
        let y_max = (y + height) as u32;

        let color_transform = args.get_object(activation, 1, "colorTransform")?;
        let color_transform = object_to_color_transform(color_transform);

        operations::color_transform(
            activation.gc(),
            activation.context.renderer,
            bitmap_data,
            x_min,
            y_min,
            x_max,
            y_max,
            &color_transform,
        );
    }

    Ok(Value::Undefined)
}

pub fn get_color_bounds_rect<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    let Some(bitmap_data) = this.as_bitmap_data().filter(|d| !d.disposed()) else {
        return Ok(Value::Undefined);
    };

    let find_color = args.get_bool(2);

    let mask = args.get_u32(0);
    let color = args.get_u32(1);

    let (x, y, w, h) = operations::color_bounds_rect(
        activation.context.renderer,
        bitmap_data,
        find_color,
        mask,
        color,
    );

    let rect = activation
        .avm2()
        .classes()
        .rectangle
        .construct(activation, &[x.into(), y.into(), w.into(), h.into()])?;

    Ok(rect)
}

pub fn lock<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    // `BitmapData.lock` tells Flash Player to temporarily stop updating the player's
    // dirty region for any Bitmap stage instances displaying this BitmapData.
    // Normally, each call to `setPixel` etc. causes Flash to update the player dirty
    // region with the changed area.
    //
    // Note that `lock` has no effect on future `BitmapData` operations, they will always
    // see the latest pixel data. Instead, it potentially delays the re-rendering of `Bitmap`
    // instances on the stage, based on how the player decides to update its dirty region
    // ("Show Redraw Regions" in Flash Player debugger context menu).
    //
    // Ruffle has no concept of a player dirty region for now, so this has no effect.
    Ok(Value::Undefined)
}

pub fn unlock<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    // No effect (see comments for `lock`).
    Ok(Value::Undefined)
}

pub fn hit_test<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    let Some(bitmap_data) = this.as_bitmap_data().filter(|d| !d.disposed()) else {
        return Ok(false.into());
    };

    let first_point = args.get_object(activation, 0, "firstPoint")?;
    let top_left = (
        first_point
            .get_slot(point_slots::X)
            .coerce_to_i32(activation)?,
        first_point
            .get_slot(point_slots::Y)
            .coerce_to_i32(activation)?,
    );
    let source_threshold = args.get_u32(1).clamp(0, u8::MAX.into()) as u8;
    let compare_object = args.get_value(2);
    let point_class = activation.avm2().classes().point.inner_class_definition();
    let rectangle_class = activation
        .avm2()
        .classes()
        .rectangle
        .inner_class_definition();

    let Value::Object(compare_object) = compare_object else {
        // This is the error message Flash Player produces. Even though it's misleading.
        return Err(make_error_2005(activation, 0, "BitmapData"));
    };

    if compare_object.is_of_type(point_class) {
        let test_point = (
            compare_object
                .get_slot(point_slots::X)
                .coerce_to_i32(activation)?
                - top_left.0,
            compare_object
                .get_slot(point_slots::Y)
                .coerce_to_i32(activation)?
                - top_left.1,
        );

        Ok(Value::Bool(operations::hit_test_point(
            activation.context.renderer,
            bitmap_data,
            source_threshold,
            test_point,
        )))
    } else if compare_object.is_of_type(rectangle_class) {
        let test_point = (
            compare_object
                .get_slot(rectangle_slots::X)
                .coerce_to_i32(activation)?
                - top_left.0,
            compare_object
                .get_slot(rectangle_slots::Y)
                .coerce_to_i32(activation)?
                - top_left.1,
        );
        let size = (
            compare_object
                .get_slot(rectangle_slots::WIDTH)
                .coerce_to_i32(activation)?,
            compare_object
                .get_slot(rectangle_slots::HEIGHT)
                .coerce_to_i32(activation)?,
        );

        Ok(Value::Bool(operations::hit_test_rectangle(
            activation.context.renderer,
            bitmap_data,
            source_threshold,
            test_point,
            size,
        )))
    } else if let Some(other_bmd) = compare_object.as_bitmap_data() {
        other_bmd.check_valid(activation)?;
        let second_point = args.get_object(activation, 3, "secondBitmapDataPoint")?;
        let second_point = (
            second_point
                .get_slot(point_slots::X)
                .coerce_to_i32(activation)?,
            second_point
                .get_slot(point_slots::Y)
                .coerce_to_i32(activation)?,
        );
        let second_threshold = args.get_u32(4).clamp(0, u8::MAX.into()) as u8;

        let result = operations::hit_test_bitmapdata(
            activation.context.renderer,
            bitmap_data,
            top_left,
            source_threshold,
            other_bmd,
            second_point,
            second_threshold,
        );

        Ok(Value::Bool(result))
    } else if let Some(bitmap) = compare_object
        .as_display_object()
        .and_then(|dobj| dobj.as_bitmap())
    {
        let other_bmd = bitmap.bitmap_data();
        other_bmd.check_valid(activation)?;
        let second_point = args.get_object(activation, 3, "secondBitmapDataPoint")?;
        let second_point = (
            second_point
                .get_slot(point_slots::X)
                .coerce_to_i32(activation)?,
            second_point
                .get_slot(point_slots::Y)
                .coerce_to_i32(activation)?,
        );
        let second_threshold = args.get_u32(4).clamp(0, u8::MAX.into()) as u8;

        Ok(Value::Bool(operations::hit_test_bitmapdata(
            activation.context.renderer,
            bitmap_data,
            top_left,
            source_threshold,
            other_bmd,
            second_point,
            second_threshold,
        )))
    } else {
        // This is the error message Flash Player produces. Even though it's misleading.
        Err(make_error_2005(activation, 0, "BitmapData"))
    }
}

/// Implements `BitmapData.draw`
pub fn draw<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(bitmap_data) = this.as_bitmap_data() {
        let mut transform = Transform::default();
        let mut blend_mode = BlendMode::Normal;

        if let Some(matrix) = args.try_get_object(1) {
            transform.matrix = object_to_matrix(matrix);
        }

        if let Some(color_transform) = args.try_get_object(2) {
            transform.color_transform = object_to_color_transform(color_transform);
        }

        if let Some(mode) = args.try_get_string(3) {
            if let Ok(mode) = BlendMode::from_str(&mode.to_string()) {
                blend_mode = mode;
            } else {
                tracing::error!("Unknown blend mode {:?}", mode);
                return Err(make_error_2008(activation, "blendMode"));
            }
        }

        let mut clip_rect = None;

        if let Some(clip_rect_obj) = args.try_get_object(4) {
            clip_rect = Some(object_to_rectangle(clip_rect_obj));
        }

        let smoothing = args.get_bool(5);

        let source = args.get_object(activation, 0, "source")?;

        let source = if let Some(source_object) = source.as_display_object() {
            IBitmapDrawable::DisplayObject(source_object)
        } else if let Some(source_bitmap) = source.as_bitmap_data() {
            IBitmapDrawable::BitmapData(source_bitmap)
        } else {
            return Err(format!("BitmapData.draw: unexpected source {source:?}").into());
        };

        // If the bitmapdata is invalid, it's fine to return early, since the pixels
        // are inaccessible
        bitmap_data.check_valid(activation)?;

        // Do this last, so that we only call `overwrite_cpu_pixels_from_gpu`
        // if we're actually going to draw something.
        let quality = activation.context.stage.quality();
        match operations::draw(
            activation.context,
            bitmap_data,
            source,
            transform,
            smoothing,
            blend_mode,
            clip_rect,
            quality,
        ) {
            Ok(()) => {}
            Err(BitmapDataDrawError::Unimplemented) => {
                return Err("Render backend does not support BitmapData.draw".into());
            }
        };
    }
    Ok(Value::Undefined)
}

/// Implements `BitmapData.drawWithQuality`
pub fn draw_with_quality<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(bitmap_data) = this.as_bitmap_data() {
        let mut transform = Transform::default();
        let mut blend_mode = BlendMode::Normal;

        if let Some(matrix) = args.try_get_object(1) {
            transform.matrix = object_to_matrix(matrix);
        }

        if let Some(color_transform) = args.try_get_object(2) {
            transform.color_transform = object_to_color_transform(color_transform);
        }

        if let Some(mode) = args.try_get_string(3) {
            if let Ok(mode) = BlendMode::from_str(&mode.to_string()) {
                blend_mode = mode;
            } else {
                tracing::error!("Unknown blend mode {:?}", mode);
                return Err(make_error_2008(activation, "blendMode"));
            }
        }

        let mut clip_rect = None;

        if let Some(clip_rect_obj) = args.try_get_object(4) {
            clip_rect = Some(object_to_rectangle(clip_rect_obj));
        }

        let smoothing = args.get_bool(5);

        let source = args.get_object(activation, 0, "source")?;

        let source = if let Some(source_object) = source.as_display_object() {
            IBitmapDrawable::DisplayObject(source_object)
        } else if let Some(source_bitmap) = source.as_bitmap_data() {
            IBitmapDrawable::BitmapData(source_bitmap)
        } else {
            return Err(format!("BitmapData.drawWithQuality: unexpected source {source:?}").into());
        };

        // Unknown quality defaults to stage's quality
        let quality = if let Some(quality) = args.try_get_string(6) {
            match quality.parse() {
                Ok(quality) => quality,
                Err(_) => return Err(make_error_2004(activation, Error2004Type::ArgumentError)),
            }
        } else {
            activation.context.stage.quality()
        };

        match operations::draw(
            activation.context,
            bitmap_data,
            source,
            transform,
            smoothing,
            blend_mode,
            clip_rect,
            quality,
        ) {
            Ok(()) => {}
            Err(BitmapDataDrawError::Unimplemented) => {
                return Err("Render backend does not support BitmapData.draw".into());
            }
        };
    }
    Ok(Value::Undefined)
}

/// Implement `BitmapData.fillRect`
pub fn fill_rect<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    let rectangle = args.get_object(activation, 0, "rect")?;

    let color = args.get_u32(1);

    if let Some(bitmap_data) = this.as_bitmap_data() {
        bitmap_data.check_valid(activation)?;
        let (x, y, width, height) = get_rectangle_x_y_width_height(activation, rectangle)?;

        operations::fill_rect(
            activation.gc(),
            activation.context.renderer,
            bitmap_data,
            x,
            y,
            width,
            height,
            color,
        );
    }
    Ok(Value::Undefined)
}

/// Implements `BitmapData.dispose`
pub fn dispose<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(bitmap_data) = this.as_bitmap_data() {
        // Don't check if we've already disposed this BitmapData - 'BitmapData.dispose()' can be called
        // multiple times
        bitmap_data.dispose(activation.gc());
    }
    Ok(Value::Undefined)
}

/// Implement `BitmapData.rect`
pub fn get_rect<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(bitmap_data) = this.as_bitmap_data() {
        return activation.avm2().classes().rectangle.construct(
            activation,
            &[
                0.into(),
                0.into(),
                bitmap_data.width().into(),
                bitmap_data.height().into(),
            ],
        );
    }
    Ok(Value::Undefined)
}

/// Implement `BitmapData.applyFilter`
pub fn apply_filter<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(dest_bitmap) = this.as_bitmap_data() {
        let source_bitmap = args
            .get_object(activation, 0, "sourceBitmapData")?
            .as_bitmap_data()
            .unwrap();
        let source_rect = args.get_object(activation, 1, "sourceRect")?;
        let source_rect = object_to_rectangle(source_rect);
        let filter = args.get_object(activation, 3, "filter")?;
        let filter = Filter::from_avm2_object(activation, filter)?;

        let mut source_point = (
            source_rect.x_min.to_pixels().floor() as u32,
            source_rect.y_min.to_pixels().floor() as u32,
        );
        let mut source_size = (
            source_rect.width().to_pixels().ceil() as u32,
            source_rect.height().to_pixels().ceil() as u32,
        );
        // Timffle: a ShaderFilter over a sourceRect that is not the whole source: the
        // region is copied into a temporary bitmap of the rect's size (clamped to the
        // source) and the shader runs over that bitmap, so outCoord() starts at the
        // rect's corner like for the other filters. Flash's behaviour at the rect's
        // edges (it crops/translates oddly for a non-zero x/y, and ignores width/height
        // when x = y = 0) is not reproduced; see timffle/docs/CHANGES-FROM-RUFFLE.md.
        let mut source_bitmap = source_bitmap;
        if matches!(filter, Filter::ShaderFilter(_)) {
            let source_bitmap_rect = Rectangle {
                x_min: Twips::ZERO,
                x_max: Twips::from_pixels(source_bitmap.width() as f64),
                y_min: Twips::ZERO,
                y_max: Twips::from_pixels(source_bitmap.height() as f64),
            };
            if source_rect != source_bitmap_rect {
                let max_width = source_bitmap.width().saturating_sub(source_point.0);
                let max_height = source_bitmap.height().saturating_sub(source_point.1);
                let width = source_size.0.min(max_width);
                let height = source_size.1.min(max_height);
                if width == 0 || height == 0 {
                    return Ok(Value::Undefined);
                }
                let temporary = BitmapData::new(
                    activation.gc(),
                    width,
                    height,
                    source_bitmap.transparency(),
                    0,
                );
                operations::copy_pixels(
                    activation.context,
                    temporary,
                    source_bitmap,
                    (
                        source_point.0 as i32,
                        source_point.1 as i32,
                        width as i32,
                        height as i32,
                    ),
                    (0, 0),
                    false,
                );
                source_bitmap = temporary;
                source_point = (0, 0);
                source_size = (width, height);
            }
        }
        let dest_point = args.get_object(activation, 2, "destPoint")?;
        let dest_point = (
            dest_point
                .get_slot(point_slots::X)
                .coerce_to_i32(activation)?,
            dest_point
                .get_slot(point_slots::Y)
                .coerce_to_i32(activation)?,
        );

        operations::apply_filter(
            activation.context,
            dest_bitmap,
            source_bitmap,
            source_point,
            source_size,
            dest_point,
            filter,
        );
    }
    Ok(Value::Undefined)
}

/// Implement `BitmapData.clone`
pub fn clone<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(bitmap_data) = this.as_bitmap_data()
        && !bitmap_data.disposed()
    {
        let new_bitmap_data =
            bitmap_data.clone_data(activation.context.gc_context, activation.context.renderer);

        let new_bitmap_data_object =
            BitmapDataObject::from_bitmap_data(activation.context, new_bitmap_data);

        return Ok(new_bitmap_data_object.into());
    }
    Ok(Value::Undefined)
}

/// Implement `BitmapData.paletteMap`
pub fn palette_map<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(bitmap_data) = this.as_bitmap_data() {
        bitmap_data.check_valid(activation)?;
        let source_bitmap = args
            .get_object(activation, 0, "sourceBitmapData")?
            .as_bitmap_data()
            .unwrap();

        let source_rect = args.get_object(activation, 1, "sourceRect")?;
        let source_rect = object_to_rectangle(source_rect);
        let source_point = (
            source_rect.x_min.to_pixels().floor() as i32,
            source_rect.y_min.to_pixels().floor() as i32,
        );
        let source_size = (
            source_rect.width().to_pixels().ceil() as i32,
            source_rect.height().to_pixels().ceil() as i32,
        );
        let dest_point = args.get_object(activation, 2, "destPoint")?;
        let dest_point = (
            dest_point
                .get_slot(point_slots::X)
                .coerce_to_i32(activation)?,
            dest_point
                .get_slot(point_slots::Y)
                .coerce_to_i32(activation)?,
        );

        let mut get_channel = |index: usize, shift: usize| -> Result<[u32; 256], Error<'gc>> {
            let arg = args.try_get_object(index);
            let mut array = [0_u32; 256];
            for (i, item) in array.iter_mut().enumerate() {
                *item = if let Some(arg) = arg {
                    arg.get_enumerant_value(i as u32, activation)?
                        .coerce_to_u32(activation)?
                } else {
                    // This is an "identity mapping", fulfilling the part of the spec that
                    // says that channels which have no array provided are simply copied.
                    (i << shift) as u32
                }
            }
            Ok(array)
        };

        let red_array = get_channel(3, 16)?;
        let green_array = get_channel(4, 8)?;
        let blue_array = get_channel(5, 0)?;
        let alpha_array = get_channel(6, 24)?;

        operations::palette_map(
            activation.gc(),
            activation.context.renderer,
            bitmap_data,
            source_bitmap,
            (source_point.0, source_point.1, source_size.0, source_size.1),
            dest_point,
            (red_array, green_array, blue_array, alpha_array),
        );
    }

    Ok(Value::Undefined)
}

/// Implement `BitmapData.perlinNoise`
pub fn perlin_noise<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(bitmap_data) = this.as_bitmap_data()
        && !bitmap_data.disposed()
    {
        let base_x = args.get_f64(0);
        let base_y = args.get_f64(1);
        let num_octaves = args.get_u32(2) as usize;
        let seed = args.get_i32(3) as i64;
        let stitch = args.get_bool(4);
        let fractal_noise = args.get_bool(5);
        let channel_options = ChannelOptions::from_bits_truncate(args.get_i32(6) as u8);
        let grayscale = args.get_bool(7);
        let offsets = args.try_get_object(8);

        let point_class = activation.avm2().classes().point.inner_class_definition();

        let octave_offsets: Result<Vec<_>, Error<'gc>> = (0..num_octaves)
            .map(|i| {
                if let Some(offsets) = offsets
                    && let Some(offsets) = offsets.as_array_storage()
                    && let Some(Value::Object(point)) = offsets.get(i)
                    && point.is_of_type(point_class)
                {
                    let x = point
                        .get_slot(point_slots::X)
                        .coerce_to_number(activation)?;
                    let y = point
                        .get_slot(point_slots::Y)
                        .coerce_to_number(activation)?;

                    Ok((x, y))
                } else {
                    Ok((0.0, 0.0))
                }
            })
            .collect();

        operations::perlin_noise(
            activation.gc(),
            bitmap_data,
            (base_x, base_y),
            num_octaves,
            seed,
            stitch,
            fractal_noise,
            channel_options,
            grayscale,
            octave_offsets?,
        );
    }

    Ok(Value::Undefined)
}

/// Implement `BitmapData.threshold`
pub fn threshold<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(bitmap_data) = this.as_bitmap_data()
        && !bitmap_data.disposed()
    {
        let src_bitmap = args.get_object(activation, 0, "sourceBitmapData")?;
        let source_rect = args.get_object(activation, 1, "sourceRect")?;
        let dest_point = args.get_object(activation, 2, "destPoint")?;
        let dest_point = (
            dest_point
                .get_slot(point_slots::X)
                .coerce_to_i32(activation)?,
            dest_point
                .get_slot(point_slots::Y)
                .coerce_to_i32(activation)?,
        );
        let operation = args.get_string_non_null(activation, 3, "operationStr")?;
        let threshold = args.get_u32(4);
        let color = args.get_u32(5);
        let mask = args.get_u32(6);
        let copy_source = args.get_bool(7);

        let operation = if let Some(operation) = ThresholdOperation::from_wstr(&operation) {
            operation
        } else {
            // It's wrong but this is what Flash says.
            return Err(make_error_2005(activation, 0, "Operation"));
        };

        let (src_min_x, src_min_y, src_width, src_height) =
            get_rectangle_x_y_width_height(activation, source_rect)?;

        if let Some(src_bitmap) = src_bitmap.as_bitmap_data() {
            src_bitmap.check_valid(activation)?;

            return Ok(operations::threshold(
                activation.gc(),
                activation.context.renderer,
                bitmap_data,
                src_bitmap,
                (src_min_x, src_min_y, src_width, src_height),
                dest_point,
                operation,
                threshold,
                color,
                mask,
                copy_source,
            )
            .into());
        }
    }

    Ok(Value::Undefined)
}

/// Implement `BitmapData.compare`
pub fn compare<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    const EQUIVALENT: i32 = 0;
    const NOT_BITMAP: i32 = -1;
    const BITMAP_DISPOSED: i32 = -2;
    const DIFFERENT_WIDTHS: i32 = -3;
    const DIFFERENT_HEIGHTS: i32 = -4;

    let this_bitmap_data = if let Some(this_bitmap_data) = this.as_bitmap_data() {
        this_bitmap_data
    } else {
        return Ok(NOT_BITMAP.into());
    };
    this_bitmap_data.check_valid(activation)?;

    if this_bitmap_data.disposed() {
        // The documentation says that -2 should be returned here, but -1 is actually returned.
        return Ok(NOT_BITMAP.into());
    }

    let other_bitmap_data = if let Some(other_bitmap_data) = args
        .get_object(activation, 0, "otherBitmapData")?
        .as_bitmap_data()
    {
        other_bitmap_data
    } else {
        // The documentation for AVM1 says that -1 should be returned here,
        // but -2 is actually returned.
        // TODO: For AVM2, this branch should never get reached, since
        //   AVM2 checks types.
        return Ok(BITMAP_DISPOSED.into());
    };
    other_bitmap_data.check_valid(activation)?;

    // TODO: Given the above check with `other_bitmap_data.check_valid`, this branch will
    //   presumably never get executed.
    if other_bitmap_data.disposed() {
        return Ok(BITMAP_DISPOSED.into());
    }

    if this_bitmap_data.width() != other_bitmap_data.width() {
        return Ok(DIFFERENT_WIDTHS.into());
    }

    if this_bitmap_data.height() != other_bitmap_data.height() {
        return Ok(DIFFERENT_HEIGHTS.into());
    }

    match operations::compare(
        activation.context.gc_context,
        activation.context.renderer,
        this_bitmap_data,
        other_bitmap_data,
    ) {
        Some(bitmap_data) => {
            Ok(BitmapDataObject::from_bitmap_data(activation.context, bitmap_data).into())
        }
        None => Ok(EQUIVALENT.into()),
    }
}

/// Implements `BitmapData.pixelDissolve`.
pub fn pixel_dissolve<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(bitmap_data) = this.as_bitmap_data() {
        bitmap_data.check_valid(activation)?;

        let src_bitmap_data = args.get_object(activation, 0, "sourceBitmapData")?;

        let source_rect = args.get_object(activation, 1, "sourceRect")?;

        let (src_min_x, src_min_y, src_width, src_height) =
            get_rectangle_x_y_width_height(activation, source_rect)?;

        let dest_point = args.get_object(activation, 2, "destPoint")?;
        let dest_point = (
            dest_point
                .get_slot(point_slots::X)
                .coerce_to_i32(activation)?,
            dest_point
                .get_slot(point_slots::Y)
                .coerce_to_i32(activation)?,
        );

        let random_seed = args.get_i32(3);

        let num_pixels = args.get_i32(4);
        if num_pixels < 0 {
            return Err(make_error_2027(activation, "numPixels", num_pixels));
        }

        let fill_color = args.get_u32(5);

        if let Some(src_bitmap_data) = src_bitmap_data.as_bitmap_data() {
            src_bitmap_data.check_valid(activation)?;

            return Ok(operations::pixel_dissolve(
                activation.gc(),
                activation.context.renderer,
                bitmap_data,
                src_bitmap_data,
                (src_min_x, src_min_y, src_width, src_height),
                dest_point,
                random_seed,
                num_pixels,
                fill_color,
            )
            .into());
        }
    }

    Ok(Value::Undefined)
}

// Implements `BitmapData.merge`.
pub fn merge<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(bitmap_data) = this.as_bitmap_data()
        && !bitmap_data.disposed()
    {
        let src_bitmap = args.get_object(activation, 0, "sourceBitmapData")?;

        let (src_min_x, src_min_y, src_width, src_height) = {
            let source_rect = args.get_object(activation, 1, "sourceRect")?;
            get_rectangle_x_y_width_height(activation, source_rect)?
        };

        let dest_point = {
            let dest_point = args.get_object(activation, 2, "destPoint")?;

            let x = dest_point
                .get_slot(point_slots::X)
                .coerce_to_i32(activation)?;

            let y = dest_point
                .get_slot(point_slots::Y)
                .coerce_to_i32(activation)?;

            (x, y)
        };

        let red_mult = args.get_i32(3);
        let green_mult = args.get_i32(4);
        let blue_mult = args.get_i32(5);
        let alpha_mult = args.get_i32(6);

        if let Some(src_bitmap) = src_bitmap.as_bitmap_data()
            && !src_bitmap.disposed()
        {
            operations::merge(
                activation.gc(),
                activation.context.renderer,
                bitmap_data,
                src_bitmap,
                (src_min_x, src_min_y, src_width, src_height),
                dest_point,
                (red_mult, green_mult, blue_mult, alpha_mult),
            );
        }
    }

    Ok(Value::Undefined)
}

// Timffle: Flash's "no such area" rectangle, as `generateFilterRect` returns
// it for a source rectangle outside the bitmap or with a negative size
// (x = y = 2^27 - 1, width = height = 0; measured on Flash Player 32).
const FLASH_EMPTY_RECT_COORD: i64 = 0x7FF_FFFF;

/// Timffle: how many pixels a blur of `blur` with `quality` passes grows a
/// rectangle on one side, as Flash Player 32 computes it for
/// `generateFilterRect` (timffle/difftest/src/D53BlurRect.hx and
/// D54BlurRect2.hx sampled every quality): the per-quality scale is the
/// half-width of Ruffle's accumulated pass scale as a single-precision
/// constant (1.05 is a hair below 1.05, 1.35 a hair above: blur 5 at
/// quality 2 grows 5, blur 15 at quality 3 grows 21), a blur below 1 counts
/// as 1, and `floor(x + 0.75)` is the rounding (quality 0 grows nothing,
/// quality above 15 is 15).
fn flash_blur_growth(blur: f64, quality: i32) -> i64 {
    const HALF_PASS_SCALES: [f32; 15] = [
        0.5, 1.05, 1.35, 1.55, 1.75, 1.9, 2.0, 2.1, 2.2, 2.3, 2.5, 3.0, 3.0, 3.5, 3.5,
    ];
    if quality <= 0 {
        return 0;
    }
    let scale = HALF_PASS_SCALES[(quality.min(15) - 1) as usize] as f64;
    let blur = if blur.is_nan() { 1.0 } else { blur.max(1.0) };
    (scale * blur + 0.75).floor() as i64
}

/// Timffle: a rectangle in whole pixels, `x_min..x_max` exclusive.
#[derive(Clone, Copy)]
struct PixelRect {
    x_min: i64,
    y_min: i64,
    x_max: i64,
    y_max: i64,
}

impl PixelRect {
    fn grown(self, x: i64, y: i64) -> Self {
        Self {
            x_min: self.x_min - x,
            y_min: self.y_min - y,
            x_max: self.x_max + x,
            y_max: self.y_max + y,
        }
    }

    fn shifted(self, x: i64, y: i64) -> Self {
        Self {
            x_min: self.x_min + x,
            y_min: self.y_min + y,
            x_max: self.x_max + x,
            y_max: self.y_max + y,
        }
    }

    fn union(self, other: Self) -> Self {
        Self {
            x_min: self.x_min.min(other.x_min),
            y_min: self.y_min.min(other.y_min),
            x_max: self.x_max.max(other.x_max),
            y_max: self.y_max.max(other.y_max),
        }
    }
}

/// Timffle: the slot values of a filter object as `f64`, read straight from
/// the ActionScript object so that Flash's own numbers (not the fixed-point
/// SWF copies) drive the rounding.
fn filter_number<'gc>(
    activation: &mut Activation<'_, 'gc>,
    filter: Object<'gc>,
    slot: usize,
) -> Result<f64, Error<'gc>> {
    filter.get_slot(slot).coerce_to_number(activation)
}

/// Timffle: Flash's offset of a shadow/bevel: `floor(distance * cos(angle))`
/// and `floor(distance * sin(angle))` with the angle in degrees. Flash treats
/// an offset that is a whole pixel up to floating-point error as that pixel
/// (4 at 30 degrees moves down 2, 4 at 90 or 180 degrees moves 0 sideways),
/// hence the epsilon.
fn flash_filter_offset(distance: f64, angle: f64) -> (i64, i64) {
    const EPSILON: f64 = 1e-6;
    let angle = angle.to_radians();
    (
        (distance * angle.cos() + EPSILON).floor() as i64,
        (distance * angle.sin() + EPSILON).floor() as i64,
    )
}

/// Implements `BitmapData.generateFilterRectInternal` (the native part of
/// `generateFilterRect`).
///
/// Timffle: real implementation. The source rectangle is rounded to whole
/// pixels like every other `BitmapData` rectangle (round half to even on each
/// edge), clamped to the bitmap (a rectangle outside the bitmap or with a
/// negative size becomes Flash's "empty" marker rectangle), and then grown
/// per filter the way Flash Player 32 does (measured with
/// timffle/difftest/src/D51DisplayMisc.hx, D52DisplayEdge.hx, D53BlurRect.hx
/// and D54BlurRect2.hx):
/// * blur / glow: `flash_blur_growth` on each axis;
/// * drop shadow / gradient glow: the blurred rectangle moved by
///   `floor(distance * cos/sin(angle))`, united with the source rectangle;
/// * bevel / gradient bevel: the blurred rectangle moved both ways, united
///   with the source rectangle;
/// * convolution: `floor(matrixX / 2)` and `floor(matrixY / 2)`;
/// * colour matrix / displacement map: unchanged;
/// * shader: the whole bitmap, whatever the source rectangle.
pub fn generate_filter_rect_internal<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    use crate::avm2::globals::slots::{
        flash_filters_bevel_filter as bevel_slots, flash_filters_blur_filter as blur_slots,
        flash_filters_convolution_filter as convolution_slots,
        flash_filters_drop_shadow_filter as drop_shadow_slots,
        flash_filters_glow_filter as glow_slots,
        flash_filters_gradient_bevel_filter as gradient_bevel_slots,
        flash_filters_gradient_glow_filter as gradient_glow_slots,
    };

    let this = this.as_object().unwrap();
    let Some(bitmap_data) = this.as_bitmap_data() else {
        return Ok(Value::Undefined);
    };
    bitmap_data.check_valid(activation)?;
    let source_rect = args.get_object(activation, 0, "sourceRect")?;
    let filter_object = args.get_object(activation, 1, "filter")?;

    let width = bitmap_data.width() as i64;
    let height = bitmap_data.height() as i64;
    // A ShaderFilter (even one without a shader) covers the whole bitmap.
    let shader_filter = activation
        .avm2()
        .classes()
        .shaderfilter
        .inner_class_definition();
    if filter_object.is_of_type(shader_filter) {
        return new_rectangle_from_pixels(activation, 0, 0, width, height);
    }
    let filter = Filter::from_avm2_object(activation, filter_object)?;

    let (x, y, w, h) = get_rectangle_x_y_width_height(activation, source_rect)?;
    let (x, y, w, h) = (x as i64, y as i64, w as i64, h as i64);
    let (x_max, y_max) = (x + w, y + h);
    let valid = w >= 0 && h >= 0 && x < width && y < height && x_max > 0 && y_max > 0;
    let rect = if valid {
        PixelRect {
            x_min: x.max(0),
            y_min: y.max(0),
            x_max: x_max.min(width),
            y_max: y_max.min(height),
        }
    } else {
        PixelRect {
            x_min: FLASH_EMPTY_RECT_COORD,
            y_min: FLASH_EMPTY_RECT_COORD,
            x_max: FLASH_EMPTY_RECT_COORD,
            y_max: FLASH_EMPTY_RECT_COORD,
        }
    };

    let blur_growth = |activation: &mut Activation<'_, 'gc>,
                       blur_x: usize,
                       blur_y: usize,
                       quality: usize|
     -> Result<(i64, i64), Error<'gc>> {
        let blur_x = filter_number(activation, filter_object, blur_x)?;
        let blur_y = filter_number(activation, filter_object, blur_y)?;
        let quality = filter_object.get_slot(quality).coerce_to_i32(activation)?;
        Ok((
            flash_blur_growth(blur_x, quality),
            flash_blur_growth(blur_y, quality),
        ))
    };
    let offset = |activation: &mut Activation<'_, 'gc>,
                  distance: usize,
                  angle: usize|
     -> Result<(i64, i64), Error<'gc>> {
        let distance = filter_number(activation, filter_object, distance)?;
        let angle = filter_number(activation, filter_object, angle)?;
        Ok(flash_filter_offset(distance, angle))
    };

    let result = match filter {
        Filter::BlurFilter(_) => {
            let (gx, gy) = blur_growth(
                activation,
                blur_slots::BLUR_X,
                blur_slots::BLUR_Y,
                blur_slots::QUALITY,
            )?;
            rect.grown(gx, gy)
        }
        Filter::GlowFilter(_) => {
            let (gx, gy) = blur_growth(
                activation,
                glow_slots::BLUR_X,
                glow_slots::BLUR_Y,
                glow_slots::QUALITY,
            )?;
            rect.grown(gx, gy)
        }
        Filter::DropShadowFilter(_) => {
            let (gx, gy) = blur_growth(
                activation,
                drop_shadow_slots::BLUR_X,
                drop_shadow_slots::BLUR_Y,
                drop_shadow_slots::QUALITY,
            )?;
            let (dx, dy) = offset(
                activation,
                drop_shadow_slots::DISTANCE,
                drop_shadow_slots::ANGLE,
            )?;
            rect.union(rect.grown(gx, gy).shifted(dx, dy))
        }
        Filter::GradientGlowFilter(_) => {
            let (gx, gy) = blur_growth(
                activation,
                gradient_glow_slots::_BLUR_X,
                gradient_glow_slots::_BLUR_Y,
                gradient_glow_slots::_QUALITY,
            )?;
            let (dx, dy) = offset(
                activation,
                gradient_glow_slots::_DISTANCE,
                gradient_glow_slots::_ANGLE,
            )?;
            rect.union(rect.grown(gx, gy).shifted(dx, dy))
        }
        Filter::BevelFilter(_) => {
            let (gx, gy) = blur_growth(
                activation,
                bevel_slots::BLUR_X,
                bevel_slots::BLUR_Y,
                bevel_slots::QUALITY,
            )?;
            let (dx, dy) = offset(activation, bevel_slots::DISTANCE, bevel_slots::ANGLE)?;
            let blurred = rect.grown(gx, gy);
            rect.union(blurred.shifted(dx, dy))
                .union(blurred.shifted(-dx, -dy))
        }
        Filter::GradientBevelFilter(_) => {
            let (gx, gy) = blur_growth(
                activation,
                gradient_bevel_slots::_BLUR_X,
                gradient_bevel_slots::_BLUR_Y,
                gradient_bevel_slots::_QUALITY,
            )?;
            let (dx, dy) = offset(
                activation,
                gradient_bevel_slots::_DISTANCE,
                gradient_bevel_slots::_ANGLE,
            )?;
            let blurred = rect.grown(gx, gy);
            rect.union(blurred.shifted(dx, dy))
                .union(blurred.shifted(-dx, -dy))
        }
        Filter::ConvolutionFilter(_) => {
            let matrix_x = filter_number(activation, filter_object, convolution_slots::MATRIX_X)?;
            let matrix_y = filter_number(activation, filter_object, convolution_slots::MATRIX_Y)?;
            let half = |n: f64| -> i64 {
                if n.is_nan() || n <= 0.0 {
                    0
                } else {
                    (n.floor() as i64) / 2
                }
            };
            rect.grown(half(matrix_x), half(matrix_y))
        }
        Filter::ColorMatrixFilter(_) | Filter::DisplacementMapFilter(_) => rect,
        Filter::ShaderFilter(_) => unreachable!(),
    };

    new_rectangle_from_pixels(
        activation,
        result.x_min,
        result.y_min,
        result.x_max - result.x_min,
        result.y_max - result.y_min,
    )
}

/// Timffle: a new `flash.geom.Rectangle` from whole-pixel values (which may
/// exceed the twips range, unlike `new_rectangle`).
fn new_rectangle_from_pixels<'gc>(
    activation: &mut Activation<'_, 'gc>,
    x: i64,
    y: i64,
    width: i64,
    height: i64,
) -> Result<Value<'gc>, Error<'gc>> {
    let args = &[
        (x as f64).into(),
        (y as f64).into(),
        (width as f64).into(),
        (height as f64).into(),
    ];
    activation
        .avm2()
        .classes()
        .rectangle
        .construct(activation, args)
}

/// Implements `BitmapData.encodeInternal` (the native part of `encode`).
///
/// Timffle: real PNG and JPEG encoding with the `image` crate, and JPEG XR with Timffle's own
/// encoder (`bitmap_data/jpegxr_encode.rs`). Like Flash Player 32
/// (timffle/difftest/src/D51DisplayMisc.hx, D63JpegXr.hx, D64JpegXrQp.hx, D65JpegXrMap.hx): the
/// rectangle is rounded like every `BitmapData` rectangle and clamped to the bitmap, and an empty
/// or disjoint one is `ArgumentError #2006`; a disposed bitmap is `ArgumentError #2015`; PNG is
/// RGBA for a transparent bitmap and RGB otherwise (`fastCompression` picks the fast zlib level);
/// JPEG drops the alpha channel; JPEG XR checks quantization (above 100: `RangeError #2006`),
/// colorSpace (null: `TypeError #2007`, not one of the four constants: `ArgumentError #2004`) and
/// trimFlexBits (above 15: `Error #3699`) in that order, after the rectangle, and writes 24bppBGR
/// or, for a transparent bitmap, 32bppPBGRA with an alpha plane; the bytes go to the given
/// ByteArray at its current position (the same object comes back, position at the end of the
/// data) or to a new big-endian ByteArray.
pub fn encode_internal<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    use image::ImageEncoder;
    use image::codecs::jpeg::JpegEncoder;
    use image::codecs::png::{CompressionType, FilterType, PngEncoder};
    use ruffle_render::bitmap::PixelRegion;

    let this = this.as_object().unwrap();
    let Some(bitmap_data) = this.as_bitmap_data() else {
        return Ok(Value::Undefined);
    };
    bitmap_data.check_valid(activation)?;
    let rect = args.get_object(activation, 0, "rect")?;
    let kind = args.get_i32(1);
    let param = args.get_u32(2);
    let byte_array = args.try_get_object(3);

    let (x, y, w, h) = get_rectangle_x_y_width_height(activation, rect)?;
    let bitmap_width = bitmap_data.width();
    let bitmap_height = bitmap_data.height();
    let disjoint = w <= 0
        || h <= 0
        || x >= bitmap_width as i32
        || y >= bitmap_height as i32
        || x.saturating_add(w) <= 0
        || y.saturating_add(h) <= 0;
    let mut region = PixelRegion::for_region_i32(x, y, w, h);
    region.clamp(bitmap_width, bitmap_height);
    if disjoint || region.width() == 0 || region.height() == 0 {
        return Err(make_error_2006(activation, Error2006Type::ArgumentError));
    }

    let transparent = bitmap_data.transparency();
    let width = region.width();
    let height = region.height();

    if kind == 2 {
        if param > 100 {
            return Err(make_error_2006(activation, Error2006Type::RangeError));
        }
        let Some(color_space) = args.try_get_string(4) else {
            return Err(make_error_2007(activation, "colorSpace"));
        };
        // "auto" is 4:4:4 in Flash. 4:2:0 and 4:2:2 are encoded as 4:4:4 too (the encoder has
        // no chroma subsampling): valid files, bigger than Flash's, at least as good.
        if !(&color_space == b"auto"
            || &color_space == b"4:4:4"
            || &color_space == b"4:2:2"
            || &color_space == b"4:2:0")
        {
            return Err(make_error_2004(activation, Error2004Type::ArgumentError));
        }
        let trim_flex_bits = args.get_u32(5);
        if trim_flex_bits > 15 {
            return Err(make_error_3699(activation));
        }
        let mut pixels = Vec::with_capacity((width * height) as usize);
        {
            let read = bitmap_data.read_area(region, activation.context.renderer);
            for py in region.y_min..region.y_max {
                for px in region.x_min..region.x_max {
                    // Flash stores its own (premultiplied) pixel values: 32bppPBGRA.
                    let color = read.get_pixel32_raw(px, py);
                    pixels.push([color.red(), color.green(), color.blue(), color.alpha()]);
                }
            }
        }
        let encoded = jpegxr_encode::encode(
            width,
            height,
            &pixels,
            transparent,
            jpegxr_encode::quantization_to_qp_index(param),
            trim_flex_bits as u8,
        );
        return write_encoded(activation, &encoded, byte_array);
    }

    let channels = if kind == 0 && transparent { 4 } else { 3 };
    let mut encoded = Vec::new();
    let mut pixels = Vec::with_capacity((width * height) as usize * channels);
    {
        let read = bitmap_data.read_area(region, activation.context.renderer);
        for py in region.y_min..region.y_max {
            for px in region.x_min..region.x_max {
                let color = read.get_pixel32_raw(px, py).to_un_multiplied_alpha();
                pixels.push(color.red());
                pixels.push(color.green());
                pixels.push(color.blue());
                if channels == 4 {
                    pixels.push(color.alpha());
                }
            }
        }
    }

    let result = if kind == 0 {
        let compression = if param != 0 {
            CompressionType::Fast
        } else {
            CompressionType::Default
        };
        let color = if channels == 4 {
            image::ExtendedColorType::Rgba8
        } else {
            image::ExtendedColorType::Rgb8
        };
        PngEncoder::new_with_quality(&mut encoded, compression, FilterType::Adaptive)
            .write_image(&pixels, width, height, color)
    } else {
        let quality = param.clamp(1, 100) as u8;
        JpegEncoder::new_with_quality(&mut encoded, quality).write_image(
            &pixels,
            width,
            height,
            image::ExtendedColorType::Rgb8,
        )
    };
    if let Err(error) = result {
        tracing::error!("BitmapData.encode failed: {error}");
        return Err(make_error_2004(activation, Error2004Type::ArgumentError));
    }
    write_encoded(activation, &encoded, byte_array)
}

/// Timffle: the end of `encodeInternal`: the bytes at the given ByteArray's position, or a new
/// ByteArray.
fn write_encoded<'gc>(
    activation: &mut Activation<'_, 'gc>,
    encoded: &[u8],
    byte_array: Option<Object<'gc>>,
) -> Result<Value<'gc>, Error<'gc>> {
    if let Some(byte_array) = byte_array {
        if let Some(mut storage) = byte_array.as_bytearray_mut() {
            storage
                .write_bytes(encoded)
                .map_err(|e| e.to_avm(activation))?;
            return Ok(byte_array.into());
        }
        return Err(make_error_2004(activation, Error2004Type::TypeError));
    }
    let mut storage = ByteArrayStorage::new(activation.context);
    storage
        .write_bytes(encoded)
        .map_err(|e| e.to_avm(activation))?;
    Ok(ByteArrayObject::from_storage(activation.context, storage).into())
}
