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
