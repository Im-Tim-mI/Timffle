use crate::avm2::error::make_error_2189;
use crate::avm2::function::FunctionArgs;
use crate::avm2::globals::slots::flash_geom_color_transform as ct_slots;
use crate::avm2::globals::slots::flash_geom_matrix as matrix_slots;
use crate::avm2::globals::slots::flash_geom_perspective_projection as pp_slots;
use crate::avm2::globals::slots::flash_geom_point as point_slots;
use crate::avm2::globals::slots::flash_geom_transform as transform_slots;
use crate::avm2::object::Matrix3DObject;
use crate::avm2::parameters::ParametersExt;
use crate::avm2::{Activation, Error, Object, TObject as _, Value};
use crate::display_object::{BoundsMode, TDisplayObject};
use crate::prelude::{DisplayObject, Matrix, Twips};
use ruffle_render::matrix3d::Matrix3D;
use ruffle_render::perspective_projection::PerspectiveProjection;
use ruffle_render::quality::StageQuality;
use swf::{ColorTransform, Fixed8, Rectangle};

fn get_display_object(this: Object<'_>) -> DisplayObject<'_> {
    this.get_slot(transform_slots::DISPLAY_OBJECT)
        .as_object()
        .unwrap()
        .as_display_object()
        .unwrap()
}

pub fn get_color_transform<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    let color_transform = color_transform_from_transform_object(this);
    color_transform_to_object(&color_transform, activation)
}

pub fn set_color_transform<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    let ct = args.get_object(activation, 0, "colorTransform")?;
    let ct = object_to_color_transform(ct);

    let dobj = get_display_object(this);
    dobj.set_color_transform(ct);
    dobj.set_transformed_by_script(true);
    if let Some(parent) = dobj.parent() {
        parent.invalidate_cached_bitmap();
    }
    Ok(Value::Undefined)
}

pub fn get_matrix<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if get_display_object(this).base().has_matrix3d() {
        Ok(Value::Null)
    } else {
        let matrix = matrix_from_transform_object(this);
        matrix_to_object(matrix, activation)
    }
}

pub fn set_matrix<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    let dobj = get_display_object(this);
    let Some(obj) = args.try_get_object(0) else {
        // `null`: the object becomes 3D (with the position and scale it has)
        dobj.set_z(dobj.z());
        return Ok(Value::Undefined);
    };

    let matrix = object_to_matrix(obj);
    dobj.set_matrix(matrix);
    dobj.set_transformed_by_script(true);
    if let Some(parent) = dobj.parent() {
        // Self-transform changes are automatically handled,
        // we only want to inform ancestors to avoid unnecessary invalidations for tx/ty
        parent.invalidate_cached_bitmap();
    }
    Ok(Value::Undefined)
}

pub fn get_concatenated_matrix<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    let dobj = get_display_object(this);
    if dobj.base().has_matrix3d() {
        // A 3D object has no 2D matrix.
        return Ok(Value::Null);
    }
    let mut node = Some(dobj);
    while let Some(obj) = node {
        if obj.as_stage().is_some() {
            break;
        }
        node = obj.parent();
    }

    // We're a child of the Stage, and not the stage itself
    if node.is_some() && dobj.as_stage().is_none() {
        let matrix = concatenated_2d_matrix(dobj);
        matrix_to_object(matrix, activation)
    } else {
        // If this object is the Stage itself, or an object
        // that's not a child of the stage, then we need to mimic
        // Flash's bizarre behavior.
        let scale = match activation.context.stage.quality() {
            StageQuality::Low => 20.0,
            StageQuality::Medium => 10.0,
            StageQuality::High | StageQuality::Best => 5.0,
            StageQuality::High8x8 | StageQuality::High8x8Linear => 2.5,
            StageQuality::High16x16 | StageQuality::High16x16Linear => 1.25,
        };

        let mut mat = dobj.base().matrix();
        mat.a *= scale;
        mat.d *= scale;

        matrix_to_object(mat, activation)
    }
}

pub fn matrix3d_from_transform_object(transform_object: Object<'_>) -> Option<Matrix3D> {
    get_display_object(transform_object).base().matrix3d()
}

/// The product of the 2D matrices from the stage down to the object. Like in Flash Player, 3D objects above it
/// do not contribute.
fn concatenated_2d_matrix(dobj: DisplayObject<'_>) -> Matrix {
    let mut matrix = dobj.base().matrix();
    let mut node = dobj.parent();
    while let Some(ancestor) = node {
        if ancestor.as_stage().is_some() {
            break;
        }
        if let Some(rect) = ancestor.scroll_rect() {
            matrix = Matrix::translate(-rect.x_min, -rect.y_min) * matrix;
        }
        if !ancestor.base().has_matrix3d() {
            matrix = ancestor.base().matrix() * matrix;
        }
        node = ancestor.parent();
    }
    matrix
}

pub fn matrix_from_transform_object(transform_object: Object<'_>) -> Matrix {
    get_display_object(transform_object).base().matrix()
}

pub fn color_transform_from_transform_object(transform_object: Object<'_>) -> ColorTransform {
    get_display_object(transform_object)
        .base()
        .color_transform()
}

// FIXME - handle clamping. We're throwing away precision here in converting to an integer:
// is that what we should be doing?
pub fn object_to_color_transform<'gc>(object: Object<'gc>) -> ColorTransform {
    let red_multiplier = object.get_slot(ct_slots::RED_MULTIPLIER).as_f64();
    let green_multiplier = object.get_slot(ct_slots::GREEN_MULTIPLIER).as_f64();
    let blue_multiplier = object.get_slot(ct_slots::BLUE_MULTIPLIER).as_f64();
    let alpha_multiplier = object.get_slot(ct_slots::ALPHA_MULTIPLIER).as_f64();
    let red_offset = object.get_slot(ct_slots::RED_OFFSET).as_f64();
    let green_offset = object.get_slot(ct_slots::GREEN_OFFSET).as_f64();
    let blue_offset = object.get_slot(ct_slots::BLUE_OFFSET).as_f64();
    let alpha_offset = object.get_slot(ct_slots::ALPHA_OFFSET).as_f64();

    ColorTransform {
        r_multiply: Fixed8::from_f64(red_multiplier),
        g_multiply: Fixed8::from_f64(green_multiplier),
        b_multiply: Fixed8::from_f64(blue_multiplier),
        a_multiply: Fixed8::from_f64(alpha_multiplier),
        r_add: red_offset as i16,
        g_add: green_offset as i16,
        b_add: blue_offset as i16,
        a_add: alpha_offset as i16,
    }
}

pub fn color_transform_to_object<'gc>(
    color_transform: &ColorTransform,
    activation: &mut Activation<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let args = [
        color_transform.r_multiply.to_f64().into(),
        color_transform.g_multiply.to_f64().into(),
        color_transform.b_multiply.to_f64().into(),
        color_transform.a_multiply.to_f64().into(),
        color_transform.r_add.into(),
        color_transform.g_add.into(),
        color_transform.b_add.into(),
        color_transform.a_add.into(),
    ];
    let ct_class = activation.avm2().classes().colortransform;
    let object = ct_class.construct(activation, &args)?;
    Ok(object)
}

pub fn object_to_perspective_projection<'gc>(
    object: Object<'gc>,
    _activation: &mut Activation<'_, 'gc>,
) -> Result<PerspectiveProjection, Error<'gc>> {
    if let Some(display_object) = object.get_slot(pp_slots::DISPLAY_OBJECT).as_object() {
        return Ok(display_object
            .as_display_object()
            .unwrap()
            .base()
            .perspective_projection()
            .unwrap_or_default());
    }

    let fov = object.get_slot(pp_slots::FOV).as_f64();

    let center = object.get_slot(pp_slots::CENTER).as_object().unwrap();
    let x = center.get_slot(point_slots::X).as_f64();
    let y = center.get_slot(point_slots::Y).as_f64();

    Ok(PerspectiveProjection {
        field_of_view: fov,
        center: (x, y),
    })
}

pub fn matrix_to_object<'gc>(
    matrix: Matrix,
    activation: &mut Activation<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let args = [
        matrix.a.into(),
        matrix.b.into(),
        matrix.c.into(),
        matrix.d.into(),
        matrix.tx.to_pixels().into(),
        matrix.ty.to_pixels().into(),
    ];
    let object = activation
        .avm2()
        .classes()
        .matrix
        .construct(activation, &args)?;
    Ok(object)
}

pub fn object_to_matrix<'gc>(object: Object<'gc>) -> Matrix {
    let a = object.get_slot(matrix_slots::A).as_f64() as f32;
    let b = object.get_slot(matrix_slots::B).as_f64() as f32;
    let c = object.get_slot(matrix_slots::C).as_f64() as f32;
    let d = object.get_slot(matrix_slots::D).as_f64() as f32;
    let tx = Twips::from_pixels(object.get_slot(matrix_slots::TX).as_f64());
    let ty = Twips::from_pixels(object.get_slot(matrix_slots::TY).as_f64());

    Matrix { a, b, c, d, tx, ty }
}

pub fn get_pixel_bounds<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    let display_object = get_display_object(this);
    if display_object.base().has_matrix3d() {
        // Flash Player reports the untransformed bounds for a 3D object.
        return rectangle_to_object(display_object.bounds(BoundsMode::Script), activation);
    }
    rectangle_to_object(display_object.pixel_bounds(BoundsMode::Script), activation)
}

fn rectangle_to_object<'gc>(
    rectangle: Rectangle<Twips>,
    activation: &mut Activation<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let object = activation.avm2().classes().rectangle.construct(
        activation,
        &[
            rectangle.x_min.to_pixels().into(),
            rectangle.y_min.to_pixels().into(),
            rectangle.width().to_pixels().into(),
            rectangle.height().to_pixels().into(),
        ],
    )?;
    Ok(object)
}

pub fn get_matrix_3d<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    let display_object = get_display_object(this);
    match display_object.base().matrix3d() {
        Some(matrix3d) => {
            // The matrix is a live view of the object's own.
            let object = Matrix3DObject::new(activation.context, matrix3d);
            object.bind_to(activation.context, display_object);
            Ok(object.into())
        }
        None => Ok(Value::Null),
    }
}

pub fn set_matrix_3d<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    let display_object = get_display_object(this);
    match args.try_get_object(0) {
        Some(obj) => {
            let matrix3d = obj.as_matrix3d_object().unwrap();
            if let Some(owner) = matrix3d.owner()
                && !DisplayObject::ptr_eq(owner, display_object)
                && owner.base().has_matrix3d()
            {
                return Err(make_error_2189(activation));
            }
            display_object.base().set_matrix3d(Some(matrix3d.matrix()));
            matrix3d.bind_to(activation.context, display_object);
        }
        None => display_object.base().set_matrix3d(None),
    }
    if let Some(parent) = display_object.parent() {
        parent.invalidate_cached_bitmap();
    }

    Ok(Value::Undefined)
}

pub fn get_perspective_projection<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    if get_display_object(this)
        .base()
        .perspective_projection()
        .is_some()
    {
        let object = activation
            .avm2()
            .classes()
            .perspectiveprojection
            .construct(activation, &[])?
            .as_object()
            .unwrap();

        object.set_slot(
            pp_slots::DISPLAY_OBJECT,
            this.get_slot(transform_slots::DISPLAY_OBJECT),
            activation,
        )?;
        Ok(object.into())
    } else {
        Ok(Value::Null)
    }
}

pub fn set_perspective_projection<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    let perspective_projection = args
        .try_get_object(0)
        .map(|object| object_to_perspective_projection(object, activation))
        .transpose()?;

    get_display_object(this).set_perspective_projection(perspective_projection);

    Ok(Value::Undefined)
}

pub fn get_relative_matrix_3d<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap();

    let relative_to = args.get_object(activation, 0, "relativeTo")?;

    let display_object = get_display_object(this);
    if !display_object.base().has_matrix3d() {
        return Ok(Value::Null);
    }
    let Some(target) = relative_to.as_display_object() else {
        return Ok(Value::Null);
    };

    // The matrix that takes this object's space to the target's, no projection involved.
    let to_stage = display_object.matrix3d_to_stage().to_matrix3d();
    let target_to_stage = target.matrix3d_to_stage().to_matrix3d();
    let mut relative = match target_to_stage.invert() {
        Some(inverse) => inverse.multiply(&to_stage),
        None => to_stage,
    };
    if target.as_stage().is_some() {
        // Relative to the stage, Flash Player scales x and y by what it uses for the stage's own matrix.
        let scale = match activation.context.stage.quality() {
            StageQuality::Low => 20.0,
            StageQuality::Medium => 10.0,
            StageQuality::High | StageQuality::Best => 5.0,
            StageQuality::High8x8 | StageQuality::High8x8Linear => 2.5,
            StageQuality::High16x16 | StageQuality::High16x16Linear => 1.25,
        };
        for column in 0..4 {
            relative.raw_data[column * 4] /= scale;
            relative.raw_data[column * 4 + 1] /= scale;
        }
    }
    Ok(Matrix3DObject::new(activation.context, relative).into())
}
