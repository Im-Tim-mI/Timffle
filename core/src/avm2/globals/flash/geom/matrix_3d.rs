use crate::avm2::error::{Error2004Type, make_error_2004, make_error_2183, make_error_2187};
use crate::avm2::function::FunctionArgs;
use crate::avm2::globals::slots::flash_geom_vector_3d as vector3d_slots;
use crate::avm2::object::{Matrix3DObject, VectorObject};
use crate::avm2::parameters::ParametersExt;
use crate::avm2::vector::VectorStorage;
use crate::avm2::{Activation, Avm2StrRepresentable as _, Error, Object, TObject as _, Value};
use num_traits::Zero;
use ruffle_macros::Avm2Enum;
use ruffle_render::matrix3d::Matrix3D;

pub use crate::avm2::object::matrix_3d_allocator;

/// A 4x4 matrix, stored in column-major order, like `Matrix3D.rawData`.
type RawData = [f32; 16];

/// A value of `flash.geom.Orientation3D`, as passed to `recompose`.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Avm2Enum)]
enum Orientation3D {
    #[avm2_variant("eulerAngles")]
    EulerAngles,
    #[avm2_variant("axisAngle")]
    AxisAngle,
    #[avm2_variant("quaternion")]
    Quaternion,
}

/// Reads the `x`, `y`, `z` and `w` components of a `Vector3D`, or `None` if it's null.
pub(super) fn read_vector3d(vector: Object<'_>) -> [f64; 4] {
    [
        vector.get_slot(vector3d_slots::X).as_f64(),
        vector.get_slot(vector3d_slots::Y).as_f64(),
        vector.get_slot(vector3d_slots::Z).as_f64(),
        vector.get_slot(vector3d_slots::W).as_f64(),
    ]
}

/// Same as [`read_vector3d`] but accepts a value.
fn read_vector3d_value(value: Option<Value<'_>>) -> Option<[f64; 4]> {
    let object = value?.as_object()?;
    Some(read_vector3d(object))
}

/// Creates a `Vector3D` with the given components.
pub(super) fn vector3d_to_object<'gc>(
    activation: &mut Activation<'_, 'gc>,
    components: [f64; 4],
) -> Value<'gc> {
    let [x, y, z, w] = components;

    activation
        .avm2()
        .classes()
        .vector3d
        .construct(activation, &[x.into(), y.into(), z.into(), w.into()])
        .unwrap()
}

pub fn get_raw_data<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap().as_matrix3d_object().unwrap();

    let number = activation.avm2().class_defs().number;
    let storage = VectorStorage::from_values(
        this.matrix_ref()
            .raw_data
            .iter()
            .map(|value| (*value).into())
            .collect(),
        false,
        Some(number),
    );

    Ok(VectorObject::from_vector(storage, activation).into())
}

/// Implements `Matrix3D.rawData`'s setter.
pub fn set_raw_data<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap().as_matrix3d_object().unwrap();
    let Some(value) = args.try_get_object(0) else {
        return Ok(Value::Undefined);
    };
    let value = value.as_vector_storage().unwrap();
    if value.length() != 16 {
        return Ok(Value::Undefined);
    }

    let raw_data: RawData =
        std::array::from_fn(|i| value.get_optional(i).map(|v| v.as_f64() as f32).unwrap());

    this.replace_matrix(Matrix3D { raw_data });

    Ok(Value::Undefined)
}

/// Implements `Matrix3D.identity`.
pub fn identity<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap().as_matrix3d_object().unwrap();

    this.replace_matrix(Matrix3D::IDENTITY);

    Ok(Value::Undefined)
}

/// Implements `Matrix3D.appendTranslation`.
pub fn append_translation<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap().as_matrix3d_object().unwrap();
    let x = args.get_f64(0);
    let y = args.get_f64(1);
    let z = args.get_f64(2);

    let mut matrix = this.matrix_mut();
    matrix.raw_data[12] += x as f32;
    matrix.raw_data[13] += y as f32;
    matrix.raw_data[14] += z as f32;

    Ok(Value::Undefined)
}

/// Implements `Matrix3D.appendScale`.
pub fn append_scale<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap().as_matrix3d_object().unwrap();
    let x = args.get_f64(0);
    let y = args.get_f64(1);
    let z = args.get_f64(2);

    if x.is_zero() || y.is_zero() || z.is_zero() {
        return Err(make_error_2183(activation));
    }

    let scale = Matrix3D::scale(x as f32, y as f32, z as f32);
    let result = scale.multiply(&this.matrix_ref());
    this.replace_matrix(result);

    Ok(Value::Undefined)
}

/// Implements `Matrix3D.append`.
pub fn append<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap().as_matrix3d_object().unwrap();
    let lhs = args
        .get_object(activation, 0, "lhs")?
        .as_matrix3d_object()
        .unwrap();

    let result = lhs.matrix_ref().multiply(&this.matrix_ref());
    this.replace_matrix(result);

    Ok(Value::Undefined)
}

/// Implements `Matrix3D.prepend`.
pub fn prepend<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap().as_matrix3d_object().unwrap();
    let rhs = args
        .get_object(activation, 0, "rhs")?
        .as_matrix3d_object()
        .unwrap();

    let result = this.matrix_ref().multiply(&rhs.matrix_ref());
    this.replace_matrix(result);

    Ok(Value::Undefined)
}

/// Implements `Matrix3D.prependTranslation`.
pub fn prepend_translation<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap().as_matrix3d_object().unwrap();
    let x = args.get_f64(0);
    let y = args.get_f64(1);
    let z = args.get_f64(2);

    let translation = Matrix3D::translate(x as f32, y as f32, z as f32);
    let result = this.matrix_ref().multiply(&translation);
    this.replace_matrix(result);

    Ok(Value::Undefined)
}

/// Implements `Matrix3D.prependScale`.
pub fn prepend_scale<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap().as_matrix3d_object().unwrap();
    let x = args.get_f64(0);
    let y = args.get_f64(1);
    let z = args.get_f64(2);

    if x.is_zero() || y.is_zero() || z.is_zero() {
        return Err(make_error_2183(activation));
    }

    let scale = Matrix3D::scale(x as f32, y as f32, z as f32);
    let result = this.matrix_ref().multiply(&scale);
    this.replace_matrix(result);

    Ok(Value::Undefined)
}

/// Implements `Matrix3D.appendRotation`.
///
/// Based on OpenFL: https://github.com/openfl/openfl/blob/971a4c9e43b5472fd84d73920a2b7c1b3d8d9257/src/openfl/geom/Matrix3D.hx
pub fn append_rotation<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap().as_matrix3d_object().unwrap();
    let degrees = args.get_f64(0);
    let axis = args.get_object(activation, 1, "axis")?;
    let pivot_point = args.try_get_object(2);

    let [tx, ty, tz, _] = if let Some(pivot_point) = pivot_point {
        read_vector3d(pivot_point)
    } else {
        [0.0, 0.0, 0.0, 0.0]
    };

    let radian = degrees * std::f64::consts::PI / 180.0;
    let cos = radian.cos();
    let sin = radian.sin();

    let [mut x, mut y, mut z, _] = read_vector3d(axis);
    let mut x2 = x * x;
    let mut y2 = y * y;
    let mut z2 = z * z;
    // Flash Player measures the axis in single precision: tiny axes count as zero, and a zero axis yields
    // `cos(angle) * I` instead of a degenerate matrix.
    let ls32 = (x as f32) * (x as f32) + (y as f32) * (y as f32) + (z as f32) * (z as f32);
    let ls = x2 + y2 + z2;

    if ls32 != 0.0 && ls32.is_finite() {
        let l = ls.sqrt();
        x /= l;
        y /= l;
        z /= l;
        x2 /= ls;
        y2 /= ls;
        z2 /= ls;
    } else if ls32 == 0.0 {
        (x, y, z, x2, y2, z2) = (0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
    }

    let ccos = 1.0 - cos;

    // The rotation part, then the translation that keeps the pivot point in place: `pivot - R * pivot`.
    #[rustfmt::skip]
    let r = [
        cos + x2 * ccos,
        x * y * ccos + z * sin,
        x * z * ccos - y * sin,
        x * y * ccos - z * sin,
        cos + y2 * ccos,
        y * z * ccos + x * sin,
        x * z * ccos + y * sin,
        y * z * ccos - x * sin,
        cos + z2 * ccos,
    ];

    #[rustfmt::skip]
    let m: RawData = [
        r[0], r[1], r[2], 0.0,
        r[3], r[4], r[5], 0.0,
        r[6], r[7], r[8], 0.0,
        tx - (r[0] * tx + r[3] * ty + r[6] * tz),
        ty - (r[1] * tx + r[4] * ty + r[7] * tz),
        tz - (r[2] * tx + r[5] * ty + r[8] * tz),
        1.0,
    ].map(|f| f as f32);

    let result = Matrix3D { raw_data: m }.multiply(&this.matrix_ref());
    this.replace_matrix(result);

    Ok(Value::Undefined)
}

/// Implements `Matrix3D.copyColumnTo`.
pub fn copy_column_to<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap().as_matrix3d_object().unwrap();
    let column = args.get_u32(0);
    let vector3d = args.get_object(activation, 1, "vector3D")?;

    if column > 3 {
        return Err(make_error_2004(activation, Error2004Type::ArgumentError));
    }

    let raw_data = this.matrix_ref().raw_data;
    let base = column as usize * 4;

    vector3d.set_slot(vector3d_slots::X, raw_data[base].into(), activation)?;
    vector3d.set_slot(vector3d_slots::Y, raw_data[base + 1].into(), activation)?;
    vector3d.set_slot(vector3d_slots::Z, raw_data[base + 2].into(), activation)?;
    vector3d.set_slot(vector3d_slots::W, raw_data[base + 3].into(), activation)?;

    Ok(Value::Undefined)
}

/// Implements `Matrix3D.copyColumnFrom`.
pub fn copy_column_from<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap().as_matrix3d_object().unwrap();
    let column = args.get_u32(0);
    let vector3d = args.get_object(activation, 1, "vector3D")?;

    if column > 3 {
        return Err(make_error_2004(activation, Error2004Type::ArgumentError));
    }

    let [x, y, z, w] = read_vector3d(vector3d);

    let mut matrix = this.matrix_mut();
    let base = column as usize * 4;
    matrix.raw_data[base] = x as f32;
    matrix.raw_data[base + 1] = y as f32;
    matrix.raw_data[base + 2] = z as f32;
    matrix.raw_data[base + 3] = w as f32;

    Ok(Value::Undefined)
}

/// Implements `Matrix3D.copyRowTo`.
pub fn copy_row_to<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap().as_matrix3d_object().unwrap();
    let row = args.get_u32(0);
    let vector3d = args.get_object(activation, 1, "vector3D")?;

    if row > 3 {
        return Err(make_error_2004(activation, Error2004Type::ArgumentError));
    }

    let raw_data = this.matrix_ref().raw_data;
    let base = row as usize;

    vector3d.set_slot(vector3d_slots::X, raw_data[base].into(), activation)?;
    vector3d.set_slot(vector3d_slots::Y, raw_data[base + 4].into(), activation)?;
    vector3d.set_slot(vector3d_slots::Z, raw_data[base + 8].into(), activation)?;
    vector3d.set_slot(vector3d_slots::W, raw_data[base + 12].into(), activation)?;

    Ok(Value::Undefined)
}

/// Implements `Matrix3D.copyRowFrom`.
pub fn copy_row_from<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap().as_matrix3d_object().unwrap();
    let row = args.get_u32(0);
    let vector3d = args.get_object(activation, 1, "vector3D")?;

    if row > 3 {
        return Err(make_error_2004(activation, Error2004Type::ArgumentError));
    }

    let [x, y, z, w] = read_vector3d(vector3d);

    let mut matrix = this.matrix_mut();
    let base = row as usize;
    matrix.raw_data[base] = x as f32;
    matrix.raw_data[base + 4] = y as f32;
    matrix.raw_data[base + 8] = z as f32;
    matrix.raw_data[base + 12] = w as f32;

    Ok(Value::Undefined)
}

/// Implements `Matrix3D.copyFrom`.
pub fn copy_from<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap().as_matrix3d_object().unwrap();
    let source = args
        .get_object(activation, 0, "source")?
        .as_matrix3d_object()
        .unwrap();
    this.replace_matrix(source.matrix());
    Ok(Value::Undefined)
}

/// Implements `Matrix3D.copyRawDataFrom`.
pub fn copy_raw_data_from<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap().as_matrix3d_object().unwrap();
    let source = args.get_object(activation, 0, "source")?;
    let source = source.as_vector_storage().unwrap();
    let index = args.get_u32(1) as usize;
    let do_transpose = args.get_bool(2);

    if index + 16 > source.length() {
        return Err(make_error_2004(activation, Error2004Type::ArgumentError));
    }

    let raw_data: RawData =
        std::array::from_fn(|i| source.get_optional(index + i).unwrap().as_f64() as f32);
    let mut matrix = Matrix3D { raw_data };

    if do_transpose {
        matrix.transpose_in_place();
    }

    this.replace_matrix(matrix);

    Ok(Value::Undefined)
}

/// Implements `Matrix3D.copyRawDataTo`.
pub fn copy_raw_data_to<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap().as_matrix3d_object().unwrap();
    let dest = args
        .get_object(activation, 0, "dest")?
        .as_vector_object()
        .unwrap();
    let index = args.get_u32(1) as usize;
    let do_transpose = args.get_bool(2);

    let mut storage = dest.storage_mut(activation.gc());
    if index + 16 > storage.length() {
        storage.resize(index + 16, activation)?;
    }

    let mut matrix = this.matrix();
    if do_transpose {
        matrix.transpose_in_place();
    }

    for (i, value) in matrix.raw_data.into_iter().enumerate() {
        storage.set(index + i, value.into(), activation)?;
    }

    Ok(Value::Undefined)
}

/// Implements `Matrix3D.copyToMatrix3D`.
pub fn copy_to_matrix_3d<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap().as_matrix3d_object().unwrap();
    let dest = args
        .get_object(activation, 0, "dest")?
        .as_matrix3d_object()
        .unwrap();
    dest.replace_matrix(this.matrix());
    Ok(Value::Undefined)
}

/// Implements `Matrix3D.clone`.
pub fn clone<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap().as_matrix3d_object().unwrap();
    Ok(Matrix3DObject::new(activation.context, this.matrix()).into())
}

/// Implements `Matrix3D.position`'s getter.
pub fn get_position<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap().as_matrix3d_object().unwrap();
    let mr = this.matrix_ref().raw_data;

    Ok(vector3d_to_object(
        activation,
        [mr[12] as f64, mr[13] as f64, mr[14] as f64, 0.0],
    ))
}

/// Implements `Matrix3D.position`'s setter.
pub fn set_position<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap().as_matrix3d_object().unwrap();
    let Some(val) = args.try_get_object(0) else {
        return Ok(Value::Undefined);
    };

    let [x, y, z, _] = read_vector3d(val);

    let mut matrix = this.matrix_mut();
    matrix.raw_data[12] = x as f32;
    matrix.raw_data[13] = y as f32;
    matrix.raw_data[14] = z as f32;

    Ok(Value::Undefined)
}

/// Implements `Matrix3D.transpose`.
pub fn transpose<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap().as_matrix3d_object().unwrap();
    this.matrix_mut().transpose_in_place();
    Ok(Value::Undefined)
}

/// Implements `Matrix3D.deltaTransformVector`.
pub fn delta_transform_vector<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap().as_matrix3d_object().unwrap();
    let v = args.get_object(activation, 0, "vector")?;

    let mr = this.matrix_ref().raw_data;
    let [x, y, z, _] = read_vector3d(v);

    // deltaTransformVector() casts the vector to f32 first, losing accuracy, and (measured on Flash Player) is
    // transformVector() minus the translation, in single precision.
    let transformed = transform_point(&mr, x as f32, y as f32, z as f32);
    let delta = [
        transformed[0] - mr[12],
        transformed[1] - mr[13],
        transformed[2] - mr[14],
        transformed[3] - mr[15],
    ];

    Ok(vector3d_to_object(activation, delta.map(|f| f as f64)))
}

/// `matrix * (x, y, z, 1)` as Flash Player's `transformVector()` computes it: the products and their sum are exact
/// to double precision, and rounded to f32 once (measured: all of 60 random samples match bit for bit).
pub fn transform_point(mr: &RawData, x: f32, y: f32, z: f32) -> [f32; 4] {
    let (x, y, z) = (f64::from(x), f64::from(y), f64::from(z));
    [0, 1, 2, 3].map(|r| {
        (f64::from(mr[r]) * x
            + f64::from(mr[4 + r]) * y
            + f64::from(mr[8 + r]) * z
            + f64::from(mr[12 + r])) as f32
    })
}

/// Implements `Matrix3D.transformVector`.
pub fn transform_vector<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap().as_matrix3d_object().unwrap();
    let v = args.get_object(activation, 0, "vector")?;

    let mr = this.matrix_ref().raw_data;
    let [x, y, z, _] = read_vector3d(v);

    // transformVector() casts the vector to f32 first, losing accuracy.
    let transformed = transform_point(&mr, x as f32, y as f32, z as f32);

    Ok(vector3d_to_object(
        activation,
        transformed.map(|f| f as f64),
    ))
}

/// Implements `Matrix3D.transformVectors`.
pub fn transform_vectors<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap().as_matrix3d_object().unwrap();
    let vin = args
        .get_object(activation, 0, "vin")?
        .as_vector_object()
        .unwrap();
    let vout = args
        .get_object(activation, 1, "vout")?
        .as_vector_object()
        .unwrap();

    let vin_length = vin.storage().length();
    let vout_length = vout.storage().length();
    let result_vecs_length = (vin_length / 3) * 3;

    if result_vecs_length > vout_length {
        vout.storage_mut(activation.gc())
            .resize(result_vecs_length, activation)?;
    }

    // transformVectors(), in contrast to transformVector() or
    // deltaTransformVector(), uses 64-bit operations with higher precision.
    let mr = this.matrix_ref().raw_data.map(|f| f as f64);

    // 'vin' and 'vout' may be the same object, so borrows of their storage
    // are scoped to a single access, never held across a read and a write.
    let mut i = 0;
    while i < result_vecs_length {
        let (x, y, z) = {
            let storage = vin.storage();
            (
                storage.get(i, activation)?.as_f64(),
                storage.get(i + 1, activation)?.as_f64(),
                storage.get(i + 2, activation)?.as_f64(),
            )
        };

        let result = [
            mr[0] * x + mr[4] * y + mr[8] * z + mr[12],
            mr[1] * x + mr[5] * y + mr[9] * z + mr[13],
            mr[2] * x + mr[6] * y + mr[10] * z + mr[14],
        ];

        let mut storage = vout.storage_mut(activation.gc());
        for (offset, value) in result.into_iter().enumerate() {
            storage.set(i + offset, value.into(), activation)?;
        }

        i += 3;
    }

    Ok(Value::Undefined)
}

/// Implements `Matrix3D.determinant`'s getter.
pub fn get_determinant<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap().as_matrix3d_object().unwrap();
    Ok(this.matrix_ref().determinant().into())
}

/// Implements `Matrix3D.invert`.
pub fn invert<'gc>(
    _activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    _args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap().as_matrix3d_object().unwrap();
    let Some(result) = this.matrix_ref().invert() else {
        return Ok(false.into());
    };

    this.replace_matrix(result);

    Ok(true.into())
}

/// Implements `Matrix3D.recompose`.
///
/// Based on OpenFL: https://github.com/openfl/openfl/blob/971a4c9e43b5472fd84d73920a2b7c1b3d8d9257/src/openfl/geom/Matrix3D.hx#L1437
pub fn recompose<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap().as_matrix3d_object().unwrap();

    let components = args.get_object(activation, 0, "components")?;
    let components = components.as_vector_storage().unwrap();

    let orientation = args.get_string_non_null(activation, 1, "orientationStyle")?;
    let Some(orientation) = Orientation3D::from_avm2_str(&orientation) else {
        return Err(make_error_2187(activation, orientation));
    };

    // A null component makes 'recompose' fail, leaving the matrix untouched.
    let (Some(translation), Some(rotation), Some(scale)) = (
        read_vector3d_value(components.get_optional(0)),
        read_vector3d_value(components.get_optional(1)),
        read_vector3d_value(components.get_optional(2)),
    ) else {
        return Ok(false.into());
    };

    let [translation_x, translation_y, translation_z, _] = translation.map(|f| f as f32);
    let [rotation_x, rotation_y, rotation_z, rotation_w] = rotation;
    let [scale_x, scale_y, scale_z, _] = scale.map(|f| f as f32);

    let mut rotation_matrix = [0.0; 16];
    match orientation {
        Orientation3D::EulerAngles => {
            let cx = rotation_x.cos();
            let cy = rotation_y.cos();
            let cz = rotation_z.cos();
            let sx = rotation_x.sin();
            let sy = rotation_y.sin();
            let sz = rotation_z.sin();

            rotation_matrix[0] = cy * cz;
            rotation_matrix[1] = cy * sz;
            rotation_matrix[2] = -sy;
            rotation_matrix[4] = sx * sy * cz - cx * sz;
            rotation_matrix[5] = sx * sy * sz + cx * cz;
            rotation_matrix[6] = sx * cy;
            rotation_matrix[8] = cx * sy * cz + sx * sz;
            rotation_matrix[9] = cx * sy * sz - sx * cz;
            rotation_matrix[10] = cx * cy;
        }

        Orientation3D::AxisAngle => {
            // Measured on Flash Player: the axis is normalised in single precision and the angle is divided by
            // the axis' length (`(0, 2, 0, 0.8)` turns by 0.4); a zero axis gives `cos(angle) * I`.
            let (mut x, mut y, mut z, mut angle) = (rotation_x, rotation_y, rotation_z, rotation_w);
            let ls32 = (x as f32) * (x as f32) + (y as f32) * (y as f32) + (z as f32) * (z as f32);
            if ls32 == 0.0 {
                (x, y, z) = (0.0, 0.0, 0.0);
            } else {
                let length = (x * x + y * y + z * z).sqrt();
                x /= length;
                y /= length;
                z /= length;
                angle /= length;
            }
            let cos = angle.cos();
            let sin = angle.sin();
            let ccos = 1.0 - cos;

            rotation_matrix[0] = cos + x * x * ccos;
            rotation_matrix[1] = x * y * ccos + z * sin;
            rotation_matrix[2] = x * z * ccos - y * sin;
            rotation_matrix[4] = x * y * ccos - z * sin;
            rotation_matrix[5] = cos + y * y * ccos;
            rotation_matrix[6] = y * z * ccos + x * sin;
            rotation_matrix[8] = x * z * ccos + y * sin;
            rotation_matrix[9] = y * z * ccos - x * sin;
            rotation_matrix[10] = cos + z * z * ccos;
        }

        Orientation3D::Quaternion => {
            let (x, y, z, w) = (rotation_x, rotation_y, rotation_z, rotation_w);

            // Flash Player only accepts (nearly) unit quaternions: the squared length must be within 1e-5 of 1
            // (measured: `0.99999f ..= 1.00001f`).
            let length_squared = x * x + y * y + z * z + w * w;
            if !(length_squared >= 0.99999_f32 as f64 && length_squared <= 1.00001_f32 as f64) {
                return Err(make_error_2004(activation, Error2004Type::ArgumentError));
            }

            rotation_matrix[0] = 1.0 - 2.0 * y * y - 2.0 * z * z;
            rotation_matrix[1] = 2.0 * x * y + 2.0 * w * z;
            rotation_matrix[2] = 2.0 * x * z - 2.0 * w * y;
            rotation_matrix[4] = 2.0 * x * y - 2.0 * w * z;
            rotation_matrix[5] = 1.0 - 2.0 * x * x - 2.0 * z * z;
            rotation_matrix[6] = 2.0 * y * z + 2.0 * w * x;
            rotation_matrix[8] = 2.0 * x * z + 2.0 * w * y;
            rotation_matrix[9] = 2.0 * y * z - 2.0 * w * x;
            rotation_matrix[10] = 1.0 - 2.0 * x * x - 2.0 * y * y;
        }
    }
    rotation_matrix[15] = 1.0;

    let translation = Matrix3D::translate(translation_x, translation_y, translation_z);
    let rotation = Matrix3D {
        raw_data: rotation_matrix.map(|f| f as f32),
    };
    let scale = Matrix3D::scale(scale_x, scale_y, scale_z);

    // The order of operations is observable when some of the components are not
    // finite.
    let result = translation.multiply(&rotation.multiply(&scale));
    this.replace_matrix(result);

    Ok(true.into())
}

/// Implements `Matrix3D.decompose`.
///
/// Based on OpenFL: https://github.com/openfl/openfl/blob/971a4c9e43b5472fd84d73920a2b7c1b3d8d9257/src/openfl/geom/Matrix3D.hx#L437
pub fn decompose<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap().as_matrix3d_object().unwrap();

    let orientation = args.get_string_non_null(activation, 0, "orientationStyle")?;
    let Some(orientation) = Orientation3D::from_avm2_str(&orientation) else {
        return Err(make_error_2187(activation, orientation));
    };

    let mut mr = this.matrix_ref().raw_data.map(|f| f as f64);

    let translation = [mr[12], mr[13], mr[14], 0.0];

    // Like Flash Player, take the scale and rotation of a matrix with shear by Gram-Schmidt orthogonalisation of
    // its columns (the first column keeps its direction).
    let dot = |a: [f64; 3], b: [f64; 3]| a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
    let c0 = [mr[0], mr[1], mr[2]];
    let c1 = [mr[4], mr[5], mr[6]];
    let c2 = [mr[8], mr[9], mr[10]];
    let scale_x = dot(c0, c0).sqrt();
    let u0 = c0.map(|v| v / scale_x);
    let d1 = dot(c1, u0);
    let t1 = [c1[0] - d1 * u0[0], c1[1] - d1 * u0[1], c1[2] - d1 * u0[2]];
    let scale_y = dot(t1, t1).sqrt();
    let u1 = t1.map(|v| v / scale_y);
    let (d2a, d2b) = (dot(c2, u0), dot(c2, u1));
    let t2 = [
        c2[0] - d2a * u0[0] - d2b * u1[0],
        c2[1] - d2a * u0[1] - d2b * u1[1],
        c2[2] - d2a * u0[2] - d2b * u1[2],
    ];
    let mut scale_z = dot(t2, t2).sqrt();
    let mut u2 = t2.map(|v| v / scale_z);
    let cross = [
        u0[1] * u1[2] - u0[2] * u1[1],
        u0[2] * u1[0] - u0[0] * u1[2],
        u0[0] * u1[1] - u0[1] * u1[0],
    ];
    if dot(cross, u2) < 0.0 {
        scale_z = -scale_z;
        u2 = u2.map(|v| -v);
    }
    mr[0..3].copy_from_slice(&u0);
    mr[4..7].copy_from_slice(&u1);
    mr[8..11].copy_from_slice(&u2);

    let mut rotation = [0.0; 4];

    match orientation {
        Orientation3D::AxisAngle | Orientation3D::Quaternion => {
            let trace = mr[0] + mr[5] + mr[10];

            if trace > 0.0 {
                rotation[3] = (1.0 + trace).sqrt() / 2.0;

                rotation[0] = (mr[6] - mr[9]) / (4.0 * rotation[3]);
                rotation[1] = (mr[8] - mr[2]) / (4.0 * rotation[3]);
                rotation[2] = (mr[1] - mr[4]) / (4.0 * rotation[3]);
            } else if mr[0] > mr[5] && mr[0] > mr[10] {
                rotation[0] = (1.0 + mr[0] - mr[5] - mr[10]).sqrt() / 2.0;

                rotation[3] = (mr[6] - mr[9]) / (4.0 * rotation[0]);
                rotation[1] = (mr[1] + mr[4]) / (4.0 * rotation[0]);
                rotation[2] = (mr[8] + mr[2]) / (4.0 * rotation[0]);
            } else if mr[5] > mr[10] {
                rotation[1] = (1.0 + mr[5] - mr[0] - mr[10]).sqrt() / 2.0;

                rotation[0] = (mr[1] + mr[4]) / (4.0 * rotation[1]);
                rotation[3] = (mr[8] - mr[2]) / (4.0 * rotation[1]);
                rotation[2] = (mr[6] + mr[9]) / (4.0 * rotation[1]);
            } else {
                rotation[2] = (1.0 + mr[10] - mr[0] - mr[5]).sqrt() / 2.0;

                rotation[0] = (mr[8] + mr[2]) / (4.0 * rotation[2]);
                rotation[1] = (mr[6] + mr[9]) / (4.0 * rotation[2]);
                rotation[3] = (mr[1] - mr[4]) / (4.0 * rotation[2]);
            }

            if orientation == Orientation3D::AxisAngle {
                // Flash Player derives the axis and angle from the quaternion above, whose sign it does not
                // normalise: the angle is `2 * acos(w)`, i.e. up to a whole turn.
                let [x, y, z, w] = rotation;
                let sin_half = (x * x + y * y + z * z).sqrt();
                rotation[3] = 2.0 * w.clamp(-1.0, 1.0).acos();
                if sin_half != 0.0 {
                    rotation[0] = x / sin_half;
                    rotation[1] = y / sin_half;
                    rotation[2] = z / sin_half;
                } else {
                    rotation[0] = 0.0;
                    rotation[1] = 0.0;
                    rotation[2] = 0.0;
                }
            }
        }

        Orientation3D::EulerAngles => {
            rotation[1] = (-mr[2]).asin();

            if mr[2] != 1.0 && mr[2] != -1.0 {
                rotation[0] = mr[6].atan2(mr[10]);
                rotation[2] = mr[1].atan2(mr[0]);
            } else {
                rotation[2] = 0.0;
                rotation[0] = mr[4].atan2(mr[5]);
            }
        }
    }

    // NOTE: It looks like Flash Player returns uninitialized values here when
    // it doesn't write to a certain component, e.g. rotation.w in case of
    // "eulerAngles". Take this into account when testing.
    let components = [
        vector3d_to_object(activation, translation),
        vector3d_to_object(activation, rotation),
        vector3d_to_object(activation, [scale_x, scale_y, scale_z, 0.0]),
    ];

    let vector3d = activation
        .avm2()
        .classes()
        .vector3d
        .inner_class_definition();
    let storage = VectorStorage::from_values(components.to_vec(), false, Some(vector3d));

    Ok(VectorObject::from_vector(storage, activation).into())
}

type V = [f64; 3];

fn dot3(a: V, b: V) -> f64 {
    a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
}

fn cross3(a: V, b: V) -> V {
    [
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    ]
}

fn unit3(a: V) -> V {
    let length = dot3(a, a).sqrt();
    a.map(|v| v / length)
}

/// The two orthonormal frames of `Matrix3D.pointAt`, or why there are none.
enum Frames {
    /// Flash Player leaves the matrix alone: no direction to `pos`, `at` or `up` is zero or they are parallel (to
    /// the world's up, for the direction).
    Degenerate,
    /// A vector is not finite.
    NotFinite,
    /// `(world, object)`: the frames `(d, w1, w2)` of the direction to `pos` and `(a0, a1, a2)` of `at` and `up`.
    Frames([V; 3], [V; 3]),
}

/// Builds the frames `Matrix3D.pointAt` aligns, from the translation of the matrix and `pos`, `at`, `up`.
///
/// Measured on Flash Player, in single precision: the direction `d` to `pos`; `w2 = d x worldUp` (the world's up
/// is (0, -1, 0)) and `w1 = w2 x d`; `a0` is `at` (default +Y), `a2 = at x up` (default +Z) and `a1 = a2 x a0`.
fn pointing_frames(translation: [f32; 3], pos: [f32; 3], at: [f32; 3], up: [f32; 3]) -> Frames {
    if pos.iter().chain(&at).chain(&up).any(|v| !v.is_finite()) {
        return Frames::NotFinite;
    }

    let to_v = |a: [f32; 3]| a.map(f64::from);
    let d32 = [
        pos[0] - translation[0],
        pos[1] - translation[1],
        pos[2] - translation[2],
    ];
    let side32 = [d32[2], 0.0, -d32[0]];
    let side_ls = side32[0] * side32[0] + side32[2] * side32[2];
    let d_ls = d32[0] * d32[0] + d32[1] * d32[1] + d32[2] * d32[2];
    if side_ls == 0.0 || !side_ls.is_finite() || !d_ls.is_finite() {
        return Frames::Degenerate;
    }
    let d = unit3(to_v(d32));
    let w2 = unit3(to_v(side32));
    let w1 = cross3(w2, d);

    let at_ls = at.iter().map(|v| v * v).sum::<f32>();
    let side_a32 = cross3(to_v(at), to_v(up)).map(|v| v as f32);
    let side_a_ls = side_a32.iter().map(|v| v * v).sum::<f32>();
    if at_ls == 0.0 || side_a_ls == 0.0 || !at_ls.is_finite() || !side_a_ls.is_finite() {
        return Frames::Degenerate;
    }
    let a0 = unit3(to_v(at));
    let a2 = unit3(to_v(side_a32));
    let a1 = cross3(a2, a0);

    Frames::Frames([d, w1, w2], [a0, a1, a2])
}

/// Reads the optional `at` and `up` arguments of `pointAt`/`pointTowards` (+Y and +Z by default).
fn pointing_vectors<'gc>(
    pos: Object<'gc>,
    at: Option<Object<'gc>>,
    up: Option<Object<'gc>>,
) -> ([f32; 3], [f32; 3], [f32; 3]) {
    let xyz = |vector: Object<'gc>| {
        let [x, y, z, _] = read_vector3d(vector);
        [x as f32, y as f32, z as f32]
    };
    (
        xyz(pos),
        at.map_or([0.0, 1.0, 0.0], xyz),
        up.map_or([0.0, 0.0, 1.0], xyz),
    )
}

/// Implements `Matrix3D.pointAt`.
///
/// Fitted to measurements of Flash Player (the result matches it to 4 decimals in 100+ probes, including sheared
/// and mirrored matrices). The matrix is split into rotation `Q`, scale `D = diag(sx, sy, sz)` and the shear
/// that is left, `Sh = Q * H * Q^T` with `H = U * D^-1` (`Q * U` being the Gram-Schmidt factorisation of its
/// columns), see [`pointing_frames`] for the frames `W` (world) and `A` (object); the new matrix is
/// `Sh * W * diag(sz, sy, sx) * A^T`: `A` maps the object frame to `W`, and the scale comes back reversed. The
/// translation stays and the projective part is cleared. Degenerate directions leave the matrix unchanged;
/// non-finite inputs and singular matrices turn it into NaNs (or, for a column that is exactly zero, zeros).
pub fn point_at<'gc>(
    activation: &mut Activation<'_, 'gc>,
    this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let this = this.as_object().unwrap().as_matrix3d_object().unwrap();
    let pos = args.get_object(activation, 0, "pos")?;
    let (pos, at, up) = pointing_vectors(pos, args.try_get_object(1), args.try_get_object(2));

    let raw = this.matrix_ref().raw_data;
    let (world, object) = match pointing_frames([raw[12], raw[13], raw[14]], pos, at, up) {
        Frames::Degenerate => return Ok(Value::Undefined),
        Frames::NotFinite => {
            this.replace_matrix(Matrix3D {
                raw_data: [f32::NAN; 16],
            });
            return Ok(Value::Undefined);
        }
        Frames::Frames(world, object) => (world, object),
    };

    // Gram-Schmidt on the columns of the current matrix (a reflection gives a negative `sz`), in single precision
    // like Flash Player, where dependent columns cancel out exactly. A singular matrix poisons its result with
    // NaN.
    type V32 = [f32; 3];
    let dot32 = |a: V32, b: V32| a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
    let cross32 = |a: V32, b: V32| -> V32 {
        [
            a[1] * b[2] - a[2] * b[1],
            a[2] * b[0] - a[0] * b[2],
            a[0] * b[1] - a[1] * b[0],
        ]
    };
    // A zero column (exactly) zeroes the matrix; one whose square underflows poisons it with NaN.
    let singular = |v: V32| Matrix3D {
        raw_data: if v == [0.0; 3] {
            [0.0; 16]
        } else {
            [f32::NAN; 16]
        },
    };
    let c32: [V32; 3] = [
        [raw[0], raw[1], raw[2]],
        [raw[4], raw[5], raw[6]],
        [raw[8], raw[9], raw[10]],
    ];
    let ls0 = dot32(c32[0], c32[0]);
    if ls0 == 0.0 {
        this.replace_matrix(singular(c32[0]));
        return Ok(Value::Undefined);
    }
    let sx = ls0.sqrt();
    let q0 = c32[0].map(|v| v / sx);
    // (Not normalising the first vectors before projecting on them makes dependent columns cancel exactly.)
    let k1 = dot32(c32[1], c32[0]) / ls0;
    let t1: V32 = [0, 1, 2].map(|i| c32[1][i] - k1 * c32[0][i]);
    let ls1 = dot32(t1, t1);
    if ls1 == 0.0 {
        this.replace_matrix(singular(t1));
        return Ok(Value::Undefined);
    }
    let sy = ls1.sqrt();
    let q1 = t1.map(|v| v / sy);
    let (k2a, k2b) = (dot32(c32[2], c32[0]) / ls0, dot32(c32[2], t1) / ls1);
    let t2: V32 = [0, 1, 2].map(|i| c32[2][i] - k2a * c32[0][i] - k2b * t1[i]);
    let ls2 = dot32(t2, t2);
    if ls2 == 0.0 {
        this.replace_matrix(singular(t2));
        return Ok(Value::Undefined);
    }
    let mut sz = ls2.sqrt();
    let mut q2 = t2.map(|v| v / sz);
    if dot32(cross32(q0, q1), q2) < 0.0 {
        q2 = q2.map(|v| -v);
        sz = -sz;
    }
    let (q0, q1, q2) = (q0.map(f64::from), q1.map(f64::from), q2.map(f64::from));
    let (sx, sy, sz) = (f64::from(sx), f64::from(sy), f64::from(sz));
    let c = c32.map(|v| v.map(f64::from));
    let q = [q0, q1, q2]; // columns
    let scale = [sx, sy, sz];

    // H = U * D^-1 (unit upper triangular), U = Q^T * L.
    let u = |row: usize, col: usize| dot3(q[row], c[col]);
    let h = |row: usize, col: usize| u(row, col) / scale[col];
    // Sh = Q * H * Q^T, as a function (row, col) of the world axes.
    let sh = |row: usize, col: usize| {
        let mut sum = 0.0;
        for i in 0..3 {
            for j in i..3 {
                sum += q[i][row] * h(i, j) * q[j][col];
            }
        }
        sum
    };
    // X = W * diag(sz, sy, sx) * A^T, columns are the images of the axes.
    let sigma = [sz, sy, sx];
    let x_col = |col: usize| -> V {
        let mut v = [0.0; 3];
        for k in 0..3 {
            let coefficient = sigma[k] * object[k][col];
            for r in 0..3 {
                v[r] += coefficient * world[k][r];
            }
        }
        v
    };

    let mut result = [0.0f32; 16];
    for col in 0..3 {
        let x = x_col(col);
        for row in 0..3 {
            result[col * 4 + row] = (0..3).map(|k| sh(row, k) * x[k]).sum::<f64>() as f32;
        }
    }
    result[12] = raw[12];
    result[13] = raw[13];
    result[14] = raw[14];
    result[15] = 1.0;

    this.replace_matrix(Matrix3D { raw_data: result });
    Ok(Value::Undefined)
}

/// The rotation quaternion `(x, y, z, w)` that Flash Player reads straight from the upper 3x3 part of a raw
/// matrix, with its scale left in, in `Matrix3D.interpolate` (and so `Utils3D.pointTowards`). Ties between the
/// diagonal elements go to the lowest index (a zero matrix reads as 180 degrees around x).
fn raw_quaternion(m: &RawData) -> [f64; 4] {
    let m = m.map(f64::from);
    let (m00, m10, m20) = (m[0], m[1], m[2]);
    let (m01, m11, m21) = (m[4], m[5], m[6]);
    let (m02, m12, m22) = (m[8], m[9], m[10]);

    let trace = m00 + m11 + m22;
    let (x, y, z, w);
    if trace > 0.0 {
        let s = (trace + 1.0).sqrt() * 2.0;
        w = 0.25 * s;
        x = (m21 - m12) / s;
        y = (m02 - m20) / s;
        z = (m10 - m01) / s;
    } else if m00 >= m11 && m00 >= m22 {
        let s = (1.0 + m00 - m11 - m22).sqrt() * 2.0;
        w = (m21 - m12) / s;
        x = 0.25 * s;
        y = (m01 + m10) / s;
        z = (m02 + m20) / s;
    } else if m11 >= m22 {
        let s = (1.0 + m11 - m00 - m22).sqrt() * 2.0;
        w = (m02 - m20) / s;
        x = (m01 + m10) / s;
        y = 0.25 * s;
        z = (m12 + m21) / s;
    } else {
        let s = (1.0 + m22 - m00 - m11).sqrt() * 2.0;
        w = (m10 - m01) / s;
        x = (m02 + m20) / s;
        y = (m12 + m21) / s;
        z = 0.25 * s;
    }

    let length = (x * x + y * y + z * z + w * w).sqrt();
    if length == 0.0 {
        return [0.0, 0.0, 0.0, 1.0];
    }
    [x / length, y / length, z / length, w / length]
}

/// `Matrix3D.interpolate`: the translations are interpolated linearly, the rotations (see [`raw_quaternion`], the
/// scale is dropped) spherically; `percent` is clamped to 0..1 (a NaN gives NaNs).
pub fn interpolate_raw(from: &RawData, to: &RawData, percent: f64) -> RawData {
    let percent = percent.clamp(0.0, 1.0);

    let q0 = raw_quaternion(from);
    let mut q1 = raw_quaternion(to);
    let translation = [0, 1, 2].map(|i| {
        let a = f64::from(from[12 + i]);
        let b = f64::from(to[12 + i]);
        a + (b - a) * percent
    });

    let mut dot = q0.iter().zip(&q1).map(|(a, b)| a * b).sum::<f64>();
    if dot < 0.0 {
        dot = -dot;
        q1 = q1.map(|v| -v);
    }

    let (k0, k1) = if dot > 0.9995 {
        (1.0 - percent, percent)
    } else {
        let theta = dot.acos();
        let sin_theta = theta.sin();
        (
            ((1.0 - percent) * theta).sin() / sin_theta,
            (percent * theta).sin() / sin_theta,
        )
    };

    let mut rotation = [0, 1, 2, 3].map(|i| q0[i] * k0 + q1[i] * k1);
    let mut length = rotation.iter().map(|v| v * v).sum::<f64>().sqrt();
    if length == 0.0 {
        rotation = [0.0, 0.0, 0.0, 1.0];
        length = 1.0;
    }
    let [x, y, z, w] = rotation.map(|v| v / length);

    #[rustfmt::skip]
    let result = [
        1.0 - 2.0 * y * y - 2.0 * z * z,
        2.0 * x * y + 2.0 * w * z,
        2.0 * x * z - 2.0 * w * y,
        0.0,
        2.0 * x * y - 2.0 * w * z,
        1.0 - 2.0 * x * x - 2.0 * z * z,
        2.0 * y * z + 2.0 * w * x,
        0.0,
        2.0 * x * z + 2.0 * w * y,
        2.0 * y * z - 2.0 * w * x,
        1.0 - 2.0 * x * x - 2.0 * y * y,
        0.0,
        translation[0],
        translation[1],
        translation[2],
        1.0,
    ];
    result.map(|v| v as f32)
}

/// Implements `Matrix3D.interpolate`.
pub fn interpolate<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let from = args.get_object(activation, 0, "fromMat")?;
    let to = args.get_object(activation, 1, "toMat")?;
    let percent = args.get_f64(2);

    let from = from.as_matrix3d_object().unwrap().matrix_ref().raw_data;
    let to = to.as_matrix3d_object().unwrap().matrix_ref().raw_data;
    let raw_data = interpolate_raw(&from, &to, percent);

    Ok(Matrix3DObject::new(activation.context, Matrix3D { raw_data }).into())
}

/// Implements `Utils3D.pointTowards`: interpolates the orientation of `mat` towards the pure rotation
/// [`Matrix3D.pointAt`] aligns (its frames, without the scale and the shear of `mat`), keeping the translation.
/// A degenerate direction returns a copy of `mat`.
pub fn point_towards<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let percent = args.get_f64(0);
    let mat = args.get_object(activation, 1, "mat")?;
    let pos = args.get_object(activation, 2, "pos")?;
    let (pos, at, up) = pointing_vectors(pos, args.try_get_object(3), args.try_get_object(4));

    let raw = mat.as_matrix3d_object().unwrap().matrix_ref().raw_data;

    let mut target = [0.0f32; 16];
    target[12..15].copy_from_slice(&raw[12..15]);
    target[15] = 1.0;
    match pointing_frames([raw[12], raw[13], raw[14]], pos, at, up) {
        Frames::Degenerate => {
            return Ok(Matrix3DObject::new(activation.context, Matrix3D { raw_data: raw }).into());
        }
        Frames::NotFinite => {
            for (i, v) in target.iter_mut().enumerate() {
                if i % 4 != 3 && i < 12 {
                    *v = f32::NAN;
                }
            }
        }
        Frames::Frames(world, object) => {
            // R = W * A^T
            for col in 0..3 {
                for row in 0..3 {
                    target[col * 4 + row] =
                        (0..3).map(|k| world[k][row] * object[k][col]).sum::<f64>() as f32;
                }
            }
        }
    }

    let raw_data = interpolate_raw(&raw, &target, percent);
    Ok(Matrix3DObject::new(activation.context, Matrix3D { raw_data }).into())
}
