use crate::context::RenderContext;
use ruffle_render::backend::{RenderBackend, ShapeHandle};
use ruffle_render::bitmap::{BitmapHandle, BitmapInfo, BitmapSize, BitmapSource};
use ruffle_render::commands::CommandHandler;
use ruffle_render::shape_utils::{
    DistilledShape, DrawCommand, DrawPath, FillRule, cubic_curve_bounds, quadratic_curve_bounds,
};
use std::cell::OnceCell;
use swf::{FillStyle, LineStyle, Point, Rectangle, Twips};

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
        id
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
                line.commands.push(DrawCommand::LineTo(self.fill_start));
            }
            self.mark_dirty();
        }
    }
}

impl BitmapSource for Drawing {
    fn bitmap_size(&self, id: u16) -> Option<BitmapSize> {
        self.bitmaps.get(id as usize).map(|bm| BitmapSize {
            width: bm.width,
            height: bm.height,
        })
    }
    fn bitmap_handle(&self, id: u16, _backend: &mut dyn RenderBackend) -> Option<BitmapHandle> {
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
