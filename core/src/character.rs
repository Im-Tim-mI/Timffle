use std::borrow::Cow;
use std::cell::OnceCell;

use crate::backend::audio::SoundHandle;
use crate::binary_data::BinaryData;
use crate::display_object::{
    Avm1Button, Avm2Button, BitmapClass, EditText, Graphic, MorphShape, MovieClip, Text, Video,
};
use crate::font::Font;
use crate::tag_utils::SwfSlice;
use gc_arena::barrier::unlock;
use gc_arena::lock::Lock;
use gc_arena::{Collect, Gc, Mutation};
use ruffle_render::backend::RenderBackend;
use ruffle_render::bitmap::{Bitmap as RenderBitmap, BitmapHandle, BitmapSize};
use ruffle_render::error::Error as RenderError;
use swf::DefineBitsLossless;

#[derive(Copy, Clone, Collect, Debug)]
#[collect(no_drop)]
pub enum Character<'gc> {
    EditText(EditText<'gc>),
    Graphic(Graphic<'gc>),
    MovieClip(MovieClip<'gc>),
    Bitmap(Gc<'gc, BitmapCharacter<'gc>>),
    Avm1Button(Avm1Button<'gc>),
    Avm2Button(Avm2Button<'gc>),
    Font(Font<'gc>),
    MorphShape(MorphShape<'gc>),
    Text(Text<'gc>),
    Sound(#[collect(require_static)] SoundHandle),
    Video(Video<'gc>),
    BinaryData(Gc<'gc, BinaryData>),
}

#[derive(Collect, Debug)]
#[collect(no_drop)]
pub struct BitmapCharacter<'gc> {
    #[collect(require_static)]
    compressed: CompressedBitmap,
    /// A lazily constructed GPU handle, used when performing fills with this bitmap
    #[collect(require_static)]
    handle: OnceCell<BitmapHandle>,
    /// The bitmap class set by `SymbolClass` - this is used when we instantaite
    /// a `Bitmap` displayobject.
    avm2_class: Lock<BitmapClass<'gc>>,
}

impl<'gc> BitmapCharacter<'gc> {
    pub fn new(compressed: CompressedBitmap) -> Self {
        Self {
            compressed,
            handle: OnceCell::default(),
            avm2_class: Lock::new(BitmapClass::NoSubclass),
        }
    }

    pub fn compressed(&self) -> &CompressedBitmap {
        &self.compressed
    }

    pub fn avm2_class(&self) -> BitmapClass<'gc> {
        self.avm2_class.get()
    }

    pub fn set_avm2_class(this: Gc<'gc, Self>, bitmap_class: BitmapClass<'gc>, mc: &Mutation<'gc>) {
        unlock!(Gc::write(mc, this), Self, avm2_class).set(bitmap_class);
    }

    pub fn bitmap_handle(
        &self,
        backend: &mut dyn RenderBackend,
    ) -> Result<BitmapHandle, RenderError> {
        // FIXME - use `OnceCell::get_or_try_init` when stabilized.
        if let Some(handle) = self.handle.get() {
            return Ok(handle.clone());
        }
        let decoded = self.compressed.decode()?;
        let new_handle = backend.register_bitmap(decoded)?;
        // FIXME - do we ever want to release this handle, to avoid taking up GPU memory?
        self.handle.set(new_handle.clone()).unwrap();
        Ok(new_handle)
    }
}

/// The payload bytes of a character definition tag.
///
/// Timffle: image and sound payloads used to be copied out of the tag into an owned
/// `Vec<u8>`, while the library already keeps the whole decompressed SWF alive
/// (`SwfMovieData.data`). Asset SWFs are mostly images and sounds, so each library
/// entry cost close to twice the SWF size. A `Movie` view shares the movie's
/// `Arc<Vec<u8>>` and adds no retention of its own; `Owned` is used only when the
/// bytes do not exist in the movie in this form (JPEG data glued to `JPEGTables`,
/// or a tag that was not read from the movie's own buffer).
#[derive(Clone, Debug)]
pub enum CharacterBytes {
    Movie(SwfSlice),
    Owned(Box<[u8]>),
}

impl CharacterBytes {
    /// Keeps `slice` as a view into `movie` when it points into the movie's data,
    /// otherwise copies it.
    pub fn from_movie_slice(movie: &SwfSlice, slice: &[u8]) -> Self {
        match movie.try_subslice(slice) {
            Some(view) => CharacterBytes::Movie(view),
            None => CharacterBytes::Owned(slice.into()),
        }
    }

    /// Like `from_movie_slice`, but a `Cow::Owned` (bytes that were rewritten
    /// after reading, e.g. glued JPEG tables) is stored as an owned copy.
    pub fn from_movie_cow(movie: &SwfSlice, bytes: Cow<'_, [u8]>) -> Self {
        match bytes {
            Cow::Borrowed(slice) => Self::from_movie_slice(movie, slice),
            Cow::Owned(vec) => CharacterBytes::Owned(vec.into_boxed_slice()),
        }
    }

    pub fn len(&self) -> usize {
        self.as_ref().len()
    }

    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }

    /// Bytes this value keeps alive on its own, i.e. not shared with the movie data.
    pub fn owned_len(&self) -> usize {
        match self {
            CharacterBytes::Movie(_) => 0,
            CharacterBytes::Owned(data) => data.len(),
        }
    }
}

impl AsRef<[u8]> for CharacterBytes {
    #[inline]
    fn as_ref(&self) -> &[u8] {
        match self {
            CharacterBytes::Movie(slice) => slice.data(),
            CharacterBytes::Owned(data) => data,
        }
    }
}

/// Holds a bitmap from an SWF tag, plus the decoded width/height.
/// We avoid decompressing the image until it's actually needed - some pathological SWFS
/// like 'House' have thousands of highly-compressed (mostly empty) bitmaps, which can
/// take over 10GB of ram if we decompress them all during preloading.
#[derive(Clone, Debug)]
pub enum CompressedBitmap {
    Jpeg {
        data: CharacterBytes,
        alpha: Option<CharacterBytes>,
        width: u32,
        height: u32,
    },
    /// The fields of a `DefineBitsLossless` tag, with the (still zlib-compressed)
    /// pixel data as a view into the movie.
    Lossless {
        version: u8,
        id: swf::CharacterId,
        format: swf::BitmapFormat,
        width: u16,
        height: u16,
        data: CharacterBytes,
    },
}

impl CompressedBitmap {
    pub fn size(&self) -> BitmapSize {
        match self {
            CompressedBitmap::Jpeg { width, height, .. } => BitmapSize {
                width: *width,
                height: *height,
            },
            CompressedBitmap::Lossless { width, height, .. } => BitmapSize {
                width: (*width).into(),
                height: (*height).into(),
            },
        }
    }
    pub fn decode(&self) -> Result<RenderBitmap<'static>, RenderError> {
        match self {
            CompressedBitmap::Jpeg {
                data,
                alpha,
                width: _,
                height: _,
            } => ruffle_render::utils::decode_define_bits_jpeg(
                data.as_ref(),
                alpha.as_ref().map(|a| a.as_ref()),
            ),
            CompressedBitmap::Lossless {
                version,
                id,
                format,
                width,
                height,
                data,
            } => ruffle_render::utils::decode_define_bits_lossless(&DefineBitsLossless {
                version: *version,
                id: *id,
                format: *format,
                width: *width,
                height: *height,
                data: Cow::Borrowed(data.as_ref()),
            }),
        }
    }

    /// Compressed bytes this bitmap keeps alive on its own (not shared with the movie).
    pub fn owned_len(&self) -> usize {
        match self {
            CompressedBitmap::Jpeg { data, alpha, .. } => {
                data.owned_len() + alpha.as_ref().map_or(0, |a| a.owned_len())
            }
            CompressedBitmap::Lossless { data, .. } => data.owned_len(),
        }
    }

    /// Total compressed bytes of this bitmap (what an owned copy would cost).
    pub fn compressed_len(&self) -> usize {
        match self {
            CompressedBitmap::Jpeg { data, alpha, .. } => {
                data.len() + alpha.as_ref().map_or(0, |a| a.len())
            }
            CompressedBitmap::Lossless { data, .. } => data.len(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{CharacterBytes, CompressedBitmap};
    use crate::tag_utils::{SwfMovieData, SwfSlice};
    use std::borrow::Cow;

    /// A small SWF with `JPEGTables` + `DefineBits`, `DefineBitsLossless`,
    /// `DefineBitsLossless2` and `DefineBitsJPEG3` (alpha) tags.
    const BITMAP_SWF: &str = "../tests/tests/swfs/from_shumway/bitmapbuttons/test.swf";

    fn load_movie(path: &str) -> SwfMovieData {
        let path = format!("{}/{}", env!("CARGO_MANIFEST_DIR"), path);
        let bytes = std::fs::read(&path).unwrap_or_else(|e| panic!("{path}: {e}"));
        SwfMovieData::from_data(&bytes, "file:///test.swf".to_string(), None, None).unwrap()
    }

    /// Builds every bitmap of the movie twice: as the pre-M4 owned copy and as a
    /// view into the movie's data. Returns `(owned, view)` pairs.
    fn bitmaps_both_ways(movie: &SwfMovieData) -> Vec<(CompressedBitmap, CompressedBitmap)> {
        let slice = SwfSlice::from(movie);
        let mut reader = slice.read_from(0);
        let mut jpeg_tables: Option<&[u8]> = None;
        let mut out = Vec::new();
        while let Ok(tag) = reader.read_tag() {
            match tag {
                swf::Tag::JpegTables(data) => {
                    jpeg_tables = (!data.is_empty()).then_some(data);
                }
                swf::Tag::DefineBits { jpeg_data, .. } => {
                    let glued = ruffle_render::utils::glue_tables_to_jpeg(jpeg_data, jpeg_tables);
                    let (width, height) =
                        ruffle_render::utils::decode_define_bits_jpeg_dimensions(&glued).unwrap();
                    let owned = CharacterBytes::Owned(glued.clone().into_owned().into());
                    let view = CharacterBytes::from_movie_cow(&slice, glued);
                    out.push((
                        CompressedBitmap::Jpeg {
                            data: owned,
                            alpha: None,
                            width,
                            height,
                        },
                        CompressedBitmap::Jpeg {
                            data: view,
                            alpha: None,
                            width,
                            height,
                        },
                    ));
                }
                swf::Tag::DefineBitsJpeg2 { jpeg_data, .. } => {
                    let (width, height) =
                        ruffle_render::utils::decode_define_bits_jpeg_dimensions(jpeg_data)
                            .unwrap();
                    out.push((
                        CompressedBitmap::Jpeg {
                            data: CharacterBytes::Owned(jpeg_data.into()),
                            alpha: None,
                            width,
                            height,
                        },
                        CompressedBitmap::Jpeg {
                            data: CharacterBytes::from_movie_slice(&slice, jpeg_data),
                            alpha: None,
                            width,
                            height,
                        },
                    ));
                }
                swf::Tag::DefineBitsJpeg3(jpeg) => {
                    let (width, height) =
                        ruffle_render::utils::decode_define_bits_jpeg_dimensions(jpeg.data)
                            .unwrap();
                    out.push((
                        CompressedBitmap::Jpeg {
                            data: CharacterBytes::Owned(jpeg.data.into()),
                            alpha: Some(CharacterBytes::Owned(jpeg.alpha_data.into())),
                            width,
                            height,
                        },
                        CompressedBitmap::Jpeg {
                            data: CharacterBytes::from_movie_slice(&slice, jpeg.data),
                            alpha: Some(CharacterBytes::from_movie_slice(&slice, jpeg.alpha_data)),
                            width,
                            height,
                        },
                    ));
                }
                swf::Tag::DefineBitsLossless(tag) => {
                    let make = |data| CompressedBitmap::Lossless {
                        version: tag.version,
                        id: tag.id,
                        format: tag.format,
                        width: tag.width,
                        height: tag.height,
                        data,
                    };
                    let owned = make(CharacterBytes::Owned(tag.data.clone().into_owned().into()));
                    let view = make(CharacterBytes::from_movie_cow(&slice, tag.data));
                    out.push((owned, view));
                }
                swf::Tag::End => break,
                _ => {}
            }
        }
        out
    }

    #[test]
    fn bitmap_views_decode_identically() {
        let movie = load_movie(BITMAP_SWF);
        let pairs = bitmaps_both_ways(&movie);
        assert!(
            pairs.len() >= 12,
            "expected many bitmaps, got {}",
            pairs.len()
        );

        let mut seen_jpeg_with_tables = false;
        let mut seen_lossless = false;
        let mut seen_alpha = false;
        for (owned, view) in &pairs {
            match view {
                CompressedBitmap::Jpeg { data, alpha, .. } => {
                    assert!(matches!(data, CharacterBytes::Movie(_)), "{view:?}");
                    if let Some(alpha) = alpha {
                        assert!(matches!(alpha, CharacterBytes::Movie(_)));
                        seen_alpha = true;
                    } else {
                        seen_jpeg_with_tables = true;
                    }
                }
                CompressedBitmap::Lossless { data, .. } => {
                    assert!(matches!(data, CharacterBytes::Movie(_)));
                    seen_lossless = true;
                }
            }
            assert_eq!(owned.compressed_len(), view.compressed_len());
            assert_eq!(view.owned_len(), 0);
            assert_eq!(owned.owned_len(), owned.compressed_len());

            let a = owned.decode().expect("owned decode");
            let b = view.decode().expect("view decode");
            assert_eq!(a.width(), b.width());
            assert_eq!(a.height(), b.height());
            assert_eq!(a.format(), b.format());
            assert_eq!(a.data(), b.data(), "decoded pixels differ for {view:?}");
        }
        assert!(seen_jpeg_with_tables && seen_lossless && seen_alpha);
    }

    #[test]
    fn glued_jpeg_tables_fall_back_to_an_owned_copy() {
        let movie = load_movie(BITMAP_SWF);
        let slice = SwfSlice::from(&movie);
        let jpeg: Vec<u8> = vec![0xFF, 0xD8, 0xFF, 0xD9];
        let tables: Vec<u8> = vec![0xFF, 0xD8, 0x01, 0x02, 0xFF, 0xD9];
        let glued = ruffle_render::utils::glue_tables_to_jpeg(&jpeg, Some(&tables));
        assert!(matches!(glued, Cow::Owned(_)));
        let bytes = CharacterBytes::from_movie_cow(&slice, glued);
        assert!(matches!(bytes, CharacterBytes::Owned(_)));
        assert_eq!(bytes.as_ref(), &[0xFF, 0xD8, 0x01, 0x02, 0xFF, 0xD9]);
        assert_eq!(bytes.owned_len(), 6);

        // A slice that is not part of the movie is copied, not referenced.
        let foreign = [1u8, 2, 3];
        let bytes = CharacterBytes::from_movie_slice(&slice, &foreign);
        assert!(matches!(bytes, CharacterBytes::Owned(_)));
        assert_eq!(bytes.as_ref(), &foreign);
    }

    /// Loads the SWF into a real `Player` and measures what the library's bitmap
    /// characters keep on their own, next to the movie data that is held anyway.
    #[test]
    fn library_keeps_no_second_copy_of_bitmap_bytes() {
        use crate::character::Character;
        use crate::display_object::TDisplayObject;
        use crate::limits::ExecutionLimit;

        let movie = load_movie(BITMAP_SWF);
        let movie_len = movie.data().len();
        let player = crate::player::PlayerBuilder::new()
            .with_movie(movie)
            .build();
        let mut player = player.lock().unwrap();
        player.preload(&mut ExecutionLimit::none());

        let (count, compressed, owned) = player.mutate_with_update_context(|context| {
            let root = context.stage.root_clip().expect("root");
            let library = context
                .library
                .library_for_movie(root.movie())
                .expect("root library");
            let mut count = 0usize;
            let mut compressed = 0usize;
            let mut owned = 0usize;
            for character in library.characters().values() {
                if let Character::Bitmap(bitmap) = character {
                    count += 1;
                    compressed += bitmap.compressed().compressed_len();
                    owned += bitmap.compressed().owned_len();
                }
            }
            (count, compressed, owned)
        });
        eprintln!(
            "M4 bitmaps: {count} characters, movie data {movie_len} bytes, \
             compressed image bytes {compressed}, owned copies now {owned} (before: {compressed})"
        );
        assert!(count >= 12, "{count}");
        assert!(compressed > 10_000, "{compressed}");
        assert_eq!(owned, 0);
    }
}
