use crate::matrix::Matrix;
use swf::Twips;

/// The transformation matrix for 3D used by Flash display objects.
#[derive(Copy, Clone, Debug, PartialEq)]
pub struct Matrix3D {
    /// 4x4 matrix elements.
    pub raw_data: [f32; 16],
}

impl Matrix3D {
    pub const IDENTITY: Self = Self {
        raw_data: [
            1.0, 0.0, 0.0, 0.0, //
            0.0, 1.0, 0.0, 0.0, //
            0.0, 0.0, 1.0, 0.0, //
            0.0, 0.0, 0.0, 1.0,
        ],
    };

    pub fn scale(x: f32, y: f32, z: f32) -> Self {
        Self {
            raw_data: [
                x, 0.0, 0.0, 0.0, //
                0.0, y, 0.0, 0.0, //
                0.0, 0.0, z, 0.0, //
                0.0, 0.0, 0.0, 1.0,
            ],
        }
    }

    pub fn translate(x: f32, y: f32, z: f32) -> Self {
        Self {
            raw_data: [
                1.0, 0.0, 0.0, 0.0, //
                0.0, 1.0, 0.0, 0.0, //
                0.0, 0.0, 1.0, 0.0, //
                x, y, z, 1.0,
            ],
        }
    }

    pub fn from_matrix(matrix: Matrix) -> Self {
        Self {
            raw_data: [
                // 1st column
                matrix.a,
                matrix.b,
                0.0,
                0.0,
                // 2nd column
                matrix.c,
                matrix.d,
                0.0,
                0.0,
                // 3rd column
                0.0,
                0.0,
                1.0,
                0.0,
                // 4th column
                matrix.tx.to_pixels() as f32,
                matrix.ty.to_pixels() as f32,
                0.0,
                1.0,
            ],
        }
    }

    pub fn to_matrix(self) -> Matrix {
        Matrix {
            a: self.raw_data[0],
            b: self.raw_data[1],
            c: self.raw_data[4],
            d: self.raw_data[5],
            tx: Twips::from_pixels(self.raw_data[12] as f64),
            ty: Twips::from_pixels(self.raw_data[13] as f64),
        }
    }

    pub fn transpose_in_place(&mut self) {
        self.raw_data.swap(1, 4);
        self.raw_data.swap(2, 8);
        self.raw_data.swap(3, 12);
        self.raw_data.swap(6, 9);
        self.raw_data.swap(7, 13);
        self.raw_data.swap(11, 14);
    }

    pub fn determinant(&self) -> f32 {
        let m = &self.raw_data;

        /// The determinant of a 3x3 matrix, stored in column-major order.
        fn determinant_3x3(m: [f32; 9]) -> f32 {
            m[0] * (m[4] * m[8] - m[7] * m[5]) - m[3] * (m[1] * m[8] - m[7] * m[2])
                + m[6] * (m[1] * m[5] - m[4] * m[2])
        }

        // When projection is 0, Flash ignores translation, suggesting there is
        // a fast path here.
        if m[3] == 0.0 && m[7] == 0.0 && m[11] == 0.0 {
            // This is equivalent to doing a Laplace expansion over the last
            // column, but considering only the last row is non-zero, we can
            // skip other rows.
            //
            // Usually we'd calculate the determinant of the inner 3x3 matrix
            // and multiply by the last element, but Flash appears to factor the
            // last element into the formula (observable when it's +-Infinity).
            determinant_3x3([
                m[0],
                m[1],
                m[2] * m[15],
                m[4],
                m[5],
                m[6] * m[15],
                m[8],
                m[9],
                m[10] * m[15],
            ])
        } else {
            // Based on the condition above, it looks like we should do the
            // Laplace expansion over the last column, but that's not what
            // happens. This is observable when using +-Infinity in a dense
            // matrix; infinities are preserved only in the first row, which
            // means that no two infinities are subtracted in the expression,
            // suggesting we should do the Laplace expansion over that row.
            let det0 = determinant_3x3([m[5], m[6], m[7], m[9], m[10], m[11], m[13], m[14], m[15]]);
            let det4 = determinant_3x3([m[1], m[2], m[3], m[9], m[10], m[11], m[13], m[14], m[15]]);
            let det8 = determinant_3x3([m[1], m[2], m[3], m[5], m[6], m[7], m[13], m[14], m[15]]);
            let det12 = determinant_3x3([m[1], m[2], m[3], m[5], m[6], m[7], m[9], m[10], m[11]]);
            m[0] * det0 - m[4] * det4 + m[8] * det8 - m[12] * det12
        }
    }

    pub fn invert(&self) -> Option<Self> {
        let d = self.determinant();
        let invertible = d.abs() > 0.00000000001;

        if !invertible {
            return None;
        }

        let d = 1.0 / d;

        let m = self.raw_data;
        let m11 = m[0];
        let m21 = m[4];
        let m31 = m[8];
        let m41 = m[12];
        let m12 = m[1];
        let m22 = m[5];
        let m32 = m[9];
        let m42 = m[13];
        let m13 = m[2];
        let m23 = m[6];
        let m33 = m[10];
        let m43 = m[14];
        let m14 = m[3];
        let m24 = m[7];
        let m34 = m[11];
        let m44 = m[15];

        #[rustfmt::skip]
        let raw_data = [
             d * (m22 * (m33 * m44 - m43 * m34) - m32 * (m23 * m44 - m43 * m24) + m42 * (m23 * m34 - m33 * m24)),
            -d * (m12 * (m33 * m44 - m43 * m34) - m32 * (m13 * m44 - m43 * m14) + m42 * (m13 * m34 - m33 * m14)),
             d * (m12 * (m23 * m44 - m43 * m24) - m22 * (m13 * m44 - m43 * m14) + m42 * (m13 * m24 - m23 * m14)),
            -d * (m12 * (m23 * m34 - m33 * m24) - m22 * (m13 * m34 - m33 * m14) + m32 * (m13 * m24 - m23 * m14)),
            -d * (m21 * (m33 * m44 - m43 * m34) - m31 * (m23 * m44 - m43 * m24) + m41 * (m23 * m34 - m33 * m24)),
             d * (m11 * (m33 * m44 - m43 * m34) - m31 * (m13 * m44 - m43 * m14) + m41 * (m13 * m34 - m33 * m14)),
            -d * (m11 * (m23 * m44 - m43 * m24) - m21 * (m13 * m44 - m43 * m14) + m41 * (m13 * m24 - m23 * m14)),
             d * (m11 * (m23 * m34 - m33 * m24) - m21 * (m13 * m34 - m33 * m14) + m31 * (m13 * m24 - m23 * m14)),
             d * (m21 * (m32 * m44 - m42 * m34) - m31 * (m22 * m44 - m42 * m24) + m41 * (m22 * m34 - m32 * m24)),
            -d * (m11 * (m32 * m44 - m42 * m34) - m31 * (m12 * m44 - m42 * m14) + m41 * (m12 * m34 - m32 * m14)),
             d * (m11 * (m22 * m44 - m42 * m24) - m21 * (m12 * m44 - m42 * m14) + m41 * (m12 * m24 - m22 * m14)),
            -d * (m11 * (m22 * m34 - m32 * m24) - m21 * (m12 * m34 - m32 * m14) + m31 * (m12 * m24 - m22 * m14)),
            -d * (m21 * (m32 * m43 - m42 * m33) - m31 * (m22 * m43 - m42 * m23) + m41 * (m22 * m33 - m32 * m23)),
             d * (m11 * (m32 * m43 - m42 * m33) - m31 * (m12 * m43 - m42 * m13) + m41 * (m12 * m33 - m32 * m13)),
            -d * (m11 * (m22 * m43 - m42 * m23) - m21 * (m12 * m43 - m42 * m13) + m41 * (m12 * m23 - m22 * m13)),
             d * (m11 * (m22 * m33 - m32 * m23) - m21 * (m12 * m33 - m32 * m13) + m31 * (m12 * m23 - m22 * m13)),
        ];

        Some(Self { raw_data })
    }

    pub fn multiply(&self, rhs: &Self) -> Self {
        let lhs = &self.raw_data;
        let rhs = &rhs.raw_data;
        let mut result = [0.0; 16];

        for column in 0..4 {
            for row in 0..4 {
                result[column * 4 + row] = lhs[row] * rhs[column * 4]
                    + lhs[4 + row] * rhs[column * 4 + 1]
                    + lhs[8 + row] * rhs[column * 4 + 2]
                    + lhs[12 + row] * rhs[column * 4 + 3];
            }
        }

        Self { raw_data: result }
    }

    pub fn tz(&self) -> f32 {
        self.raw_data[14]
    }
    pub fn set_tz(&mut self, tz: f32) {
        self.raw_data[14] = tz;
    }
}

/// The rotation (in degrees, about the x, y and z axes) and the scale of a 3D object. Flash derives these
/// properties from a matrix by Gram-Schmidt orthogonalisation of its columns and builds the matrix back as
/// `T * Rz * Ry * Rx * S`, which is why a matrix with shear does not survive a round trip.
#[derive(Copy, Clone, Debug, PartialEq)]
pub struct Trs3D {
    pub rotation: [f64; 3],
    pub scale: [f64; 3],
}

impl Default for Trs3D {
    fn default() -> Self {
        Trs3D {
            rotation: [0.0; 3],
            scale: [1.0; 3],
        }
    }
}

fn dot3(a: [f64; 3], b: [f64; 3]) -> f64 {
    a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
}

fn cross3(a: [f64; 3], b: [f64; 3]) -> [f64; 3] {
    [
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    ]
}

fn scale3(a: [f64; 3], s: f64) -> [f64; 3] {
    [a[0] * s, a[1] * s, a[2] * s]
}

fn sub3(a: [f64; 3], b: [f64; 3]) -> [f64; 3] {
    [a[0] - b[0], a[1] - b[1], a[2] - b[2]]
}

/// A unit vector perpendicular to `a` (`a` need not be normalised).
fn perpendicular(a: [f64; 3]) -> [f64; 3] {
    let helper = if a[0].abs() < 0.9 {
        [1.0, 0.0, 0.0]
    } else {
        [0.0, 1.0, 0.0]
    };
    let p = cross3(a, helper);
    let n = dot3(p, p).sqrt();
    if n > 0.0 {
        scale3(p, 1.0 / n)
    } else {
        [0.0, 0.0, 1.0]
    }
}

impl Matrix3D {
    /// The rotation and scale of the matrix, the way Flash reports them for a display object.
    pub fn decompose_trs(&self) -> Trs3D {
        let m = self.raw_data.map(f64::from);
        let c0 = [m[0], m[1], m[2]];
        let c1 = [m[4], m[5], m[6]];
        let c2 = [m[8], m[9], m[10]];

        let sx = dot3(c0, c0).sqrt();
        let u0 = if sx > 0.0 {
            scale3(c0, 1.0 / sx)
        } else {
            [1.0, 0.0, 0.0]
        };
        let t1 = sub3(c1, scale3(u0, dot3(c1, u0)));
        let sy = dot3(t1, t1).sqrt();
        let u1 = if sy > 0.0 {
            scale3(t1, 1.0 / sy)
        } else {
            perpendicular(u0)
        };
        let t2 = sub3(sub3(c2, scale3(u0, dot3(c2, u0))), scale3(u1, dot3(c2, u1)));
        let mut sz = dot3(t2, t2).sqrt();
        let mut u2 = if sz > 0.0 {
            scale3(t2, 1.0 / sz)
        } else {
            cross3(u0, u1)
        };
        if dot3(cross3(u0, u1), u2) < 0.0 {
            // A reflection: carry it on the z scale.
            u2 = scale3(u2, -1.0);
            sz = -sz;
        }

        // R = Rz * Ry * Rx with the unit columns u0, u1, u2.
        let ry = (-u0[2]).clamp(-1.0, 1.0).asin();
        let (rx, rz) = if u0[2].abs() < 0.999_999 {
            (u1[2].atan2(u2[2]), u0[1].atan2(u0[0]))
        } else if u0[2] < 0.0 {
            // ry = +90 degrees: only rx - rz is defined
            (u1[0].atan2(u1[1]), 0.0)
        } else {
            // ry = -90 degrees: only rx + rz is defined
            ((-u1[0]).atan2(u1[1]), 0.0)
        };
        Trs3D {
            rotation: [rx.to_degrees(), ry.to_degrees(), rz.to_degrees()],
            scale: [sx, sy, sz],
        }
    }

    /// `T * Rz * Ry * Rx * S` with the translation given in pixels.
    pub fn from_trs(translation: [f32; 3], trs: &Trs3D) -> Self {
        let [rx, ry, rz] = trs.rotation.map(f64::to_radians);
        let (sx, cx) = rx.sin_cos();
        let (sy, cy) = ry.sin_cos();
        let (sz, cz) = rz.sin_cos();
        // columns of R = Rz * Ry * Rx
        let r0 = [cy * cz, cy * sz, -sy];
        let r1 = [sx * sy * cz - cx * sz, sx * sy * sz + cx * cz, sx * cy];
        let r2 = [cx * sy * cz + sx * sz, cx * sy * sz - sx * cz, cx * cy];
        let [kx, ky, kz] = trs.scale;
        let col = |r: [f64; 3], k: f64| [(r[0] * k) as f32, (r[1] * k) as f32, (r[2] * k) as f32];
        let (c0, c1, c2) = (col(r0, kx), col(r1, ky), col(r2, kz));
        Self {
            raw_data: [
                c0[0],
                c0[1],
                c0[2],
                0.0,
                c1[0],
                c1[1],
                c1[2],
                0.0,
                c2[0],
                c2[1],
                c2[2],
                0.0,
                translation[0],
                translation[1],
                translation[2],
                1.0,
            ],
        }
    }
}

#[cfg(test)]
mod trs_tests {
    use super::*;

    fn close(a: f64, b: f64) -> bool {
        (a - b).abs() < 1e-3
    }

    #[test]
    fn matches_what_flash_reports() {
        // rotationX/Y/Z = 20/30/40 gives these columns in Flash
        let m = Matrix3D::from_trs(
            [0.0; 3],
            &Trs3D {
                rotation: [20.0, 30.0, 40.0],
                scale: [1.0; 3],
            },
        );
        let flash = [
            0.6634, 0.5567, -0.5, -0.473, 0.8298, 0.2962, 0.5798, 0.04, 0.8138,
        ];
        let mine = [
            m.raw_data[0],
            m.raw_data[1],
            m.raw_data[2],
            m.raw_data[4],
            m.raw_data[5],
            m.raw_data[6],
            m.raw_data[8],
            m.raw_data[9],
            m.raw_data[10],
        ];
        for (a, b) in mine.iter().zip(flash) {
            assert!(close(*a as f64, b), "{mine:?}");
        }
        let back = m.decompose_trs();
        assert!(
            close(back.rotation[0], 20.0)
                && close(back.rotation[1], 30.0)
                && close(back.rotation[2], 40.0)
        );
        assert!(back.scale.iter().all(|s| close(*s, 1.0)));
    }

    #[test]
    fn a_matrix_with_shear_decomposes_like_flash() {
        // [1, 0.2, 0, 0, 0.3, 1, 0, 0, ...]: Flash reports sx 1.0198, sy 0.9217, rotationZ 11.3099
        let m = Matrix3D {
            raw_data: [
                1.0, 0.2, 0.0, 0.0, 0.3, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 10.0, 20.0, 30.0, 1.0,
            ],
        };
        let t = m.decompose_trs();
        assert!(
            close(t.scale[0], 1.0198) && close(t.scale[1], 0.9217) && close(t.scale[2], 1.0),
            "{t:?}"
        );
        assert!(
            close(t.rotation[2], 11.3099) && close(t.rotation[0], 0.0) && close(t.rotation[1], 0.0),
            "{t:?}"
        );
    }

    #[test]
    fn scale_comes_before_rotation() {
        let m = Matrix3D::from_trs(
            [1.0, 2.0, 3.0],
            &Trs3D {
                rotation: [0.0, 0.0, 0.0],
                scale: [2.0, 3.0, 4.0],
            },
        );
        assert_eq!(m.raw_data[0], 2.0);
        assert_eq!(m.raw_data[5], 3.0);
        assert_eq!(m.raw_data[10], 4.0);
        assert_eq!(m.raw_data[12], 1.0);
    }
}
