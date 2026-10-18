use js_sys::JSON;
use ruffle_core::font::FontAtlases;
use ruffle_core::font::FontMetrics;
use ruffle_core::font::FontRenderer;
use ruffle_core::font::Glyph;
use ruffle_core::swf::Twips;
use ruffle_render::bitmap::Bitmap;
use ruffle_render::bitmap::BitmapFormat;
use wasm_bindgen::JsCast;
use wasm_bindgen::JsValue;
use web_sys::OffscreenCanvas;
use web_sys::OffscreenCanvasRenderingContext2d;

#[derive(Debug)]
pub struct CanvasFontRenderer {
    canvas: OffscreenCanvas,
    ctx: OffscreenCanvasRenderingContext2d,
    font_str: String,
    ascent: f64,
    descent: f64,
    atlases: FontAtlases,
}

/// The line metrics Windows gives a font that Flash content asks for by name.
struct WindowsFont {
    /// The font's names, lower-case as far as the script has case.
    names: &'static [&'static str],
    ascent: f64,
    descent: f64,
    /// Whether these metrics are used even when the browser has a font of that
    /// name. Fonts like SimSun are often "installed" only as a substitute the
    /// system maps the name to (fontconfig does that), and the substitute's
    /// metrics are the wrong ones.
    even_if_installed: bool,
}

impl CanvasFontRenderer {
    /// Render fonts with size 64px. It affects the bitmap size.
    const SIZE_PX: f64 = 64.0;

    /// Divide each pixel into 20 (use twips precision). It affects metrics.
    const SCALE: f64 = 20.0;

    /// Line height (ascent + descent, in em) above which a stand-in font's
    /// line metrics are replaced by its CJK em box, see [`Self::line_metrics`].
    const TALL_LINE_EM: f64 = 1.25;

    /// Windows fonts that Flash content asks for by name and that are missing
    /// on most devices, with the ascent and descent (in em) Windows lays their
    /// lines out with: the SimSun family (its Chinese names included), Microsoft
    /// YaHei and the Latin fonts the games use. See [`Self::line_metrics`].
    const WINDOWS_FONTS: &[WindowsFont] = &[
        WindowsFont {
            names: &[
                "simsun",
                "nsimsun",
                "\u{5B8B}\u{4F53}",
                "\u{5B8B}\u{9AD4}",
                "\u{65B0}\u{5B8B}\u{4F53}",
                "\u{65B0}\u{5B8B}\u{9AD4}",
            ],
            ascent: 220.0 / 256.0,
            descent: 36.0 / 256.0,
            even_if_installed: true,
        },
        WindowsFont {
            names: &["arial black"],
            ascent: 2254.0 / 2048.0,
            descent: 634.0 / 2048.0,
            even_if_installed: false,
        },
        WindowsFont {
            names: &["tahoma"],
            ascent: 2049.0 / 2048.0,
            descent: 423.0 / 2048.0,
            even_if_installed: false,
        },
        WindowsFont {
            names: &["verdana"],
            ascent: 2059.0 / 2048.0,
            descent: 430.0 / 2048.0,
            even_if_installed: false,
        },
        WindowsFont {
            names: &["microsoft yahei"],
            ascent: 2171.0 / 2048.0,
            descent: 514.0 / 2048.0,
            even_if_installed: false,
        },
        WindowsFont {
            names: &["arial"],
            ascent: 1854.0 / 2048.0,
            descent: 434.0 / 2048.0,
            even_if_installed: false,
        },
        WindowsFont {
            names: &["times new roman"],
            ascent: 1825.0 / 2048.0,
            descent: 443.0 / 2048.0,
            even_if_installed: false,
        },
        WindowsFont {
            names: &["courier new"],
            ascent: 1705.0 / 2048.0,
            descent: 615.0 / 2048.0,
            even_if_installed: false,
        },
    ];

    pub fn new(
        italic: bool,
        bold: bool,
        font_family: &str,
        atlases: &FontAtlases,
    ) -> Result<Self, JsValue> {
        if !Self::is_offscreen_canvas_supported() {
            return Err(JsValue::from_str("OffscreenCanvas unsupported"));
        }

        let canvas = OffscreenCanvas::new(1, 1)?;

        let ctx = canvas.get_context("2d")?.expect("2d context");
        let ctx = ctx
            .dyn_into::<OffscreenCanvasRenderingContext2d>()
            .map_err(|err| JsValue::from_str(&format!("Not a 2d context: {err:?}")))?;

        let font_str = Self::to_font_str(italic, bold, Self::SIZE_PX, font_family);
        tracing::debug!("Using the following font string: {font_str}");
        Self::apply_style(&ctx, &font_str);

        let (ascent, descent) = Self::line_metrics(&ctx, italic, bold, font_family)?;
        Self::apply_style(&ctx, &font_str);

        Ok(Self {
            canvas,
            ctx,
            font_str,
            ascent,
            descent,
            atlases: atlases.clone(),
        })
    }

    /// Ascent and descent in pixels at [`Self::SIZE_PX`] (timffle).
    ///
    /// Flash lays text out with the font it asked for: its ascent and descent
    /// decide where each line's baseline falls and how tall the line is (the
    /// first baseline is at the top gutter plus the ascent, rounded to whole
    /// pixels). The browser often has to put another font in its place, and a
    /// stand-in's metrics can be far off: Noto Serif CJK as SimSun (0.86 +
    /// 0.14 em) reports 1.16 + 0.29 em and puts every line a quarter em too
    /// low, Times as Arial Black (1.10 + 0.31 em) puts it a fifth of an em too
    /// high.
    ///
    /// So the Windows fonts the games use are looked up by name first
    /// ([`Self::WINDOWS_FONTS`]) and keep the metrics Windows gives them; the
    /// stand-in only draws the glyphs. A font from the table that the browser
    /// does have keeps its own metrics, except for the SimSun family, whose
    /// "installed" copy is usually such a stand-in.
    ///
    /// Other fonts keep the browser's metrics, unless the browser chose a tall
    /// stand-in (Android's Noto Sans CJK reports 1.16 + 0.29 em): that uses
    /// the CJK em box instead (bottom at the ideographic baseline, 0.88 +
    /// 0.12 em for Noto Sans CJK), which matches the classic CJK fonts.
    /// Installed fonts and ordinary fallbacks keep the browser's metrics.
    fn line_metrics(
        ctx: &OffscreenCanvasRenderingContext2d,
        italic: bool,
        bold: bool,
        font_family: &str,
    ) -> Result<(f64, f64), JsValue> {
        let font_str = Self::to_font_str(italic, bold, Self::SIZE_PX, font_family);
        let name = font_family.trim().to_lowercase();
        let windows_font = Self::WINDOWS_FONTS
            .iter()
            .find(|font| font.names.contains(&name.as_str()));
        if let Some(font) = windows_font {
            if font.even_if_installed || !Self::is_installed(ctx, &font_str)? {
                return Ok((font.ascent * Self::SIZE_PX, font.descent * Self::SIZE_PX));
            }
        }
        ctx.set_font(&font_str);
        let measurement = ctx.measure_text("Myjg")?;
        let ascent = measurement.font_bounding_box_ascent();
        let descent = measurement.font_bounding_box_descent();
        if ascent + descent <= Self::TALL_LINE_EM * Self::SIZE_PX
            || (!Self::is_generic_family(font_family) && Self::is_installed(ctx, &font_str)?)
        {
            return Ok((ascent, descent));
        }
        let ideographic =
            js_sys::Reflect::get(&measurement, &JsValue::from_str("ideographicBaseline"))?.as_f64();
        match ideographic.map(|baseline| -baseline) {
            Some(em_bottom) if em_bottom > 0.0 && em_bottom < Self::SIZE_PX / 2.0 => {
                Ok((Self::SIZE_PX - em_bottom, em_bottom))
            }
            _ => Ok((ascent, descent)),
        }
    }

    /// Whether the browser has the font itself rather than a fallback: text
    /// measures the same with two different fallback families only then.
    fn is_installed(
        ctx: &OffscreenCanvasRenderingContext2d,
        font_str: &str,
    ) -> Result<bool, JsValue> {
        const PROBE: &str = "mmmmmmmmmmlli\u{570B}";
        ctx.set_font(&format!("{font_str}, monospace"));
        let with_monospace = ctx.measure_text(PROBE)?.width();
        ctx.set_font(&format!("{font_str}, serif"));
        let with_serif = ctx.measure_text(PROBE)?.width();
        Ok(with_monospace == with_serif)
    }

    // TODO Remove it when we stop supporting Firefox <105, Safari <16.4
    fn is_offscreen_canvas_supported() -> bool {
        let global = js_sys::global();
        match js_sys::Reflect::get(&global, &JsValue::from_str("OffscreenCanvas")) {
            Ok(value) => !value.is_undefined(),
            Err(_) => false,
        }
    }

    fn to_font_str(italic: bool, bold: bool, size: f64, font_family: &str) -> String {
        let italic = if italic { "italic " } else { "" };
        let bold = if bold { "bold " } else { "" };

        // Generic family keywords lose their meaning when quoted: the browser
        // would look for a font literally named "sans-serif" instead.
        let font_family = if Self::is_generic_family(font_family) {
            font_family.to_owned()
        } else {
            // Escape font family properly
            JSON::stringify(&JsValue::from_str(font_family))
                .ok()
                .and_then(|js_str| js_str.as_string())
                .unwrap_or_else(|| format!("\"{font_family}\""))
        };
        format!("{italic}{bold}{size}px {font_family}")
    }

    /// Whether the name is one of the CSS generic families that stand in for
    /// the default device fonts when rendering through canvas.
    fn is_generic_family(font_family: &str) -> bool {
        matches!(font_family, "serif" | "sans-serif" | "monospace")
    }

    fn apply_style(ctx: &OffscreenCanvasRenderingContext2d, font_str: &str) {
        ctx.set_fill_style_str("white");
        ctx.set_font(font_str);
    }

    fn calculate_width(&self, text: &str) -> Result<f64, JsValue> {
        Ok(self.ctx.measure_text(text)?.width())
    }

    fn ensure_canvas_large_enough(&self, width: u32, height: u32) {
        if self.canvas.width() < width || self.canvas.height() < height {
            self.canvas.set_width(width);
            self.canvas.set_height(height);

            // After changing canvas size, we need to reapply the style.
            // Somehow, when canvas size is too small for the text, the
            // text is rendered smaller, but its reported metrics are correct.
            Self::apply_style(&self.ctx, &self.font_str);
        }
    }

    fn render_glyph_internal(&self, character: char) -> Result<Glyph, JsValue> {
        let text = &character.to_string();
        let metrics = self.ctx.measure_text(text)?;

        let bitmap_width = metrics.actual_bounding_box_left() + metrics.actual_bounding_box_right();
        let bitmap_width = bitmap_width.ceil() as i32;
        let bitmap_height =
            metrics.actual_bounding_box_ascent() + metrics.actual_bounding_box_descent();
        let bitmap_height = bitmap_height.ceil() as i32;
        let advance = Twips::from_pixels(metrics.width());

        // Glyphs with no ink will produce empty bitmaps.
        if bitmap_width <= 0 || bitmap_height <= 0 {
            return Ok(Glyph::whitespace(character, advance));
        }

        let bitmap_tx = -metrics.actual_bounding_box_left();
        let bitmap_ty = -metrics.actual_bounding_box_ascent();

        self.ensure_canvas_large_enough(bitmap_width as u32, bitmap_height as u32);

        self.ctx.clear_rect(
            0.0,
            0.0,
            self.canvas.width() as f64,
            self.canvas.height() as f64,
        );
        self.ctx.fill_text(text, -bitmap_tx, -bitmap_ty)?;

        let image_data = self.ctx.get_image_data(0, 0, bitmap_width, bitmap_height)?;
        let width = image_data.width();
        let height = image_data.height();
        let pixels = image_data.data().0;

        let bitmap = Bitmap::new(width, height, BitmapFormat::Rgba, pixels);
        let bitmap_tx = Twips::from_pixels(bitmap_tx);
        let bitmap_ty = Twips::from_pixels(self.ascent + bitmap_ty);
        let atlas_glyph = self.atlases.rgba().new_glyph(bitmap, bitmap_tx, bitmap_ty);
        Ok(Glyph::from_atlas(character, atlas_glyph, advance))
    }

    fn calculate_kerning_internal(&self, left: char, right: char) -> Result<Twips, JsValue> {
        let left_width = self.calculate_width(&left.to_string())?;
        let right_width = self.calculate_width(&right.to_string())?;
        let both_width = self.calculate_width(&format!("{left}{right}"))?;

        let kern = both_width - left_width - right_width;
        Ok(Twips::from_pixels(kern))
    }
}

impl FontRenderer for CanvasFontRenderer {
    fn scale(&self) -> f32 {
        (Self::SIZE_PX * Self::SCALE) as f32
    }

    fn get_font_metrics(&self) -> FontMetrics {
        FontMetrics {
            scale: self.scale(),
            ascent: (self.ascent * Self::SCALE) as i32,
            descent: (self.descent * Self::SCALE) as i32,
            leading: 0,
        }
    }

    fn has_kerning_info(&self) -> bool {
        true
    }

    fn render_glyph(&self, character: char) -> Option<Glyph> {
        self.render_glyph_internal(character)
            .map_err(|err| tracing::error!("Failed to render a glyph: {err:?}"))
            .ok()
    }

    fn calculate_kerning(&self, left: char, right: char) -> Twips {
        self.calculate_kerning_internal(left, right)
            .map_err(|err| tracing::error!("Failed to calculate kerning: {err:?}"))
            .unwrap_or(Twips::ZERO)
    }

    fn atlases(&self) -> Option<&FontAtlases> {
        Some(&self.atlases)
    }
}
