use crate::context::RenderContext;
use gc_arena::{DynamicRoot, Rootable};
use ruffle_render::backend::{PixelBenderTarget, RenderBackend, ShapeHandle};
use ruffle_render::bitmap::{BitmapHandle, BitmapInfo, BitmapSize, BitmapSource};
use ruffle_render::commands::CommandHandler;
use ruffle_render::pixel_bender::PixelBenderShaderHandle;
use ruffle_render::pixel_bender_support::PixelBenderShaderArgument;
use ruffle_render::shape_utils::{
    DistilledShape, DrawCommand, DrawPath, FillRule, cubic_curve_bounds, quadratic_curve_bounds,
};
use std::cell::{Cell, OnceCell, RefCell};
use std::num::NonZeroU32;
use swf::{FillStyle, LineStyle, Point, Rectangle, Twips};

/// Timffle: a GC object kept alive by a `Drawing` (the `BitmapData` of a bitmap fill, so
/// `Graphics.readGraphicsData` can hand back the same object Flash Player returns).
#[derive(Clone)]
pub struct ObjectRoot(pub DynamicRoot<Rootable![crate::avm2::Object<'_>]>);

impl std::fmt::Debug for ObjectRoot {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("ObjectRoot")
    }
}

/// Timffle: bitmap ids at or above this value name a `ShaderFill` instead of an entry of
/// `Drawing::bitmaps` (see `Drawing::add_shader_fill`).
const SHADER_FILL_ID_BASE: u16 = 0x8000;

/// Timffle: a `Graphics.beginShaderFill` / `lineShaderStyle` fill. The Pixel Bender
/// shader is evaluated once, when the shape is registered with the renderer, over the
/// bounds of the fill it belongs to (mapped through the inverse of `matrix`, the
/// shader-to-shape matrix), and the result is used as a bitmap fill. Shader inputs
/// changed after the fill was committed are not re-evaluated until the drawing changes.
#[derive(Clone)]
pub struct ShaderFill {
    shader: PixelBenderShaderHandle,
    arguments: Vec<PixelBenderShaderArgument<'static>>,
    /// Shader coordinates -> shape pixels, as given to `beginShaderFill`.
    matrix: swf::Matrix,
    /// The `Shader` object, handed back by readGraphicsData.
    object: Option<ObjectRoot>,
    /// Size of the evaluated bitmap, computed from the fill's bounds on first use.
    size: Cell<Option<BitmapSize>>,
    /// The evaluated bitmap (`Some(None)` once evaluation failed, e.g. without a GPU).
    bitmap: RefCell<Option<Option<BitmapHandle>>>,
}

impl std::fmt::Debug for ShaderFill {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ShaderFill")
            .field("matrix", &self.matrix)
            .field("size", &self.size.get())
            .finish()
    }
}

/// Timffle: the largest bitmap a shader fill is evaluated into (per side, pixels).
const SHADER_FILL_MAX_SIZE: f64 = 4096.0;

/// Timffle: one item of `Graphics.readGraphicsData`, in Flash Player's order (each fill
/// group, then the strokes recorded inside it). Fill commands exclude the implicit
/// closing segment; stroke commands include it and closed loops are already rotated
/// the way Flash reports them (see `rotate_closed_stroke`).
#[derive(Clone, Debug)]
pub enum GraphicsReadItem {
    Fill {
        style: FillStyle,
        /// The rule Flash reports: `evenOdd` for ordinary and triangle groups, the
        /// `drawPath` rule for drawPath groups.
        rule: FillRule,
        commands: Vec<DrawCommand>,
    },
    Stroke {
        style: LineStyle,
        commands: Vec<DrawCommand>,
    },
}

// Timffle: which API started a fill group. Flash Player keeps the sub-paths of one
// `beginFill` in separate groups: ordinary drawing commands (moveTo/lineTo/drawRect…)
// share an even-odd group, every `drawPath`/`GraphicsPath` call starts a group with its
// own winding rule (consecutive calls with the same rule merge), and every
// `drawTriangles`/`GraphicsTrianglePath` call is its own group (measured on Flash 32,
// timffle/difftest/src/D57Winding.hx).
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum FillOrigin {
    /// moveTo/lineTo/curveTo/drawRect/… commands.
    Commands,
    /// `Graphics.drawPath` / `GraphicsPath` with the given winding rule.
    Path(FillRule),
    /// `Graphics.drawTriangles` / `GraphicsTrianglePath` (rendered as a union).
    Triangles,
}

#[derive(Clone, Debug)]
pub struct Drawing {
    render_handle: OnceCell<ShapeHandle>,
    shape_bounds: Rectangle<Twips>,
    edge_bounds: Rectangle<Twips>,
    paths: Vec<DrawingPath>,
    bitmaps: Vec<BitmapInfo>,
    // Timffle: the `BitmapData` objects behind `bitmaps` (same length), for readGraphicsData.
    bitmap_objects: Vec<Option<ObjectRoot>>,
    // Timffle: shader fills, addressed by `SHADER_FILL_ID_BASE + index`.
    shader_fills: Vec<ShaderFill>,
    current_fill: Option<DrawingFill>,
    current_line: Option<DrawingLine>,
    pending_lines: Vec<DrawingLine>,
    cursor: Point<Twips>,
    fill_start: Point<Twips>,
    default_winding_rule: FillRule,
    /// Cached for fast emptiness check.
    is_empty: bool,
}

impl Default for Drawing {
    fn default() -> Self {
        Self::new()
    }
}

impl Drawing {
    pub fn new() -> Self {
        Self {
            render_handle: OnceCell::new(),
            shape_bounds: Default::default(),
            edge_bounds: Default::default(),
            paths: Vec::new(),
            bitmaps: Vec::new(),
            bitmap_objects: Vec::new(),
            shader_fills: Vec::new(),
            current_fill: None,
            current_line: None,
            pending_lines: Vec::new(),
            cursor: Point::ZERO,
            fill_start: Point::ZERO,
            default_winding_rule: FillRule::EvenOdd,
            is_empty: true,
        }
    }

    pub fn from_swf_shape(shape: &swf::Shape) -> Self {
        let mut this = Self {
            render_handle: OnceCell::new(),
            shape_bounds: shape.shape_bounds,
            edge_bounds: shape.edge_bounds,
            paths: Vec::new(),
            bitmaps: Vec::new(),
            bitmap_objects: Vec::new(),
            shader_fills: Vec::new(),
            current_fill: None,
            current_line: None,
            pending_lines: Vec::new(),
            cursor: Point::ZERO,
            fill_start: Point::ZERO,
            default_winding_rule: if shape.flags.contains(swf::ShapeFlag::NON_ZERO_WINDING_RULE) {
                FillRule::NonZero
            } else {
                FillRule::EvenOdd
            },
            is_empty: true,
        };

        let shape: DistilledShape = shape.into();
        for path in shape.paths {
            match path {
                DrawPath::Stroke {
                    style,
                    is_closed: _,
                    commands,
                } => {
                    this.set_line_style(Some(style.clone()));

                    for command in commands {
                        this.draw_command(command);
                    }

                    this.set_line_style(None);
                }
                DrawPath::Fill {
                    style,
                    commands,
                    winding_rule,
                } => {
                    this.new_fill(Some(style.clone()), Some(winding_rule));

                    for command in commands {
                        this.draw_command(command);
                    }

                    this.set_fill_style(None);
                }
            }
        }

        this
    }

    fn mark_dirty(&mut self) {
        self.is_empty = false;
        self.render_handle.take();
    }

    /// Set fill style and reset fill rule to default.
    pub fn set_fill_style(&mut self, style: Option<FillStyle>) {
        self.new_fill(style, Some(self.default_winding_rule));
    }

    /// Set fill rule and keep the same fill style.
    pub fn set_fill_rule(&mut self, rule: Option<FillRule>) {
        let style = self.current_fill.as_ref().map(|fill| fill.style.clone());
        self.new_fill(style, rule);
    }

    /// Set fill style and rule.
    pub fn new_fill(&mut self, style: Option<FillStyle>, rule: Option<FillRule>) {
        self.new_fill_with_origin(style, rule, FillOrigin::Commands);
    }

    // Timffle: start a new fill group (see `FillOrigin`).
    fn new_fill_with_origin(
        &mut self,
        style: Option<FillStyle>,
        rule: Option<FillRule>,
        origin: FillOrigin,
    ) {
        self.close_path();
        if let Some(existing) = self.current_fill.take() {
            self.paths.push(DrawingPath::Fill(existing));
        }
        self.paths
            .extend(self.pending_lines.drain(..).map(DrawingPath::Line));
        if let Some(mut existing) = self.current_line.take() {
            existing.is_closed = self.cursor == self.fill_start;
            let style = existing.style.clone();
            let auto_close = existing.auto_close;
            self.paths.push(DrawingPath::Line(existing));
            self.current_line = Some(DrawingLine {
                style,
                commands: vec![DrawCommand::MoveTo(self.cursor)],
                is_closed: false,
                auto_close,
                close_only: false,
            });
        }
        if let Some(style) = style {
            self.current_fill = Some(DrawingFill {
                style,
                rule: rule.unwrap_or(self.default_winding_rule),
                commands: vec![DrawCommand::MoveTo(self.cursor)],
                origin,
            });
        }
        self.fill_start = self.cursor;
        self.mark_dirty();
    }

    /// Timffle: the style of the fill that is currently open, if any.
    pub fn current_fill_style(&self) -> Option<&FillStyle> {
        self.current_fill.as_ref().map(|fill| &fill.style)
    }

    /// Timffle: start (or continue) the fill group of a `drawPath` call with the given
    /// winding rule. Consecutive `drawPath` calls with the same rule share one group;
    /// anything else starts a new group with the current fill style.
    pub fn begin_path_group(&mut self, rule: FillRule) {
        if let Some(fill) = &self.current_fill {
            if fill.origin == FillOrigin::Path(rule) {
                return;
            }
            let style = fill.style.clone();
            self.new_fill_with_origin(Some(style), Some(rule), FillOrigin::Path(rule));
        }
    }

    /// Timffle: start a `drawTriangles` fill group with the given style (the current
    /// fill style, or a per-triangle bitmap fill for textured triangles). Triangles are
    /// drawn with a consistent orientation under the non-zero rule, so overlapping
    /// triangles form a union like in Flash Player.
    pub fn begin_triangles_group(&mut self, style: FillStyle) {
        self.new_fill_with_origin(Some(style), Some(FillRule::NonZero), FillOrigin::Triangles);
    }

    /// Timffle: `drawPath` strokes are never implicitly closed (Flash's documented rule),
    /// unlike lineTo strokes inside a fill. Starts a new stroke sub-path with the current
    /// line style that will not get the closing segment.
    pub fn begin_path_stroke(&mut self) {
        self.split_line(false);
    }

    /// Timffle: end the `drawPath` stroke sub-path; later lineTo strokes close normally.
    pub fn end_path_stroke(&mut self) {
        self.split_line(true);
    }

    fn split_line(&mut self, auto_close: bool) {
        if let Some(mut existing) = self.current_line.take() {
            existing.is_closed = self.cursor == self.fill_start;
            let style = existing.style.clone();
            if self.current_fill.is_some() {
                self.pending_lines.push(existing);
            } else {
                self.paths.push(DrawingPath::Line(existing));
            }
            self.current_line = Some(DrawingLine {
                style,
                commands: vec![DrawCommand::MoveTo(self.cursor)],
                is_closed: false,
                auto_close,
                close_only: false,
            });
            self.mark_dirty();
        }
    }

    pub fn clear(&mut self) {
        self.current_fill = None;
        self.current_line = None;
        self.pending_lines.clear();
        self.paths.clear();
        self.bitmaps.clear();
        self.bitmap_objects.clear();
        self.shader_fills.clear();
        self.edge_bounds = Default::default();
        self.shape_bounds = Default::default();
        self.cursor = Point::ZERO;
        self.fill_start = Point::ZERO;
        self.is_empty = true;

        // An empty drawing doesn't need to hold onto a `ShapeHandle`.
        self.render_handle.take();
    }

    pub fn set_line_style(&mut self, style: Option<LineStyle>) {
        if let Some(mut existing) = self.current_line.take() {
            existing.is_closed = self.cursor == self.fill_start;
            if self.current_fill.is_some() {
                self.pending_lines.push(existing);
            } else {
                self.paths.push(DrawingPath::Line(existing));
            }
        }
        if let Some(style) = style {
            self.current_line = Some(DrawingLine {
                style,
                commands: vec![DrawCommand::MoveTo(self.cursor)],
                is_closed: false,
                auto_close: true,
                close_only: false,
            });
        }

        self.mark_dirty();
    }

    pub fn set_line_fill_style(&mut self, fill_style: FillStyle) {
        if let Some(style) = self.current_line.as_ref().map(|l| l.style.clone()) {
            self.set_line_style(Some(style.with_fill_style(fill_style)));
        }
    }

    pub fn draw_command(&mut self, command: DrawCommand) {
        // Timffle: an ordinary command after a drawPath/drawTriangles group starts a new
        // even-odd group with the same fill style (Flash keeps them apart).
        if let Some(fill) = &self.current_fill
            && fill.origin != FillOrigin::Commands
        {
            let style = fill.style.clone();
            let rule = self.default_winding_rule;
            self.new_fill_with_origin(Some(style), Some(rule), FillOrigin::Commands);
        }
        self.draw_command_in_group(command);
    }

    /// Timffle: like `draw_command`, but keeps the current drawPath/drawTriangles group.
    pub fn draw_command_in_group(&mut self, command: DrawCommand) {
        let add_to_bounds = if let DrawCommand::MoveTo(move_to) = &command {
            // Close any pending fills before moving.
            self.close_path();
            self.fill_start = *move_to;
            false
        } else {
            true
        };

        // Add command to current fill.
        if let Some(fill) = &mut self.current_fill {
            fill.commands.push(command.clone());
        }
        // Add command to current line.
        let stroke_width = if let Some(line) = &mut self.current_line {
            line.commands.push(command.clone());
            line.style.width()
        } else {
            Twips::ZERO
        };

        // Expand bounds.
        if add_to_bounds {
            if self.fill_start == self.cursor {
                // If this is the initial command after a move, include the starting point.
                let command = DrawCommand::MoveTo(self.cursor);
                self.shape_bounds =
                    stretch_bounds(&self.shape_bounds, &command, stroke_width, self.cursor);
                self.edge_bounds =
                    stretch_bounds(&self.edge_bounds, &command, Twips::ZERO, self.cursor);
            }
            self.shape_bounds =
                stretch_bounds(&self.shape_bounds, &command, stroke_width, self.cursor);
            self.edge_bounds =
                stretch_bounds(&self.edge_bounds, &command, Twips::ZERO, self.cursor);
        }

        self.cursor = command.end_point();
        self.mark_dirty()
    }

    pub fn add_bitmap(&mut self, bitmap: BitmapInfo) -> u16 {
        let id = self.bitmaps.len() as u16;
        self.bitmaps.push(bitmap);
        self.bitmap_objects.push(None);
        id
    }

    /// Timffle: remember the `BitmapData` object behind bitmap `id` (readGraphicsData
    /// returns the same object, like Flash Player).
    pub fn set_bitmap_object(&mut self, id: u16, object: ObjectRoot) {
        if let Some(slot) = self.bitmap_objects.get_mut(id as usize) {
            *slot = Some(object);
        }
    }

    /// Timffle: the `BitmapData` object behind bitmap `id`, if known.
    pub fn bitmap_object(&self, id: u16) -> Option<&ObjectRoot> {
        self.bitmap_objects.get(id as usize)?.as_ref()
    }

    /// Timffle: register a shader fill (see `ShaderFill`) and return the bitmap fill
    /// style that stands for it. `matrix` maps shader coordinates to shape pixels.
    pub fn add_shader_fill(
        &mut self,
        shader: PixelBenderShaderHandle,
        arguments: Vec<PixelBenderShaderArgument<'static>>,
        matrix: swf::Matrix,
        object: Option<ObjectRoot>,
    ) -> FillStyle {
        let id = SHADER_FILL_ID_BASE + self.shader_fills.len() as u16;
        self.shader_fills.push(ShaderFill {
            shader,
            arguments,
            matrix,
            object,
            size: Cell::new(None),
            bitmap: RefCell::new(None),
        });
        let scale_matrix = swf::Matrix::scale(
            (Twips::TWIPS_PER_PIXEL as i16).into(),
            (Twips::TWIPS_PER_PIXEL as i16).into(),
        );
        FillStyle::Bitmap {
            id,
            matrix: matrix * scale_matrix,
            is_smoothed: false,
            is_repeating: false,
        }
    }

    /// Timffle: whether bitmap `id` stands for a shader fill.
    pub fn is_shader_fill(&self, id: u16) -> bool {
        id >= SHADER_FILL_ID_BASE && ((id - SHADER_FILL_ID_BASE) as usize) < self.shader_fills.len()
    }

    /// Timffle: the bounds (in twips) of every fill and stroke drawn with bitmap `id`.
    fn bitmap_fill_bounds(&self, id: u16) -> Rectangle<Twips> {
        fn uses(style: &FillStyle, id: u16) -> bool {
            matches!(style, FillStyle::Bitmap { id: fill_id, .. } if *fill_id == id)
        }
        let mut bounds = Rectangle::default();
        let mut add = |commands: &[DrawCommand], width: Twips| {
            let mut from = Point::ZERO;
            for command in commands {
                if !matches!(command, DrawCommand::MoveTo(_)) {
                    bounds = stretch_bounds(&bounds, &DrawCommand::MoveTo(from), width, from);
                    bounds = stretch_bounds(&bounds, command, width, from);
                }
                from = command.end_point();
            }
        };
        let fills = self
            .paths
            .iter()
            .filter_map(|path| match path {
                DrawingPath::Fill(fill) => Some(fill),
                DrawingPath::Line(_) => None,
            })
            .chain(self.current_fill.iter());
        for fill in fills {
            if uses(&fill.style, id) {
                add(&fill.commands, Twips::ZERO);
            }
        }
        let lines = self
            .paths
            .iter()
            .filter_map(|path| match path {
                DrawingPath::Line(line) => Some(line),
                DrawingPath::Fill(_) => None,
            })
            .chain(self.pending_lines.iter())
            .chain(self.current_line.iter());
        for line in lines {
            if uses(line.style.fill_style(), id) {
                add(&line.commands, line.style.width());
            }
        }
        bounds
    }

    /// Timffle: the size of the bitmap a shader fill is evaluated into: the fill's bounds
    /// mapped back into shader space (where `outCoord()` starts at the origin), so the
    /// shader sees the same coordinates as in Flash Player for a fill that lies in the
    /// positive quadrant.
    fn shader_fill_size(&self, id: u16) -> Option<BitmapSize> {
        let entry = self.shader_fills.get((id - SHADER_FILL_ID_BASE) as usize)?;
        if let Some(size) = entry.size.get() {
            return Some(size);
        }
        let bounds = self.bitmap_fill_bounds(id);
        if !bounds.is_valid() {
            return None;
        }
        let inverse = ruffle_render::matrix::Matrix::from(entry.matrix)
            .inverse()
            .unwrap_or_default();
        let corners = [
            Point::new(bounds.x_min, bounds.y_min),
            Point::new(bounds.x_max, bounds.y_min),
            Point::new(bounds.x_min, bounds.y_max),
            Point::new(bounds.x_max, bounds.y_max),
        ];
        let (mut max_x, mut max_y) = (0.0f64, 0.0f64);
        for corner in corners {
            let p = inverse * corner;
            max_x = max_x.max(p.x.to_pixels());
            max_y = max_y.max(p.y.to_pixels());
        }
        let size = BitmapSize {
            width: max_x.ceil().clamp(1.0, SHADER_FILL_MAX_SIZE) as u32,
            height: max_y.ceil().clamp(1.0, SHADER_FILL_MAX_SIZE) as u32,
        };
        entry.size.set(Some(size));
        Some(size)
    }

    /// Timffle: evaluate the shader fill `id` (once) and return its bitmap.
    fn shader_fill_bitmap(&self, id: u16, backend: &mut dyn RenderBackend) -> Option<BitmapHandle> {
        let size = self.shader_fill_size(id)?;
        let entry = self.shader_fills.get((id - SHADER_FILL_ID_BASE) as usize)?;
        if let Some(cached) = entry.bitmap.borrow().as_ref() {
            return cached.clone();
        }
        let result = (|| {
            let handle = backend
                .create_empty_texture(NonZeroU32::new(size.width)?, NonZeroU32::new(size.height)?)
                .ok()?;
            backend
                .run_pixelbender_shader(
                    entry.shader.clone(),
                    &entry.arguments,
                    &PixelBenderTarget::Bitmap(handle.clone()),
                )
                .ok()?;
            Some(handle)
        })();
        if result.is_none() {
            tracing::warn!("Shader fill could not be evaluated by this renderer; drawing nothing");
        }
        *entry.bitmap.borrow_mut() = Some(result.clone());
        result
    }

    /// Timffle: the matrix a shader fill was given (shader coordinates -> shape pixels).
    pub fn shader_fill_matrix(&self, id: u16) -> Option<swf::Matrix> {
        self.shader_fills
            .get(id.checked_sub(SHADER_FILL_ID_BASE)? as usize)
            .map(|entry| entry.matrix)
    }

    /// Timffle: the `Shader` object of a shader fill, if known.
    pub fn shader_fill_object(&self, id: u16) -> Option<&ObjectRoot> {
        self.shader_fills
            .get(id.checked_sub(SHADER_FILL_ID_BASE)? as usize)?
            .object
            .as_ref()
    }

    /// Obtain a `ShapeHandle` that represents this `Drawing`, or `None` if it is empty.
    pub fn register_or_replace(&self, renderer: &mut dyn RenderBackend) -> Option<ShapeHandle> {
        if self.is_empty {
            return None;
        }

        let handle = self.render_handle.get_or_init(|| {
            let mut paths = Vec::with_capacity(self.paths.len());

            for path in &self.paths {
                match path {
                    DrawingPath::Fill(fill) => {
                        paths.push(DrawPath::Fill {
                            style: &fill.style,
                            commands: fill.commands.to_owned(),
                            winding_rule: fill.rule,
                        });
                    }
                    DrawingPath::Line(line) => {
                        paths.push(DrawPath::Stroke {
                            style: &line.style,
                            commands: line.commands.to_owned(),
                            is_closed: line.is_closed,
                        });
                    }
                }
            }

            if let Some(fill) = &self.current_fill {
                paths.push(DrawPath::Fill {
                    style: &fill.style,
                    commands: fill.commands.to_owned(),
                    winding_rule: fill.rule,
                })
            }

            for line in &self.pending_lines {
                let mut commands = line.commands.to_owned();
                // Timffle: drawPath strokes are never implicitly closed.
                let is_closed = if self.current_fill.is_some() && line.auto_close {
                    commands.push(DrawCommand::LineTo(self.fill_start));
                    true
                } else {
                    self.cursor == self.fill_start
                };
                paths.push(DrawPath::Stroke {
                    style: &line.style,
                    commands,
                    is_closed,
                })
            }

            if let Some(line) = &self.current_line {
                let mut commands = line.commands.to_owned();
                let is_closed = if self.current_fill.is_some() && line.auto_close {
                    commands.push(DrawCommand::LineTo(self.fill_start));
                    true
                } else {
                    self.cursor == self.fill_start
                };
                paths.push(DrawPath::Stroke {
                    style: &line.style,
                    commands,
                    is_closed,
                })
            }

            let shape = DistilledShape {
                paths,
                shape_bounds: self.shape_bounds,
                edge_bounds: self.edge_bounds,
                id: 0,
            };
            renderer.register_shape(shape, self)
        });

        Some(handle.clone())
    }

    pub fn render(&self, context: &mut RenderContext) {
        if let Some(handle) = self.register_or_replace(context.renderer) {
            context
                .commands
                .render_shape(handle, context.transform_stack.transform());
        }
    }

    pub fn self_bounds(&self, include_strokes: bool) -> Rectangle<Twips> {
        if include_strokes {
            self.shape_bounds
        } else {
            self.edge_bounds
        }
    }

    pub fn hit_test(
        &self,
        point: Point<Twips>,
        local_matrix: &ruffle_render::matrix::Matrix,
    ) -> bool {
        use ruffle_render::shape_utils;
        for path in &self.paths {
            match path {
                DrawingPath::Fill(fill) => {
                    if shape_utils::draw_command_fill_hit_test(&fill.commands, fill.rule, point) {
                        return true;
                    }
                }
                DrawingPath::Line(line) => {
                    if shape_utils::draw_command_stroke_hit_test(
                        &line.commands,
                        line.style.width(),
                        point,
                        local_matrix,
                    ) {
                        return true;
                    }
                }
            }
        }

        // The pending fill will auto-close.
        if let Some(fill) = &self.current_fill
            && shape_utils::draw_command_fill_hit_test(&fill.commands, fill.rule, point)
        {
            return true;
        }

        for line in &self.pending_lines {
            if shape_utils::draw_command_stroke_hit_test(
                &line.commands,
                line.style.width(),
                point,
                local_matrix,
            ) {
                return true;
            }
        }

        if let Some(line) = &self.current_line {
            if shape_utils::draw_command_stroke_hit_test(
                &line.commands,
                line.style.width(),
                point,
                local_matrix,
            ) {
                return true;
            }

            // Stroke auto-closes if part of a fill; also check the closing line segment.
            if self.current_fill.is_some()
                && line.auto_close
                && self.cursor != self.fill_start
                && shape_utils::draw_command_stroke_hit_test(
                    &[
                        DrawCommand::MoveTo(self.cursor),
                        DrawCommand::LineTo(self.fill_start),
                    ],
                    line.style.width(),
                    point,
                    local_matrix,
                )
            {
                return true;
            }
        }

        false
    }

    // Ensures that the path is closed for a pending fill.
    pub fn close_path(&mut self) {
        if let Some(fill) = &mut self.current_fill
            && self.cursor != self.fill_start
        {
            fill.commands.push(DrawCommand::LineTo(self.fill_start));
            if let Some(line) = &mut self.current_line
                && line.auto_close
            {
                // Timffle: a stroke made of nothing but this closing segment (the
                // lineStyle continued after a `drawPath`) is drawn but not reported by
                // readGraphicsData (Flash Player 32, measured).
                line.close_only = line.commands.len() == 1;
                line.commands.push(DrawCommand::LineTo(self.fill_start));
            }
            self.mark_dirty();
        }
    }
}

impl Drawing {
    /// Timffle: the recorded drawing in the form `Graphics.readGraphicsData` reports it
    /// (measured on Flash Player 32, timffle/difftest/src/D55Graphics.hx,
    /// D56Graphics2.hx, D57Winding.hx): every fill group in order, each followed by the
    /// strokes recorded inside it; a stroke sub-path is split at every lineStyle change,
    /// strokes of lineTo-drawn fills include the implicit closing segment and a closed
    /// loop is reported starting after its first segment.
    pub fn read_graphics_data(&self) -> Vec<GraphicsReadItem> {
        let mut items = Vec::new();
        let push_fill = |items: &mut Vec<GraphicsReadItem>, fill: &DrawingFill| {
            let commands = fill_read_commands(&fill.commands);
            if commands
                .iter()
                .any(|c| !matches!(c, DrawCommand::MoveTo(_)))
            {
                items.push(GraphicsReadItem::Fill {
                    style: fill.style.clone(),
                    rule: match fill.origin {
                        FillOrigin::Path(rule) => rule,
                        FillOrigin::Commands | FillOrigin::Triangles => FillRule::EvenOdd,
                    },
                    commands,
                });
            }
        };
        let push_line = |items: &mut Vec<GraphicsReadItem>, line: &DrawingLine, close: bool| {
            if line.close_only {
                return;
            }
            let mut commands = line.commands.clone();
            if close
                && let Some(last) = commands.last()
                && last.end_point() != self.fill_start
            {
                commands.push(DrawCommand::LineTo(self.fill_start));
            }
            let commands = stroke_read_commands(&commands);
            if !commands.is_empty() {
                items.push(GraphicsReadItem::Stroke {
                    style: line.style.clone(),
                    commands,
                });
            }
        };
        for path in &self.paths {
            match path {
                DrawingPath::Fill(fill) => push_fill(&mut items, fill),
                DrawingPath::Line(line) => push_line(&mut items, line, false),
            }
        }
        if let Some(fill) = &self.current_fill {
            push_fill(&mut items, fill);
        }
        // Only the stroke that is still being drawn gets the implicit closing segment
        // of an open fill (`close_path` adds it to the current line at endFill time).
        for line in &self.pending_lines {
            push_line(&mut items, line, false);
        }
        if let Some(line) = &self.current_line {
            push_line(
                &mut items,
                line,
                self.current_fill.is_some() && line.auto_close,
            );
        }
        items
    }
}

/// Timffle: fill commands as readGraphicsData reports them: consecutive MoveTos collapsed
/// into the last one, no trailing MoveTo, and every sub-path closed with a line back to
/// its start (Flash Player 32 reports the closing segment of an open fill, also of a
/// `drawPath` sub-path and of a fill that `endFill` has not closed yet; measured).
fn fill_read_commands(commands: &[DrawCommand]) -> Vec<DrawCommand> {
    let mut out: Vec<DrawCommand> = Vec::with_capacity(commands.len() + 2);
    let mut start: Option<Point<Twips>> = None;
    let close = |out: &mut Vec<DrawCommand>, start: Option<Point<Twips>>| {
        if let (Some(start), Some(last)) = (start, out.last())
            && !matches!(last, DrawCommand::MoveTo(_))
            && last.end_point() != start
        {
            out.push(DrawCommand::LineTo(start));
        }
    };
    for command in commands {
        if let DrawCommand::MoveTo(point) = command {
            close(&mut out, start);
            if matches!(out.last(), Some(DrawCommand::MoveTo(_))) {
                out.pop();
            }
            start = Some(*point);
        }
        out.push(command.clone());
    }
    close(&mut out, start);
    while matches!(out.last(), Some(DrawCommand::MoveTo(_))) {
        out.pop();
    }
    out
}

/// Timffle: stroke commands as readGraphicsData reports them: sub-paths without a
/// segment are dropped and closed loops are rotated (see `rotate_closed_stroke`).
fn stroke_read_commands(commands: &[DrawCommand]) -> Vec<DrawCommand> {
    let mut out = Vec::with_capacity(commands.len());
    let mut sub_path: Vec<DrawCommand> = Vec::new();
    let flush = |sub_path: &mut Vec<DrawCommand>, out: &mut Vec<DrawCommand>| {
        if sub_path.len() > 1 {
            out.extend(rotate_closed_stroke(sub_path));
        }
        sub_path.clear();
    };
    let mut start = Point::ZERO;
    for command in commands {
        if let DrawCommand::MoveTo(point) = command {
            flush(&mut sub_path, &mut out);
            start = *point;
        } else if sub_path.is_empty() {
            sub_path.push(DrawCommand::MoveTo(start));
        }
        sub_path.push(command.clone());
    }
    flush(&mut sub_path, &mut out);
    out
}

/// Timffle: Flash Player reports a closed stroke loop `M p0, s1 (->p1), s2, …, sk (->p0)`
/// as `M p1, s2, …, sk, s1` (it starts after the first segment and appends that segment
/// at the end); segments after the closure point form a new MoveTo sub-path.
fn rotate_closed_stroke(sub_path: &[DrawCommand]) -> Vec<DrawCommand> {
    let DrawCommand::MoveTo(p0) = sub_path[0] else {
        return sub_path.to_vec();
    };
    let closure = sub_path
        .iter()
        .enumerate()
        .skip(2)
        .find(|(_, c)| c.end_point() == p0)
        .map(|(i, _)| i);
    let Some(k) = closure else {
        return sub_path.to_vec();
    };
    let first = &sub_path[1];
    let mut out = Vec::with_capacity(sub_path.len() + 2);
    out.push(DrawCommand::MoveTo(first.end_point()));
    out.extend(sub_path[2..=k].iter().cloned());
    out.push(first.clone());
    if k + 1 < sub_path.len() {
        out.push(DrawCommand::MoveTo(p0));
        out.extend(sub_path[k + 1..].iter().cloned());
    }
    out
}

impl BitmapSource for Drawing {
    fn bitmap_size(&self, id: u16) -> Option<BitmapSize> {
        // Timffle: shader fills are evaluated into a bitmap sized from the fill's bounds.
        if self.is_shader_fill(id) {
            return self.shader_fill_size(id);
        }
        self.bitmaps.get(id as usize).map(|bm| BitmapSize {
            width: bm.width,
            height: bm.height,
        })
    }
    fn bitmap_handle(&self, id: u16, backend: &mut dyn RenderBackend) -> Option<BitmapHandle> {
        // Timffle: shader fills run the Pixel Bender shader when first rendered.
        if self.is_shader_fill(id) {
            return self.shader_fill_bitmap(id, backend);
        }
        self.bitmaps.get(id as usize).map(|bm| bm.handle.clone())
    }
}

#[derive(Debug, Clone)]
struct DrawingFill {
    style: FillStyle,
    rule: FillRule,
    commands: Vec<DrawCommand>,
    // Timffle: which API started this group (see `FillOrigin`).
    origin: FillOrigin,
}

#[derive(Debug, Clone)]
struct DrawingLine {
    style: LineStyle,
    commands: Vec<DrawCommand>,
    is_closed: bool,
    // Timffle: false for drawPath strokes, which never get the implicit closing segment.
    auto_close: bool,
    // Timffle: the only segment is the implicit closing one (see `close_path`).
    close_only: bool,
}

#[derive(Debug, Clone)]
enum DrawingPath {
    Fill(DrawingFill),
    Line(DrawingLine),
}

fn stretch_bounds(
    bounds: &Rectangle<Twips>,
    command: &DrawCommand,
    stroke_width: Twips,
    from: Point<Twips>,
) -> Rectangle<Twips> {
    match *command {
        DrawCommand::MoveTo(point) | DrawCommand::LineTo(point) => {
            let radius = stroke_width / 2;
            bounds
                .encompass(Point::new(point.x - radius, point.y - radius))
                .encompass(Point::new(point.x + radius, point.y + radius))
        }
        DrawCommand::QuadraticCurveTo { control, anchor } => {
            bounds.union(&quadratic_curve_bounds(from, stroke_width, control, anchor))
        }
        DrawCommand::CubicCurveTo {
            control_a,
            control_b,
            anchor,
        } => bounds.union(&cubic_curve_bounds(
            from,
            stroke_width,
            control_a,
            control_b,
            anchor,
        )),
    }
}
