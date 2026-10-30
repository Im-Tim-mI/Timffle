use crate::font::{FontAtlases, FontMetrics, Glyph, glyph::GlyphRef};
use std::cell::{Cell, Ref, RefCell};
use swf::Twips;

pub trait FontRenderer: std::fmt::Debug {
    fn scale(&self) -> f32;

    fn get_font_metrics(&self) -> FontMetrics;

    fn has_kerning_info(&self) -> bool;

    fn render_glyph(&self, character: char) -> Option<Glyph>;

    fn calculate_kerning(&self, left: char, right: char) -> Twips;

    fn atlases(&self) -> Option<&FontAtlases> {
        None
    }
}

#[derive(Debug)]
pub struct CachedValue<T> {
    value: T,
    /// The frame (see [`FontRendererGlyphSource::frame`]) this entry was last
    /// looked up in.
    last_used: u64,
}

type CacheMap<K, V> = RefCell<fnv::FnvHashMap<K, CachedValue<V>>>;

#[derive(Debug)]
pub struct FontRendererGlyphSource {
    font_renderer: Box<dyn FontRenderer>,

    /// Maps Unicode code points to glyphs rendered by the renderer.
    glyph_cache: CacheMap<u16, Option<Glyph>>,

    /// Maps Unicode pairs to kerning provided by the renderer.
    kerning_cache: CacheMap<(u16, u16), Twips>,

    sweep_caches: Cell<bool>,
    sweep_count: Cell<usize>,
    swept_glyphs_count: Cell<usize>,
    swept_kerning_count: Cell<usize>,

    /// Timffle: counts the calls to [`Self::sweep_caches`], i.e. the rendered
    /// frames; entries remember the frame they were last used in.
    frame: Cell<u64>,
}

impl FontRendererGlyphSource {
    /// Timffle: how many rendered frames an unused glyph or kerning pair stays
    /// cached.
    ///
    /// Upstream evicted everything that was not used since the previous
    /// sweep, and a sweep runs on every frame that adds a new entry. Text
    /// that comes and goes (damage numbers, chat lines, counters, tooltips)
    /// therefore had its glyphs rasterized again and again: on the web each
    /// rasterization is a canvas readback, and the game stalls on every one.
    /// Keeping entries for a while bounds the cache by the glyphs used
    /// recently instead of the glyphs on screen right now.
    const KEEP_FRAMES: u64 = 600;

    pub fn new(font_renderer: Box<dyn FontRenderer>) -> Self {
        Self {
            font_renderer,
            glyph_cache: RefCell::new(fnv::FnvHashMap::default()),
            kerning_cache: RefCell::new(fnv::FnvHashMap::default()),
            sweep_caches: Cell::new(false),
            frame: Cell::new(0),
            sweep_count: Cell::new(0),
            swept_glyphs_count: Cell::new(0),
            swept_kerning_count: Cell::new(0),
        }
    }

    pub fn glyph_cache_size(&self) -> usize {
        self.glyph_cache.borrow().len()
    }

    pub fn kerning_cache_size(&self) -> usize {
        self.kerning_cache.borrow().len()
    }

    pub fn sweep_count(&self) -> usize {
        self.sweep_count.get()
    }

    pub fn swept_glyphs_count(&self) -> usize {
        self.swept_glyphs_count.get()
    }

    pub fn swept_kerning_count(&self) -> usize {
        self.swept_kerning_count.get()
    }

    pub fn font_renderer(&self) -> &dyn FontRenderer {
        self.font_renderer.as_ref()
    }

    pub fn get_by_code_point(&self, code_point: char) -> Option<GlyphRef<'_>> {
        let character = code_point;
        let code_point = code_point as u16;

        let frame = self.frame.get();
        let mut cache = self.glyph_cache.borrow_mut();
        let entry = cache.entry(code_point).or_insert_with(|| {
            self.sweep_caches.set(true);
            CachedValue {
                value: self.font_renderer.render_glyph(character),
                last_used: frame,
            }
        });
        entry.last_used = frame;
        drop(cache);

        let glyph = Ref::filter_map(self.glyph_cache.borrow(), |v| {
            v.get(&code_point).and_then(|entry| entry.value.as_ref())
        })
        .ok();

        glyph.map(GlyphRef::Ref)
    }

    pub fn get_kerning_offset(&self, left: char, right: char) -> Twips {
        let (Ok(left_cp), Ok(right_cp)) = (left.try_into(), right.try_into()) else {
            return Twips::ZERO;
        };

        let frame = self.frame.get();
        let mut cache = self.kerning_cache.borrow_mut();
        let entry = cache.entry((left_cp, right_cp)).or_insert_with(|| {
            self.sweep_caches.set(true);
            CachedValue {
                value: self.font_renderer.calculate_kerning(left, right),
                last_used: frame,
            }
        });
        entry.last_used = frame;
        entry.value
    }

    /// Evicts stale entries. Called once per rendered frame; it only iterates
    /// the caches on frames that added an entry (or when `force`d), and then
    /// drops what has not been used for [`Self::KEEP_FRAMES`] frames (`force`
    /// drops everything not used in the current frame).
    pub fn sweep_caches(&self, force: bool) {
        let frame = self.frame.get().wrapping_add(1);
        self.frame.set(frame);
        if force || self.sweep_caches.replace(false) {
            self.sweep_count.set(self.sweep_count.get().wrapping_add(1));
            let max_age = if force { 1 } else { Self::KEEP_FRAMES };

            let swept_glyphs = retain_recent(&self.glyph_cache, frame, max_age);
            self.swept_glyphs_count
                .set(self.swept_glyphs_count.get().wrapping_add(swept_glyphs));

            let swept_kerning = retain_recent(&self.kerning_cache, frame, max_age);
            self.swept_kerning_count
                .set(self.swept_kerning_count.get().wrapping_add(swept_kerning));
        }
    }
}

fn retain_recent<K, V>(cache: &CacheMap<K, V>, frame: u64, max_age: u64) -> usize {
    let mut cache = cache.borrow_mut();
    let before = cache.len();
    cache.retain(|_, entry| frame.wrapping_sub(entry.last_used) <= max_age);
    before - cache.len()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::Cell;
    use std::rc::Rc;

    /// Counts how often each glyph is rasterized.
    #[derive(Debug)]
    struct CountingRenderer {
        renders: Rc<Cell<usize>>,
    }

    impl FontRenderer for CountingRenderer {
        fn scale(&self) -> f32 {
            1.0
        }

        fn get_font_metrics(&self) -> FontMetrics {
            FontMetrics {
                scale: 1.0,
                ascent: 1,
                descent: 0,
                leading: 0,
            }
        }

        fn has_kerning_info(&self) -> bool {
            true
        }

        fn render_glyph(&self, character: char) -> Option<Glyph> {
            self.renders.set(self.renders.get() + 1);
            Some(Glyph::whitespace(character, Twips::ONE_PX))
        }

        fn calculate_kerning(&self, _left: char, _right: char) -> Twips {
            Twips::ZERO
        }
    }

    fn source() -> (FontRendererGlyphSource, Rc<Cell<usize>>) {
        let renders = Rc::new(Cell::new(0));
        let renderer = CountingRenderer {
            renders: renders.clone(),
        };
        (FontRendererGlyphSource::new(Box::new(renderer)), renders)
    }

    /// A glyph that is off screen for a few frames while other glyphs appear
    /// (a damage number, a chat line) must not be rasterized again.
    #[test]
    fn glyphs_survive_frames_with_new_entries() {
        let (source, renders) = source();
        assert!(source.get_by_code_point('8').is_some());
        source.sweep_caches(false);
        assert_eq!(renders.get(), 1);

        // Ten frames each showing a new glyph, '8' not drawn at all.
        for c in "abcdefghij".chars() {
            assert!(source.get_by_code_point(c).is_some());
            source.sweep_caches(false);
        }
        assert_eq!(source.glyph_cache_size(), 11);

        assert!(source.get_by_code_point('8').is_some());
        assert_eq!(renders.get(), 11, "'8' came from the cache");
    }

    /// Entries unused for longer than `KEEP_FRAMES` go away on the next frame
    /// that adds an entry; a forced sweep keeps only the current frame's.
    #[test]
    fn stale_glyphs_are_evicted() {
        let (source, renders) = source();
        assert!(source.get_by_code_point('a').is_some());
        for _ in 0..FontRendererGlyphSource::KEEP_FRAMES + 5 {
            source.sweep_caches(false);
        }
        // Still cached: no frame added an entry, so nothing was swept.
        assert_eq!(source.glyph_cache_size(), 1);

        assert!(source.get_by_code_point('b').is_some());
        source.sweep_caches(false);
        assert_eq!(source.glyph_cache_size(), 1, "'a' is stale, 'b' stays");
        assert_eq!(source.swept_glyphs_count(), 1);

        assert!(source.get_by_code_point('a').is_some());
        assert_eq!(renders.get(), 3);
        source.sweep_caches(false);
        source.sweep_caches(true);
        assert_eq!(
            source.glyph_cache_size(),
            0,
            "forced sweep drops all unused"
        );
    }
}
