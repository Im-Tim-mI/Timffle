//! `flash.geom.Utils3D` natives

use crate::avm2::function::FunctionArgs;
use crate::avm2::parameters::ParametersExt as _;
use crate::avm2::{Activation, Error, Value};

use super::matrix_3d::{read_vector3d, transform_point, vector3d_to_object};

pub use super::matrix_3d::point_towards;

/// Implements `Utils3D.projectVector`: the vector transformed by the matrix, its x, y and z multiplied by the
/// reciprocal of w (computed in single precision; w itself is left alone); (0, 0, 0, 0) for a point on the camera
/// plane. (Measured on Flash Player, bit for bit.)
pub fn project_vector<'gc>(
    activation: &mut Activation<'_, 'gc>,
    _this: Value<'gc>,
    args: FunctionArgs<'_, 'gc>,
) -> Result<Value<'gc>, Error<'gc>> {
    let m = args.get_object(activation, 0, "m")?;
    let v = args.get_object(activation, 1, "v")?;

    let mr = m.as_matrix3d_object().unwrap().matrix_ref().raw_data;
    let [x, y, z, _] = read_vector3d(v);
    let [x, y, z, w] = transform_point(&mr, x as f32, y as f32, z as f32);

    let projected = if w == 0.0 {
        [0.0, 0.0, 0.0, 0.0]
    } else {
        let reciprocal = f64::from(1.0f32 / w);
        [
            f64::from(x) * reciprocal,
            f64::from(y) * reciprocal,
            f64::from(z) * reciprocal,
            f64::from(w),
        ]
    };
    Ok(vector3d_to_object(activation, projected))
}
