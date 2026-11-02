//! Screen-space bounds of a command list (Timffle).
//!
//! A blend mode other than Normal is drawn into its own surface, which is then
//! composited onto the parent. Upstream always makes that surface as large as the
//! parent, so even a small blended button costs several full-stage passes per
//! frame. These helpers find the pixel box that a command list can touch, so the
//! blend surface can be kept to that box instead.
//!
//! The answer must never be too small: anything that is not understood (3D
//! transforms, Stage3D, shader blends, Alpha/Erase blends that reach for a layer
//! further out) makes the whole list "unbounded" and the caller keeps the old
//! full-size behaviour.

use crate::mesh::as_mesh;
use ruffle_render::commands::{Command, CommandList, RenderBlendMode};
use ruffle_render::matrix::Matrix;
use swf::BlendMode;

/// Extra pixels kept around the computed box, for anti-aliasing, pixel snapping,
/// hairlines and MSAA sample spread.
const PADDING: f32 = 3.0;

/// A box in surface pixels: `x_min, y_min, x_max, y_max`.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct PixelBox {
    pub x_min: f32,
    pub y_min: f32,
    pub x_max: f32,
    pub y_max: f32,
}

impl PixelBox {
    fn union(self, other: PixelBox) -> PixelBox {
        PixelBox {
            x_min: self.x_min.min(other.x_min),
            y_min: self.y_min.min(other.y_min),
            x_max: self.x_max.max(other.x_max),
            y_max: self.y_max.max(other.y_max),
        }
    }

    pub fn of_matrix(matrix: &Matrix, x0: f32, y0: f32, x1: f32, y1: f32) -> Option<PixelBox> {
        let tx = matrix.tx.to_pixels() as f32;
        let ty = matrix.ty.to_pixels() as f32;
        let mut result: Option<PixelBox> = None;
        for (x, y) in [(x0, y0), (x1, y0), (x0, y1), (x1, y1)] {
            let px = matrix.a * x + matrix.c * y + tx;
            let py = matrix.b * x + matrix.d * y + ty;
            if !px.is_finite() || !py.is_finite() {
                return None;
            }
            let point = PixelBox {
                x_min: px,
                y_min: py,
                x_max: px,
                y_max: py,
            };
            result = Some(match result {
                Some(r) => r.union(point),
                None => point,
            });
        }
        result
    }
}

/// What a command list can touch.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Extent {
    /// Draws nothing at all.
    Empty,
    /// Draws only inside this box (padding already added).
    Box(PixelBox),
    /// Could draw anywhere, or uses something that needs the full-size surface.
    Unbounded,
}

impl Extent {
    pub fn add(self, other: Extent) -> Extent {
        match (self, other) {
            (Extent::Unbounded, _) | (_, Extent::Unbounded) => Extent::Unbounded,
            (Extent::Empty, e) | (e, Extent::Empty) => e,
            (Extent::Box(a), Extent::Box(b)) => Extent::Box(a.union(b)),
        }
    }

    pub fn from_box(b: Option<PixelBox>) -> Extent {
        match b {
            Some(b) => Extent::Box(PixelBox {
                x_min: b.x_min - PADDING,
                y_min: b.y_min - PADDING,
                x_max: b.x_max + PADDING,
                y_max: b.y_max + PADDING,
            }),
            None => Extent::Unbounded,
        }
    }
}

/// Whether a blend in this mode may use a surface smaller than its parent.
/// Alpha and Erase read the nearest Layer, which may be a different surface, and
/// shader blends run a full-texture filter, so those keep the full size.
pub fn blend_can_shrink(blend_mode: &RenderBlendMode) -> bool {
    !matches!(
        blend_mode,
        RenderBlendMode::Shader(_)
            | RenderBlendMode::Builtin(BlendMode::Alpha)
            | RenderBlendMode::Builtin(BlendMode::Erase)
    )
}

/// The pixels (in the coordinates the commands are drawn in) that `commands` can touch.
///
/// `inside_layer_blend` must be true when the list is the content of a Layer
/// blend: an Alpha or Erase inside it then refers to that Layer itself.
pub fn command_list_extent(commands: &CommandList, inside_layer_blend: bool) -> Extent {
    let mut extent = Extent::Empty;
    for command in &commands.commands {
        let next = match command {
            Command::RenderBitmap {
                transform, region, ..
            } => {
                if transform.matrix3d.is_some() {
                    Extent::Unbounded
                } else {
                    Extent::from_box(PixelBox::of_matrix(
                        &transform.matrix,
                        0.0,
                        0.0,
                        region.width() as f32,
                        region.height() as f32,
                    ))
                }
            }
            Command::RenderShape { shape, transform } => {
                if transform.matrix3d.is_some() {
                    Extent::Unbounded
                } else {
                    match as_mesh(shape).bounds {
                        Some([x0, y0, x1, y1]) => {
                            Extent::from_box(PixelBox::of_matrix(&transform.matrix, x0, y0, x1, y1))
                        }
                        None => Extent::Empty,
                    }
                }
            }
            Command::RenderStage3D { .. } => Extent::Unbounded,
            Command::DrawRect { matrix, .. }
            | Command::DrawLine { matrix, .. }
            | Command::DrawLineRect { matrix, .. } => {
                Extent::from_box(PixelBox::of_matrix(matrix, 0.0, 0.0, 1.0, 1.0))
            }
            Command::PushMask
            | Command::ActivateMask
            | Command::DeactivateMask
            | Command::PopMask => Extent::Empty,
            Command::Blend(inner, blend_mode) => {
                let is_layer = matches!(blend_mode, RenderBlendMode::Builtin(BlendMode::Layer));
                let reaches_out = matches!(
                    blend_mode,
                    RenderBlendMode::Builtin(BlendMode::Alpha)
                        | RenderBlendMode::Builtin(BlendMode::Erase)
                ) && !inside_layer_blend;
                if reaches_out || matches!(blend_mode, RenderBlendMode::Shader(_)) {
                    Extent::Unbounded
                } else {
                    command_list_extent(inner, is_layer || inside_layer_blend)
                }
            }
            Command::RenderAlphaMask {
                maskee_commands,
                mask_commands,
            } => command_list_extent(maskee_commands, inside_layer_blend)
                .add(command_list_extent(mask_commands, inside_layer_blend)),
        };
        extent = extent.add(next);
        if extent == Extent::Unbounded {
            break;
        }
    }
    extent
}

/// Rounds a size up to a small set of steps, so that the texture pool (which keys
/// textures by exact size and never forgets a size) only ever sees a few sizes.
fn bucket(size: u32, max: u32) -> u32 {
    let step = if size <= 64 {
        64
    } else if size <= 512 {
        size.next_power_of_two()
    } else {
        size.div_ceil(256) * 256
    };
    step.min(max)
}

/// A rectangle inside the parent surface, in whole pixels.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct SurfaceRect {
    pub x: u32,
    pub y: u32,
    pub width: u32,
    pub height: u32,
}

impl SurfaceRect {
    pub fn intersects(&self, other: &SurfaceRect) -> bool {
        self.x < other.x + other.width
            && other.x < self.x + self.width
            && self.y < other.y + other.height
            && other.y < self.y + self.height
    }
}

/// Which pixels of a surface a group of draws can have changed.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Touched {
    None,
    Rect(SurfaceRect),
    All,
}

/// The pixels of a `width` x `height` surface whose top-left pixel is at
/// `origin` (in the commands' coordinates) that draws with `extent` can change.
pub fn touched_rect(extent: Extent, origin: (i32, i32), width: u32, height: u32) -> Touched {
    let b = match extent {
        Extent::Empty => return Touched::None,
        Extent::Unbounded => return Touched::All,
        Extent::Box(b) => b,
    };
    let x0 = (b.x_min.floor() - origin.0 as f32).max(0.0);
    let y0 = (b.y_min.floor() - origin.1 as f32).max(0.0);
    let x1 = (b.x_max.ceil() - origin.0 as f32).min(width as f32);
    let y1 = (b.y_max.ceil() - origin.1 as f32).min(height as f32);
    if x1 <= x0 || y1 <= y0 {
        return Touched::None;
    }
    let (x0, y0, x1, y1) = (x0 as u32, y0 as u32, x1 as u32, y1 as u32);
    if x0 == 0 && y0 == 0 && x1 >= width && y1 >= height {
        return Touched::All;
    }
    Touched::Rect(SurfaceRect {
        x: x0,
        y: y0,
        width: x1 - x0,
        height: y1 - y0,
    })
}

/// The two rectangles of a blend that uses a surface smaller than its parent.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct BlendRects {
    /// The blend surface's place in the parent (size rounded up to a few
    /// steps, see `bucket`).
    pub surface: SurfaceRect,
    /// The pixels the blend actually reads and writes (inside `surface`);
    /// the composite is scissored to it.
    pub tight: SurfaceRect,
}

/// Picks the part of a `parent_width` x `parent_height` surface whose top-left
/// pixel is at `origin` (in the commands' coordinates) that a blend surface for
/// `extent` must cover.
///
/// Returns `Ok(None)` when nothing visible is drawn, `Ok(Some(rects))` for a
/// smaller surface, and `Err(())` when the full-size surface should be used.
pub fn blend_rect(
    extent: Extent,
    origin: (i32, i32),
    parent_width: u32,
    parent_height: u32,
) -> Result<Option<BlendRects>, ()> {
    let b = match extent {
        Extent::Empty => return Ok(None),
        Extent::Unbounded => return Err(()),
        Extent::Box(b) => b,
    };
    let x0 = (b.x_min.floor() - origin.0 as f32).max(0.0);
    let y0 = (b.y_min.floor() - origin.1 as f32).max(0.0);
    let x1 = (b.x_max.ceil() - origin.0 as f32).min(parent_width as f32);
    let y1 = (b.y_max.ceil() - origin.1 as f32).min(parent_height as f32);
    if x1 <= x0 || y1 <= y0 {
        return Ok(None);
    }
    let (x0, y0, x1, y1) = (x0 as u32, y0 as u32, x1 as u32, y1 as u32);
    let tight = SurfaceRect {
        x: x0,
        y: y0,
        width: x1 - x0,
        height: y1 - y0,
    };
    let width = bucket(x1 - x0, parent_width);
    let height = bucket(y1 - y0, parent_height);
    // Not worth it when the box is most of the surface anyway.
    if u64::from(width) * u64::from(height) * 4
        >= u64::from(parent_width) * u64::from(parent_height) * 3
    {
        return Err(());
    }
    // Keep the (rounded-up) rectangle inside the parent.
    let x = x0.min(parent_width - width);
    let y = y0.min(parent_height - height);
    Ok(Some(BlendRects {
        surface: SurfaceRect {
            x,
            y,
            width,
            height,
        },
        tight,
    }))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn boxed(x_min: f32, y_min: f32, x_max: f32, y_max: f32) -> Extent {
        Extent::Box(PixelBox {
            x_min,
            y_min,
            x_max,
            y_max,
        })
    }

    #[test]
    fn small_box_gets_small_rect() {
        let r = blend_rect(boxed(100.2, 50.0, 140.0, 80.5), (0, 0), 960, 560)
            .unwrap()
            .unwrap();
        assert_eq!(
            r.surface,
            SurfaceRect {
                x: 100,
                y: 50,
                width: 64,
                height: 64
            }
        );
        assert_eq!(
            r.tight,
            SurfaceRect {
                x: 100,
                y: 50,
                width: 40,
                height: 31
            }
        );
    }

    #[test]
    fn rect_stays_inside_parent() {
        let r = blend_rect(boxed(940.0, 540.0, 1000.0, 600.0), (0, 0), 960, 560)
            .unwrap()
            .unwrap();
        let r = r.surface;
        assert!(r.x + r.width <= 960 && r.y + r.height <= 560);
        assert!(r.x <= 940 && r.y <= 540);
    }

    #[test]
    fn origin_is_subtracted() {
        let r = blend_rect(boxed(300.0, 300.0, 310.0, 310.0), (200, 250), 400, 400)
            .unwrap()
            .unwrap();
        assert_eq!((r.surface.x, r.surface.y), (100, 50));
        assert_eq!((r.tight.x, r.tight.y, r.tight.width), (100, 50, 10));
    }

    #[test]
    fn large_box_uses_full_surface() {
        assert_eq!(
            blend_rect(boxed(0.0, 0.0, 900.0, 500.0), (0, 0), 960, 560),
            Err(())
        );
        assert_eq!(blend_rect(Extent::Unbounded, (0, 0), 960, 560), Err(()));
    }

    #[test]
    fn offscreen_box_draws_nothing() {
        assert_eq!(
            blend_rect(boxed(-100.0, -100.0, -10.0, -10.0), (0, 0), 960, 560),
            Ok(None)
        );
        assert_eq!(blend_rect(Extent::Empty, (0, 0), 960, 560), Ok(None));
    }

    #[test]
    fn touched_rect_clips_and_detects_full() {
        assert_eq!(
            touched_rect(boxed(10.5, 20.5, 30.2, 40.0), (0, 0), 960, 560),
            Touched::Rect(SurfaceRect {
                x: 10,
                y: 20,
                width: 21,
                height: 20
            })
        );
        assert_eq!(
            touched_rect(boxed(-5.0, -5.0, 1000.0, 600.0), (0, 0), 960, 560),
            Touched::All
        );
        assert_eq!(
            touched_rect(boxed(300.0, 300.0, 310.0, 310.0), (200, 250), 400, 400),
            Touched::Rect(SurfaceRect {
                x: 100,
                y: 50,
                width: 10,
                height: 10
            })
        );
        assert_eq!(
            touched_rect(boxed(-50.0, -50.0, -1.0, -1.0), (0, 0), 960, 560),
            Touched::None
        );
        assert_eq!(touched_rect(Extent::Unbounded, (0, 0), 1, 1), Touched::All);
        assert_eq!(touched_rect(Extent::Empty, (0, 0), 1, 1), Touched::None);
    }

    #[test]
    fn rect_intersection() {
        let a = SurfaceRect {
            x: 10,
            y: 10,
            width: 20,
            height: 20,
        };
        let touching = SurfaceRect {
            x: 30,
            y: 10,
            width: 5,
            height: 5,
        };
        let inside = SurfaceRect {
            x: 15,
            y: 15,
            width: 1,
            height: 1,
        };
        assert!(!a.intersects(&touching));
        assert!(a.intersects(&inside));
        assert!(inside.intersects(&a));
    }

    #[test]
    fn rotated_matrix_box() {
        let m = Matrix {
            a: 0.0,
            b: 1.0,
            c: -1.0,
            d: 0.0,
            ..Default::default()
        };
        let b = PixelBox::of_matrix(&m, 0.0, 0.0, 10.0, 20.0).unwrap();
        assert_eq!(
            (b.x_min, b.y_min, b.x_max, b.y_max),
            (-20.0, 0.0, 0.0, 10.0)
        );
    }
}
