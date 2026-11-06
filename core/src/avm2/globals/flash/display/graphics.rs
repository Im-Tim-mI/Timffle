//! `flash.display.Graphics` builtin/prototype

use crate::avm2::activation::Activation;
use crate::avm2::error::{
    Error2004Type, make_error_2004, make_error_2007, make_error_2008, make_error_2171,
};
use crate::avm2::function::FunctionArgs;
use crate::avm2::globals::flash::display::shader_job::get_shader_args;
use crate::avm2::globals::flash::geom::transform::object_to_matrix;
use crate::avm2::globals::slots::flash_display_graphics_bitmap_fill as graphics_bitmap_fill_slots;
use crate::avm2::globals::slots::flash_display_graphics_gradient_fill as graphics_gradient_fill_slots;
use crate::avm2::globals::slots::flash_display_graphics_path as graphics_path_slots;
use crate::avm2::globals::slots::flash_display_graphics_shader_fill as graphics_shader_fill_slots;
use crate::avm2::globals::slots::flash_display_graphics_solid_fill as graphics_solid_fill_slots;
use crate::avm2::globals::slots::flash_display_graphics_stroke as graphics_stroke_slots;
use crate::avm2::globals::slots::flash_display_graphics_triangle_path as graphics_triangle_path_slots;
use crate::avm2::globals::slots::flash_display_shader as shader_slots;
use crate::avm2::object::{ArrayObject, Object, TObject as _, VectorObject};
use crate::avm2::parameters::ParametersExt;
use crate::avm2::value::Value;
use crate::avm2::vector::VectorStorage;
use crate::avm2::{ArrayStorage, Error};
use crate::display_object::{DisplayObject, TDisplayObject, TDisplayObjectContainer};
use crate::drawing::{Drawing, GraphicsReadItem, ObjectRoot};
use crate::string::{AvmString, WStr};
use either::Either;
use gc_arena::Gc;
use ruffle_render::matrix::Matrix as RenderMatrix;
use ruffle_render::shape_utils::{DrawCommand, FillRule, GradientType};
use std::f64::consts::FRAC_1_SQRT_2;
use swf::{
    Color, FillStyle, Fixed8, Gradient, GradientInterpolation, GradientRecord, GradientSpread,
    LineCapStyle, LineJoinStyle, LineStyle, Matrix, Point, Twips,
};

/// Convert an RGB `color` and `alpha` argument pair into a `swf::Color`.
/// `alpha` is normalized from 0.0 - 1.0.
fn color_from_args(rgb: u32, alpha: f64) -> Color {
    Color::from_rgb(rgb, (alpha * 255.0) as u8)
}

/// Implements `Graphics.beginFill`.
pub fn begin_fill<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(this) = this.as_display_object() {
        let color = args.get_u32(0);
        let alpha = args.get_f64(1);

        if let Some(mut draw) = this.as_drawing() {
            draw.set_fill_style(Some(FillStyle::Color(color_from_args(color, alpha))));
        }
    }

    Ok(Value::Undefined)
}

/// Implements `Graphics.beginBitmapFill`.
pub fn begin_bitmap_fill<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(this) = this.as_display_object() {
        let bitmap_object = args.get_object(activation, 0, "bitmap")?;
        let bitmap = bitmap_object
            .as_bitmap_data()
            .expect("Bitmap argument is ensured to be a BitmapData from actionscript");
        let matrix = if let Some(matrix) = args.try_get_object(1) {
            Matrix::from(object_to_matrix(matrix))
        } else {
            // Users can explicitly pass in `null` to mean identity matrix
            Matrix::IDENTITY
        };
        let is_repeating = args.get_bool(2);
        let is_smoothed = args.get_bool(3);

        let handle = bitmap.bitmap_handle(activation.gc(), activation.context.renderer);

        let bitmap = ruffle_render::bitmap::BitmapInfo {
            handle,
            width: bitmap.width(),
            height: bitmap.height(),
        };
        let scale_matrix = Matrix::scale(
            (Twips::TWIPS_PER_PIXEL as i16).into(),
            (Twips::TWIPS_PER_PIXEL as i16).into(),
        );

        if let Some(mut draw) = this.as_drawing() {
            let id = draw.add_bitmap(bitmap);
            // Timffle: readGraphicsData returns the same BitmapData object.
            draw.set_bitmap_object(id, stash_object(activation, bitmap_object));
            draw.set_fill_style(Some(FillStyle::Bitmap {
                id,
                matrix: matrix * scale_matrix,
                is_smoothed,
                is_repeating,
            }));
        }
    }

    Ok(Value::Undefined)
}

/// Implements `Graphics.beginGradientFill`.
pub fn begin_gradient_fill<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(this) = this.as_display_object() {
        let gradient_type = args.get_string(activation, 0);
        let gradient_type = parse_gradient_type(activation, gradient_type)?;
        let colors = args.get_object(activation, 1, "colors")?;
        let alphas = args.try_get_object(2);
        let ratios = args.try_get_object(3);

        let records = build_gradient_records(
            activation,
            &colors.as_array_storage().expect("Guaranteed by AS"),
            alphas,
            ratios,
        )?;

        let matrix = if let Some(matrix) = args.try_get_object(4) {
            Matrix::from(object_to_matrix(matrix))
        } else {
            // Users can explicitly pass in `null` to mean identity matrix
            Matrix::IDENTITY
        };
        let spread = args.get_string(activation, 5);
        let spread = parse_spread_method(spread);
        let interpolation = args.get_string(activation, 6);
        let interpolation = parse_interpolation_method(interpolation);
        let focal_point = args.get_f64(7);

        if let Some(mut draw) = this.as_drawing() {
            match gradient_type {
                GradientType::Linear => {
                    draw.set_fill_style(Some(FillStyle::LinearGradient(Gradient {
                        matrix,
                        spread,
                        interpolation,
                        records,
                    })))
                }
                GradientType::Radial if focal_point == 0.0 => {
                    draw.set_fill_style(Some(FillStyle::RadialGradient(Gradient {
                        matrix,
                        spread,
                        interpolation,
                        records,
                    })))
                }
                _ => draw.set_fill_style(Some(FillStyle::FocalGradient {
                    gradient: Gradient {
                        matrix,
                        spread,
                        interpolation,
                        records,
                    },
                    focal_point: Fixed8::from_f64(focal_point),
                })),
            }
        }
    }
    Ok(Value::Undefined)
}

fn build_gradient_records<'gc>(
    activation: &mut Activation<'_, 'gc>,
    colors: &ArrayStorage<'gc>,
    alphas: Option<Object<'gc>>,
    ratios: Option<Object<'gc>>,
) -> Result<Vec<GradientRecord>, Error<'gc>> {
    let alphas = alphas.as_ref().map(|o| o.as_array_storage().unwrap());
    let ratios = ratios.as_ref().map(|o| o.as_array_storage().unwrap());

    let mut length = colors.length();
    if let Some(ref alphas) = alphas {
        length = length.min(alphas.length());
    }
    if let Some(ref ratios) = ratios {
        length = length.min(ratios.length());
    }

    let mut records = Vec::with_capacity(length);
    for i in 0..length {
        let color = colors
            .get(i)
            .expect("Length should be guaranteed")
            .coerce_to_u32(activation)?;

        let alpha = if let Some(ref alphas) = alphas {
            alphas
                .get(i)
                .expect("Length should be guaranteed")
                .coerce_to_number(activation)? as f32
        } else {
            1.0
        };

        let ratio = if let Some(ref ratios) = ratios {
            let ratio = ratios
                .get(i)
                .expect("Length should be guaranteed")
                .coerce_to_u32(activation)?;
            ratio.clamp(0, 255) as u8
        } else {
            // For example, with length=3: 0/2, 1/2, 2/2.
            ((i * 255) / (length - 1)) as u8
        };

        records.push(GradientRecord {
            ratio,
            color: Color::from_rgb(color, (alpha * 255.0) as u8),
        })
    }
    Ok(records)
}

fn parse_gradient_type<'gc>(
    activation: &mut Activation<'_, 'gc>,
    gradient_type: AvmString<'gc>,
) -> Result<GradientType, Error<'gc>> {
    if &gradient_type == b"linear" {
        Ok(GradientType::Linear)
    } else if &gradient_type == b"radial" {
        Ok(GradientType::Radial)
    } else {
        Err(make_error_2008(activation, "type"))
    }
}

fn parse_interpolation_method(gradient_type: AvmString) -> GradientInterpolation {
    if &gradient_type == b"linearRGB" {
        GradientInterpolation::LinearRgb
    } else {
        GradientInterpolation::Rgb
    }
}

fn parse_spread_method(spread_method: AvmString) -> GradientSpread {
    if &spread_method == b"repeat" {
        GradientSpread::Repeat
    } else if &spread_method == b"reflect" {
        GradientSpread::Reflect
    } else {
        GradientSpread::Pad
    }
}

/// Implements `Graphics.clear`
pub fn clear<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(this) = this.as_display_object()
        && let Some(mut draw) = this.as_drawing()
    {
        draw.clear()
    }

    Ok(Value::Undefined)
}

/// Implements `Graphics.curveTo`.
pub fn curve_to<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(this) = this.as_display_object() {
        let control_x = args.get_f64(0);
        let control_y = args.get_f64(1);
        let anchor_x = args.get_f64(2);
        let anchor_y = args.get_f64(3);

        if let Some(mut draw) = this.as_drawing() {
            draw.draw_command(DrawCommand::QuadraticCurveTo {
                control: Point::from_pixels(control_x, control_y),
                anchor: Point::from_pixels(anchor_x, anchor_y),
            });
        }
    }

    Ok(Value::Undefined)
}

/// Implements `Graphics.endFill`.
pub fn end_fill<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(this) = this.as_display_object()
        && let Some(mut draw) = this.as_drawing()
    {
        draw.set_fill_style(None);
    }

    Ok(Value::Undefined)
}

fn caps_to_cap_style(caps: Option<AvmString>) -> LineCapStyle {
    if let Some(caps) = caps {
        if &caps == b"none" {
            LineCapStyle::None
        } else if &caps == b"square" {
            LineCapStyle::Square
        } else {
            LineCapStyle::Round
        }
    } else {
        LineCapStyle::Round
    }
}

fn joints_to_join_style(joints: Option<AvmString>, miter_limit: f64) -> LineJoinStyle {
    if let Some(joints) = joints {
        if &joints == b"miter" {
            LineJoinStyle::Miter(Fixed8::from_f64(miter_limit))
        } else if &joints == b"bevel" {
            LineJoinStyle::Bevel
        } else {
            LineJoinStyle::Round
        }
    } else {
        LineJoinStyle::Round
    }
}

fn scale_mode_to_allow_scale_bits<'gc>(scale_mode: &WStr) -> Result<(bool, bool), Error<'gc>> {
    if scale_mode == b"none" {
        Ok((false, false))
    } else if scale_mode == b"horizontal" {
        Ok((true, false))
    } else if scale_mode == b"vertical" {
        Ok((false, true))
    } else {
        Ok((true, true))
    }
}

/// Implements `Graphics.lineStyle`.
pub fn line_style<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(this) = this.as_display_object() {
        let thickness = args.get_f64(0);

        if thickness.is_nan() {
            if let Some(mut draw) = this.as_drawing() {
                draw.set_line_style(None);
            }
        } else {
            let color = args.get_u32(1);
            let alpha = args.get_f64(2);
            let is_pixel_hinted = args.get_bool(3);
            let scale_mode = args.get_string(activation, 4);
            let caps = caps_to_cap_style(args.try_get_string(5));
            let joints = args.try_get_string(6);
            let miter_limit = args.get_f64(7);

            let width = Twips::from_pixels(thickness.clamp(0.0, 255.0));
            let color = color_from_args(color, alpha);
            let join_style = joints_to_join_style(joints, miter_limit);
            let (allow_scale_x, allow_scale_y) = scale_mode_to_allow_scale_bits(&scale_mode)?;

            let line_style = LineStyle::new()
                .with_width(width)
                .with_color(color)
                .with_start_cap(caps)
                .with_end_cap(caps)
                .with_join_style(join_style)
                .with_allow_scale_x(allow_scale_x)
                .with_allow_scale_y(allow_scale_y)
                .with_is_pixel_hinted(is_pixel_hinted)
                .with_allow_close(false);

            if let Some(mut draw) = this.as_drawing() {
                draw.set_line_style(Some(line_style));
            }
        }
    }

    Ok(Value::Undefined)
}

/// Implements `Graphics.lineTo`.
pub fn line_to<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(this) = this.as_display_object() {
        let x = Twips::from_pixels(args.get_f64(0));
        let y = Twips::from_pixels(args.get_f64(1));

        if let Some(mut draw) = this.as_drawing() {
            draw.draw_command(DrawCommand::LineTo(Point::new(x, y)));
        }
    }

    Ok(Value::Undefined)
}

/// Implements `Graphics.moveTo`.
pub fn move_to<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(this) = this.as_display_object() {
        let x = Twips::from_pixels(args.get_f64(0));
        let y = Twips::from_pixels(args.get_f64(1));

        if let Some(mut draw) = this.as_drawing() {
            draw.draw_command(DrawCommand::MoveTo(Point::new(x, y)));
        }
    }

    Ok(Value::Undefined)
}

/// Implements `Graphics.drawRect`.
pub fn draw_rect<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(this) = this.as_display_object() {
        let x = Twips::from_pixels(args.get_f64(0));
        let y = Twips::from_pixels(args.get_f64(1));
        let width = Twips::from_pixels(args.get_f64(2));
        let height = Twips::from_pixels(args.get_f64(3));

        if let Some(mut draw) = this.as_drawing() {
            draw.draw_command(DrawCommand::MoveTo(Point::new(x, y)));
            draw.draw_command(DrawCommand::LineTo(Point::new(x + width, y)));
            draw.draw_command(DrawCommand::LineTo(Point::new(x + width, y + height)));
            draw.draw_command(DrawCommand::LineTo(Point::new(x, y + height)));
            draw.draw_command(DrawCommand::LineTo(Point::new(x, y)));
        }
    }

    Ok(Value::Undefined)
}

// /// Length between two points on a unit circle that are 45 degrees apart from
// /// one another.
// ///
// /// This constant is `H`, short for 'hypotenuse', because it is also the length
// /// of the hypotenuse formed from the control point triangle of any quadratic
// /// Bezier curve approximating a 45-degree unit circle arc.
// ///
// /// The derivation of this constant - or a similar constant for any other arc
// /// angle hypotenuse - is as follows:
// ///
// /// 1. Call the arc angle `alpha`. In this special case, `alpha` is 45 degrees,
// ///    or one-quarter `PI`.
// /// 2. Consider the triangle formed by the center of the circle and the two
// ///    points at the start and end of the arc. The two other angles will be
// ///    equal, and it and `alpha` sum to 180 degrees. We'll call this angle
// ///    `beta`, and it is equal to `alpha` minus 180 degrees, divided by 2.
// /// 3. Using the law of sines, we know that the sine of `alpha` divided by `H`
// ///    is equal to the sine of `beta` divided by `r`, where `r` is the radius
// ///    of the circle. We can solve for `H` to get the result. Note that since
// ///    this is a unit circle, you won't see a radius term in this constant.
// const H:f64 = (PI * 0.25).sin() / (PI * 0.375).sin();

// /// Length between two control points of a quadratic Bezier curve approximating
// /// a 45-degree arc of a unit circle.
// ///
// /// This constant is critical to calculating the off-curve point of the control
// /// point triangle. We do so by taking the tangents at each on-curve point,
// /// which point in the direction of the off-curve points. Then, we scale one of
// /// those tangent vectors by `A_B` and add it to the on-curve point to get the
// /// off-curve point, constructing our Bezier.
// ///
// /// The derivation of this constant - or a similar constant for any other arc
// /// angle Bezier - is as follows:
// ///
// /// 1. Start with the value of `H` for the given arc angle `alpha`.
// /// 2. Consider the triangle formed by the three control points of our desired
// ///    Bezier curve. We'll call the angle at the off-curve control point
// ///    `delta`, and the two other angles of this triangle are `gamma`.
// /// 3. Because two of the lines of this triangle are tangent lines of the
// ///    circle, they will form a right angle with the normal, which is the same
// ///    as the line between the center of the circle and the point.
// ///    Coincidentally, this right angle is shared between `beta`, meaning that
// ///    we can subtract it from 90 degrees to obtain `gamma`. Or, after some
// ///    elementary algebra, just take half of `alpha`.
// /// 4. We can then derive the value of `delta` by subtracting out the other two
// ///    `gamma`s from 180 degrees. This, again, can be simplified to just
// ///    180 degrees minus `alpha`.
// /// 5. By the law of sines, the sine of `delta` divided by `H` is equal to
// ///    the sine of `gamma` divided by `A_B`. We can then rearrange this to get
// ///    `H` times the sine of `gamma`, divided by the sine of `delta`; which is
// ///    our `A_B` constant.
// const A_B:f64 = H * (PI * 0.125).sin() / (PI * 0.75).sin();

/// A list of five quadratic Bezier control points, intended to approximate the
/// bottom-right quadrant of a unit circle.
///
/// Through coordinate reflections we can obtain the rest of the circle; and
/// with translations and scaling we can obtain any ellipse on the plane.
///
/// Points are stored in counter-clockwise order from 0 degrees to 90 degrees.
const UNIT_CIRCLE_POINTS: [(f64, f64); 5] = [
    (1.0, 0.0),
    (1.0, 0.41421356237309503),
    (FRAC_1_SQRT_2, FRAC_1_SQRT_2),
    (0.4142135623730951, 1.0),
    (0.00000000000000006123233995736766, 1.0),
    // TODO: should the above be just 0.0, instead of whatever Rust printed out?
    // Same with 0.414... not being symmetric
];

/* [
    ((PI * 0.0).cos(), (PI * 0.0).sin()),
    ((PI * 0.0).cos() + *A_B * (PI * 0.0).sin() * -1.0,
    (PI * 0.0).sin() + *A_B * (PI * 0.0).cos()),
    ((PI * 0.25).cos(), (PI * 0.25).sin()),
    ((PI * 0.25).cos() + *A_B * (PI * 0.25).sin() * -1.0,
    (PI * 0.25).sin() + *A_B * (PI * 0.25).cos()),
    ((PI * 0.5).cos(), (PI * 0.5).sin()),
]; */

/// Draw a roundrect.
#[expect(clippy::too_many_arguments)]
fn draw_round_rect_internal(
    draw: &mut Drawing,
    x: f64,
    y: f64,
    width: f64,
    height: f64,
    top_left_width: f64,
    top_left_height: f64,
    top_right_width: f64,
    top_right_height: f64,
    bottom_left_width: f64,
    bottom_left_height: f64,
    bottom_right_width: f64,
    bottom_right_height: f64,
) {
    let top_left_width = top_left_width.min(width / 2.0);
    let top_left_height = top_left_height.min(height / 2.0);
    let top_right_width = top_right_width.min(width / 2.0);
    let top_right_height = top_right_height.min(height / 2.0);
    let bottom_left_width = bottom_left_width.min(width / 2.0);
    let bottom_left_height = bottom_left_height.min(height / 2.0);
    let bottom_right_width = bottom_right_width.min(width / 2.0);
    let bottom_right_height = bottom_right_height.min(height / 2.0);

    let ucp = UNIT_CIRCLE_POINTS;

    let br_ellipse_center_x = x + width - bottom_right_width;
    let br_ellipse_center_y = y + height - bottom_right_height;

    let bl_ellipse_center_x = x + bottom_left_width;
    let bl_ellipse_center_y = y + height - bottom_left_height;

    let tl_ellipse_center_x = x + top_left_width;
    let tl_ellipse_center_y = y + top_left_height;

    let tr_ellipse_center_x = x + width - top_right_width;
    let tr_ellipse_center_y = y + top_right_height;

    // Timffle: Flash Player starts at (x+w, y+h-ry) on the right edge and goes
    // clockwise with two quadratic curves per corner (measured by readGraphicsData on
    // Flash 32, D56Graphics2 s8/s9); straight edges of zero length still get a LineTo.
    let point = |cx: f64, cy: f64, rx: f64, ry: f64, (ux, uy): (f64, f64)| {
        Point::from_pixels(cx + rx * ux, cy + ry * uy)
    };
    let (brx, bry, brw, brh) = (
        br_ellipse_center_x,
        br_ellipse_center_y,
        bottom_right_width,
        bottom_right_height,
    );
    let (blx, bly, blw, blh) = (
        bl_ellipse_center_x,
        bl_ellipse_center_y,
        bottom_left_width,
        bottom_left_height,
    );
    let (tlx, tly, tlw, tlh) = (
        tl_ellipse_center_x,
        tl_ellipse_center_y,
        top_left_width,
        top_left_height,
    );
    let (trx, try_, trw, trh) = (
        tr_ellipse_center_x,
        tr_ellipse_center_y,
        top_right_width,
        top_right_height,
    );

    let bottom_r_point = point(brx, bry, brw, brh, ucp[0]);
    draw.draw_command(DrawCommand::MoveTo(bottom_r_point));

    // Bottom-right corner.
    draw.draw_command(DrawCommand::QuadraticCurveTo {
        control: point(brx, bry, brw, brh, ucp[1]),
        anchor: point(brx, bry, brw, brh, ucp[2]),
    });
    draw.draw_command(DrawCommand::QuadraticCurveTo {
        control: point(brx, bry, brw, brh, ucp[3]),
        anchor: point(brx, bry, brw, brh, ucp[4]),
    });

    // Bottom line.
    draw.draw_command(DrawCommand::LineTo(point(blx, bly, -blw, blh, ucp[4])));

    // Bottom-left corner.
    draw.draw_command(DrawCommand::QuadraticCurveTo {
        control: point(blx, bly, -blw, blh, ucp[3]),
        anchor: point(blx, bly, -blw, blh, ucp[2]),
    });
    draw.draw_command(DrawCommand::QuadraticCurveTo {
        control: point(blx, bly, -blw, blh, ucp[1]),
        anchor: point(blx, bly, -blw, blh, ucp[0]),
    });

    // Left side.
    draw.draw_command(DrawCommand::LineTo(point(tlx, tly, -tlw, -tlh, ucp[0])));

    // Top-left corner.
    draw.draw_command(DrawCommand::QuadraticCurveTo {
        control: point(tlx, tly, -tlw, -tlh, ucp[1]),
        anchor: point(tlx, tly, -tlw, -tlh, ucp[2]),
    });
    draw.draw_command(DrawCommand::QuadraticCurveTo {
        control: point(tlx, tly, -tlw, -tlh, ucp[3]),
        anchor: point(tlx, tly, -tlw, -tlh, ucp[4]),
    });

    // Top side.
    draw.draw_command(DrawCommand::LineTo(point(trx, try_, trw, -trh, ucp[4])));

    // Top-right corner.
    draw.draw_command(DrawCommand::QuadraticCurveTo {
        control: point(trx, try_, trw, -trh, ucp[3]),
        anchor: point(trx, try_, trw, -trh, ucp[2]),
    });
    draw.draw_command(DrawCommand::QuadraticCurveTo {
        control: point(trx, try_, trw, -trh, ucp[1]),
        anchor: point(trx, try_, trw, -trh, ucp[0]),
    });

    // Right side, back to the start.
    draw.draw_command(DrawCommand::LineTo(bottom_r_point));
}

/// Implements `Graphics.drawRoundRect`.
pub fn draw_round_rect<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(this) = this.as_display_object() {
        let x = args.get_f64(0);
        let y = args.get_f64(1);
        let width = args.get_f64(2);
        let height = args.get_f64(3);
        let ellipse_width = args.get_f64(4);
        let mut ellipse_height = args.get_f64(5);

        if ellipse_height.is_nan() {
            ellipse_height = ellipse_width;
        }

        if let Some(mut draw) = this.as_drawing() {
            draw_round_rect_internal(
                &mut draw,
                x,
                y,
                width,
                height,
                ellipse_width / 2.0,
                ellipse_height / 2.0,
                ellipse_width / 2.0,
                ellipse_height / 2.0,
                ellipse_width / 2.0,
                ellipse_height / 2.0,
                ellipse_width / 2.0,
                ellipse_height / 2.0,
            );
        }
    }

    Ok(Value::Undefined)
}

/// Implements `Graphics.drawRoundRectComplex`
pub fn draw_round_rect_complex<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(this) = this.as_display_object() {
        let x = args.get_f64(0);
        let y = args.get_f64(1);
        let width = args.get_f64(2);
        let height = args.get_f64(3);
        let top_left = args.get_f64(4);
        let top_right = args.get_f64(5);
        let bottom_left = args.get_f64(6);
        let bottom_right = args.get_f64(7);

        if let Some(mut draw) = this.as_drawing() {
            draw_round_rect_internal(
                &mut draw,
                x,
                y,
                width,
                height,
                top_left,
                top_left,
                top_right,
                top_right,
                bottom_left,
                bottom_left,
                bottom_right,
                bottom_right,
            );
        }
    }

    Ok(Value::Undefined)
}

/// Implements `Graphics.drawCircle`.
pub fn draw_circle<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(this) = this.as_display_object() {
        let x = args.get_f64(0);
        let y = args.get_f64(1);
        let radius = args.get_f64(2);

        if let Some(mut draw) = this.as_drawing() {
            draw_round_rect_internal(
                &mut draw,
                x - radius,
                y - radius,
                radius * 2.0,
                radius * 2.0,
                radius,
                radius,
                radius,
                radius,
                radius,
                radius,
                radius,
                radius,
            );
        }
    }

    Ok(Value::Undefined)
}

/// Implements `Graphics.drawEllipse`.
pub fn draw_ellipse<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(this) = this.as_display_object() {
        let x = args.get_f64(0);
        let y = args.get_f64(1);
        let width = args.get_f64(2);
        let height = args.get_f64(3);

        if let Some(mut draw) = this.as_drawing() {
            draw_round_rect_internal(
                &mut draw,
                x,
                y,
                width,
                height,
                width / 2.0,
                height / 2.0,
                width / 2.0,
                height / 2.0,
                width / 2.0,
                height / 2.0,
                width / 2.0,
                height / 2.0,
            )
        }
    }

    Ok(Value::Undefined)
}

/// Implements `Graphics.lineGradientStyle`
pub fn line_gradient_style<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(this) = this.as_display_object() {
        let gradient_type = args.get_string(activation, 0);
        let gradient_type = parse_gradient_type(activation, gradient_type)?;
        let colors = args.get_object(activation, 1, "colors")?;
        let alphas = args.try_get_object(2);
        let ratios = args.try_get_object(3);

        let records = build_gradient_records(
            activation,
            &colors.as_array_storage().expect("Guaranteed by AS"),
            alphas,
            ratios,
        )?;
        let matrix = if let Some(matrix) = args.try_get_object(4) {
            Matrix::from(object_to_matrix(matrix))
        } else {
            // Users can explicitly pass in `null` to mean identity matrix
            Matrix::IDENTITY
        };
        let spread = args.get_string(activation, 5);
        let spread = parse_spread_method(spread);
        let interpolation = args.get_string(activation, 6);
        let interpolation = parse_interpolation_method(interpolation);
        let focal_point = args.get_f64(7);

        if let Some(mut draw) = this.as_drawing() {
            match gradient_type {
                GradientType::Linear => {
                    draw.set_line_fill_style(FillStyle::LinearGradient(Gradient {
                        matrix,
                        spread,
                        interpolation,
                        records,
                    }))
                }
                GradientType::Radial if focal_point == 0.0 => {
                    draw.set_line_fill_style(FillStyle::RadialGradient(Gradient {
                        matrix,
                        spread,
                        interpolation,
                        records,
                    }))
                }
                _ => draw.set_line_fill_style(FillStyle::FocalGradient {
                    gradient: Gradient {
                        matrix,
                        spread,
                        interpolation,
                        records,
                    },
                    focal_point: Fixed8::from_f64(focal_point),
                }),
            }
        }
    }
    Ok(Value::Undefined)
}

/// Implements `Graphics.cubicCurveTo`
pub fn cubic_curve_to<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(this) = this.as_display_object() {
        let control_a_x = args.get_f64(0);
        let control_a_y = args.get_f64(1);
        let control_b_x = args.get_f64(2);
        let control_b_y = args.get_f64(3);
        let anchor_x = args.get_f64(4);
        let anchor_y = args.get_f64(5);

        if let Some(mut draw) = this.as_drawing() {
            draw.draw_command(DrawCommand::CubicCurveTo {
                control_a: Point::from_pixels(control_a_x, control_a_y),
                control_b: Point::from_pixels(control_b_x, control_b_y),
                anchor: Point::from_pixels(anchor_x, anchor_y),
            });
        }
    }

    Ok(Value::Undefined)
}

/// Implements `Graphics.copyFrom`
pub fn copy_from<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(this) = this.as_display_object() {
        let source = args
            .get_object(activation, 0, "sourceGraphics")?
            .as_display_object()
            .expect("Bad sourceGraphics");

        let source = source
            .as_drawing()
            .expect("Missing drawing for sourceGraphics");

        let mut target_drawing = this.as_drawing().expect("Missing drawing for target");

        target_drawing.clone_from(&source);
    }
    Ok(Value::Undefined)
}

/// Implements `Graphics.drawPath`
pub fn draw_path<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    let this = this.as_display_object().unwrap();
    let mut drawing = this.as_drawing().unwrap();
    let commands = args.get_object(activation, 0, "commands")?;
    let data = args.get_object(activation, 1, "data")?;
    let fill_rule = args
        .get_string(activation, 2)
        .parse()
        .map_err(|_| make_error_2008(activation, "winding"))?;

    // Timffle: the fill behaviour described in the Flash docs (own fill group per
    // winding rule, strokes never implicitly closed) is implemented by `process_commands`
    // on top of `Drawing::begin_path_group`/`begin_path_stroke`.

    let commands = commands
        .as_vector_storage()
        .expect("commands is not a Vector");
    let data = data.as_vector_storage().expect("data is not a Vector");

    process_commands(activation, &mut drawing, &commands, &data, fill_rule)?;

    Ok(Value::Undefined)
}

/// Implements `Graphics.drawTriangles`
pub fn draw_triangles<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(this) = this.as_display_object()
        && let Some(mut drawing) = this.as_drawing()
    {
        let vertices = args.get_object(activation, 0, "vertices")?;

        let indices = args.try_get_object(1);

        let uvt_data = args.try_get_object(2);

        let culling = {
            let culling = args.get_string(activation, 3);
            TriangleCulling::from_string(culling)
                .ok_or_else(|| make_error_2004(activation, Error2004Type::ArgumentError))?
        };

        draw_triangles_internal(
            activation,
            &mut drawing,
            &vertices,
            indices.as_ref(),
            uvt_data.as_ref(),
            culling,
        )?;
    }

    Ok(Value::Undefined)
}

/// Like [`slice::as_chunks`], but returns `None` if the slice length
/// is not a multiple of `N`.
trait AsChunksExact<T> {
    fn as_chunks_exact<const N: usize>(&self) -> Option<&[[T; N]]>;
}

impl<T> AsChunksExact<T> for [T] {
    fn as_chunks_exact<const N: usize>(&self) -> Option<&[[T; N]]> {
        let (chunks, remainder) = self.as_chunks::<N>();

        remainder.is_empty().then_some(chunks)
    }
}

/// Parsed and validated triangle geometry for `Graphics.drawTriangles`.
///
/// # Invariants
///
/// * `vertices`, `indices`, and `triangles` are non-empty.
/// * Every value in `indices` is `< vertices.len()`. Flash stops at the first
///   out-of-bounds index, so any trailing triples that would have been out of
///   bounds are dropped at construction time.
enum TriangleData {
    /// Triangles described by shared `vertices` and triples of indices into
    /// that array.
    Indexed {
        vertices: Box<[Point<Twips>]>,
        indices: Box<[[u32; 3]]>,
    },
    /// Triangles described as independent vertex triples.
    Sequential { triangles: Box<[[Point<Twips>; 3]]> },
}

impl TriangleData {
    /// Parses raw `Graphics.drawTriangles` arguments into a validated
    /// [`TriangleData`].
    ///
    /// Returns `Ok(None)` for inputs that produce no triangles (empty
    /// vertices, empty indices, or all indices out of bounds).
    fn new<'gc>(
        activation: &mut Activation<'_, 'gc>,
        vertices: &Object<'gc>,
        indices: Option<&Object<'gc>>,
    ) -> Result<Option<Self>, Error<'gc>> {
        let vertex_storage = vertices
            .as_vector_storage()
            .expect("vertices is not a Vector");

        let vertex_pairs = vertex_storage
            .storage()
            .as_chunks_exact::<2>()
            .ok_or_else(|| make_error_2004(activation, Error2004Type::ArgumentError))?;

        if vertex_pairs.is_empty() {
            return Ok(None);
        }

        if let Some(indices) = indices {
            let indices_storage = indices
                .as_vector_storage()
                .expect("indices is not a Vector");

            let index_triples = indices_storage
                .storage()
                .as_chunks_exact::<3>()
                .ok_or_else(|| make_error_2004(activation, Error2004Type::ArgumentError))?;

            if index_triples.is_empty() {
                return Ok(None);
            }

            let vertices = vertex_pairs
                .iter()
                .map(|pair| make_point(pair))
                .collect::<Box<_>>();

            let num_vertices = vertices.len();

            // `Vector.<int>` elements are always `Value::Integer`
            let indices: Box<_> = index_triples
                .iter()
                .map(|[i0, i1, i2]| [i0.as_u32(), i1.as_u32(), i2.as_u32()])
                // Flash stops at the first out-of-bounds index.
                .take_while(|tri| tri.iter().all(|&i| (i as usize) < num_vertices))
                .collect();

            if indices.is_empty() {
                return Ok(None);
            }

            Ok(Some(Self::Indexed { vertices, indices }))
        } else {
            let vertex_triples = vertex_pairs
                .as_chunks_exact::<3>()
                .ok_or_else(|| make_error_2004(activation, Error2004Type::ArgumentError))?;

            let triangles = vertex_triples
                .iter()
                .map(|[p0, p1, p2]| [make_point(p0), make_point(p1), make_point(p2)])
                .collect::<Box<_>>();

            Ok(Some(Self::Sequential { triangles }))
        }
    }

    fn iter_triangles(&self) -> impl Iterator<Item = [Point<Twips>; 3]> + '_ {
        match self {
            Self::Indexed { vertices, indices } => {
                Either::Left(indices.iter().map(|&[i0, i1, i2]| {
                    [
                        vertices[i0 as usize],
                        vertices[i1 as usize],
                        vertices[i2 as usize],
                    ]
                }))
            }
            Self::Sequential { triangles } => Either::Right(triangles.iter().copied()),
        }
    }

    // Timffle: the vertex indices (into the `vertices` vector) of every triangle, in the
    // same order as `iter_triangles`; used to look up UVT data.
    fn iter_vertex_indices(&self) -> impl Iterator<Item = [usize; 3]> + '_ {
        match self {
            Self::Indexed { indices, .. } => Either::Left(
                indices
                    .iter()
                    .map(|&[i0, i1, i2]| [i0 as usize, i1 as usize, i2 as usize]),
            ),
            Self::Sequential { triangles } => {
                Either::Right((0..triangles.len()).map(|i| [i * 3, i * 3 + 1, i * 3 + 2]))
            }
        }
    }
}

fn make_point<'gc>([x, y]: &[Value<'gc>; 2]) -> Point<Twips> {
    let x = Twips::from_pixels(x.as_f64());
    let y = Twips::from_pixels(y.as_f64());

    Point::new(x, y)
}

#[derive(Debug, Clone, Copy)]
enum TriangleCulling {
    None,
    Positive,
    Negative,
}

impl TriangleCulling {
    fn from_string(value: AvmString) -> Option<Self> {
        if &value == b"none" {
            Some(Self::None)
        } else if &value == b"positive" {
            Some(Self::Positive)
        } else if &value == b"negative" {
            Some(Self::Negative)
        } else {
            None
        }
    }

    fn orientation([a, b, c]: [Point<Twips>; 3]) -> i64 {
        let ax = a.x.get() as i64;
        let ay = a.y.get() as i64;
        let bx = b.x.get() as i64;
        let by = b.y.get() as i64;
        let cx = c.x.get() as i64;
        let cy = c.y.get() as i64;
        (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
    }

    #[inline]
    fn cull(self, points: [Point<Twips>; 3]) -> bool {
        match self {
            Self::None => false,
            Self::Positive => Self::orientation(points) >= 0,
            Self::Negative => Self::orientation(points) <= 0,
        }
    }
}

// Timffle: real `drawTriangles`. Measured on Flash Player 32 (timffle/difftest/src/
// D55Graphics.hx, D56Graphics2.hx, D57Winding.hx):
// * every call is its own fill group and overlapping triangles form a union whatever
//   their orientation (drawn with a consistent orientation under the non-zero rule);
// * `uvtData` must hold 2 or 3 numbers per vertex, otherwise ArgumentError #2004, even
//   without a bitmap fill;
// * with a bitmap fill, UVs map the bitmap onto each triangle (the fill matrix is
//   ignored, repeat/smooth are kept); a third `t` value gives perspective-correct
//   mapping (u/v weighted by t), approximated by subdividing the triangle;
// * a gradient fill with uvtData draws nothing; a solid fill ignores the UVs.
fn draw_triangles_internal<'gc>(
    activation: &mut Activation<'_, 'gc>,
    drawing: &mut Drawing,
    vertices: &Object<'gc>,
    indices: Option<&Object<'gc>>,
    uvt_data: Option<&Object<'gc>>,
    culling: TriangleCulling,
) -> Result<(), Error<'gc>> {
    let num_vertices = vertices
        .as_vector_storage()
        .expect("vertices is not a Vector")
        .length()
        / 2;

    let uvt: Option<Vec<f64>> = if let Some(uvt_data) = uvt_data {
        let storage = uvt_data
            .as_vector_storage()
            .expect("uvtData is not a Vector");
        let len = storage.length();
        if len != num_vertices * 2 && len != num_vertices * 3 {
            return Err(make_error_2004(activation, Error2004Type::ArgumentError));
        }
        Some(storage.storage().iter().map(|v| v.as_f64()).collect())
    } else {
        None
    };

    let Some(data) = TriangleData::new(activation, vertices, indices)? else {
        return Ok(());
    };

    let Some(fill_style) = drawing.current_fill_style().cloned() else {
        // No fill: only the stroke is drawn (triangles still need their own group so
        // later commands do not join them).
        for [a, b, c] in data.iter_triangles().filter(|&tri| !culling.cull(tri)) {
            drawing.draw_command(DrawCommand::MoveTo(a));
            drawing.draw_command(DrawCommand::LineTo(b));
            drawing.draw_command(DrawCommand::LineTo(c));
            drawing.draw_command(DrawCommand::LineTo(a));
        }
        return Ok(());
    };

    let textured = match (&uvt, &fill_style) {
        (Some(_), FillStyle::Bitmap { .. }) => true,
        (Some(_), FillStyle::Color(_)) | (None, _) => false,
        // Flash draws nothing for a gradient fill with UV data.
        (Some(_), _) => {
            drawing.begin_triangles_group(fill_style);
            return Ok(());
        }
    };

    drawing.begin_triangles_group(fill_style.clone());

    if !textured {
        for tri in data.iter_triangles().filter(|&tri| !culling.cull(tri)) {
            let [a, b, c] = orient(tri);
            drawing.draw_command_in_group(DrawCommand::MoveTo(a));
            drawing.draw_command_in_group(DrawCommand::LineTo(b));
            drawing.draw_command_in_group(DrawCommand::LineTo(c));
            drawing.draw_command_in_group(DrawCommand::LineTo(a));
        }
        return Ok(());
    }

    let uvt = uvt.expect("checked above");
    let stride = uvt.len() / num_vertices.max(1);
    let (bitmap_width, bitmap_height) = match &fill_style {
        FillStyle::Bitmap { id, .. } => {
            use ruffle_render::bitmap::BitmapSource;
            let size = drawing
                .bitmap_size(*id)
                .expect("bitmap fill refers to a registered bitmap");
            (size.width as f64, size.height as f64)
        }
        _ => unreachable!(),
    };

    let uvt_at = |vertex: usize| -> [f64; 3] {
        let base = vertex * stride;
        let t = if stride == 3 { uvt[base + 2] } else { 1.0 };
        [uvt[base] * bitmap_width, uvt[base + 1] * bitmap_height, t]
    };

    for (tri, verts) in data
        .iter_triangles()
        .zip(data.iter_vertex_indices())
        .filter(|&(tri, _)| !culling.cull(tri))
    {
        let tv = [
            TexturedVertex {
                p: tri[0],
                uvt: uvt_at(verts[0]),
            },
            TexturedVertex {
                p: tri[1],
                uvt: uvt_at(verts[1]),
            },
            TexturedVertex {
                p: tri[2],
                uvt: uvt_at(verts[2]),
            },
        ];
        draw_textured_triangle(drawing, &fill_style, tv, 0);
    }

    // Leave a fresh triangles group with the original fill style so the next ordinary
    // command continues with it.
    drawing.begin_triangles_group(fill_style);

    Ok(())
}

/// Timffle: put a triangle into a consistent orientation so that all triangles of a
/// `drawTriangles` group have the same winding direction (union under non-zero).
fn orient([a, b, c]: [Point<Twips>; 3]) -> [Point<Twips>; 3] {
    if TriangleCulling::orientation([a, b, c]) < 0 {
        [a, c, b]
    } else {
        [a, b, c]
    }
}

#[derive(Clone, Copy)]
struct TexturedVertex {
    p: Point<Twips>,
    /// u and v in bitmap pixels, t as given (1 without perspective).
    uvt: [f64; 3],
}

impl TexturedVertex {
    /// Perspective-correct midpoint of an edge: u and v are interpolated weighted by t.
    fn midpoint(self, other: Self) -> Self {
        let [u0, v0, t0] = self.uvt;
        let [u1, v1, t1] = other.uvt;
        let tsum = t0 + t1;
        let (u, v) = if tsum.abs() > f64::EPSILON {
            ((u0 * t0 + u1 * t1) / tsum, (v0 * t0 + v1 * t1) / tsum)
        } else {
            ((u0 + u1) / 2.0, (v0 + v1) / 2.0)
        };
        Self {
            p: Point::new(
                Twips::new((self.p.x.get() + other.p.x.get()) / 2),
                Twips::new((self.p.y.get() + other.p.y.get()) / 2),
            ),
            uvt: [u, v, tsum / 2.0],
        }
    }
}

/// Timffle: draw one textured triangle as a bitmap fill whose matrix maps the bitmap
/// onto the triangle. Triangles whose `t` values differ (perspective) are subdivided
/// into affine pieces until the perspective error is small.
fn draw_textured_triangle(
    drawing: &mut Drawing,
    fill_style: &FillStyle,
    tv: [TexturedVertex; 3],
    depth: u32,
) {
    const MAX_DEPTH: u32 = 5;
    const MIN_EDGE: i32 = 4 * Twips::TWIPS_PER_PIXEL;

    let ts = [tv[0].uvt[2], tv[1].uvt[2], tv[2].uvt[2]];
    let t_min = ts.iter().cloned().fold(f64::INFINITY, f64::min);
    let t_max = ts.iter().cloned().fold(f64::NEG_INFINITY, f64::max);
    let needs_split = t_min > 0.0 && t_max / t_min > 1.02;
    let edge = |a: Point<Twips>, b: Point<Twips>| {
        (a.x.get() - b.x.get())
            .abs()
            .max((a.y.get() - b.y.get()).abs())
    };
    let longest = edge(tv[0].p, tv[1].p)
        .max(edge(tv[1].p, tv[2].p))
        .max(edge(tv[2].p, tv[0].p));

    if needs_split && depth < MAX_DEPTH && longest > MIN_EDGE {
        let m01 = tv[0].midpoint(tv[1]);
        let m12 = tv[1].midpoint(tv[2]);
        let m20 = tv[2].midpoint(tv[0]);
        draw_textured_triangle(drawing, fill_style, [tv[0], m01, m20], depth + 1);
        draw_textured_triangle(drawing, fill_style, [m01, tv[1], m12], depth + 1);
        draw_textured_triangle(drawing, fill_style, [m20, m12, tv[2]], depth + 1);
        draw_textured_triangle(drawing, fill_style, [m01, m12, m20], depth + 1);
        return;
    }

    let [a, b, c] = [tv[0].p, tv[1].p, tv[2].p];
    let (p0, p1, p2) = (
        (a.x.get() as f64, a.y.get() as f64),
        (b.x.get() as f64, b.y.get() as f64),
        (c.x.get() as f64, c.y.get() as f64),
    );
    let (b0, b1, b2) = (
        (tv[0].uvt[0], tv[0].uvt[1]),
        (tv[1].uvt[0], tv[1].uvt[1]),
        (tv[2].uvt[0], tv[2].uvt[1]),
    );
    // Affine map M with M * (u_i, v_i) = p_i (bitmap pixels -> twips).
    let (db1x, db1y) = (b1.0 - b0.0, b1.1 - b0.1);
    let (db2x, db2y) = (b2.0 - b0.0, b2.1 - b0.1);
    let (dp1x, dp1y) = (p1.0 - p0.0, p1.1 - p0.1);
    let (dp2x, dp2y) = (p2.0 - p0.0, p2.1 - p0.1);
    let det = db1x * db2y - db2x * db1y;
    let style = if det.abs() > 1e-9 {
        let ma = (dp1x * db2y - dp2x * db1y) / det;
        let mc = (dp2x * db1x - dp1x * db2x) / det;
        let mb = (dp1y * db2y - dp2y * db1y) / det;
        let md = (dp2y * db1x - dp1y * db2x) / det;
        let tx = p0.0 - ma * b0.0 - mc * b0.1;
        let ty = p0.1 - mb * b0.0 - md * b0.1;
        let matrix = Matrix::from(ruffle_render::matrix::Matrix {
            a: ma as f32,
            b: mb as f32,
            c: mc as f32,
            d: md as f32,
            tx: Twips::new(tx.round() as i32),
            ty: Twips::new(ty.round() as i32),
        });
        match fill_style {
            FillStyle::Bitmap {
                id,
                is_smoothed,
                is_repeating,
                ..
            } => FillStyle::Bitmap {
                id: *id,
                matrix,
                is_smoothed: *is_smoothed,
                is_repeating: *is_repeating,
            },
            other => other.clone(),
        }
    } else {
        // Degenerate UVs: the whole triangle samples one bitmap point.
        fill_style.clone()
    };

    let [a, b, c] = orient([a, b, c]);
    drawing.begin_triangles_group(style);
    drawing.draw_command_in_group(DrawCommand::MoveTo(a));
    drawing.draw_command_in_group(DrawCommand::LineTo(b));
    drawing.draw_command_in_group(DrawCommand::LineTo(c));
    drawing.draw_command_in_group(DrawCommand::LineTo(a));
}

/// Implements `Graphics.drawGraphicsDataItem` (one non-GraphicsPath item of
/// `drawGraphicsData`; GraphicsPath items go through `drawPath` in Graphics.as).
// Timffle: was `drawGraphicsData` over the whole vector.
pub fn draw_graphics_data_item<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();
    let obj = args.get_object(activation, 0, "item")?;
    let this = this.as_display_object().expect("Bad this");

    if let Some(mut drawing) = this.as_drawing() {
        handle_igraphics_data(activation, &mut drawing, &obj)?;
    }

    Ok(Value::Undefined)
}

/// Implements `Graphics.lineBitmapStyle`
pub fn line_bitmap_style<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if let Some(this) = this.as_display_object() {
        let bitmap_object = args.get_object(activation, 0, "bitmap")?;
        let bitmap = bitmap_object
            .as_bitmap_data()
            .expect("Bitmap argument is ensured to be a BitmapData from actionscript");
        let matrix = if let Some(matrix) = args.try_get_object(1) {
            Matrix::from(object_to_matrix(matrix))
        } else {
            // Users can explicitly pass in `null` to mean identity matrix
            Matrix::IDENTITY
        };
        let is_repeating = args.get_bool(2);
        let is_smoothed = args.get_bool(3);

        let handle = bitmap.bitmap_handle(activation.gc(), activation.context.renderer);

        let bitmap = ruffle_render::bitmap::BitmapInfo {
            handle,
            width: bitmap.width(),
            height: bitmap.height(),
        };
        let scale_matrix = Matrix::scale(
            (Twips::TWIPS_PER_PIXEL as i16).into(),
            (Twips::TWIPS_PER_PIXEL as i16).into(),
        );

        if let Some(mut draw) = this.as_drawing() {
            let id = draw.add_bitmap(bitmap);
            // Timffle: readGraphicsData returns the same BitmapData object.
            draw.set_bitmap_object(id, stash_object(activation, bitmap_object));
            draw.set_line_fill_style(FillStyle::Bitmap {
                id,
                matrix: matrix * scale_matrix,
                is_smoothed,
                is_repeating,
            });
        }
    }

    Ok(Value::Undefined)
}

/// Implements `Graphics.readGraphicsData`
///
/// Timffle: real implementation over `Drawing::read_graphics_data`, in the structure
/// measured on Flash Player 32 (timffle/difftest/src/D55Graphics.hx, D56Graphics2.hx,
/// D57Winding.hx): every fill group as [fill, GraphicsPath, GraphicsEndFill], the strokes
/// recorded inside it as [GraphicsStroke, GraphicsPath(nonZero), GraphicsStroke(0)], a
/// trailing GraphicsEndFill when the list ends with a stroke; the object's own transform
/// is not applied, the children's data (`recurse`, visible children only, in child order)
/// is transformed into this object's space. Solid colours come back through Flash's 8-bit
/// premultiplied round trip, gradient colours as ARGB, bitmap fill matrices scaled by
/// 4095/4096 with repeat=true/smooth=false, strokes with pixelHinting=false,
/// scaleMode=normal, caps=none, joints=round, miterLimit=3 (Flash does not keep them),
/// cubic curves as four quadratics, round rects/circles/ellipses starting at
/// (x+w, y+h-ry) clockwise.
pub fn read_graphics_data<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();
    let recurse = args.get_bool(0);
    let value_type = activation.avm2().class_defs().igraphicsdata;
    let mut out = Vec::new();
    if let Some(display_object) = this.as_display_object() {
        read_display_object_graphics(
            activation,
            display_object,
            RenderMatrix::IDENTITY,
            recurse,
            &mut out,
        )?;
    }
    let storage = VectorStorage::from_values(out, false, Some(value_type));
    Ok(VectorObject::from_vector(storage, activation).into())
}

/// Timffle: the readGraphicsData items of one display object (and, with `recurse`, of
/// its visible children, transformed by `transform`).
fn read_display_object_graphics<'gc>(
    activation: &mut Activation<'_, 'gc>,
    display_object: DisplayObject<'gc>,
    transform: RenderMatrix,
    recurse: bool,
    out: &mut Vec<Value<'gc>>,
) -> Result<(), Error<'gc>> {
    // Read everything out of the drawing before any AS constructor runs.
    let (items, bitmap_objects, shader_fills) = match display_object.as_drawing() {
        Some(drawing) => {
            let items = drawing.read_graphics_data();
            let mut bitmap_objects: Vec<(u16, Object<'gc>)> = Vec::new();
            let mut shader_fills: Vec<(u16, Option<Object<'gc>>, Matrix)> = Vec::new();
            let mut note_style = |style: &FillStyle| {
                if let FillStyle::Bitmap { id, .. } = style {
                    if let Some(matrix) = drawing.shader_fill_matrix(*id) {
                        if !shader_fills.iter().any(|(i, ..)| i == id) {
                            let shader = drawing
                                .shader_fill_object(*id)
                                .map(|root| *activation.context.dynamic_root.fetch(&root.0));
                            shader_fills.push((*id, shader, matrix));
                        }
                    } else if !bitmap_objects.iter().any(|(i, _)| i == id)
                        && let Some(root) = drawing.bitmap_object(*id)
                    {
                        bitmap_objects.push((*id, *activation.context.dynamic_root.fetch(&root.0)));
                    }
                }
            };
            for item in &items {
                match item {
                    GraphicsReadItem::Fill { style, .. } => note_style(style),
                    GraphicsReadItem::Stroke { style, .. } => note_style(style.fill_style()),
                }
            }
            (items, bitmap_objects, shader_fills)
        }
        None => (Vec::new(), Vec::new(), Vec::new()),
    };

    // Timffle: Flash Player 32 leaves shader fills and shader strokes out of
    // readGraphicsData (with their path; a shape that only has them reads as an empty
    // vector), keeping everything else; measured in tests/tests/swfs/avm2/graphics_shader_fill.
    let is_shader_style = |style: &FillStyle| match style {
        FillStyle::Bitmap { id, .. } => shader_fills.iter().any(|(i, ..)| i == id),
        _ => false,
    };
    let mut last_was_stroke = false;
    for item in items {
        let skip = match &item {
            GraphicsReadItem::Fill { style, .. } => is_shader_style(style),
            GraphicsReadItem::Stroke { style, .. } => is_shader_style(style.fill_style()),
        };
        if skip {
            // The closing GraphicsEndFill after a final stroke goes with it (a plain
            // stroke followed by a shader stroke reads without one).
            last_was_stroke = false;
            continue;
        }
        match item {
            GraphicsReadItem::Fill {
                style,
                rule,
                commands,
            } => {
                let fill = fill_style_to_object(
                    activation,
                    &style,
                    transform,
                    &bitmap_objects,
                    &shader_fills,
                )?;
                out.push(fill);
                out.push(path_to_object(activation, &commands, rule, transform)?);
                out.push(construct_graphics(
                    activation,
                    |defs| defs.graphicsendfill,
                    &[],
                )?);
                last_was_stroke = false;
            }
            GraphicsReadItem::Stroke { style, commands } => {
                let fill = fill_style_to_object(
                    activation,
                    style.fill_style(),
                    transform,
                    &bitmap_objects,
                    &shader_fills,
                )?;
                out.push(stroke_to_object(
                    activation,
                    style.width().to_pixels(),
                    fill,
                )?);
                out.push(path_to_object(
                    activation,
                    &commands,
                    FillRule::NonZero,
                    transform,
                )?);
                out.push(stroke_to_object(activation, 0.0, Value::Null)?);
                last_was_stroke = true;
            }
        }
    }
    if last_was_stroke {
        out.push(construct_graphics(
            activation,
            |defs| defs.graphicsendfill,
            &[],
        )?);
    }

    if recurse && let Some(container) = display_object.as_container() {
        for child in container.iter_render_list() {
            if !child.visible() {
                continue;
            }
            let child_transform = transform * child.base().matrix();
            read_display_object_graphics(activation, child, child_transform, true, out)?;
        }
    }
    Ok(())
}

/// Timffle: construct an instance of one of the `flash.display.Graphics*` data classes.
fn construct_graphics<'gc>(
    activation: &mut Activation<'_, 'gc>,
    class: impl FnOnce(&crate::avm2::globals::SystemClassDefs<'gc>) -> crate::avm2::Class<'gc>,
    args: &[Value<'gc>],
) -> Result<Value<'gc>, Error<'gc>> {
    let class = class(activation.avm2().class_defs())
        .class_object()
        .expect("Graphics data classes are loaded with playerglobal");
    class.construct(activation, args)
}

/// Timffle: Flash Player reports solid colours after an 8-bit premultiplied-alpha round
/// trip: p = round(c * a / 255), c' = floor(p * 255 / a) (matches 5 of the 7 measured
/// samples of D56Graphics2 c1; the exact formula is unknown). Alpha 0 gives black.
fn flash_color_roundtrip(color: Color) -> u32 {
    let a = color.a as f64;
    if color.a == 0 {
        return 0;
    }
    let channel = |c: u8| -> u32 {
        let p = (c as f64 * a / 255.0).round();
        ((p * 255.0 / a).floor() as u32).min(255)
    };
    (channel(color.r) << 16) | (channel(color.g) << 8) | channel(color.b)
}

/// Timffle: a `flash.geom.Matrix` from an swf matrix (tx/ty in twips), optionally
/// transformed into the parent's space, with a–d scaled by `factor` (Flash's 4095/4096
/// quirk for bitmap fill matrices). Flash Player 32 reports a fill matrix's translation
/// in whole pixels, cut toward zero (measured: tx 1.5 → 1, ty −2.5 → −2, a bitmap fill's
/// tx 5 stays 5).
fn matrix_to_object<'gc>(
    activation: &mut Activation<'_, 'gc>,
    matrix: RenderMatrix,
    transform: RenderMatrix,
    factor: f64,
) -> Result<Value<'gc>, Error<'gc>> {
    let m = transform * matrix;
    activation.avm2().classes().matrix.construct(
        activation,
        &[
            (m.a as f64 * factor).into(),
            (m.b as f64 * factor).into(),
            (m.c as f64 * factor).into(),
            (m.d as f64 * factor).into(),
            m.tx.to_pixels().trunc().into(),
            m.ty.to_pixels().trunc().into(),
        ],
    )
}

/// Timffle: the `GraphicsSolidFill` / `GraphicsGradientFill` / `GraphicsBitmapFill` /
/// `GraphicsShaderFill` object for a recorded fill style.
fn fill_style_to_object<'gc>(
    activation: &mut Activation<'_, 'gc>,
    style: &FillStyle,
    transform: RenderMatrix,
    bitmap_objects: &[(u16, Object<'gc>)],
    shader_fills: &[(u16, Option<Object<'gc>>, Matrix)],
) -> Result<Value<'gc>, Error<'gc>> {
    match style {
        FillStyle::Color(color) => construct_graphics(
            activation,
            |defs| defs.graphicssolidfill,
            &[
                flash_color_roundtrip(*color).into(),
                (color.a as f64 / 255.0).into(),
            ],
        ),
        FillStyle::LinearGradient(gradient)
        | FillStyle::RadialGradient(gradient)
        | FillStyle::FocalGradient { gradient, .. } => {
            let (gradient_type, focal_point) = match style {
                FillStyle::LinearGradient(_) => ("linear", 0.0),
                FillStyle::RadialGradient(_) => ("radial", 0.0),
                // Flash Player 32 reads the 8.8 fixed-point focal ratio back over 255
                // (0.5 → 0.50196, −0.4 → −0.4), measured.
                FillStyle::FocalGradient { focal_point, .. } => {
                    ("radial", f64::from(focal_point.get()) / 255.0)
                }
                _ => unreachable!(),
            };
            let colors: Vec<Value<'gc>> = gradient
                .records
                .iter()
                .map(|record| {
                    let c = record.color;
                    (((c.a as u32) << 24) | ((c.r as u32) << 16) | ((c.g as u32) << 8) | c.b as u32)
                        .into()
                })
                .collect();
            let alphas: Vec<Value<'gc>> = gradient
                .records
                .iter()
                .map(|record| (record.color.a as f64 / 255.0).into())
                .collect();
            let ratios: Vec<Value<'gc>> = gradient
                .records
                .iter()
                .map(|record| (record.ratio as u32).into())
                .collect();
            let colors =
                ArrayObject::from_storage(activation.context, ArrayStorage::from_args(&colors));
            let alphas =
                ArrayObject::from_storage(activation.context, ArrayStorage::from_args(&alphas));
            let ratios =
                ArrayObject::from_storage(activation.context, ArrayStorage::from_args(&ratios));
            let matrix = matrix_to_object(
                activation,
                RenderMatrix::from(gradient.matrix),
                transform,
                1.0,
            )?;
            let spread = match gradient.spread {
                GradientSpread::Pad => "pad",
                GradientSpread::Reflect => "reflect",
                GradientSpread::Repeat => "repeat",
            };
            let interpolation = match gradient.interpolation {
                GradientInterpolation::Rgb => "rgb",
                GradientInterpolation::LinearRgb => "linearRGB",
            };
            construct_graphics(
                activation,
                |defs| defs.graphicsgradientfill,
                &[
                    AvmString::new_utf8(activation.gc(), gradient_type).into(),
                    colors.into(),
                    alphas.into(),
                    ratios.into(),
                    matrix,
                    AvmString::new_utf8(activation.gc(), spread).into(),
                    AvmString::new_utf8(activation.gc(), interpolation).into(),
                    focal_point.into(),
                ],
            )
        }
        FillStyle::Bitmap { id, matrix, .. } => {
            if let Some((_, shader, shader_matrix)) =
                shader_fills.iter().find(|(fill_id, ..)| fill_id == id)
            {
                let matrix = matrix_to_object(
                    activation,
                    RenderMatrix::from(*shader_matrix),
                    transform,
                    1.0,
                )?;
                let shader = shader.map(Value::from).unwrap_or(Value::Null);
                return construct_graphics(
                    activation,
                    |defs| defs.graphicsshaderfill,
                    &[shader, matrix],
                );
            }
            // The stored matrix maps bitmap pixels to twips: undo the x20 pixel scale.
            let stored = RenderMatrix::from(*matrix);
            let scale = Twips::TWIPS_PER_PIXEL as f32;
            let given = RenderMatrix {
                a: stored.a / scale,
                b: stored.b / scale,
                c: stored.c / scale,
                d: stored.d / scale,
                tx: stored.tx,
                ty: stored.ty,
            };
            let matrix = matrix_to_object(activation, given, transform, 4095.0 / 4096.0)?;
            let bitmap = bitmap_objects
                .iter()
                .find(|(bitmap_id, _)| bitmap_id == id)
                .map(|(_, object)| Value::from(*object))
                .unwrap_or(Value::Null);
            construct_graphics(
                activation,
                |defs| defs.graphicsbitmapfill,
                &[bitmap, matrix, true.into(), false.into()],
            )
        }
    }
}

/// Timffle: a `GraphicsStroke` the way Flash reports it (only the thickness and the fill
/// survive; pixelHinting=false, scaleMode=normal, caps=none, joints=round, miterLimit=3).
fn stroke_to_object<'gc>(
    activation: &mut Activation<'_, 'gc>,
    thickness: f64,
    fill: Value<'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let normal = AvmString::new_utf8(activation.gc(), "normal");
    let none = AvmString::new_utf8(activation.gc(), "none");
    let round = AvmString::new_utf8(activation.gc(), "round");
    construct_graphics(
        activation,
        |defs| defs.graphicsstroke,
        &[
            thickness.into(),
            false.into(),
            normal.into(),
            none.into(),
            round.into(),
            3.0.into(),
            fill,
        ],
    )
}

/// Timffle: a `GraphicsPath` for recorded commands transformed by `transform`. Cubic
/// curves are reported as four quadratics (split at t = 1/4, 1/2, 3/4; control point
/// (3(Q1+Q2)-Q0-Q3)/4), every coordinate rounded to twips, like Flash Player.
fn path_to_object<'gc>(
    activation: &mut Activation<'_, 'gc>,
    commands: &[DrawCommand],
    rule: FillRule,
    transform: RenderMatrix,
) -> Result<Value<'gc>, Error<'gc>> {
    let mut command_values: Vec<Value<'gc>> = Vec::with_capacity(commands.len());
    let mut data: Vec<Value<'gc>> = Vec::with_capacity(commands.len() * 2);
    let px = |point: Point<Twips>| -> (f64, f64) {
        let p = transform * point;
        (p.x.to_pixels(), p.y.to_pixels())
    };
    let push_point = |data: &mut Vec<Value<'gc>>, (x, y): (f64, f64)| {
        data.push(x.into());
        data.push(y.into());
    };
    let round_twips =
        |v: f64| (v * Twips::TWIPS_PER_PIXEL as f64).round() / Twips::TWIPS_PER_PIXEL as f64;
    let mut from = (0.0, 0.0);
    for command in commands {
        match command {
            DrawCommand::MoveTo(point) => {
                command_values.push(1.into());
                from = px(*point);
                push_point(&mut data, from);
            }
            DrawCommand::LineTo(point) => {
                command_values.push(2.into());
                from = px(*point);
                push_point(&mut data, from);
            }
            DrawCommand::QuadraticCurveTo { control, anchor } => {
                command_values.push(3.into());
                push_point(&mut data, px(*control));
                from = px(*anchor);
                push_point(&mut data, from);
            }
            DrawCommand::CubicCurveTo {
                control_a,
                control_b,
                anchor,
            } => {
                let mut p0 = from;
                let mut p1 = px(*control_a);
                let mut p2 = px(*control_b);
                let p3 = px(*anchor);
                // Split off the first quarter three times (de Casteljau at t = 1/3,
                // 1/2, 1 of the remainder = 1/4, 1/2, 3/4 of the whole curve).
                for t in [0.25, 1.0 / 3.0, 0.5, 1.0] {
                    let lerp = |a: (f64, f64), b: (f64, f64)| {
                        (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t)
                    };
                    let q0 = lerp(p0, p1);
                    let q1 = lerp(p1, p2);
                    let q2 = lerp(p2, p3);
                    let r0 = lerp(q0, q1);
                    let r1 = lerp(q1, q2);
                    let end = lerp(r0, r1);
                    // Piece p0, q0, r0, end -> one quadratic.
                    let control = (
                        (3.0 * (q0.0 + r0.0) - p0.0 - end.0) / 4.0,
                        (3.0 * (q0.1 + r0.1) - p0.1 - end.1) / 4.0,
                    );
                    command_values.push(3.into());
                    push_point(&mut data, (round_twips(control.0), round_twips(control.1)));
                    push_point(&mut data, (round_twips(end.0), round_twips(end.1)));
                    // Remainder end, r1, q2, p3.
                    p0 = end;
                    p1 = r1;
                    p2 = q2;
                }
                from = p3;
            }
        }
    }
    let int_class = activation.avm2().class_defs().int;
    let number_class = activation.avm2().class_defs().number;
    let commands = VectorObject::from_vector(
        VectorStorage::from_values(command_values, false, Some(int_class)),
        activation,
    );
    let data = VectorObject::from_vector(
        VectorStorage::from_values(data, false, Some(number_class)),
        activation,
    );
    let winding = match rule {
        FillRule::EvenOdd => "evenOdd",
        FillRule::NonZero => "nonZero",
    };
    construct_graphics(
        activation,
        |defs| defs.graphicspath,
        &[
            commands.into(),
            data.into(),
            AvmString::new_utf8(activation.gc(), winding).into(),
        ],
    )
}

fn read_point<'gc>(
    activation: &mut Activation<'_, 'gc>,
    data: &VectorStorage<'gc>,
    data_index: &mut usize,
) -> Option<Point<Twips>> {
    let x = data.get(*data_index, activation).ok()?.as_f64();

    let y = data.get(*data_index + 1, activation).ok()?.as_f64();

    *data_index += 2;

    Some(Point {
        x: Twips::from_pixels(x),
        y: Twips::from_pixels(y),
    })
}

fn process_commands<'gc>(
    activation: &mut Activation<'_, 'gc>,
    drawing: &mut Drawing,
    commands: &VectorStorage<'gc>,
    data: &VectorStorage<'gc>,
    fill_rule: FillRule,
) -> Result<(), Error<'gc>> {
    // Flash special cases this, and doesn't throw an error,
    // even if data has odd number of coordinates.
    if commands.length() == 0 {
        return Ok(());
    }

    // This error is always thrown at this point,
    // no matter if data is superfluous.
    if !data.length().is_multiple_of(2) {
        return Err(make_error_2004(activation, Error2004Type::ArgumentError));
    }

    // Timffle: Flash's drawPath fill rules — own fill group per winding rule (merged with
    // a directly preceding drawPath of the same rule), strokes never implicitly closed.
    drawing.begin_path_group(fill_rule);
    drawing.begin_path_stroke();

    fn process_command<'gc>(
        activation: &mut Activation<'_, 'gc>,
        drawing: &mut Drawing,
        data: &VectorStorage<'gc>,
        command: i32,
        data_index: &mut usize,
    ) -> Option<()> {
        // Flash ignores commands which do not have data associated with them.
        match command {
            // NO_OP
            0 => {}
            // MOVE_TO
            1 => {
                let point = read_point(activation, data, data_index)?;
                drawing.draw_command_in_group(DrawCommand::MoveTo(point));
            }
            // LINE_TO
            2 => {
                let point = read_point(activation, data, data_index)?;
                drawing.draw_command_in_group(DrawCommand::LineTo(point));
            }
            // CURVE_TO
            3 => {
                let control = read_point(activation, data, data_index)?;
                let anchor = read_point(activation, data, data_index)?;
                drawing.draw_command_in_group(DrawCommand::QuadraticCurveTo { control, anchor });
            }
            // WIDE_MOVE_TO
            4 => {
                *data_index += 2;
                let point = read_point(activation, data, data_index)?;
                drawing.draw_command_in_group(DrawCommand::MoveTo(point));
            }
            // WIDE_LINE_TO
            5 => {
                *data_index += 2;
                let point = read_point(activation, data, data_index)?;
                drawing.draw_command_in_group(DrawCommand::LineTo(point));
            }
            // CUBIC_CURVE_TO
            6 => {
                let control_a = read_point(activation, data, data_index)?;
                let control_b = read_point(activation, data, data_index)?;
                let anchor = read_point(activation, data, data_index)?;
                drawing.draw_command_in_group(DrawCommand::CubicCurveTo {
                    control_a,
                    control_b,
                    anchor,
                });
            }
            _ => {
                // Unknown commands stop processing
                return None;
            }
        }
        Some(())
    }

    let mut data_index = 0;
    for i in 0..commands.length() {
        let command = commands
            .get(i, activation)
            .expect("missing command")
            .as_i32();

        if process_command(activation, drawing, data, command, &mut data_index).is_none() {
            break;
        }
    }

    // Timffle: the drawPath stroke sub-path ends here (never implicitly closed); the fill
    // group stays open so a following drawPath with the same rule joins it.
    drawing.end_path_stroke();

    Ok(())
}

fn handle_igraphics_data<'gc>(
    activation: &mut Activation<'_, 'gc>,
    drawing: &mut Drawing,
    obj: &Object<'gc>,
) -> Result<(), Error<'gc>> {
    let class = obj.instance_class();

    if class == activation.avm2().class_defs().graphicsbitmapfill {
        let style = handle_bitmap_fill(activation, drawing, obj)?;
        drawing.set_fill_style(Some(style));
    } else if class == activation.avm2().class_defs().graphicsendfill {
        drawing.set_fill_style(None);
    } else if class == activation.avm2().class_defs().graphicsgradientfill {
        let style = handle_gradient_fill(activation, obj)?;
        drawing.set_fill_style(Some(style));
    } else if class == activation.avm2().class_defs().graphicspath {
        let commands = obj.get_slot(graphics_path_slots::COMMANDS).as_object();

        let data = obj.get_slot(graphics_path_slots::DATA).as_object();

        let fill_rule = obj
            .get_slot(graphics_path_slots::_WINDING)
            .coerce_to_string(activation)?
            .parse()
            .expect("AS3 setter guarantees value of winding");

        if let (Some(commands), Some(data)) = (commands, data) {
            process_commands(
                activation,
                drawing,
                &commands.as_vector_storage().unwrap(),
                &data.as_vector_storage().unwrap(),
                fill_rule,
            )?;
        }
    } else if class == activation.avm2().class_defs().graphicssolidfill {
        let style = handle_solid_fill(activation, obj)?;
        drawing.set_fill_style(Some(style));
    } else if class == activation.avm2().class_defs().graphicsshaderfill {
        // Timffle: same as beginShaderFill (null shader: TypeError #2007).
        let style = handle_igraphics_fill(activation, drawing, obj)?;
        drawing.set_fill_style(style);
    } else if class == activation.avm2().class_defs().graphicsstroke {
        let thickness = obj
            .get_slot(graphics_stroke_slots::THICKNESS)
            .coerce_to_number(activation)?;

        if thickness.is_nan() {
            drawing.set_line_style(None);
        } else {
            let caps = {
                let caps = obj
                    .get_slot(graphics_stroke_slots::_CAPS)
                    .coerce_to_string(activation);
                caps_to_cap_style(caps.ok())
            };
            let fill = {
                let fill = obj.get_slot(graphics_stroke_slots::FILL).as_object();

                if let Some(fill) = fill {
                    handle_igraphics_fill(activation, drawing, &fill)?
                } else {
                    None
                }
            };

            let joints = obj
                .get_slot(graphics_stroke_slots::_JOINTS)
                .coerce_to_string(activation)
                .ok();
            let miter_limit = obj
                .get_slot(graphics_stroke_slots::MITER_LIMIT)
                .coerce_to_number(activation)?;
            let pixel_hinting = obj
                .get_slot(graphics_stroke_slots::PIXEL_HINTING)
                .coerce_to_boolean();
            let scale_mode = obj
                .get_slot(graphics_stroke_slots::_SCALE_MODE)
                .coerce_to_string(activation)?;

            let width = Twips::from_pixels(thickness.clamp(0.0, 255.0));
            let join_style = joints_to_join_style(joints, miter_limit);
            let (allow_scale_x, allow_scale_y) = scale_mode_to_allow_scale_bits(&scale_mode)?;

            let mut line_style = LineStyle::new()
                .with_width(width)
                .with_start_cap(caps)
                .with_end_cap(caps)
                .with_join_style(join_style)
                .with_allow_scale_x(allow_scale_x)
                .with_allow_scale_y(allow_scale_y)
                .with_is_pixel_hinted(pixel_hinting)
                .with_allow_close(false);

            if let Some(fill) = fill {
                line_style = line_style.with_fill_style(fill);
            }

            drawing.set_line_style(Some(line_style));
        }
    } else if class == activation.avm2().class_defs().graphicstrianglepath {
        handle_graphics_triangle_path(activation, drawing, obj)?;
    } else {
        panic!("Unknown graphics data class {class:?}");
    }

    Ok(())
}

fn handle_graphics_triangle_path<'gc>(
    activation: &mut Activation<'_, 'gc>,
    drawing: &mut Drawing,
    obj: &Object<'gc>,
) -> Result<(), Error<'gc>> {
    let culling = {
        let culling = obj
            .get_slot(graphics_triangle_path_slots::_CULLING)
            .coerce_to_string(activation)?;

        TriangleCulling::from_string(culling)
            .ok_or_else(|| make_error_2008(activation, "culling"))?
    };

    let vertices = obj
        .get_slot(graphics_triangle_path_slots::VERTICES)
        .as_object();
    let indices = obj
        .get_slot(graphics_triangle_path_slots::INDICES)
        .as_object();
    let uvt_data = obj
        .get_slot(graphics_triangle_path_slots::UVT_DATA)
        .as_object();

    if let Some(vertices) = vertices {
        draw_triangles_internal(
            activation,
            drawing,
            &vertices,
            indices.as_ref(),
            uvt_data.as_ref(),
            culling,
        )?;
    }

    Ok(())
}

fn handle_igraphics_fill<'gc>(
    activation: &mut Activation<'_, 'gc>,
    drawing: &mut Drawing,
    obj: &Object<'gc>,
) -> Result<Option<FillStyle>, Error<'gc>> {
    let class = obj.instance_class();

    if class == activation.avm2().class_defs().graphicsbitmapfill {
        let style = handle_bitmap_fill(activation, drawing, obj)?;
        Ok(Some(style))
    } else if class == activation.avm2().class_defs().graphicsendfill {
        Ok(None)
    } else if class == activation.avm2().class_defs().graphicsgradientfill {
        let style = handle_gradient_fill(activation, obj)?;
        Ok(Some(style))
    } else if class == activation.avm2().class_defs().graphicssolidfill {
        let style = handle_solid_fill(activation, obj)?;
        Ok(Some(style))
    } else if class == activation.avm2().class_defs().graphicsshaderfill {
        // Timffle: like beginShaderFill.
        let shader = obj
            .get_slot(graphics_shader_fill_slots::SHADER)
            .as_object()
            .ok_or_else(|| make_error_2007(activation, "shader"))?;
        let matrix = obj.get_slot(graphics_shader_fill_slots::MATRIX).as_object();
        Ok(Some(shader_fill_style(
            activation, drawing, shader, matrix,
        )?))
    } else {
        tracing::warn!("Unknown graphics fill class {:?}", class);
        Ok(None)
    }
}

fn handle_solid_fill<'gc>(
    activation: &mut Activation<'_, 'gc>,
    obj: &Object<'gc>,
) -> Result<FillStyle, Error<'gc>> {
    let alpha = obj
        .get_slot(graphics_solid_fill_slots::ALPHA)
        .coerce_to_number(activation)
        .unwrap_or(1.0);

    let color = obj
        .get_slot(graphics_solid_fill_slots::COLOR)
        .coerce_to_u32(activation)
        .unwrap_or(0);

    Ok(FillStyle::Color(color_from_args(color, alpha)))
}

fn handle_gradient_fill<'gc>(
    activation: &mut Activation<'_, 'gc>,
    obj: &Object<'gc>,
) -> Result<FillStyle, Error<'gc>> {
    let alphas = obj
        .get_slot(graphics_gradient_fill_slots::ALPHAS)
        .as_object();
    let ratios = obj
        .get_slot(graphics_gradient_fill_slots::RATIOS)
        .as_object();

    let colors = obj
        .get_slot(graphics_gradient_fill_slots::COLORS)
        .as_object()
        .ok_or_else(|| make_error_2007(activation, "colors"))?;

    let gradient_type = {
        let gradient_type = obj
            .get_slot(graphics_gradient_fill_slots::_TYPE)
            .coerce_to_string(activation)?;

        parse_gradient_type(activation, gradient_type)?
    };

    let records = build_gradient_records(
        activation,
        &colors.as_array_storage().expect("Guaranteed by AS"),
        alphas,
        ratios,
    )?;

    let matrix = {
        let matrix = obj
            .get_slot(graphics_gradient_fill_slots::MATRIX)
            .as_object();

        match matrix {
            Some(matrix) => Matrix::from(object_to_matrix(matrix)),
            None => Matrix::IDENTITY,
        }
    };

    let spread = {
        let spread_method = obj
            .get_slot(graphics_gradient_fill_slots::_SPREAD_METHOD)
            .coerce_to_string(activation)?;

        parse_spread_method(spread_method)
    };

    let interpolation = {
        let interpolation_method = obj
            .get_slot(graphics_gradient_fill_slots::_INTERPOLATION_METHOD)
            .coerce_to_string(activation)?;

        parse_interpolation_method(interpolation_method)
    };

    let focal_point = obj
        .get_slot(graphics_gradient_fill_slots::FOCAL_POINT_RATIO)
        .coerce_to_number(activation)?;

    let fill = match gradient_type {
        GradientType::Linear => FillStyle::LinearGradient(Gradient {
            matrix,
            spread,
            interpolation,
            records,
        }),
        GradientType::Radial if focal_point == 0.0 => FillStyle::RadialGradient(Gradient {
            matrix,
            spread,
            interpolation,
            records,
        }),
        _ => FillStyle::FocalGradient {
            gradient: Gradient {
                matrix,
                spread,
                interpolation,
                records,
            },
            focal_point: Fixed8::from_f64(focal_point),
        },
    };

    Ok(fill)
}

fn handle_bitmap_fill<'gc>(
    activation: &mut Activation<'_, 'gc>,
    drawing: &mut Drawing,
    obj: &Object<'gc>,
) -> Result<FillStyle, Error<'gc>> {
    let bitmap_object = obj
        .get_slot(graphics_bitmap_fill_slots::BITMAP_DATA)
        .as_object()
        .ok_or_else(|| make_error_2007(activation, "bitmap"))?;
    let bitmap_data = bitmap_object
        .as_bitmap_data()
        .expect("Bitmap argument is ensured to be a BitmapData from actionscript");

    let matrix = obj
        .get_slot(graphics_bitmap_fill_slots::MATRIX)
        .as_object()
        .map(|matrix| Matrix::from(object_to_matrix(matrix)))
        .unwrap_or(Matrix::IDENTITY);

    let is_repeating = obj
        .get_slot(graphics_bitmap_fill_slots::REPEAT)
        .coerce_to_boolean();

    let is_smoothed = obj
        .get_slot(graphics_bitmap_fill_slots::SMOOTH)
        .coerce_to_boolean();

    let handle = bitmap_data.bitmap_handle(activation.gc(), activation.context.renderer);

    let bitmap = ruffle_render::bitmap::BitmapInfo {
        handle,
        width: bitmap_data.width(),
        height: bitmap_data.height(),
    };

    let scale_matrix = Matrix::scale(
        (Twips::TWIPS_PER_PIXEL as i16).into(),
        (Twips::TWIPS_PER_PIXEL as i16).into(),
    );

    let id = drawing.add_bitmap(bitmap);
    // Timffle: readGraphicsData returns the same BitmapData object.
    drawing.set_bitmap_object(id, stash_object(activation, bitmap_object));

    let style = FillStyle::Bitmap {
        id,
        matrix: matrix * scale_matrix,
        is_smoothed,
        is_repeating,
    };

    Ok(style)
}

/// Timffle: keep an AVM2 object alive from inside a `Drawing` (see `ObjectRoot`).
fn stash_object<'gc>(activation: &mut Activation<'_, 'gc>, object: Object<'gc>) -> ObjectRoot {
    let mc = activation.gc();
    ObjectRoot(
        activation
            .context
            .dynamic_root
            .stash::<gc_arena::Rootable![Object<'_>]>(mc, Gc::new(mc, object)),
    )
}

/// Timffle: the fill style of a `beginShaderFill` / `lineShaderStyle` / `GraphicsShaderFill`
/// (see `Drawing::add_shader_fill`). `shader` must not be null (TypeError #2007); a Shader
/// without byte code throws ArgumentError #2171 (both measured on Flash Player 32).
fn shader_fill_style<'gc>(
    activation: &mut Activation<'_, 'gc>,
    drawing: &mut Drawing,
    shader: Object<'gc>,
    matrix: Option<Object<'gc>>,
) -> Result<FillStyle, Error<'gc>> {
    let has_shader = shader
        .get_slot(shader_slots::_DATA)
        .as_object()
        .and_then(|data| data.as_shader_data())
        .is_some_and(|data| data.pixel_bender_shader().is_some());
    if !has_shader {
        // Flash Player 32: ArgumentError #2171 "The Shader object contains no byte code".
        return Err(make_error_2171(activation));
    }
    let (handle, arguments) = get_shader_args(shader, activation)?;
    let matrix = matrix
        .map(|matrix| Matrix::from(object_to_matrix(matrix)))
        .unwrap_or(Matrix::IDENTITY);
    let shader_root = stash_object(activation, shader);
    Ok(drawing.add_shader_fill(handle, arguments, matrix, Some(shader_root)))
}

/// Implements `Graphics.beginShaderFill`.
///
/// Timffle: the shader is evaluated once over the fill's bounds when the shape is first
/// rendered and used as a (non-repeating) bitmap fill; see `Drawing::add_shader_fill`.
pub fn begin_shader_fill<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();
    let shader = args.get_object(activation, 0, "shader")?;
    let matrix = args.try_get_object(1);
    if let Some(this) = this.as_display_object()
        && let Some(mut draw) = this.as_drawing()
    {
        let style = shader_fill_style(activation, &mut draw, shader, matrix)?;
        draw.set_fill_style(Some(style));
    }
    Ok(Value::Undefined)
}

/// Implements `Graphics.lineShaderStyle` (same evaluation as `beginShaderFill`, used as
/// the stroke's fill).
pub fn line_shader_style<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();
    let shader = args.get_object(activation, 0, "shader")?;
    let matrix = args.try_get_object(1);
    if let Some(this) = this.as_display_object()
        && let Some(mut draw) = this.as_drawing()
    {
        let style = shader_fill_style(activation, &mut draw, shader, matrix)?;
        draw.set_line_fill_style(style);
    }
    Ok(Value::Undefined)
}
