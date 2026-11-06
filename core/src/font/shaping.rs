//! Timffle: OpenType shaping of `flash.text.engine` text set in DefineFont4 (CFF) fonts.
//!
//! Flash Player's text engine lays text out with the font's OpenType tables (GSUB
//! ligatures, GPOS kerning and the digit and small-caps features selected by
//! `ElementFormat`); classic TextFields do not. Measured in Flash Player 32
//! (`tests/tests/swfs/avm2/fte_opentype_shaping`):
//!
//! - `ligatureLevel` `none` and `minimum` leave ligatures out, `common` applies the
//!   standard ligatures (`liga`), `uncommon` and `exotic` also the discretionary ones
//!   (`dlig`: the Exo 2 subset of `visual/definefont4` has its "ft" ligature there).
//! - A ligature stays one atom per character: the ligature glyph is drawn at the first
//!   character and its advance is split evenly between its characters (`getAtomBounds`).
//! - `kerning` `on` and `auto` kern Latin text with the font's GPOS/`kern` data, `off`
//!   does not. The kerning between two glyphs is split in the middle: the atom boundary
//!   sits half the kerning value after the first glyph's own advance, so both atoms
//!   change by half of it while the glyphs keep their kerned positions.
//! - `digitCase` `lining`/`oldStyle` select `lnum`/`onum`, `digitWidth`
//!   `proportional`/`tabular` select `pnum`/`tnum`, `typographicCase` `smallCaps` turns
//!   capitals into small capitals (`c2sc`) and `capsAndSmallCaps` lowercase letters
//!   (`smcp`).
//! - FTE cannot use DefineFont3 fonts at all (`embeddedCFF` with a DefineFont3 name
//!   finds no font).

use crate::string::WStr;
use bitflags::bitflags;
use rustybuzz::ttf_parser::Tag;

bitflags! {
    /// The OpenType features a span of FTE text is shaped with. TextField text has none
    /// (`EvalParameters::opentype` is `None`) and keeps the per-character layout.
    #[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, Default)]
    pub struct OpenTypeFeatures: u16 {
        /// Standard ligatures (`liga`, `clig`).
        const LIGATURES = 1 << 0;
        /// Required ligatures (`rlig`); everything except `ligatureLevel = none`.
        const REQUIRED_LIGATURES = 1 << 1;
        /// Discretionary ligatures (`dlig`).
        const DISCRETIONARY_LIGATURES = 1 << 9;
        /// Pair kerning (`kern`).
        const KERNING = 1 << 2;
        const LINING_FIGURES = 1 << 3;
        const OLD_STYLE_FIGURES = 1 << 4;
        const PROPORTIONAL_FIGURES = 1 << 5;
        const TABULAR_FIGURES = 1 << 6;
        /// Capitals to small capitals (`c2sc`).
        const CAPS_TO_SMALL_CAPS = 1 << 7;
        /// Lowercase to small capitals (`smcp`).
        const SMALL_CAPS = 1 << 8;
    }
}

impl OpenTypeFeatures {
    fn to_rustybuzz(self) -> Vec<rustybuzz::Feature> {
        let mut features = Vec::new();
        let mut set = |tag: &[u8; 4], on: bool| {
            features.push(rustybuzz::Feature::new(
                Tag::from_bytes(tag),
                u32::from(on),
                ..,
            ));
        };
        set(b"liga", self.contains(Self::LIGATURES));
        set(b"clig", self.contains(Self::LIGATURES));
        set(b"rlig", self.contains(Self::REQUIRED_LIGATURES));
        set(b"dlig", self.contains(Self::DISCRETIONARY_LIGATURES));
        set(b"kern", self.contains(Self::KERNING));
        for (flag, tag) in [
            (Self::LINING_FIGURES, b"lnum"),
            (Self::OLD_STYLE_FIGURES, b"onum"),
            (Self::PROPORTIONAL_FIGURES, b"pnum"),
            (Self::TABULAR_FIGURES, b"tnum"),
            (Self::CAPS_TO_SMALL_CAPS, b"c2sc"),
            (Self::SMALL_CAPS, b"smcp"),
        ] {
            if self.contains(flag) {
                set(tag, true);
            }
        }
        features
    }
}

/// One character of shaped text, in the order of the text.
#[derive(Clone, Copy, Debug)]
pub struct ShapedChar {
    /// Position of the character in the text (UTF-16 units).
    pub pos: usize,
    pub character: char,
    /// The glyph drawn for this character, with its pen position and vertical offset in
    /// font units (`None` for the later characters of a ligature).
    pub glyph: Option<(u16, f64, f64)>,
    /// Start of the character's atom and its end, in font units.
    pub x: f64,
    pub end: f64,
    /// Whether the font has a glyph for the character (or a ligature includes it).
    /// Characters it has none for (a paragraph separator, for example) take no space,
    /// as in the per-character layout; the caller lays the text out per character
    /// instead when a fallback font has a glyph for one of them.
    pub glyph_or_ligature: bool,
}

/// Shapes `text` (left to right) with the font in `data`.
///
/// Returns `None` when the text cannot be shaped as one run of this font: right-to-left
/// characters (the fallback field holds them in visual order), or a cluster with more
/// glyphs than characters.
pub fn shape(
    data: &[u8],
    font_index: u32,
    text: &WStr,
    features: OpenTypeFeatures,
) -> Option<Vec<ShapedChar>> {
    let face = rustybuzz::Face::from_slice(data, font_index)?;
    let chars: Vec<(usize, char)> = text
        .char_indices()
        .map(|(pos, c)| (pos, c.unwrap_or(char::REPLACEMENT_CHARACTER)))
        .collect();
    if chars.is_empty() {
        return Some(Vec::new());
    }

    let mut buffer = rustybuzz::UnicodeBuffer::new();
    let mut present = vec![false; chars.len()];
    for (i, &(_, c)) in chars.iter().enumerate() {
        if face.glyph_index(c).is_none() {
            continue;
        }
        present[i] = true;
        if matches!(
            unicode_bidi::bidi_class(c),
            unicode_bidi::BidiClass::R | unicode_bidi::BidiClass::AL
        ) {
            return None;
        }
        buffer.add(c, i as u32);
    }
    buffer.set_direction(rustybuzz::Direction::LeftToRight);
    buffer.guess_segment_properties();
    let output = rustybuzz::shape(&face, &features.to_rustybuzz(), buffer);
    let infos = output.glyph_infos();
    let positions = output.glyph_positions();

    // Pen position of every glyph, and the atom boundary in front of it: half of the
    // previous glyph's kerning (its shaped advance minus its own advance) after the
    // previous glyph's own advance.
    let mut pen = Vec::with_capacity(infos.len());
    let mut boundary = Vec::with_capacity(infos.len() + 1);
    let mut x = 0.0;
    let mut previous: Option<(f64, f64)> = None;
    for (info, position) in infos.iter().zip(positions) {
        boundary.push(match previous {
            Some((start, kerning)) => start + kerning / 2.0,
            None => 0.0,
        });
        let own = face
            .glyph_hor_advance(rustybuzz::ttf_parser::GlyphId(info.glyph_id as u16))
            .map_or(f64::from(position.x_advance), f64::from);
        pen.push((
            x,
            f64::from(position.x_offset),
            f64::from(position.y_offset),
        ));
        previous = Some((x + own, f64::from(position.x_advance) - own));
        x += f64::from(position.x_advance);
    }
    boundary.push(x);

    let mut shaped: Vec<ShapedChar> = chars
        .iter()
        .map(|&(pos, character)| ShapedChar {
            pos,
            character,
            glyph: None,
            x: 0.0,
            end: 0.0,
            glyph_or_ligature: false,
        })
        .collect();
    // Clusters are runs of glyphs with the same cluster value (the index of the
    // cluster's first character), in increasing order for left-to-right text.
    let mut g = 0;
    while g < infos.len() {
        let cluster = infos[g].cluster as usize;
        let mut g_end = g + 1;
        while g_end < infos.len() && infos[g_end].cluster as usize == cluster {
            g_end += 1;
        }
        let char_end = infos
            .get(g_end)
            .map_or(chars.len(), |info| info.cluster as usize);
        if char_end <= cluster {
            return None;
        }
        // The characters of the cluster that are in the font.
        let members: Vec<usize> = (cluster..char_end).filter(|&i| present[i]).collect();
        if g_end - g > members.len() {
            return None;
        }
        let (start, end) = (boundary[g], boundary[g_end]);
        let count = members.len() as f64;
        for (k, &i) in members.iter().enumerate() {
            let c = &mut shaped[i];
            c.x = start + (end - start) * k as f64 / count;
            c.end = start + (end - start) * (k + 1) as f64 / count;
            c.glyph_or_ligature = true;
            if g + k < g_end {
                let (pen_x, x_offset, y_offset) = pen[g + k];
                c.glyph = Some((infos[g + k].glyph_id as u16, pen_x + x_offset, y_offset));
            }
        }
        g = g_end;
    }
    // Characters the font has no glyph for sit where the previous character ends.
    let mut last_end = 0.0;
    for c in &mut shaped {
        if c.glyph_or_ligature {
            last_end = c.end;
        } else {
            c.x = last_end;
            c.end = last_end;
        }
    }
    Some(shaped)
}
