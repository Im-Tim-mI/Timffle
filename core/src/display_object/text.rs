use crate::avm1::Object as Avm1Object;
use crate::avm2::StageObject as Avm2StageObject;
use crate::context::{RenderContext, UpdateContext};
use crate::display_object::{BoundsMode, DisplayObjectBase, DisplayObjectContainer};
use crate::font::{Font, FontLike, TextRenderSettings};
use crate::prelude::*;
use crate::tag_utils::SwfMovie;
use crate::vminterface::Instantiator;
use core::fmt;
use gc_arena::Lock;
use gc_arena::barrier::unlock;
use gc_arena::{Collect, Gc, Mutation};
use ruffle_common::utils::HasPrefixField;
use ruffle_render::commands::CommandHandler as _; // Timffle: draw_rect
use ruffle_render::transform::Transform;
use ruffle_wstr::{WStr, WString};
use std::borrow::Cow;
use std::cell::{Cell, RefCell};

#[derive(Clone, Collect, Copy)]
#[collect(no_drop)]
pub struct Text<'gc>(Gc<'gc, TextData<'gc>>);

impl fmt::Debug for Text<'_> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("Text")
            .field("ptr", &Gc::as_ptr(self.0))
            .finish()
    }
}

#[derive(Clone, Collect, HasPrefixField)]
#[collect(no_drop)]
#[repr(C, align(8))]
pub struct TextData<'gc> {
    base: DisplayObjectBase<'gc>,
    shared: Lock<Gc<'gc, TextShared<'gc>>>,
    render_settings: RefCell<TextRenderSettings>,
    avm2_object: Lock<Option<Avm2StageObject<'gc>>>,
    /// Timffle: `TextSnapshot.setSelected` state, one flag per glyph of this
    /// text in `text_blocks` order. Selected glyphs are drawn over a rectangle
    /// of `snapshot_select_color` (`TextSnapshot.setSelectColor`, default
    /// `0xFFFF00`).
    #[collect(require_static)]
    snapshot_selection: RefCell<Vec<bool>>,
    #[collect(require_static)]
    snapshot_select_color: Cell<u32>,
}

impl<'gc> Text<'gc> {
    pub fn from_swf_tag(
        context: &mut UpdateContext<'gc>,
        swf: SwfMovie<'gc>,
        tag: &swf::Text,
    ) -> Self {
        Text(Gc::new(
            context.gc(),
            TextData {
                base: Default::default(),
                shared: Lock::new(Gc::new(
                    context.gc(),
                    TextShared {
                        swf,
                        id: tag.id,
                        bounds: tag.bounds,
                        text_transform: tag.matrix.into(),
                        text_blocks: tag.records.clone(),
                    },
                )),
                render_settings: RefCell::new(Default::default()),
                avm2_object: Lock::new(None),
                snapshot_selection: RefCell::new(Vec::new()),
                snapshot_select_color: Cell::new(TextSnapshot::DEFAULT_SELECT_COLOR),
            },
        ))
    }

    pub fn instantiate(self, mc: &Mutation<'gc>) -> Self {
        Self(Gc::new(mc, (*self.0).clone()))
    }

    fn set_shared(&self, context: &mut UpdateContext<'gc>, to: Gc<'gc, TextShared<'gc>>) {
        let mc = context.gc();
        unlock!(Gc::write(mc, self.0), TextData, shared).set(to);
    }

    pub fn set_render_settings(self, settings: TextRenderSettings) {
        *self.0.render_settings.borrow_mut() = settings;
        self.invalidate_cached_bitmap();
    }

    pub fn text(self, context: &mut UpdateContext<'gc>) -> Option<WString> {
        let mut ret = WString::new();

        let mut font_id = None;

        for block in &self.0.shared.get().text_blocks {
            if block.font_id.is_some() {
                font_id = block.font_id;
            }

            let font = context
                .library
                .library_for_movie(self.movie())
                .unwrap()
                .get_font(font_id?)?;

            for glyph in &block.glyphs {
                if let Some(g) = font.get_glyph(glyph.index as usize) {
                    ret.push_char(g.character());
                }
            }
        }

        if ret.is_empty() { None } else { Some(ret) }
    }

    /// Timffle: the glyphs of this static text with their geometry, in the
    /// text's own (pre-`text_transform`) coordinate space, in `text_blocks`
    /// order. This is the same walk `render_self` and `hit_test_shape` do.
    pub fn glyph_layout(self, context: &mut UpdateContext<'gc>) -> Vec<StaticGlyph<'gc>> {
        let shared = self.0.shared.get();
        let mut glyphs = Vec::new();
        let mut color = swf::Color::from_rgba(0);
        let mut font_id = 0;
        let mut height = Twips::ZERO;
        let mut x = Twips::ZERO;
        let mut y = Twips::ZERO;
        for block in &shared.text_blocks {
            if let Some(bx) = block.x_offset {
                x = bx;
            }
            if let Some(by) = block.y_offset {
                y = by;
            }
            color = block.color.unwrap_or(color);
            font_id = block.font_id.unwrap_or(font_id);
            height = block.height.unwrap_or(height);
            let Some(font) = context
                .library
                .library_for_movie(self.movie())
                .and_then(|library| library.get_font(font_id))
            else {
                continue;
            };
            let metrics = font.metrics();
            for (index_in_record, entry) in block.glyphs.iter().enumerate() {
                let Some(glyph) = font.get_glyph(entry.index as usize) else {
                    continue;
                };
                glyphs.push(StaticGlyph {
                    index_in_record,
                    character: glyph.character(),
                    font,
                    color,
                    height,
                    x,
                    baseline: y,
                    advance: Twips::new(entry.advance),
                    ascent: metrics.ascent(height),
                    descent: metrics.descent(height),
                });
                x += Twips::new(entry.advance);
            }
        }
        glyphs
    }

    /// Timffle: the matrix from this text's glyph space to its parent's
    /// coordinate space (the text's own transform times the `DefineText`
    /// matrix), which is what `TextSnapshot` reports positions in.
    pub fn text_to_parent_matrix(self) -> Matrix {
        self.base().matrix() * self.0.shared.get().text_transform
    }

    /// Timffle: whether the glyph at `index` is selected through `TextSnapshot`.
    pub fn is_glyph_selected(self, index: usize) -> bool {
        self.0
            .snapshot_selection
            .borrow()
            .get(index)
            .copied()
            .unwrap_or(false)
    }

    /// Timffle: `TextSnapshot.setSelected` for the glyphs `from..to` of this text.
    pub fn set_glyphs_selected(self, from: usize, to: usize, select: bool) {
        {
            let mut selection = self.0.snapshot_selection.borrow_mut();
            if selection.len() < to {
                selection.resize(to, false);
            }
            for flag in &mut selection[from..to] {
                *flag = select;
            }
        }
        self.invalidate_cached_bitmap();
    }

    /// Timffle: `TextSnapshot.setSelectColor`; the colour is always opaque.
    pub fn set_snapshot_select_color(self, color: u32) {
        self.0.snapshot_select_color.set(color & 0xFF_FFFF);
        self.invalidate_cached_bitmap();
    }

    /// Timffle: draws the `TextSnapshot.setSelected` rectangles. Must run with
    /// the `DefineText` matrix already on the transform stack.
    fn render_snapshot_selection(self, context: &mut RenderContext<'_, 'gc>) {
        let selection = self.0.snapshot_selection.borrow();
        if !selection.iter().any(|&selected| selected) {
            return;
        }
        let color = swf::Color::from_rgb(self.0.snapshot_select_color.get(), 0xFF);
        let shared = self.0.shared.get();
        let mut font_id = 0;
        let mut height = Twips::ZERO;
        let mut x = Twips::ZERO;
        let mut y = Twips::ZERO;
        let mut index = 0;
        for block in &shared.text_blocks {
            if let Some(bx) = block.x_offset {
                x = bx;
            }
            if let Some(by) = block.y_offset {
                y = by;
            }
            font_id = block.font_id.unwrap_or(font_id);
            height = block.height.unwrap_or(height);
            let Some(font) = context
                .library
                .library_for_movie(self.movie())
                .and_then(|library| library.get_font(font_id))
            else {
                continue;
            };
            let metrics = font.metrics();
            for entry in &block.glyphs {
                if font.get_glyph(entry.index as usize).is_none() {
                    continue;
                }
                let advance = Twips::new(entry.advance);
                if selection.get(index).copied().unwrap_or(false) {
                    let ascent = metrics.ascent(height);
                    let box_height = ascent + metrics.descent(height);
                    let matrix = context.transform_stack.transform().matrix
                        * Matrix::create_box(
                            advance.to_pixels() as f32,
                            box_height.to_pixels() as f32,
                            x,
                            y - ascent,
                        );
                    context.commands.draw_rect(color, matrix);
                }
                x += advance;
                index += 1;
            }
        }
    }
}

/// Timffle: one glyph of a static text as `TextSnapshot` sees it. Positions
/// are in the text's own coordinate space (before `DefineText`'s matrix).
#[derive(Clone, Copy)]
pub struct StaticGlyph<'gc> {
    /// The glyph's position in its `DefineText` text record (`indexInRun`).
    pub index_in_record: usize,
    pub character: char,
    pub font: Font<'gc>,
    pub color: swf::Color,
    /// The font height (the `height` of the text record).
    pub height: Twips,
    /// The glyph's left edge.
    pub x: Twips,
    /// The baseline the glyph sits on.
    pub baseline: Twips,
    pub advance: Twips,
    pub ascent: Twips,
    pub descent: Twips,
}

impl StaticGlyph<'_> {
    /// The glyph's bounding box: `advance` wide, from `ascent` above the
    /// baseline to `descent` below it.
    pub fn bounds(&self) -> Rectangle<Twips> {
        Rectangle {
            x_min: self.x,
            x_max: self.x + self.advance,
            y_min: self.baseline - self.ascent,
            y_max: self.baseline + self.descent,
        }
    }
}

impl<'gc> TDisplayObject<'gc> for Text<'gc> {
    fn base(self) -> Gc<'gc, DisplayObjectBase<'gc>> {
        HasPrefixField::as_prefix_gc(self.0)
    }

    fn id(self) -> CharacterId {
        self.0.shared.get().id
    }

    fn movie(self) -> SwfMovie<'gc> {
        self.0.shared.get().swf
    }

    fn replace_with(self, context: &mut UpdateContext<'gc>, id: CharacterId) {
        if let Some(new_text) = context
            .library
            .library_for_movie_mut(self.movie())
            .get_text(id)
        {
            self.set_shared(context, new_text.0.shared.get());
        } else {
            tracing::warn!("PlaceObject: expected text at character ID {}", id);
        }
        self.invalidate_cached_bitmap();
    }

    fn render_self(self, context: &mut RenderContext<'_, 'gc>) {
        if !context.is_offscreen
            && !self
                .world_bounds(BoundsMode::Engine)
                .intersects(&context.stage.view_bounds())
        {
            // Off-screen; culled
            return;
        }

        let shared = self.0.shared.get();
        context.transform_stack.push(&Transform {
            matrix: shared.text_transform,
            ..Default::default()
        });

        // Timffle: `TextSnapshot.setSelected` highlights go under the glyphs.
        self.render_snapshot_selection(context);

        let mut color = swf::Color {
            r: 0,
            g: 0,
            b: 0,
            a: 0,
        };
        let mut font_id = 0;
        let mut height = Twips::ZERO;
        let mut transform: Transform = Default::default();
        for block in &shared.text_blocks {
            if let Some(x) = block.x_offset {
                transform.matrix.tx = x;
            }
            if let Some(y) = block.y_offset {
                transform.matrix.ty = y;
            }
            color = block.color.unwrap_or(color);
            font_id = block.font_id.unwrap_or(font_id);
            height = block.height.unwrap_or(height);
            if let Some(font) = context
                .library
                .library_for_movie(self.movie())
                .unwrap()
                .get_font(font_id)
            {
                let scale = (height.get() as f32) / font.scale();
                transform.matrix.a = scale;
                transform.matrix.d = scale;
                transform.color_transform.set_mult_color(color);
                for c in &block.glyphs {
                    if let Some(glyph) = font.get_glyph(c.index as usize) {
                        if glyph.renderable(context) {
                            context.transform_stack.push(&transform);
                            glyph.render(context);
                            context.transform_stack.pop();
                        }

                        transform.matrix.tx += Twips::new(c.advance);
                    }
                }
            }
        }
        context.transform_stack.pop();
    }

    fn self_bounds(self, _mode: BoundsMode) -> Rectangle<Twips> {
        self.0.shared.get().bounds
    }

    fn hit_test_shape(
        self,
        context: &mut UpdateContext<'gc>,
        mut point: Point<Twips>,
        options: HitTestOptions,
    ) -> bool {
        if (!options.contains(HitTestOptions::SKIP_INVISIBLE) || self.visible())
            && self.world_bounds(BoundsMode::Engine).contains(point)
        {
            // Texts using the "Advanced text rendering" always hit test using their bounding box.
            if self.0.render_settings.borrow().is_advanced() {
                return true;
            }

            let shared = self.0.shared.get();

            // Transform the point into the text's local space.
            let Some(local_matrix) = self.global_to_local_matrix() else {
                return false;
            };
            let Some(text_matrix) = shared.text_transform.inverse() else {
                return false;
            };
            let _ = local_matrix;
            let Some(local_point) = self.global_to_local(point) else {
                return false;
            };
            point = text_matrix * local_point;

            let mut font_id = 0;
            let mut height = Twips::ZERO;
            let mut glyph_matrix = Matrix::default();
            for block in &shared.text_blocks {
                if let Some(x) = block.x_offset {
                    glyph_matrix.tx = x;
                }
                if let Some(y) = block.y_offset {
                    glyph_matrix.ty = y;
                }
                font_id = block.font_id.unwrap_or(font_id);
                height = block.height.unwrap_or(height);

                if let Some(font) = context
                    .library
                    .library_for_movie(self.movie())
                    .unwrap()
                    .get_font(font_id)
                {
                    let scale = (height.get() as f32) / font.scale();
                    glyph_matrix.a = scale;
                    glyph_matrix.d = scale;
                    for c in &block.glyphs {
                        if let Some(glyph) = font.get_glyph(c.index as usize) {
                            // Transform the point into glyph space and test.
                            let Some(matrix) = glyph_matrix.inverse() else {
                                return false;
                            };
                            let point = matrix * point;
                            if glyph.hit_test(point, &local_matrix) {
                                return true;
                            }

                            glyph_matrix.tx += Twips::new(c.advance);
                        }
                    }
                }
            }
        }

        false
    }

    fn construct_frame(self, context: &mut UpdateContext<'gc>) {
        if self.movie().is_action_script_3() && self.object2().is_none() {
            let statictext = context.avm2.classes().statictext;

            let object = Avm2StageObject::for_display_object(context.gc(), self.into(), statictext);
            // We don't need to call the initializer method, as AVM2 can't link
            // a custom class to a StaticText, and the initializer method for
            // StaticText itself is a no-op
            self.set_object2(context, object);

            self.on_construction_complete(context);
        }
    }

    fn post_instantiation(
        self,
        context: &mut UpdateContext<'gc>,
        _init_object: Option<Avm1Object<'gc>>,
        _instantiated_by: Instantiator,
        _run_frame: bool,
    ) {
        if self.movie().is_action_script_3() {
            self.set_default_instance_name(context);
        }
    }

    fn object1(self) -> Option<crate::avm1::Object<'gc>> {
        None
    }

    fn object2(self) -> Option<Avm2StageObject<'gc>> {
        self.0.avm2_object.get()
    }

    fn set_object2(self, context: &mut UpdateContext<'gc>, to: Avm2StageObject<'gc>) {
        let mc = context.gc();
        unlock!(Gc::write(mc, self.0), TextData, avm2_object).set(Some(to));
    }
}

/// Data shared between all instances of a text object.
#[derive(Debug, Clone, Collect)]
#[collect(no_drop)]
struct TextShared<'gc> {
    swf: SwfMovie<'gc>,
    id: CharacterId,

    #[collect(require_static)]
    bounds: Rectangle<Twips>,

    #[collect(require_static)]
    text_transform: Matrix,

    #[collect(require_static)]
    text_blocks: Vec<swf::TextRecord>,
}

#[derive(Clone, Collect, Copy)]
#[collect(no_drop)]
pub struct TextSnapshot<'gc>(Gc<'gc, TextSnapshotData<'gc>>);

impl fmt::Debug for TextSnapshot<'_> {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        f.debug_struct("TextSnapshot")
            .field("ptr", &Gc::as_ptr(self.0))
            .finish()
    }
}

#[derive(Collect)]
#[collect(no_drop)]
pub struct TextSnapshotData<'gc> {
    chunks: Vec<TextSnapshotChunk<'gc>>,
}

#[derive(Collect)]
#[collect(no_drop)]
struct TextSnapshotChunk<'gc> {
    object: Text<'gc>,
    #[collect(require_static)]
    text: WString,
    global_index: usize,
}

impl<'gc> TextSnapshotChunk<'gc> {
    fn sub_string(&self, global_index_start: usize, global_index_end: usize) -> &WStr {
        let start = global_index_start.saturating_sub(self.global_index);
        let end = global_index_end
            .saturating_sub(self.global_index)
            .min(self.text.len());
        &self.text[start..end]
    }
}

impl<'gc> TextSnapshot<'gc> {
    /// Timffle: the `hexColor` default of `TextSnapshot.setSelectColor`.
    pub const DEFAULT_SELECT_COLOR: u32 = 0xFF_FF00;

    // Timffle: takes any container (AVM2 `DisplayObjectContainer.textSnapshot`
    // exists on Sprite, Loader and Stage too), not only a MovieClip.
    pub fn new(context: &mut UpdateContext<'gc>, target: DisplayObjectContainer<'gc>) -> Self {
        let mut chunks = Vec::new();
        let mut index = 0;
        for child in target.iter_render_list() {
            if let Some(object) = child.as_text()
                && let Some(text) = object.text(context)
            {
                let len = text.len();
                chunks.push(TextSnapshotChunk {
                    object,
                    text,
                    global_index: index,
                });
                index += len;
            }
        }

        Self(Gc::new(context.gc(), TextSnapshotData { chunks }))
    }

    pub fn count(self) -> usize {
        self.0.chunks.iter().map(|c| c.text.len()).sum()
    }

    /// Timffle: the index rules every range method of `TextSnapshot` shares
    /// (Adobe reference, `getSelected`): a negative `beginIndex` is 0 and it is
    /// at most `charCount - 1`; `endIndex` is at most `charCount`, and when it
    /// is not past `beginIndex` it becomes `beginIndex + 1`. `None` when the
    /// snapshot has no text at all.
    fn clamp_range(self, from: i32, to: i32) -> Option<(usize, usize)> {
        let count = self.count();
        if count == 0 {
            return None;
        }
        let start = usize::try_from(from).unwrap_or_default().min(count - 1);
        let end = usize::try_from(to)
            .unwrap_or_default()
            .min(count)
            .max(start + 1);
        Some((start, end))
    }

    pub fn get_text(self, from: i32, to: i32, include_newlines: bool) -> WString {
        let Some((start, end)) = self.clamp_range(from, to) else {
            return WString::new();
        };

        let mut chunks = self
            .0
            .chunks
            .iter()
            .filter(|c| c.global_index < end)
            .filter(|c| c.global_index + c.text.len() > start)
            .map(|c| c.sub_string(start, end));

        let mut ret = WString::new();

        if let Some(chunk) = chunks.next() {
            ret.push_str(chunk);
        }

        for chunk in chunks {
            if include_newlines {
                ret.push_char('\n');
            }
            ret.push_str(chunk);
        }

        ret
    }

    pub fn find_text(self, from: i32, text: &WStr, case_sensitive: bool) -> i32 {
        if text.is_empty() {
            return -1;
        }

        let Ok(from) = usize::try_from(from) else {
            return -1;
        };
        let count = self.count();

        let chunks = self
            .0
            .chunks
            .iter()
            .filter(|c| c.global_index + c.text.len() > from)
            .map(|c| c.sub_string(from, count));

        let mut full_text = WString::new();
        for chunk in chunks {
            full_text.push_str(chunk);
        }

        let text = if !case_sensitive {
            full_text.make_ascii_lowercase();
            Cow::Owned(text.to_ascii_lowercase())
        } else {
            Cow::Borrowed(text)
        };

        let Some(index) = full_text.find(text.as_ref()) else {
            return -1;
        };

        i32::try_from(from + index).unwrap_or(-1)
    }

    /// Timffle: `TextSnapshot.setSelected`. Calls accumulate: selecting a range
    /// does not deselect the rest.
    pub fn set_selected(self, from: i32, to: i32, select: bool) {
        let Some((start, end)) = self.clamp_range(from, to) else {
            return;
        };
        for chunk in &self.0.chunks {
            let chunk_start = chunk.global_index;
            let chunk_end = chunk_start + chunk.text.len();
            if chunk_end <= start || chunk_start >= end {
                continue;
            }
            let local_from = start.max(chunk_start) - chunk_start;
            let local_to = end.min(chunk_end) - chunk_start;
            chunk
                .object
                .set_glyphs_selected(local_from, local_to, select);
        }
    }

    /// Timffle: whether the glyph at the global index `index` is selected.
    fn is_selected(self, index: usize) -> bool {
        self.0
            .chunks
            .iter()
            .find(|c| c.global_index <= index && index < c.global_index + c.text.len())
            .is_some_and(|c| c.object.is_glyph_selected(index - c.global_index))
    }

    /// Timffle: `TextSnapshot.getSelected`: true when at least one character
    /// of the range is selected.
    pub fn get_selected(self, from: i32, to: i32) -> bool {
        let Some((start, end)) = self.clamp_range(from, to) else {
            return false;
        };
        (start..end).any(|i| self.is_selected(i))
    }

    /// Timffle: `TextSnapshot.getSelectedText`: the selected characters, with a
    /// newline between two texts when `include_newlines` is set (like `getText`).
    pub fn get_selected_text(self, include_newlines: bool) -> WString {
        let mut ret = WString::new();
        let mut first_chunk = true;
        for chunk in &self.0.chunks {
            let mut chunk_has_selection = false;
            for (i, c) in chunk.text.iter().enumerate() {
                if chunk.object.is_glyph_selected(i) {
                    if !chunk_has_selection {
                        if include_newlines && !first_chunk {
                            ret.push_char('\n');
                        }
                        chunk_has_selection = true;
                    }
                    ret.push(c);
                }
            }
            if chunk_has_selection {
                first_chunk = false;
            }
        }
        ret
    }

    /// Timffle: `TextSnapshot.setSelectColor` for every text in the snapshot.
    pub fn set_select_color(self, color: u32) {
        for chunk in &self.0.chunks {
            chunk.object.set_snapshot_select_color(color);
        }
    }

    /// Timffle: the glyphs of the range `from..to` (global indices) with their
    /// geometry in the parent container's coordinate space.
    pub fn text_run_info(
        self,
        context: &mut UpdateContext<'gc>,
        from: i32,
        to: i32,
    ) -> Vec<TextRunInfo<'gc>> {
        // Timffle: unlike the other range methods, Flash Player 32 includes `endIndex`
        // here (`getTextRunInfo(0, 2)` is three characters; `(0, 0)`, `(1, 1)` and
        // `(38, 40)` of a 38-character snapshot are one), measured.
        let Some((start, _)) = self.clamp_range(from, to) else {
            return Vec::new();
        };
        let last = self.count() - 1;
        let end = usize::try_from(to).unwrap_or_default().min(last).max(start) + 1;
        let mut runs = Vec::new();
        for chunk in &self.0.chunks {
            let chunk_start = chunk.global_index;
            let chunk_end = chunk_start + chunk.text.len();
            if chunk_end <= start || chunk_start >= end {
                continue;
            }
            let matrix = chunk.object.text_to_parent_matrix();
            let glyphs = chunk.object.glyph_layout(context);
            for (i, glyph) in glyphs.into_iter().enumerate() {
                let index = chunk_start + i;
                if index < start || index >= end {
                    continue;
                }
                runs.push(TextRunInfo {
                    index,
                    selected: chunk.object.is_glyph_selected(i),
                    glyph,
                    matrix,
                });
            }
        }
        runs
    }

    /// Timffle: `TextSnapshot.hitTestTextNearPos`. `x`/`y` are in the parent
    /// container's coordinate space. With `max_distance == 0` the point must be
    /// inside a character's bounding box; otherwise the nearest character
    /// whose centre is within `max_distance` pixels wins.
    pub fn hit_test_text_near_pos(
        self,
        context: &mut UpdateContext<'gc>,
        x: f64,
        y: f64,
        max_distance: f64,
    ) -> i32 {
        let point = Point::new(Twips::from_pixels(x), Twips::from_pixels(y));
        let mut best: Option<(usize, f64)> = None;
        for chunk in &self.0.chunks {
            let matrix = chunk.object.text_to_parent_matrix();
            let Some(inverse) = matrix.inverse() else {
                continue;
            };
            let local = inverse * point;
            for (i, glyph) in chunk.object.glyph_layout(context).into_iter().enumerate() {
                // Timffle: a font without layout data has no character boxes, and
                // Flash Player 32 never hits such text (measured: -1 even at the
                // character's position with a large maxDistance).
                if !glyph.font.has_layout() {
                    continue;
                }
                let bounds = glyph.bounds();
                let index = chunk.global_index + i;
                if max_distance <= 0.0 {
                    if bounds.contains(local) {
                        return i32::try_from(index).unwrap_or(-1);
                    }
                    continue;
                }
                let centre = matrix
                    * Point::new(
                        (bounds.x_min + bounds.x_max) / 2,
                        (bounds.y_min + bounds.y_max) / 2,
                    );
                let dx = centre.x.to_pixels() - x;
                let dy = centre.y.to_pixels() - y;
                let distance = (dx * dx + dy * dy).sqrt();
                if distance <= max_distance && best.is_none_or(|(_, d)| distance < d) {
                    best = Some((index, distance));
                }
            }
        }
        best.and_then(|(index, _)| i32::try_from(index).ok())
            .unwrap_or(-1)
    }
}

/// Timffle: one entry of `TextSnapshot.getTextRunInfo`.
pub struct TextRunInfo<'gc> {
    /// The character's index in the whole snapshot.
    pub index: usize,
    pub selected: bool,
    pub glyph: StaticGlyph<'gc>,
    /// From the glyph's own space to the parent container's space.
    pub matrix: Matrix,
}
