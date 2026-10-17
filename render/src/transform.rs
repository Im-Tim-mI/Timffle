use crate::matrix::Matrix;
use crate::matrix3d::Matrix3D;
use crate::perspective_projection::PerspectiveProjection;
use swf::{ColorTransform, Twips};

/// Represents the transform for a DisplayObject.
/// This includes the transformation matrix and the color transform.
///
/// What a transform means depends on where it is used:
/// * When pushed on a [`TransformStack`] (or [`ChainState`]) it is the transform of one object relative to its
///   parent: `matrix` is its 2D matrix (or, for a 3D object, the affine approximation of its 3D matrix),
///   `matrix3d` is its 3D matrix if it has one, and `perspective_projection` is set if the object owns a
///   projection for its children.
/// * When returned by [`TransformStack::transform`] it is what to draw with: `matrix` maps local space to the
///   screen (for a 3D object that is the linearisation of the projective mapping at the local origin) and
///   `matrix3d`, when set, is the exact projective mapping (local pixels to screen pixels).
#[derive(Clone, Debug, Default)]
pub struct Transform {
    pub matrix: Matrix,
    pub matrix3d: Option<Matrix3D>,
    pub color_transform: ColorTransform,
    pub perspective_projection: Option<PerspectiveProjection>,
}

/// A 4x4 matrix of `f64`, column-major (element `(row, column)` is `m[column * 4 + row]`), acting on column
/// vectors, like Flash's `Matrix3D.rawData`. `a.mul(&b)` applies `b` first.
#[derive(Copy, Clone, Debug, PartialEq)]
pub struct Mat4(pub [f64; 16]);

impl Mat4 {
    pub const IDENTITY: Mat4 = Mat4([
        1.0, 0.0, 0.0, 0.0, //
        0.0, 1.0, 0.0, 0.0, //
        0.0, 0.0, 1.0, 0.0, //
        0.0, 0.0, 0.0, 1.0,
    ]);

    pub fn from_matrix3d(matrix: &Matrix3D) -> Self {
        Mat4(matrix.raw_data.map(f64::from))
    }

    pub fn to_matrix3d(&self) -> Matrix3D {
        Matrix3D {
            raw_data: self.0.map(|v| v as f32),
        }
    }

    /// A 2D matrix as a 4x4 acting on pixel coordinates.
    pub fn from_matrix(matrix: &Matrix) -> Self {
        Mat4([
            matrix.a as f64,
            matrix.b as f64,
            0.0,
            0.0, //
            matrix.c as f64,
            matrix.d as f64,
            0.0,
            0.0, //
            0.0,
            0.0,
            1.0,
            0.0, //
            matrix.tx.to_pixels(),
            matrix.ty.to_pixels(),
            0.0,
            1.0,
        ])
    }

    /// The perspective projection of a point of the owner's space onto the owner's plane (`z = 0`), seen
    /// from `(0, 0, -focal_length)` with the vanishing point at `centre`. The result is homogeneous:
    /// `x' = (f x + cx z) / (f + z)`, `y' = (f y + cy z) / (f + z)`, `z' = 0`.
    pub fn projection(centre: (f64, f64), focal_length: f64) -> Self {
        Mat4([
            focal_length,
            0.0,
            0.0,
            0.0, //
            0.0,
            focal_length,
            0.0,
            0.0, //
            centre.0,
            centre.1,
            0.0,
            1.0, //
            0.0,
            0.0,
            0.0,
            focal_length,
        ])
    }

    /// `self * rhs`: `rhs` is applied first.
    pub fn mul(&self, rhs: &Mat4) -> Mat4 {
        let a = &self.0;
        let b = &rhs.0;
        let mut out = [0.0; 16];
        for column in 0..4 {
            for row in 0..4 {
                out[column * 4 + row] = a[row] * b[column * 4]
                    + a[4 + row] * b[column * 4 + 1]
                    + a[8 + row] * b[column * 4 + 2]
                    + a[12 + row] * b[column * 4 + 3];
            }
        }
        Mat4(out)
    }

    /// Applies the matrix to the homogeneous vector `(x, y, z, w)`.
    pub fn transform4(&self, v: [f64; 4]) -> [f64; 4] {
        let m = &self.0;
        [
            m[0] * v[0] + m[4] * v[1] + m[8] * v[2] + m[12] * v[3],
            m[1] * v[0] + m[5] * v[1] + m[9] * v[2] + m[13] * v[3],
            m[2] * v[0] + m[6] * v[1] + m[10] * v[2] + m[14] * v[3],
            m[3] * v[0] + m[7] * v[1] + m[11] * v[2] + m[15] * v[3],
        ]
    }

    /// Where the point `(x, y, z)` ends up on the screen: `None` when it is at or behind the viewpoint.
    pub fn project(&self, x: f64, y: f64, z: f64) -> Option<(f64, f64)> {
        let [sx, sy, _, w] = self.transform4([x, y, z, 1.0]);
        if w > 1e-9 {
            Some((sx / w, sy / w))
        } else {
            None
        }
    }

    /// Like [`Self::project`], but without refusing points at or behind the viewpoint: they get the same formula
    /// (a negative or huge result), as Flash Player's `localToGlobal` does.
    pub fn project_unguarded(&self, x: f64, y: f64, z: f64) -> (f64, f64) {
        let [sx, sy, _, w] = self.transform4([x, y, z, 1.0]);
        let w = if w.abs() < 1e-12 { 1e-12 } else { w };
        (sx / w, sy / w)
    }

    /// The point of the plane `z = 0` of local space that is shown at the screen point `(sx, sy)`. The
    /// mapping from that plane to the screen is a 3x3 homography (columns 0, 1 and 3, rows 0, 1 and 3).
    pub fn unproject_plane(&self, sx: f64, sy: f64) -> Option<(f64, f64)> {
        let m = &self.0;
        // | m0 m4 m12 |   | x |   | X |
        // | m1 m5 m13 | * | y | = | Y |    with sx = X / W, sy = Y / W
        // | m3 m7 m15 |   | 1 |   | W |
        let (a, b, c) = (m[0] - sx * m[3], m[4] - sx * m[7], sx * m[15] - m[12]);
        let (d, e, f) = (m[1] - sy * m[3], m[5] - sy * m[7], sy * m[15] - m[13]);
        let det = a * e - b * d;
        if det.abs() < 1e-12 || !det.is_finite() {
            return None;
        }
        let x = (c * e - b * f) / det;
        let y = (a * f - c * d) / det;
        if x.is_finite() && y.is_finite() {
            Some((x, y))
        } else {
            None
        }
    }
}

/// How far a chain of display objects, from the stage down to some object, has been folded into one mapping from
/// that object's local space to the screen.
///
/// While every object of the chain is plain 2D this is just the product of the 2D matrices. As soon as an object
/// has a 3D matrix, the chain becomes a 4x4 product `F`:
///
/// ```text
/// F = V * P(stage) * L(root) * P(root) * L(a) * ... * L(object)
/// ```
///
/// where `L` is an object's own matrix (2D ones embedded), `V` is the viewport matrix, and `P(o)` is the
/// perspective projection of an object that owns a `perspectiveProjection` (its children are projected onto the
/// owner's plane), inserted right after the owner's own matrix. The stage owns the default projection. This is
/// how Flash Player draws: a point is mapped through all 3D matrices, projected by the nearest owner, and the
/// result is a point of the owner's plane, which the owner's own matrix and the owners above it then place.
#[derive(Copy, Clone, Debug)]
pub struct ChainState {
    /// The product of the 2D matrices of the chain, or, in 3D mode, the linearisation of `f` at the origin.
    matrix: Matrix,
    /// The 2D product since the nearest projection owner (the owner's own matrix is not part of it).
    rel: Matrix,
    /// Maps the children space of the nearest owner (its plane before projection) to the screen.
    owner_children: Option<Mat4>,
    /// 3D mode: the mapping from this object's space to the screen.
    f: Option<Mat4>,
    /// 3D mode: the mapping from the space of this object's children to the screen (the same as `f`, followed by
    /// the object's own projection if it owns one).
    f_children: Option<Mat4>,
    /// The width of the stage in pixels, from which focal lengths are derived.
    stage_width: f64,
}

impl ChainState {
    /// The state at the top of a chain: `base` maps stage coordinates to the screen (the viewport matrix, or the
    /// matrix of a `BitmapData.draw`), and objects that have no projection owner above them are projected
    /// about the centre of the stage.
    pub fn new(base: Matrix, stage_width: f64, stage_height: f64) -> Self {
        let mut state = ChainState {
            matrix: base,
            rel: Matrix::IDENTITY,
            owner_children: None,
            f: None,
            f_children: None,
            stage_width,
        };
        if stage_width > 0.0 {
            let focal_length = PerspectiveProjection::default().focal_length(stage_width as f32);
            state.owner_children = Some(Mat4::from_matrix(&base).mul(&Mat4::projection(
                (stage_width / 2.0, stage_height / 2.0),
                focal_length as f64,
            )));
        }
        state
    }

    /// The 2D matrix to draw with (exact for a 2D chain, the linearisation of [`Self::projective`] for a 3D one).
    pub fn matrix(&self) -> Matrix {
        self.matrix
    }

    /// The mapping from the current object's space to the screen, if the chain is 3D.
    pub fn projective(&self) -> Option<Mat4> {
        self.f
    }

    /// The mapping from the current object's space to the screen as a 4x4 matrix, whether the chain is 3D or not:
    /// a plain 2D chain is projected with the default projection, which is how a 3D point of a 2D object
    /// (`local3DToGlobal`) shows on the screen.
    pub fn mapping(&self) -> Mat4 {
        if let Some(f) = self.f {
            f
        } else if let Some(owner_children) = self.owner_children {
            owner_children.mul(&Mat4::from_matrix(&self.rel))
        } else {
            Mat4::from_matrix(&self.matrix)
        }
    }

    /// Whether anything in the chain, up to and including the current object, is 3D.
    pub fn is_3d(&self) -> bool {
        self.f.is_some()
    }

    /// The mapping from the space of the current object's children to the screen.
    fn children_mapping(&self) -> Mat4 {
        if let Some(f_children) = self.f_children {
            f_children
        } else if let Some(owner_children) = self.owner_children {
            owner_children.mul(&Mat4::from_matrix(&self.rel))
        } else {
            Mat4::from_matrix(&self.matrix)
        }
    }

    /// The state of a child with the given transform.
    pub fn push(&self, transform: &Transform) -> ChainState {
        let matrix = self.matrix * transform.matrix;
        let owner = transform.perspective_projection;
        let child_f = if let Some(own) = &transform.matrix3d {
            // A 3D object: its matrix, in its parent's space.
            Some(self.children_mapping().mul(&Mat4::from_matrix3d(own)))
        } else {
            // A 2D object inside a 3D parent is flattened onto the parent's plane.
            self.f_children
                .map(|children| children.mul(&Mat4::from_matrix(&transform.matrix)))
        };
        if let Some(f) = child_f {
            let f_children = match owner {
                Some(owner) => f.mul(&Mat4::projection(
                    owner.center,
                    owner.focal_length(self.stage_width as f32) as f64,
                )),
                None => f,
            };
            ChainState {
                matrix: linearise(&f, matrix),
                rel: Matrix::IDENTITY,
                owner_children: self.owner_children,
                f: Some(f),
                f_children: Some(f_children),
                stage_width: self.stage_width,
            }
        } else if let Some(owner) = owner {
            ChainState {
                matrix,
                rel: Matrix::IDENTITY,
                owner_children: Some(Mat4::from_matrix(&matrix).mul(&Mat4::projection(
                    owner.center,
                    owner.focal_length(self.stage_width as f32) as f64,
                ))),
                f: None,
                f_children: None,
                stage_width: self.stage_width,
            }
        } else {
            ChainState {
                matrix,
                rel: self.rel * transform.matrix,
                owner_children: self.owner_children,
                f: None,
                f_children: None,
                stage_width: self.stage_width,
            }
        }
    }
}

/// The affine map that agrees with `f` at the local origin and one pixel along each axis, in the units of
/// [`Matrix`]. Falls back to `fallback` for a mapping that puts the origin behind the viewpoint.
fn linearise(f: &Mat4, fallback: Matrix) -> Matrix {
    let (Some(o), Some(x), Some(y)) = (
        f.project(0.0, 0.0, 0.0),
        f.project(1.0, 0.0, 0.0),
        f.project(0.0, 1.0, 0.0),
    ) else {
        return fallback;
    };
    Matrix {
        a: (x.0 - o.0) as f32,
        b: (x.1 - o.1) as f32,
        c: (y.0 - o.0) as f32,
        d: (y.1 - o.1) as f32,
        tx: Twips::from_pixels(o.0),
        ty: Twips::from_pixels(o.1),
    }
}

pub struct TransformStack {
    stack: Vec<(ChainState, ColorTransform)>,
    /// The width of the stage in pixels, which every focal length is derived from.
    stage_width: f64,
}

impl TransformStack {
    pub fn new() -> Self {
        Self {
            stack: vec![(
                ChainState::new(Matrix::IDENTITY, 0.0, 0.0),
                ColorTransform::default(),
            )],
            stage_width: 0.0,
        }
    }

    /// Sets the stage width that focal lengths are derived from (see `PerspectiveProjection::focal_length`).
    pub fn set_stage_width(&mut self, width: f64) {
        self.stage_width = width;
        for (state, _) in &mut self.stack {
            state.stage_width = width;
        }
    }

    /// Makes the stack's current transform the owner of the default projection: 3D objects that have no
    /// projection owner above them are projected about the centre of the stage (`centre`, in the stage
    /// coordinates that the current transform maps to the screen), with the default field of view.
    pub fn set_root_projection(&mut self, centre: (f64, f64)) {
        let stage_width = self.stage_width;
        let (state, _) = self.stack.last_mut().expect("Transform stack underflow");
        let focal_length = PerspectiveProjection::default().focal_length(stage_width as f32);
        state.owner_children = Some(
            Mat4::from_matrix(&state.matrix).mul(&Mat4::projection(centre, focal_length as f64)),
        );
        state.stage_width = stage_width;
    }

    pub fn push(&mut self, transform: &Transform) {
        let (top, top_color) = self.stack.last().expect("Transform stack underflow");
        let state = top.push(transform);
        let color_transform = *top_color * transform.color_transform.clone();
        self.stack.push((state, color_transform));
    }

    pub fn pop(&mut self) {
        assert!(self.stack.len() > 1, "Transform stack underflow");
        self.stack.pop();
    }

    /// The transform to draw with at the current depth, perspective projection included.
    pub fn transform(&self) -> Transform {
        let (state, color_transform) = self.stack.last().expect("Transform stack underflow");
        Transform {
            matrix: state.matrix(),
            matrix3d: state.projective().map(|f| f.to_matrix3d()),
            color_transform: color_transform.clone(),
            perspective_projection: None,
        }
    }
}

impl Default for TransformStack {
    fn default() -> Self {
        TransformStack::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn close(a: f64, b: f64) -> bool {
        (a - b).abs() < 1e-6
    }

    #[test]
    fn projection_is_the_textbook_formula() {
        // centre (420, -150), f = 922.1: a point at depth 331.7 and (936.5, 342)
        let f = 922.1;
        let p = Mat4::projection((420.0, -150.0), f);
        let (x, y) = p.project(936.5, 342.0, 331.7).unwrap();
        let s = f / (f + 331.7);
        assert!(close(x, 420.0 + (936.5 - 420.0) * s));
        assert!(close(y, -150.0 + (342.0 + 150.0) * s));
        // a point on the plane stays where it is
        let (x, y) = p.project(12.0, 34.0, 0.0).unwrap();
        assert!(close(x, 12.0) && close(y, 34.0));
    }

    #[test]
    fn behind_the_viewpoint_is_not_projected() {
        let p = Mat4::projection((0.0, 0.0), 100.0);
        assert!(p.project(1.0, 1.0, -100.0).is_none());
        assert!(p.project(1.0, 1.0, -200.0).is_none());
        assert!(p.project(1.0, 1.0, -99.0).is_some());
    }

    #[test]
    fn unproject_inverts_project_on_the_plane() {
        let rot = Matrix3D {
            raw_data: [
                0.7071068, 0.0, -0.7071068, 0.0, //
                0.0, 1.0, 0.0, 0.0, //
                0.7071068, 0.0, 0.7071068, 0.0, //
                200.0, 100.0, 50.0, 1.0,
            ],
        };
        let f = Mat4::projection((480.0, 280.0), 922.1).mul(&Mat4::from_matrix3d(&rot));
        let (sx, sy) = f.project(30.0, 20.0, 0.0).unwrap();
        let (x, y) = f.unproject_plane(sx, sy).unwrap();
        assert!(close(x, 30.0) && close(y, 20.0), "{x} {y}");
    }

    #[test]
    fn a_2d_chain_is_the_plain_matrix_product() {
        let base = Matrix::scale(2.0, 2.0);
        let mut stack = TransformStack::new();
        stack.push(&Transform {
            matrix: base,
            ..Default::default()
        });
        stack.set_stage_width(960.0);
        stack.set_root_projection((480.0, 280.0));
        let child = Matrix::translate(Twips::from_pixels(10.0), Twips::from_pixels(20.0));
        stack.push(&Transform {
            matrix: child,
            ..Default::default()
        });
        let t = stack.transform();
        assert!(t.matrix3d.is_none());
        assert_eq!(t.matrix, base * child);
    }

    #[test]
    fn a_3d_child_follows_the_chain() {
        let mut stack = TransformStack::new();
        stack.push(&Transform::default());
        stack.set_stage_width(960.0);
        stack.set_root_projection((480.0, 280.0));
        stack.push(&Transform {
            matrix3d: Some(Matrix3D::translate(0.0, 0.0, 331.7)),
            ..Default::default()
        });
        let t = stack.transform();
        let f = Mat4::from_matrix3d(&t.matrix3d.unwrap());
        let (x, y) = f.project(936.5, 342.0, 0.0).unwrap();
        let focal = PerspectiveProjection::default().focal_length(960.0) as f64;
        let s = focal / (focal + 331.7);
        assert!((x - (480.0 + (936.5 - 480.0) * s)).abs() < 1e-3);
        assert!((y - (280.0 + (342.0 - 280.0) * s)).abs() < 1e-3);
    }
}
