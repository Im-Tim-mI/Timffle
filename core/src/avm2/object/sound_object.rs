//! Object representation for sounds

use crate::avm2::Avm2;
use crate::avm2::Error;
use crate::avm2::EventObject;
use crate::avm2::activation::Activation;
use crate::avm2::globals::slots::flash_media_id3info as id3_slots;
use crate::avm2::object::script_object::ScriptObjectData;
use crate::avm2::object::{ClassObject, Object, TObject};
use crate::backend::audio::{AudioManager, SoundHandle, SoundRelease, SoundSampleSource};
use crate::context::UpdateContext;
use crate::display_object::SoundTransform;
use crate::string::AvmString;
use core::fmt;
use gc_arena::barrier::unlock;
use gc_arena::{
    Collect, DynamicRoot, Gc, GcWeak, Mutation, Rootable,
    lock::{Lock, RefLock},
};
use id3::{Tag, TagLike};
use ruffle_common::utils::HasPrefixField;
use std::cell::{Cell, RefCell};
use std::io::Cursor;
use swf::SoundInfo;

use super::SoundChannelObject;

/// The sample rate `Sound.extract()` always reports (Flash: "always 44100 Hz stereo").
pub const EXTRACT_SAMPLE_RATE: u32 = 44100;

/// A class instance allocator that allocates Sound objects.
pub fn sound_allocator<'gc>(
    class: ClassObject<'gc>,
    activation: &mut Activation<'_, 'gc>,
) -> Result<Object<'gc>, Error<'gc>> {
    let base = ScriptObjectData::new(class);

    Ok(SoundObject(Gc::new(
        activation.gc(),
        SoundObjectData {
            base,
            loading_state: Cell::new(SoundLoadingState::New),
            sound_data: RefLock::new(SoundData::NotLoaded {
                queued_plays: Vec::new(),
            }),
            id3: Lock::new(None),
            url: Lock::new(None),
            bytes_loaded: Cell::new(0),
            bytes_total: Cell::new(0),
            is_buffering: Cell::new(false),
            is_url_inaccessible: Cell::new(false),
            stream_open: Cell::new(false),
            load_generation: Cell::new(0),
            extract_cursor: Cell::new(0),
            extract: RefCell::new(None),
        },
    ))
    .into())
}

#[derive(Clone, Collect, Copy)]
#[collect(no_drop)]
pub struct SoundObject<'gc>(pub Gc<'gc, SoundObjectData<'gc>>);

#[derive(Clone, Collect, Copy, Debug)]
#[collect(no_drop)]
pub struct SoundObjectWeak<'gc>(pub GcWeak<'gc, SoundObjectData<'gc>>);

impl fmt::Debug for SoundObject<'_> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("SoundObject")
            .field("ptr", &Gc::as_ptr(self.0))
            .finish()
    }
}

#[derive(Clone)]
pub struct SoundObjectHandle(DynamicRoot<Rootable![SoundObjectData<'_>]>);

impl SoundObjectHandle {
    pub fn stash<'gc>(context: &UpdateContext<'gc>, this: SoundObject<'gc>) -> Self {
        Self(context.dynamic_root.stash(context.gc(), this.0))
    }

    pub fn fetch<'gc>(&self, context: &UpdateContext<'gc>) -> SoundObject<'gc> {
        SoundObject(context.dynamic_root.fetch(&self.0))
    }
}

/// Timffle: the decoder `Sound.extract()` keeps between calls so that reading a
/// long sound in chunks does not decode it from the start every time.
struct ExtractState {
    source: Box<dyn SoundSampleSource>,
    /// Sample frames the sound has at the source's own rate.
    source_frames: u32,
    /// Sample frames already taken from `source`.
    source_pos: u32,
    /// The last frame taken from `source` (held while resampling).
    last: [i16; 2],
    /// 44.1 kHz output frames already produced.
    out_pos: u32,
}

impl ExtractState {
    /// Number of 44.1 kHz output frames the whole sound yields.
    fn total_out(&self) -> u32 {
        let rate = u64::from(self.source.sample_rate().max(1));
        if rate == u64::from(EXTRACT_SAMPLE_RATE) {
            self.source_frames
        } else {
            (u64::from(self.source_frames) * u64::from(EXTRACT_SAMPLE_RATE) / rate) as u32
        }
    }

    /// The source frame holding output frame `out`.
    fn source_index(&self, out: u32) -> u32 {
        let rate = u64::from(self.source.sample_rate().max(1));
        if rate == u64::from(EXTRACT_SAMPLE_RATE) {
            out
        } else {
            (u64::from(out) * rate / u64::from(EXTRACT_SAMPLE_RATE)) as u32
        }
    }

    fn next_out(&mut self) -> [i16; 2] {
        let want = self.source_index(self.out_pos);
        while self.source_pos <= want {
            match self.source.next() {
                Some(frame) => {
                    self.last = frame;
                    self.source_pos += 1;
                }
                None => break,
            }
        }
        self.out_pos += 1;
        self.last
    }
}

#[derive(Collect, HasPrefixField)]
#[collect(no_drop)]
#[repr(C, align(8))]
pub struct SoundObjectData<'gc> {
    /// Base script object
    base: ScriptObjectData<'gc>,

    /// Loading state of the sound.
    loading_state: Cell<SoundLoadingState>,

    /// The sound this object holds.
    sound_data: RefLock<SoundData<'gc>>,

    /// ID3Info Object
    id3: Lock<Option<Object<'gc>>>,

    /// Timffle: `Sound.url` — the final URL of a sound loaded with `load()`.
    /// Flash sets it when the first `progress` event is dispatched, not at
    /// `open` (measured on Flash Player 32), and only the origin when
    /// `isURLInaccessible` is true.
    url: Lock<Option<AvmString<'gc>>>,

    /// Timffle: `Sound.bytesLoaded` / `bytesTotal`.
    bytes_loaded: Cell<u32>,
    bytes_total: Cell<u32>,

    /// Timffle: `Sound.isBuffering` — true from `load()` on, for ever (Flash
    /// Player 32 keeps reporting true after `complete`, after `close()` and
    /// after an `ioError`; library and ByteArray sounds report false).
    is_buffering: Cell<bool>,

    /// Timffle: `Sound.isURLInaccessible`.
    is_url_inaccessible: Cell<bool>,

    /// Timffle: `load()` opened a stream that `close()` has not closed yet.
    /// `close()` without an open stream is `IOError #2029` in Flash, also on a
    /// sound that finished loading and was closed once.
    stream_open: Cell<bool>,

    /// Timffle: bumped by `load()` and `close()`; a download that finishes for
    /// an older generation (closed while loading) is dropped.
    load_generation: Cell<u32>,

    /// Timffle: the 44.1 kHz sample frame the next `extract()` without a
    /// `startPosition` continues from.
    extract_cursor: Cell<u32>,

    /// Timffle: the decoder behind `extract()`, see `ExtractState`.
    #[collect(require_static)]
    extract: RefCell<Option<ExtractState>>,
}

#[derive(Collect)]
#[collect(no_drop)]
pub enum SoundData<'gc> {
    NotLoaded {
        queued_plays: Vec<QueuedPlay<'gc>>,
    },
    Loaded {
        #[collect(require_static)]
        sound: SoundHandle,

        /// Set when this object owns `sound` (it was loaded by URL or from a
        /// `ByteArray`); dropping it releases the sound. `None` for sounds
        /// that belong to a SWF library.
        #[collect(require_static)]
        _release: Option<SoundRelease>,
    },
}

#[derive(Clone, Collect)]
#[collect(no_drop)]
pub struct QueuedPlay<'gc> {
    #[collect(require_static)]
    pub sound_info: SoundInfo,
    #[collect(require_static)]
    pub sound_transform: Option<SoundTransform>,
    pub sound_channel: SoundChannelObject<'gc>,
    pub position: f64,
}

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum SoundLoadingState {
    New,
    Loading,
    Loaded,
}

impl<'gc> SoundObject<'gc> {
    pub fn sound_handle(self) -> Option<SoundHandle> {
        let sound_data = self.0.sound_data.borrow();
        match &*sound_data {
            SoundData::NotLoaded { .. } => None,
            SoundData::Loaded { sound, .. } => Some(*sound),
        }
    }

    pub fn loading_state(self) -> SoundLoadingState {
        self.0.loading_state.get()
    }

    pub fn set_loading_state(self, value: SoundLoadingState) {
        self.0.loading_state.set(value);
    }

    pub fn url(self) -> Option<AvmString<'gc>> {
        self.0.url.get()
    }

    pub fn set_url(self, mc: &Mutation<'gc>, url: Option<AvmString<'gc>>) {
        unlock!(Gc::write(mc, self.0), SoundObjectData, url).set(url);
    }

    pub fn bytes_loaded(self) -> u32 {
        self.0.bytes_loaded.get()
    }

    pub fn bytes_total(self) -> u32 {
        self.0.bytes_total.get()
    }

    pub fn set_bytes(self, loaded: u32, total: u32) {
        self.0.bytes_loaded.set(loaded);
        self.0.bytes_total.set(total);
    }

    pub fn is_buffering(self) -> bool {
        self.0.is_buffering.get()
    }

    pub fn is_url_inaccessible(self) -> bool {
        self.0.is_url_inaccessible.get()
    }

    pub fn set_url_inaccessible(self, value: bool) {
        self.0.is_url_inaccessible.set(value);
    }

    pub fn stream_open(self) -> bool {
        self.0.stream_open.get()
    }

    pub fn load_generation(self) -> u32 {
        self.0.load_generation.get()
    }

    /// `load()` was called: the stream is open and the sound buffers.
    pub fn begin_load(self) -> u32 {
        self.0.stream_open.set(true);
        self.0.is_buffering.set(true);
        self.0.load_generation.set(self.0.load_generation.get().wrapping_add(1));
        self.0.loading_state.set(SoundLoadingState::Loading);
        self.0.load_generation.get()
    }

    /// `close()`: closes the stream; a download still running is abandoned and
    /// the object can be loaded again.
    pub fn close_stream(self) {
        self.0.stream_open.set(false);
        if self.0.loading_state.get() == SoundLoadingState::Loading {
            self.0.loading_state.set(SoundLoadingState::New);
            self.0.load_generation.set(self.0.load_generation.get().wrapping_add(1));
        }
    }

    /// A download ended without a sound (`ioError`): `load()` is allowed again.
    pub fn load_failed(self) {
        if self.0.loading_state.get() == SoundLoadingState::Loading {
            self.0.loading_state.set(SoundLoadingState::New);
        }
    }

    /// Returns `true` if a `SoundChannel` should be returned back to the AVM2 caller.
    pub fn play(self, queued: QueuedPlay<'gc>, activation: &mut Activation<'_, 'gc>) -> bool {
        let mut sound_data = unlock!(
            Gc::write(activation.gc(), self.0),
            SoundObjectData,
            sound_data
        )
        .borrow_mut();
        match &mut *sound_data {
            SoundData::NotLoaded { queued_plays } => {
                // Avoid to enqueue more unloaded sounds than the maximum allowed to be played
                if queued_plays.len() >= AudioManager::MAX_SOUNDS {
                    tracing::warn!("Sound.play: too many unloaded sounds queued");
                    return false;
                }

                queued_plays.push(queued);

                // We don't know the length yet, so return the `SoundChannel`
                true
            }
            SoundData::Loaded { sound, .. } => play_queued(queued, *sound, activation.context),
        }
    }

    /// Attach a sound that belongs to a SWF library.
    pub fn set_sound(self, context: &mut UpdateContext<'gc>, sound: SoundHandle) {
        let size = context.audio.get_sound_size(sound).unwrap_or(0);
        self.set_bytes(size, size);
        self.set_sound_inner(context, sound, None);
    }

    /// Attach a sound made by `AudioBackend::register_mp3` for this object
    /// only. It is unregistered once this object is collected.
    pub fn set_owned_sound(self, context: &mut UpdateContext<'gc>, sound: SoundHandle) {
        let release = context.audio_manager.own_sound(sound);
        self.set_sound_inner(context, sound, Some(release));
    }

    fn set_sound_inner(
        self,
        context: &mut UpdateContext<'gc>,
        sound: SoundHandle,
        release: Option<SoundRelease>,
    ) {
        let mut sound_data =
            unlock!(Gc::write(context.gc(), self.0), SoundObjectData, sound_data).borrow_mut();

        match &mut *sound_data {
            SoundData::NotLoaded { queued_plays } => {
                for queued in std::mem::take(queued_plays) {
                    play_queued(queued, sound, context);
                }
                *sound_data = SoundData::Loaded {
                    sound,
                    _release: release,
                };
            }
            SoundData::Loaded {
                sound: old_sound, ..
            } => {
                panic!("Tried to replace sound {old_sound:?} with {sound:?}")
            }
        }
        self.0.extract.replace(None);
        self.0.extract_cursor.set(0);
        self.set_loading_state(SoundLoadingState::Loaded);
    }

    /// Timffle: `Sound.extract()` — up to `count` 44.1 kHz stereo sample frames
    /// starting at output frame `start` (`None`: continue after the previous
    /// call). Returns the frames; the sequential cursor ends up after them.
    pub fn extract(
        self,
        context: &mut UpdateContext<'gc>,
        start: Option<u32>,
        count: u32,
    ) -> Vec<[i16; 2]> {
        let Some(handle) = self.sound_handle() else {
            return Vec::new();
        };
        let start = start.unwrap_or_else(|| self.0.extract_cursor.get());
        let mut slot = self.0.extract.borrow_mut();
        let needs_new = match &*slot {
            Some(state) => state.out_pos > start,
            None => true,
        };
        if needs_new {
            let Some((source, source_frames)) = context.audio.sound_samples(handle) else {
                return Vec::new();
            };
            *slot = Some(ExtractState {
                source,
                source_frames,
                source_pos: 0,
                last: [0, 0],
                out_pos: 0,
            });
        }
        let state = slot.as_mut().expect("extract state was just created");
        let total = state.total_out();
        if start >= total || count == 0 {
            return Vec::new();
        }
        let count = count.min(total - start);
        while state.out_pos < start {
            state.next_out();
        }
        let mut frames = Vec::with_capacity(count as usize);
        for _ in 0..count {
            frames.push(state.next_out());
        }
        self.0.extract_cursor.set(start + count);
        frames
    }

    pub fn id3(self) -> Option<Object<'gc>> {
        self.0.id3.get()
    }

    pub fn set_id3(self, mc: &Mutation<'gc>, id3: Option<Object<'gc>>) {
        unlock!(Gc::write(mc, self.0), SoundObjectData, id3).set(id3);
    }

    pub fn read_and_call_id3_event(self, activation: &mut Activation<'_, 'gc>, bytes: &[u8]) {
        let id3 = activation
            .avm2()
            .classes()
            .id3info
            .construct(activation, &[])
            .expect("failed to construct ID3Info object")
            .as_object()
            .unwrap();

        let tag = Tag::read_from2(Cursor::new(bytes));
        if let Ok(ref tag) = tag {
            if let Some(v) = tag.album() {
                id3.set_slot(
                    id3_slots::ALBUM,
                    AvmString::new_utf8(activation.gc(), v).into(),
                    activation,
                )
                .expect("slot is typed String");
            }
            if let Some(v) = tag.artist() {
                id3.set_slot(
                    id3_slots::ARTIST,
                    AvmString::new_utf8(activation.gc(), v).into(),
                    activation,
                )
                .expect("slot is typed String");
            }
            if let Some(v) = tag.comments().next() {
                id3.set_slot(
                    id3_slots::COMMENT,
                    AvmString::new_utf8(activation.gc(), v.text.clone()).into(),
                    activation,
                )
                .expect("slot is typed String");
            }
            if let Some(v) = tag.genre() {
                id3.set_slot(
                    id3_slots::GENRE,
                    AvmString::new_utf8(activation.gc(), v).into(),
                    activation,
                )
                .expect("slot is typed String");
            }
            if let Some(v) = tag.title() {
                id3.set_slot(
                    id3_slots::SONG_NAME,
                    AvmString::new_utf8(activation.gc(), v).into(),
                    activation,
                )
                .expect("slot is typed String");
            }
            if let Some(v) = tag.track() {
                id3.set_slot(
                    id3_slots::TRACK,
                    AvmString::new_utf8(activation.gc(), v.to_string()).into(),
                    activation,
                )
                .expect("slot is typed String");
            }
            if let Some(v) = tag.year() {
                id3.set_slot(
                    id3_slots::YEAR,
                    AvmString::new_utf8(activation.gc(), v.to_string()).into(),
                    activation,
                )
                .expect("slot is typed String");
            }
        }
        self.set_id3(activation.gc(), Some(id3));
        if tag.is_ok() {
            let id3_evt = EventObject::bare_default_event(activation.context, "id3");
            Avm2::dispatch_event(activation.context, id3_evt, self.into());
        }
    }
}

/// Returns `true` if the sound had a valid position, and `false` otherwise
fn play_queued<'gc>(
    queued: QueuedPlay<'gc>,
    sound: SoundHandle,
    context: &mut UpdateContext<'gc>,
) -> bool {
    if let Some(duration) = context.audio.get_sound_duration(sound)
        && queued.position > duration.as_millis()
    {
        tracing::error!(
            "Sound.play: position={} is greater than duration={}",
            queued.position,
            duration.as_millis()
        );
        return false;
    }

    if let Some(instance) = context.start_sound(
        sound,
        &queued.sound_info,
        queued.sound_transform,
        None,
        None,
    ) {
        queued.sound_channel.set_sound_instance(context, instance);

        context.attach_avm2_sound_channel(instance, queued.sound_channel);
    }

    true
}

impl<'gc> TObject<'gc> for SoundObject<'gc> {
    fn gc_base(&self) -> Gc<'gc, ScriptObjectData<'gc>> {
        HasPrefixField::as_prefix_gc(self.0)
    }
}
