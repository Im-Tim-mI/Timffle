//! NetStream implementation

use crate::avm1::{
    Activation as Avm1Activation, ActivationIdentifier as Avm1ActivationIdentifier,
    ExecutionReason as Avm1ExecutionReason, FlvValueAvm1Ext, Object as Avm1Object,
};
use crate::avm2::object::NetStreamObject;
use crate::avm2::{
    Activation as Avm2Activation, Avm2, Error as Avm2Error, EventObject as Avm2EventObject,
    FlvValueAvm2Ext, FunctionArgs, Object as Avm2Object, Value as Avm2Value,
};
use crate::backend::audio::{
    DecodeError, SoundInstanceHandle, SoundStreamInfo, SoundStreamWrapping,
};
use crate::backend::navigator::Request;
use crate::context::UpdateContext;
use crate::display_object::{MovieClip, SoundTransform, TDisplayObject};
use crate::loader::Error;
use crate::string::AvmString;
use flv_rs::{
    AudioData as FlvAudioData, AudioDataType as FlvAudioDataType, Error as FlvError, FlvReader,
    FrameType as FlvFrameType, Header as FlvHeader, ScriptData as FlvScriptData,
    SoundFormat as FlvSoundFormat, SoundRate as FlvSoundRate, SoundSize as FlvSoundSize,
    SoundType as FlvSoundType, Tag as FlvTag, TagData as FlvTagData, Value as FlvValue,
    VideoData as FlvVideoData, VideoPacket as FlvVideoPacket,
};
use gc_arena::barrier::unlock;
use gc_arena::{Collect, DynamicRoot, Gc, Lock, Mutation, Rootable};
use ruffle_common::buffer::{Buffer, Slice, Substream, SubstreamError};
use ruffle_common::duration::FloatDuration;
use ruffle_macros::istr;
use ruffle_render::bitmap::BitmapInfo;
use ruffle_video::VideoStreamHandle;
use ruffle_video::frame::EncodedFrame;
use std::cell::{Cell, RefCell};
use std::cmp::max;
use std::io::{Seek, SeekFrom};
use swf::{AudioCompression, SoundFormat, VideoCodec, VideoDeblocking};
use thiserror::Error;
use url::Url;

#[derive(Debug, Error)]
enum NetstreamError {
    #[error("Decoding failed because {0}")]
    DecodeError(DecodeError),

    #[error("Substream management error {0}")]
    SubstreamError(SubstreamError),

    #[error("Unknown codec")]
    UnknownCodec,
}

impl From<DecodeError> for NetstreamError {
    fn from(err: DecodeError) -> NetstreamError {
        NetstreamError::DecodeError(err)
    }
}

impl From<SubstreamError> for NetstreamError {
    fn from(err: SubstreamError) -> NetstreamError {
        NetstreamError::SubstreamError(err)
    }
}

/// Manager for all media streams.
///
/// This does *not* handle data transport; which is delegated to `LoadManager`.
/// `StreamManager` *only* handles decoding or encoding of relevant media
/// streams.
#[derive(Collect)]
#[collect(no_drop)]
pub struct StreamManager<'gc> {
    /// List of streams that need tick processing.
    ///
    /// This is not the total list of all created NetStreams; only the ones
    /// that have been configured to play media.
    ///
    /// A stream becomes active if it is either playing streaming media or is
    /// doing other tick-time processing such as seeking.
    active_streams: Vec<NetStream<'gc>>,
}

impl Default for StreamManager<'_> {
    fn default() -> Self {
        Self::new()
    }
}

impl<'gc> StreamManager<'gc> {
    pub fn new() -> Self {
        StreamManager {
            active_streams: Vec::new(),
        }
    }

    /// Activate a `NetStream`.
    ///
    /// This can be called at any time to flag that a `NetStream` has work to
    /// do, and called multiple times. The `NetStream` will determine what to
    /// do at tick time.
    pub fn activate(context: &mut UpdateContext<'gc>, stream: NetStream<'gc>) {
        if !context.stream_manager.active_streams.contains(&stream) {
            context.stream_manager.active_streams.push(stream);
        }
    }

    /// Deactivate a `NetStream`.
    ///
    /// This should only ever be called at tick time if the stream itself has
    /// determined there is no future work for it to do.
    pub fn deactivate(context: &mut UpdateContext<'gc>, stream: NetStream<'gc>) {
        let index = context
            .stream_manager
            .active_streams
            .iter()
            .position(|x| *x == stream);
        if let Some(index) = index {
            context.stream_manager.active_streams.remove(index);
        }
    }

    /// Process all active media streams.
    ///
    /// This is an unlocked timestep; the `dt` parameter indicates how many
    /// milliseconds have elapsed since the last tick. This is intended to
    /// support video framerates separate from the Stage frame rate.
    ///
    /// This does not borrow `&mut self` as we need the `UpdateContext`, too.
    pub fn tick(context: &mut UpdateContext<'gc>, dt: FloatDuration) {
        let streams = context.stream_manager.active_streams.clone();
        for stream in streams {
            stream.tick(context, dt)
        }
    }
}

#[derive(Copy, Clone, Collect, Debug)]
#[collect(no_drop)]
enum NetStreamKind<'gc> {
    Avm2(NetStreamObject<'gc>),
    Avm1(Avm1Object<'gc>),
}

/// A stream representing download of some (audiovisual) data.
///
/// `NetStream` interacts with several different parts of player
/// infrastructure:
///
///  * `LoadManager` fills individual `NetStream` buffers with data (or, in the
///    future, empties them out for media upload)
///  * `StreamManager` processes media data in the `NetStream` buffer (in the
///    future, sending it to the audio backend or `SoundManager`)
///  * `Video` display objects linked to this `NetStream` display the latest
///    decoded frame.
///
/// It corresponds directly to the AVM1 and AVM2 `NetStream` classes; it's API
/// is intended to be a VM-agnostic version of those.
#[derive(Clone, Debug, Collect, Copy)]
#[collect(no_drop)]
pub struct NetStream<'gc>(Gc<'gc, NetStreamData<'gc>>);

impl PartialEq for NetStream<'_> {
    fn eq(&self, other: &Self) -> bool {
        std::ptr::eq(Gc::as_ptr(self.0), Gc::as_ptr(other.0))
    }
}

impl Eq for NetStream<'_> {}

#[derive(Clone)]
pub struct NetStreamHandle(DynamicRoot<Rootable![NetStreamData<'_>]>);

impl NetStreamHandle {
    pub fn stash<'gc>(context: &UpdateContext<'gc>, this: NetStream<'gc>) -> Self {
        Self(context.dynamic_root.stash(context.gc(), this.0))
    }

    pub fn fetch<'gc>(&self, context: &UpdateContext<'gc>) -> NetStream<'gc> {
        NetStream(context.dynamic_root.fetch(&self.0))
    }
}

/// The current type of the data in the stream buffer.
#[derive(Clone, Debug)]
pub enum NetStreamType {
    /// The stream is an FLV.
    Flv {
        // Timffle: kept across `appendBytesAction(RESET_SEEK)`.
        header: FlvHeader,

        /// The currently playing video track's stream instance.
        video_stream: Option<VideoStreamHandle>,

        /// The index of the last processed frame.
        ///
        /// FLV does not store this information directly and we are not holding
        /// onto a table of data buffers like `Video` does, so we must maintain
        /// frame IDs ourselves for various API related purposes.
        frame_id: u32,
    },
}

#[derive(Clone, Debug, Collect)]
#[collect(no_drop)]
pub struct NetStreamSource {
    /// All data currently loaded in the stream.
    buffer: RefCell<Buffer>,

    /// The buffer position that we are currently seeking to.
    offset: Cell<usize>,

    /// The expected length of the buffer once downloading is complete.
    ///
    /// `None` indicates that downloading is already complete and that the
    /// length of the associated `Buffer` is the final length.
    expected_length: Cell<Option<usize>>,

    /// The buffer position for processing incoming data.
    ///
    /// This points to the first byte that the stream has *never* processed
    /// before in the buffer. It should always be greater than or equal to the
    /// offset position.
    ///
    /// Certain data, such as the header or metadata of an FLV, should only
    /// ever be processed one time, even if we seek backwards to it later on.
    /// We call this data "preloaded", whether or not there is actually a
    /// separate preload step for that given format.
    preload_offset: Cell<usize>,

    /// The current stream type, if known.
    stream_type: RefCell<Option<NetStreamType>>,

    /// The current seek offset in the stream in milliseconds.
    stream_time: Cell<f64>,

    /// The next queued seek offset in milliseconds.
    ///
    /// Seeks are only executed on the next stream tick.
    queued_seek_time: Cell<Option<f64>>,

    /// The `Substream` associated with the currently playing audio track and
    /// the expected playback format of that audio.
    audio_stream: RefCell<Option<(Substream, SoundStreamInfo)>>,

    /// The currently playing sound stream
    sound_instance: Cell<Option<SoundInstanceHandle>>,

    /// Timffle: true while playback waits for `bufferTime` seconds of data;
    /// `NetStream.Buffer.Full` is sent when the wait ends.
    buffering: Cell<bool>,

    /// Timffle: the FLV codec ids of the stream (`NetStream.audioCodec` /
    /// `videoCodec`), 0 until a tag of that kind was seen.
    audio_codec: Cell<u32>,
    video_codec: Cell<u32>,

    /// Timffle: frames decoded so far (`NetStream.decodedFrames`) and frames
    /// whose decoding failed (`NetStreamInfo.droppedFrames`).
    decoded_frames: Cell<u32>,
    dropped_frames: Cell<u32>,

    /// Timffle: `NetStream.currentFPS`: frames decoded since the window
    /// started (stream time in ms, count) and the last computed rate.
    fps_window: Cell<(f64, u32)>,
    current_fps: Cell<f64>,

    /// Timffle: Data Generation Mode (`play(null)` followed by `appendBytes`).
    data_generation: Cell<bool>,

    /// Timffle: after `appendBytesAction(RESET_SEEK)` the stream time restarts
    /// at the timestamp of the first tag appended.
    resync_time: Cell<bool>,

    /// Timffle: `NetStreamInfo` rates: bytes loaded at the last sample, ms
    /// elapsed since it, bytes processed since it, current/max download B/s
    /// and playback B/s.
    rate_bytes_last: Cell<usize>,
    rate_elapsed: Cell<f64>,
    rate_processed: Cell<usize>,
    current_bps: Cell<f64>,
    max_bps: Cell<f64>,
    playback_bps: Cell<f64>,
}

#[derive(Clone, Debug, Collect)]
#[collect(no_drop)]
pub struct NetStreamData<'gc> {
    /// Stream source.
    source: Lock<Gc<'gc, NetStreamSource>>,

    /// The number of seconds of video data that should be buffered. This is
    /// currently unsupported and changing it has no effect.
    buffer_time: Cell<f64>,

    /// The last decoded bitmap.
    ///
    /// Any `Video`s on the stage will display the bitmap here when attached to
    /// this `NetStream`.
    last_decoded_bitmap: RefCell<Option<BitmapInfo>>,

    /// Timffle: counts decoded frames so a `Video` can tell whether a frame
    /// is newer than the one its `clear()` hid.
    decoded_frame_serial: Cell<u64>,

    /// Timffle: the frame size announced by the FLV's `onMetaData`, which
    /// `Video.videoWidth`/`videoHeight` report before the first frame.
    metadata_size: Cell<Option<(u16, u16)>>,

    /// The AVM side of this stream.
    avm_object: Lock<Option<NetStreamKind<'gc>>>,

    /// The AVM2 client object, which corresponds to `NetStream.client`.
    avm2_client: Lock<Option<Avm2Object<'gc>>>,

    /// The URL of the requested FLV if one exists.
    url: RefCell<Option<String>>,

    /// The MovieClip this `NetStream` is attached to.
    attached_to: Lock<Option<MovieClip<'gc>>>,

    /// True if the stream should play when ticked.
    playing: Cell<bool>,

    /// Timffle: `NetStream.soundTransform`, applied to the stream's sound.
    sound_transform: Cell<SoundTransform>,

    /// Timffle: `NetStream.inBufferSeek` and `backBufferTime` (seconds).
    in_buffer_seek: Cell<bool>,
    back_buffer_time: Cell<f64>,

    /// Timffle: the last `onMetaData` / `onXMPData` objects handed to the
    /// AVM2 client (`NetStreamInfo.metaData` / `xmpData`).
    metadata: Lock<Option<Avm2Object<'gc>>>,
    xmp_data: Lock<Option<Avm2Object<'gc>>>,
}

/// Timffle: what a scan of the FLV tags in the buffer found, for
/// `bufferLength`, `backBufferLength` and `NetStreamInfo`.
#[derive(Clone, Copy, Debug, Default)]
pub struct BufferStats {
    /// Payload bytes of every audio / video / script tag in the buffer.
    pub audio_bytes: usize,
    pub video_bytes: usize,
    pub data_bytes: usize,
    /// Payload bytes of the tags not yet played.
    pub audio_ahead_bytes: usize,
    pub video_ahead_bytes: usize,
    pub data_ahead_bytes: usize,
    /// The last timestamp (ms) per kind among the tags not yet played.
    pub audio_end: Option<i32>,
    pub video_end: Option<i32>,
    pub data_end: Option<i32>,
    /// The first and last tag timestamps (ms) in the buffer.
    pub start_ts: Option<i32>,
    pub end_ts: Option<i32>,
}

impl Default for NetStreamSource {
    fn default() -> Self {
        Self {
            buffer: RefCell::new(Buffer::new()),
            offset: Cell::new(0),
            expected_length: Cell::new(Some(0)),
            preload_offset: Cell::new(0),
            stream_type: RefCell::new(None),
            stream_time: Cell::new(0.0),
            queued_seek_time: Cell::new(None),
            audio_stream: RefCell::new(None),
            sound_instance: Cell::new(None),
            buffering: Cell::new(true),
            audio_codec: Cell::new(0),
            video_codec: Cell::new(0),
            decoded_frames: Cell::new(0),
            dropped_frames: Cell::new(0),
            fps_window: Cell::new((0.0, 0)),
            current_fps: Cell::new(0.0),
            data_generation: Cell::new(false),
            resync_time: Cell::new(false),
            rate_bytes_last: Cell::new(0),
            rate_elapsed: Cell::new(0.0),
            rate_processed: Cell::new(0),
            current_bps: Cell::new(0.0),
            max_bps: Cell::new(0.0),
            playback_bps: Cell::new(0.0),
        }
    }
}

impl<'gc> NetStream<'gc> {
    /// Create a `NetStream` for use in AVM1.
    pub fn new_avm1(gc_context: &Mutation<'gc>, avm_object: Avm1Object<'gc>) -> Self {
        Self::new(gc_context, Some(NetStreamKind::Avm1(avm_object)))
    }

    /// Create a `NetStream` for use in AVM2. The caller is expected to initialize
    /// the AVM side of the `NetStream` later, by using `set_avm2_object`.
    pub fn new_avm2(gc_context: &Mutation<'gc>) -> Self {
        Self::new(gc_context, None)
    }

    fn new(gc_context: &Mutation<'gc>, avm_object: Option<NetStreamKind<'gc>>) -> Self {
        // IMPORTANT: When adding new fields consider if they need to be
        //     added here or to NetStreamSource.
        Self(Gc::new(
            gc_context,
            NetStreamData {
                source: Lock::new(Gc::new(gc_context, Default::default())),
                buffer_time: Cell::new(0.1),
                last_decoded_bitmap: RefCell::new(None),
                decoded_frame_serial: Cell::new(0),
                metadata_size: Cell::new(None),
                avm_object: Lock::new(avm_object),
                avm2_client: Lock::new(None),
                url: RefCell::new(None),
                attached_to: Lock::new(None),
                playing: Cell::new(false),
                sound_transform: Cell::new(SoundTransform::default()),
                in_buffer_seek: Cell::new(false),
                back_buffer_time: Cell::new(30.0),
                metadata: Lock::new(None),
                xmp_data: Lock::new(None),
            },
        ))
    }

    fn source(self) -> Gc<'gc, NetStreamSource> {
        self.0.source.get()
    }

    pub fn set_client(self, gc_context: &Mutation<'gc>, new_client: Avm2Object<'gc>) {
        unlock!(Gc::write(gc_context, self.0), NetStreamData, avm2_client).set(Some(new_client));
    }

    pub fn client(self) -> Option<Avm2Object<'gc>> {
        self.0.avm2_client.get()
    }

    pub fn set_avm2_object(self, gc_context: &Mutation<'gc>, object: NetStreamObject<'gc>) {
        let write = Gc::write(gc_context, self.0);
        unlock!(write, NetStreamData, avm_object).set(Some(NetStreamKind::Avm2(object)));
    }

    fn set_attached_to(self, gc_context: &Mutation<'gc>, attached_to: Option<MovieClip<'gc>>) {
        unlock!(Gc::write(gc_context, self.0), NetStreamData, attached_to).set(attached_to);
    }

    /// Reset the `NetStream` buffer to accept new source data.
    ///
    /// This must be done once per source change and should ideally be done
    /// immediately before the first `load_buffer` call for a particular source
    /// file.
    ///
    /// Externally visible AVM state must not be reinitialized here - i.e. the
    /// AS3 `client` doesn't go away because you played a new video file.
    fn reset_buffer(self, context: &mut UpdateContext<'gc>) {
        if let Some(instance) = self.source().sound_instance.get() {
            // We stop the sound twice because sounds may have either been
            // played through the audio manager or through the backend directly
            // depending on the attachment state at the time of first audio
            // playback.
            context.audio.stop_sound(instance);
            context.audio_manager.stop_sound(context.audio, instance);
        }

        unlock!(Gc::write(context.gc(), self.0), NetStreamData, source)
            .set(Gc::new(context.gc(), Default::default()));
    }

    /// Set the total number of bytes expected to be downloaded.
    pub fn set_expected_length(self, expected: usize) {
        let source = self.source();
        let mut buffer = source.buffer.borrow_mut();
        let len = buffer.len();

        // The subtract is to avoid reserving space for already-downloaded data.
        if expected > len {
            buffer.reserve(expected - len);
        }

        source.expected_length.set(Some(expected));
    }

    /// Append data to the `NetStream`'s current internal buffer.
    ///
    /// If you are loading data from a new source, you must first initialize
    /// the buffer, otherwise existing buffer contents will remain and be
    /// incorrectly parsed.
    ///
    /// Buffer loading can be done in chunks but must be done in such a way
    /// that all data is appended in the correct order and that data from
    /// separate streams is not mixed together.
    pub fn load_buffer(self, context: &mut UpdateContext<'gc>, data: &mut Vec<u8>) {
        self.source().buffer.borrow_mut().append(data);

        StreamManager::activate(context, self);

        // Timffle: `NetStream.Buffer.Full` is sent by `tick` once `bufferTime`
        // seconds are buffered (or the download is complete), like Flash; it
        // used to be sent here for every chunk.
    }

    /// Indicate that the buffer has finished loading and that no further data
    /// is expected to be downloaded to it.
    pub fn finish_buffer(self) {
        self.source().expected_length.set(None);
    }

    pub fn report_error(self, _error: Error) {
        // TODO: Report an `asyncError` to AVM1 or 2.
    }

    pub fn bytes_loaded(self) -> usize {
        self.source().buffer.borrow().len()
    }

    pub fn bytes_total(self) -> usize {
        let source = self.source();
        let buflen = source.buffer.borrow().len();
        std::cmp::max(source.expected_length.get().unwrap_or(buflen), buflen)
    }

    pub fn time(self) -> f64 {
        self.source().stream_time.get()
    }

    pub fn buffer_time(self) -> f64 {
        self.0.buffer_time.get()
    }

    pub fn set_buffer_time(self, buffer_time: f64) {
        self.0.buffer_time.set(buffer_time);
    }

    /// Queue a seek to be executed on the next frame tick.
    ///
    /// `offset` is in milliseconds.
    pub fn seek(self, context: &mut UpdateContext<'gc>, offset: f64, notify: bool) {
        self.source().queued_seek_time.set(Some(offset));
        StreamManager::activate(context, self);

        if notify {
            let trigger = format!("Start Seeking {}", offset as u64);
            self.trigger_status_event(
                context,
                [
                    ("description", trigger.as_str()),
                    ("level", "status"),
                    ("code", "NetStream.SeekStart.Notify"),
                ],
            );
        }
    }

    /// Seek to a new position in the stream.
    ///
    /// All existing audio will be paused. The stream offset will be snapped to
    /// either the prior or next keyframe depending on seek direction. If the
    /// stream is playing then new tag processing will occur when the stream
    /// ticks next.
    ///
    /// This always does an in-buffer seek. Seek-driven requests are not
    /// currently supported. When progressive download is implemented this seek
    /// algorithm will need to detect out-of-buffer seeks and trigger fresh
    /// downloads.
    ///
    /// `offset` is in milliseconds.
    ///
    /// This function should be run during stream ticks and *not* called by AVM
    /// code to service seek requests.
    pub fn execute_seek(self, context: &mut UpdateContext<'gc>, offset: f64) {
        // Timffle: with `inBufferSeek` Flash marks a seek served from the
        // buffer with `info.description = "client-inBufferSeek"`.
        if self.0.in_buffer_seek.get() {
            self.trigger_status_event(
                context,
                [
                    ("description", "client-inBufferSeek"),
                    ("level", "status"),
                    ("code", "NetStream.Seek.Notify"),
                ],
            );
        } else {
            self.trigger_status_event(
                context,
                [("code", "NetStream.Seek.Notify"), ("level", "status")],
            );
        }

        let source = self.source();

        // Ensure the container stream type is known before continuing.
        if source.stream_type.borrow().is_none() && !self.sniff_stream_type(context) {
            return;
        }

        if source.stream_time.get() == offset {
            //Don't do anything for no-op seeks.
            return;
        }

        if let Some(sound) = source.sound_instance.get() {
            context.stop_sound(sound);
            context.audio.stop_sound(sound);

            source.sound_instance.set(None);
            source.audio_stream.replace(None);
        }

        if matches!(
            &*source.stream_type.borrow(),
            Some(NetStreamType::Flv { .. })
        ) {
            let slice = source.buffer.borrow().to_full_slice();
            let buffer = slice.data();
            let mut reader = FlvReader::from_parts(&buffer, source.offset.get());
            let skipping_back = source.stream_time.get() > offset;

            loop {
                if skipping_back {
                    let res = FlvTag::skip_back(&mut reader);
                    if matches!(res, Err(FlvError::EndOfData)) {
                        //At start of video, can't skip further back
                        break;
                    }

                    if let Err(e) = res {
                        tracing::error!("FLV tag parsing failed during seek backward: {}", e);
                        break;
                    }
                }

                let old_position = reader
                    .stream_position()
                    .expect("valid stream position when seeking");

                let tag = FlvTag::parse(&mut reader);
                if matches!(tag, Err(FlvError::EndOfData)) {
                    //At end of video, can't skip further forward
                    break;
                }

                if let Err(e) = tag {
                    tracing::error!("FLV tag parsing failed during seek forward: {}", e);
                    break;
                }

                if skipping_back {
                    //Tag position won't actually move backwards if we don't do this.
                    reader
                        .seek(SeekFrom::Start(old_position))
                        .expect("valid backseek position");
                }

                let tag = tag.unwrap();
                let stream_time = tag.timestamp as f64;
                source.stream_time.set(stream_time);

                if skipping_back && stream_time > offset || !skipping_back && stream_time < offset {
                    continue;
                }

                match tag.data {
                    FlvTagData::Video(FlvVideoData {
                        frame_type: FlvFrameType::Keyframe,
                        ..
                    }) => {
                        // If we don't backseek when we find the keyframe,
                        // we will miss the keyframe.
                        reader
                            .seek(SeekFrom::Start(old_position))
                            .expect("valid backseek position");

                        break;
                    }
                    _ => continue,
                }
            }

            let offset = reader
                .stream_position()
                .expect("FLV reader stream position") as usize;
            source.offset.set(offset);
        }

        if let Some(NetStreamKind::Avm2(_)) = self.0.avm_object.get() {
            self.trigger_status_event(
                context,
                [
                    ("description", "Seek Complete -1"),
                    ("level", "status"),
                    ("code", "NetStream.Seek.Complete"),
                ],
            );
        }
    }

    /// Start playing media from this NetStream.
    ///
    /// If `name` is specified, this will also trigger streaming download of
    /// the given resource. Otherwise, the stream will play whatever data is
    /// available in the buffer.
    pub fn play(self, context: &mut UpdateContext<'gc>, name: Option<AvmString<'gc>>) {
        if let Some(name) = name {
            let request = if let Ok(stream_url) = Url::parse(context.root_swf.url())
                .and_then(|url| url.join(name.to_string().as_str()))
            {
                Request::get(stream_url.to_string())
            } else {
                Request::get(name.to_string())
            };
            self.0.url.replace(Some(request.url().to_string()));
            self.source().preload_offset.set(0);
            self.reset_buffer(context);

            let future = crate::loader::load_netstream(context, self, request);

            context.navigator.spawn_future(future);
        } else {
            // Timffle: `play(null)` enters Data Generation Mode: the buffer is
            // fed by `appendBytes` and `bytesTotal` follows `bytesLoaded`.
            let source = self.source();
            source.data_generation.set(true);
            source
                .expected_length
                .set(Some(source.buffer.borrow().len()));
        }

        self.0.playing.set(true);
        StreamManager::activate(context, self);

        self.trigger_status_event(
            context,
            [("code", "NetStream.Play.Start"), ("level", "status")],
        );
    }

    /// Pause stream playback.
    pub fn pause(self, context: &mut UpdateContext<'gc>, notify: bool) {
        // NOTE: We do not deactivate the stream here as there may be other
        // work to be done at tick time.
        self.0.playing.set(false);
        // Timffle: nothing is displayed per second while paused.
        let source = self.source();
        source.current_fps.set(0.0);
        source.fps_window.set((source.stream_time.get(), 0));

        if notify {
            self.trigger_status_event(
                context,
                [
                    ("description", "Pausing"),
                    ("level", "status"),
                    ("code", "NetStream.Pause.Notify"),
                ],
            );
        }
    }

    /// Resume stream playback.
    pub fn resume(self, context: &mut UpdateContext<'gc>) {
        self.0.playing.set(true);
        StreamManager::activate(context, self);
    }

    /// Resume stream playback if paused, pause otherwise.
    pub fn toggle_paused(self, context: &mut UpdateContext<'gc>) {
        self.0.playing.set(!self.0.playing.get());

        if self.0.playing.get() {
            StreamManager::activate(context, self);
        }
    }

    /// Indicates that this `NetStream`'s audio was detached from a `MovieClip` (AVM1)
    pub fn was_detached(self, context: &mut UpdateContext<'gc>) {
        let source = self.source();
        if let Some(sound_instance) = source.sound_instance.get() {
            context
                .audio_manager
                .stop_sound(context.audio, sound_instance);
        }

        source.audio_stream.replace(None);
        self.set_attached_to(context.gc(), None);
    }

    /// Indicates that this `NetStream`'s audio was attached to a `MovieClip` (AVM1)
    pub fn was_attached(self, context: &mut UpdateContext<'gc>, clip: MovieClip<'gc>) {
        let source = self.source();

        // A `NetStream` cannot be attached to two `MovieClip`s at once.
        // Stop the old sound; the new one will stream at the next tag read.
        // TODO: Change this to have `audio_manager` just switch the sound
        // transforms around
        if let Some(sound_instance) = source.sound_instance.get() {
            context
                .audio_manager
                .stop_sound(context.audio, sound_instance);
        }

        source.audio_stream.replace(None);
        self.set_attached_to(context.gc(), Some(clip));
    }

    /// Process a parsed FLV audio tag.
    ///
    /// `write` must be an active borrow of the current `NetStream`. `slice`
    /// must reference the underlying backing buffer.
    fn flv_audio_tag(
        self,
        slice: &Slice,
        audio_data: FlvAudioData<'_>,
    ) -> Result<(), NetstreamError> {
        let is_aac_sequence_header =
            matches!(audio_data.data, FlvAudioDataType::AacSequenceHeader(_));
        let data = match audio_data.data {
            FlvAudioDataType::Raw(data)
            | FlvAudioDataType::AacSequenceHeader(data)
            | FlvAudioDataType::AacRaw(data) => slice.to_subslice(data),
        };
        let source = self.source();
        // Timffle: `NetStream.audioCodec` is the FLV sound format id.
        source.audio_codec.set(audio_data.format as u32);
        let audio_stream = &mut *source.audio_stream.borrow_mut();
        let (substream, sound_stream_info) = match audio_stream {
            Some(audio_stream) => audio_stream,
            audio_stream => {
                // None
                let substream = Substream::new(slice.buffer().clone());
                let swf_format = SoundFormat {
                    compression: match audio_data.format {
                        FlvSoundFormat::LinearPCMPlatformEndian => {
                            AudioCompression::UncompressedUnknownEndian
                        }
                        FlvSoundFormat::Adpcm => AudioCompression::Adpcm,
                        FlvSoundFormat::MP3 => AudioCompression::Mp3,
                        FlvSoundFormat::LinearPCMLittleEndian => AudioCompression::Uncompressed,
                        FlvSoundFormat::Nellymoser16kHz => AudioCompression::Nellymoser16Khz,
                        FlvSoundFormat::Nellymoser8kHz => AudioCompression::Nellymoser8Khz,
                        FlvSoundFormat::Nellymoser => AudioCompression::Nellymoser,
                        FlvSoundFormat::G711ALawPCM => AudioCompression::G711ALawPCM,
                        FlvSoundFormat::G711MuLawPCM => AudioCompression::G711MuLawPCM,
                        FlvSoundFormat::Aac => AudioCompression::Aac,
                        FlvSoundFormat::Speex => AudioCompression::Speex,
                        FlvSoundFormat::MP38kHz => AudioCompression::Mp3,
                        FlvSoundFormat::DeviceSpecific => return Err(NetstreamError::UnknownCodec),
                    },
                    sample_rate: match (audio_data.format, audio_data.rate) {
                        (FlvSoundFormat::G711ALawPCM, _)
                        | (FlvSoundFormat::G711MuLawPCM, _)
                        | (FlvSoundFormat::MP38kHz, _) => 8_000,
                        (_, FlvSoundRate::R5_500) => 5_500,
                        (_, FlvSoundRate::R11_000) => 11_000,
                        (_, FlvSoundRate::R22_000) => 22_000,
                        (_, FlvSoundRate::R44_000) => 44_000,
                    },
                    is_stereo: match audio_data.sound_type {
                        FlvSoundType::Mono => false,
                        FlvSoundType::Stereo => true,
                    },
                    is_16_bit: match audio_data.size {
                        FlvSoundSize::Bits8 => false,
                        FlvSoundSize::Bits16 => true,
                    },
                };

                let sound_stream_head = SoundStreamInfo {
                    wrapping: SoundStreamWrapping::Unwrapped,
                    stream_format: swf_format,
                    num_samples_per_block: 0,
                    latency_seek: 0,
                    extra_data: None,
                };

                audio_stream.insert((substream, sound_stream_head))
            }
        };

        // An AAC sequence header carries the decoder configuration
        // (`AudioSpecificConfig`), not playable audio. We demux it out-of-band
        // into the stream info instead of appending it to the audio substream,
        // so the decoder only ever sees raw AAC access units and never has to
        // deal with FLV's packet framing.
        //
        // The decoder reads this config once, when it's constructed. A re-sent
        // header just refreshes the field (a no-op for the identical configs FLV
        // actually uses); a genuine mid-stream config *change* is not supported,
        // but doesn't occur in practice.
        if is_aac_sequence_header {
            sound_stream_info.extra_data = Some((*data.data()).into());
            return Ok(());
        }

        if substream
            .last_chunk()
            .map(|lc| lc.end() > data.start())
            .unwrap_or(false)
        {
            // Reject repeats of existing tags.
            // We need to do this because of lookahead - we will
            // encounter the same audio tag multiple times as we buffer
            // a few ahead for the audio backend.
            // This assumes that tags are processed in-order - which
            // should always be the case. Seeks should cancel the audio
            // stream before processing new tags.
            return Ok(());
        }

        Ok(substream.append(data)?)
    }

    /// Determine if the given sound is currently playing.
    fn sound_currently_playing(
        context: &mut UpdateContext<'gc>,
        sound: Option<SoundInstanceHandle>,
    ) -> bool {
        sound
            .map(|si| context.audio.is_sound_playing(si))
            .unwrap_or(false)
    }

    /// Clean up after a sound instance that has finished playing.
    ///
    /// Generally speaking, streams are only to be used once. However, the
    /// audio backend will only retain information about sounds that are
    /// currently playing, so if the sound has finished since the last tick, we
    /// need to restart it.
    ///
    /// Intended to be called at the start of tag processing, before any new
    /// audio data has been streamed.
    fn cleanup_sound_stream(self, context: &mut UpdateContext<'gc>) {
        let source = self.source();
        if !Self::sound_currently_playing(context, source.sound_instance.get()) {
            source.audio_stream.replace(None);
            source.sound_instance.set(None);
        }
    }

    /// Ensure that if we have queued up audio into a sound stream, that said
    /// stream gets sent over to the audio backend.
    ///
    /// Intended to be called at the end of tag processing. Audio processing
    /// should occur only after a minimum number of tags have been processed to
    /// avoid audio underruns.
    fn commit_sound_stream(self, context: &mut UpdateContext<'gc>) -> Result<(), NetstreamError> {
        let source = self.source();
        if !Self::sound_currently_playing(context, source.sound_instance.get())
            && let Some((substream, sound_stream_head)) = &mut *source.audio_stream.borrow_mut()
        {
            let sound_instance = if let Some(mc) = self.0.attached_to.get() {
                context.audio_manager.start_substream(
                    context.audio,
                    substream.clone(),
                    mc,
                    sound_stream_head,
                )?
            } else {
                context
                    .audio
                    .start_substream(substream.clone(), sound_stream_head)?
            };
            source.sound_instance.set(Some(sound_instance));
            // Timffle: `NetStream.soundTransform` applies to every sound the
            // stream starts.
            self.apply_sound_transform(context, sound_instance);
        }

        Ok(())
    }

    /// Attempt to sniff the stream type from data in the buffer.
    ///
    /// Returns true if the stream type was successfully sniffed. False
    /// indicates that there is either not enough data in the buffer, or the
    /// data is of an unrecognized format. This should be used as a signal to
    /// stop stream processing until new data has been retrieved.
    pub fn sniff_stream_type(self, context: &mut UpdateContext<'gc>) -> bool {
        let source = self.source();
        let slice = source.buffer.borrow().to_full_slice();
        let buffer = slice.data();

        // A nonzero preload offset indicates that we tried and failed to
        // sniff the container format, so in that case do not process the
        // stream anymore.
        if source.preload_offset.get() > 0 {
            return false;
        }

        match buffer.get(0..3) {
            Some([0x46, 0x4C, 0x56]) => {
                let mut reader = FlvReader::from_parts(&buffer, source.offset.get());
                match FlvHeader::parse(&mut reader) {
                    Ok(header) => {
                        source.offset.set(reader.into_parts().1);
                        source.preload_offset.set(source.offset.get());
                        source.stream_type.replace(Some(NetStreamType::Flv {
                            header,
                            video_stream: None,
                            frame_id: 0,
                        }));
                        true
                    }
                    Err(FlvError::EndOfData) => false,
                    Err(e) => {
                        //TODO: Fire an error event to AS & stop playing too
                        tracing::error!("FLV header parsing failed: {}", e);
                        source.preload_offset.set(3);
                        false
                    }
                }
            }
            Some(magic) => {
                //Unrecognized signature
                //TODO: Fire an error event to AS & stop playing too
                tracing::error!("Unrecognized file signature: {:?}", magic);
                source.preload_offset.set(3);
                if let Some(url) = &*self.0.url.borrow() {
                    if url.is_empty() {
                        return false;
                    }
                    let parsed_url = match context.navigator.resolve_url(url) {
                        Ok(parsed_url) => parsed_url,
                        Err(e) => {
                            tracing::error!(
                                "Could not parse URL because of {}, the corrupt URL was: {}",
                                e,
                                url
                            );
                            return false;
                        }
                    };
                    context.ui.display_unsupported_video(parsed_url);
                }
                false
            }
            None => false, //Data not yet loaded
        }
    }

    /// Process a parsed FLV video tag.
    ///
    /// `write` must be an active borrow of the current `NetStream`. `slice`
    /// must reference the underlying backing buffer.
    ///
    /// `tag_needs_preloading` indicates that this video tag has not been
    /// encountered before.
    fn flv_video_tag(
        self,
        context: &mut UpdateContext<'gc>,
        slice: &Slice,
        video_data: FlvVideoData<'_>,
        tag_needs_preloading: bool,
    ) {
        let source = self.source();
        let (video_handle, frame_id) = match *source.stream_type.borrow() {
            Some(NetStreamType::Flv {
                video_stream,
                frame_id,
                ..
            }) => (video_stream, frame_id),
            _ => unreachable!(),
        };
        let codec = VideoCodec::from_u8(video_data.codec_id as u8);
        // Timffle: `NetStream.videoCodec` is the FLV codec id.
        source.video_codec.set(video_data.codec_id as u32);
        let buffer = slice.data();

        match (video_handle, codec, video_data.data) {
            (
                maybe_video_handle,
                Some(codec),
                FlvVideoPacket::Data(mut data)
                | FlvVideoPacket::Vp6Data {
                    hadjust: _,
                    vadjust: _,
                    mut data,
                },
            ) => {
                //Some movies don't actually have metadata, so let's register a
                //dummy stream just in case. All the actual data in the registration
                //is lies, of course.
                let video_handle = match maybe_video_handle {
                    Some(stream) => stream,
                    None => {
                        match context.video.register_video_stream(
                            1,
                            (8, 8),
                            codec,
                            VideoDeblocking::UseVideoPacketValue,
                        ) {
                            Ok(new_handle) => {
                                match &mut *source.stream_type.borrow_mut() {
                                    Some(NetStreamType::Flv { video_stream, .. }) => {
                                        *video_stream = Some(new_handle)
                                    }
                                    _ => unreachable!(),
                                }

                                new_handle
                            }
                            Err(e) => {
                                tracing::error!(
                                    "Got error when registering FLV video stream: {}",
                                    e
                                );
                                return; //TODO: This originally breaks and halts tag processing
                            }
                        }
                    }
                };

                if codec == VideoCodec::ScreenVideo || codec == VideoCodec::ScreenVideoV2 {
                    // ScreenVideo streams consider the FLV
                    // video data byte to be integral to their
                    // own bitstream.
                    let offset = data.as_ptr() as usize - buffer.as_ptr() as usize;
                    let len = data.len();
                    data = buffer
                        .get(offset - 1..offset + len)
                        .expect("screenvideo flvs have video data bytes");
                }

                // NOTE: Currently, no implementation of the decoder backend actually requires
                if tag_needs_preloading {
                    let encoded_frame = EncodedFrame {
                        codec,
                        data, //TODO: ScreenVideo's decoder wants the FLV header bytes
                        frame_id,
                    };

                    if let Err(e) = context
                        .video
                        .preload_video_stream_frame(video_handle, encoded_frame)
                    {
                        tracing::error!("Preloading video frame {} failed: {}", frame_id, e);
                    }
                }

                let encoded_frame = EncodedFrame {
                    codec,
                    data, //TODO: ScreenVideo's decoder wants the FLV header bytes
                    frame_id,
                };

                match context.video.decode_video_stream_frame(
                    video_handle,
                    encoded_frame,
                    context.renderer,
                ) {
                    Ok(bitmap_info) => {
                        self.store_decoded_frame(bitmap_info);
                        if let Some(mc) = self.0.attached_to.get() {
                            mc.invalidate_cached_bitmap();
                            *context.needs_render = true;
                        }
                    }
                    Err(e) => {
                        // Timffle: counted as `NetStreamInfo.droppedFrames`.
                        source.dropped_frames.set(source.dropped_frames.get() + 1);
                        tracing::error!("Decoding video frame {} failed: {}", frame_id, e);
                    }
                }
            }
            (_, _, FlvVideoPacket::CommandFrame(_command)) => {
                tracing::warn!("Stub: FLV command frame processing")
            }
            (Some(video_handle), _, FlvVideoPacket::AvcSequenceHeader(data)) => {
                match context
                    .video
                    .configure_video_stream_decoder(video_handle, data)
                {
                    Ok(_) => {}
                    Err(e) => {
                        tracing::error!("Configuring video decoder {} failed: {}", frame_id, e);
                    }
                }
            }
            (
                Some(video_handle),
                Some(codec),
                FlvVideoPacket::AvcNalu {
                    composition_time_offset: _,
                    data,
                },
            ) => {
                let encoded_frame = EncodedFrame {
                    codec,
                    data,
                    frame_id,
                };

                match context.video.decode_video_stream_frame(
                    video_handle,
                    encoded_frame,
                    context.renderer,
                ) {
                    Ok(bitmap_info) => {
                        self.store_decoded_frame(bitmap_info);
                        if let Some(mc) = self.0.attached_to.get() {
                            mc.invalidate_cached_bitmap();
                            *context.needs_render = true;
                        }
                    }
                    Err(e) => {
                        // Timffle: counted as `NetStreamInfo.droppedFrames`.
                        source.dropped_frames.set(source.dropped_frames.get() + 1);
                        tracing::error!("Decoding video frame {} failed: {}", frame_id, e);
                    }
                }
            }
            (_, _, FlvVideoPacket::AvcEndOfSequence) => {
                tracing::warn!("Stub: FLV AVC/H.264 End of Sequence processing")
            }
            (_, None, _) => {
                tracing::error!(
                    "FLV video tag has invalid codec id {}",
                    video_data.codec_id as u8
                )
            }
            (None, _, _) => {
                tracing::error!("No video handle")
            }
        }

        match &mut *source.stream_type.borrow_mut() {
            Some(NetStreamType::Flv { frame_id, .. }) => *frame_id += 1,
            _ => unreachable!(),
        };
    }

    /// Process a parsed FLV script tag.
    ///
    /// This function attempts to borrow the current `NetStream`, you must drop
    /// any existing borrows and pick them back up when you're done.
    ///
    /// `tag_needs_preloading` indicates that this script tag has not been
    /// encountered before.
    fn flv_script_tag(
        self,
        context: &mut UpdateContext<'gc>,
        script_data: FlvScriptData<'_>,
        tag_needs_preloading: bool,
    ) {
        let source = self.source();
        let has_stream_already = match &*source.stream_type.borrow() {
            Some(NetStreamType::Flv { video_stream, .. }) => video_stream.is_some(),
            _ => unreachable!(),
        };

        let mut width = None;
        let mut height = None;
        let mut video_codec_id = None;
        let mut frame_rate = None;
        let mut duration = None;

        for var in script_data.0 {
            if var.name == b"onMetaData" && !has_stream_already {
                match var.data.clone() {
                    FlvValue::Object(subvars) | FlvValue::EcmaArray(subvars) => {
                        for subvar in subvars {
                            match (subvar.name, subvar.data) {
                                (b"width", FlvValue::Number(val)) => width = Some(val),
                                (b"height", FlvValue::Number(val)) => height = Some(val),
                                (b"videocodecid", FlvValue::Number(val)) => {
                                    video_codec_id = Some(val)
                                }
                                (b"framerate", FlvValue::Number(val)) => frame_rate = Some(val),
                                (b"duration", FlvValue::Number(val)) => duration = Some(val),
                                _ => {}
                            }
                        }
                    }
                    _ => tracing::error!("Invalid FLV metadata tag!"),
                }
                // Timffle: `Video.videoWidth`/`videoHeight` already know the
                // size inside the `onMetaData` callback (Flash does).
                if let (Some(width), Some(height)) = (width, height) {
                    self.0
                        .metadata_size
                        .set(Some((width as u16, height as u16)));
                }
            }
            let avm_object = self.0.avm_object.get();
            // This is necessary because the script callback functions can call back into
            // these methods, (e.g. NetStream::play), so we need to avoid holding a borrow
            // while the script data is being handled.
            let _ = self.handle_script_data(avm_object, context, var.name, var.data);
            // Any errors while trying to lookup or call AVM2 properties are silently swallowed.
        }

        if tag_needs_preloading
            && let (
                Some(width),
                Some(height),
                Some(video_codec_id),
                Some(frame_rate),
                Some(duration),
            ) = (width, height, video_codec_id, frame_rate, duration)
        {
            let num_frames = frame_rate * duration;
            if let Some(video_codec) = VideoCodec::from_u8(video_codec_id as u8) {
                match context.video.register_video_stream(
                    num_frames as u32,
                    (width as u16, height as u16),
                    video_codec,
                    VideoDeblocking::UseVideoPacketValue,
                ) {
                    Ok(stream_handle) => match &mut *source.stream_type.borrow_mut() {
                        Some(NetStreamType::Flv { video_stream, .. }) => {
                            *video_stream = Some(stream_handle)
                        }
                        _ => unreachable!(),
                    },
                    Err(e) => {
                        tracing::error!("Got error when registering FLV video stream: {}", e)
                    }
                }
            } else {
                tracing::error!("FLV video stream has invalid codec ID {}", video_codec_id);
            }
        }
    }

    /// Process stream data.
    ///
    /// `dt` is the elapsed time since the last tick.
    pub fn tick(self, context: &mut UpdateContext<'gc>, dt: FloatDuration) {
        let source = self.source();
        let seek_offset = source.queued_seek_time.take();
        if let Some(offset) = seek_offset {
            self.execute_seek(context, offset);
        }

        // Paused streams deactivate themselves after seek processing.
        if !self.0.playing.get() {
            StreamManager::deactivate(context, self);
            return;
        }

        // Ensure the container stream type is known before continuing.
        if source.stream_type.borrow().is_none() && !self.sniff_stream_type(context) {
            return;
        }

        // Timffle: `NetStreamInfo` download / playback rates, sampled once a
        // second of player time.
        self.sample_rates(dt.as_millis());

        // Timffle: wait for `bufferTime` seconds of data (or the end of the
        // download) before playing; `NetStream.Buffer.Full` marks the start.
        if source.buffering.get() {
            let complete = source.expected_length.get().is_none();
            if !complete && self.buffer_length() < self.buffer_time() {
                return;
            }
            source.buffering.set(false);
            self.trigger_status_event(
                context,
                [("code", "NetStream.Buffer.Full"), ("level", "status")],
            );
            if !Gc::ptr_eq(source, self.source()) || !self.0.playing.get() {
                return;
            }
        }

        // Timffle: after `appendBytesAction(RESET_SEEK)` time restarts at the
        // first tag's timestamp.
        if source.resync_time.get() {
            let slice = source.buffer.borrow().to_full_slice();
            let buffer = slice.data();
            let mut reader = FlvReader::from_parts(&buffer, source.offset.get());
            match FlvTag::parse(&mut reader) {
                Ok(tag) => {
                    source.stream_time.set(tag.timestamp as f64);
                    source.resync_time.set(false);
                }
                Err(_) => return,
            }
        }

        self.cleanup_sound_stream(context);
        let slice = source.buffer.borrow().to_full_slice();
        let buffer = slice.data();

        let max_time = source.stream_time.get() + dt.as_millis();
        let mut buffer_underrun = false;
        let mut error = false;
        let mut max_lookahead_audio_tags = 5;
        let mut is_lookahead_tag = false;

        // At this point we should know our stream type.
        if matches!(
            &*source.stream_type.borrow(),
            Some(NetStreamType::Flv { .. })
        ) {
            let mut reader = FlvReader::from_parts(&buffer, source.offset.get());

            loop {
                let tag = FlvTag::parse(&mut reader);
                if let Err(e) = tag {
                    // `is_lookahead_tag` gets set once we start reading tags
                    // after the end & won't ever be set back. We don't want
                    // error states or playback ending to trip until we run
                    // those tags "for realsies"
                    if !is_lookahead_tag && matches!(e, FlvError::EndOfData) {
                        buffer_underrun = true;
                    } else if !is_lookahead_tag {
                        //Corrupt tag or out of data
                        tracing::error!("FLV tag parsing failed: {}", e);
                        error = true;
                    }

                    break;
                }

                let tag = tag.expect("valid tag");
                is_lookahead_tag = tag.timestamp as f64 >= max_time; //FLV timestamps are also ms
                if is_lookahead_tag && max_lookahead_audio_tags == 0 {
                    break;
                }

                let tag_needs_preloading = reader.stream_position().expect("valid position")
                    as usize
                    >= source.preload_offset.get();

                match tag.data {
                    FlvTagData::Audio(audio_data) => {
                        if is_lookahead_tag {
                            max_lookahead_audio_tags -= 1;
                        }

                        if let Err(e) = self.flv_audio_tag(&slice, audio_data) {
                            //TODO: Fire an error event at AS.
                            tracing::error!("Error committing sound stream: {}", e);
                        }
                    }
                    FlvTagData::Video(video_data) if !is_lookahead_tag => {
                        self.flv_video_tag(context, &slice, video_data, tag_needs_preloading)
                    }
                    FlvTagData::Script(script_data) if !is_lookahead_tag => {
                        self.flv_script_tag(context, script_data, tag_needs_preloading);
                    }
                    FlvTagData::Invalid(e) => {
                        tracing::error!("FLV data parsing failed: {}", e)
                    }
                    FlvTagData::Video(_) | FlvTagData::Script(_) => {}
                }

                if !is_lookahead_tag {
                    let offset = reader
                        .stream_position()
                        .expect("FLV reader stream position")
                        as usize;
                    // Timffle: bytes played, for `playbackBytesPerSecond`.
                    source.rate_processed.set(
                        source.rate_processed.get() + offset.saturating_sub(source.offset.get()),
                    );
                    source.offset.set(offset);
                    source
                        .preload_offset
                        .set(max(source.offset.get(), source.preload_offset.get()));
                }
            }
        }

        source.stream_time.set(max_time);
        if let Err(e) = self.commit_sound_stream(context) {
            //TODO: Fire an error event at AS.
            tracing::error!("Error committing sound stream: {}", e);
        }

        // Timffle: `currentFPS` = frames decoded over the last second of stream time.
        let (window_start, frames) = source.fps_window.get();
        if max_time - window_start >= 1000.0 {
            source
                .current_fps
                .set(frames as f64 * 1000.0 / (max_time - window_start));
            source.fps_window.set((max_time, 0));
        }

        if buffer_underrun {
            let is_end_of_video = source.expected_length.get().is_none();

            self.trigger_status_event(
                context,
                [("code", "NetStream.Buffer.Flush"), ("level", "status")],
            );

            if is_end_of_video {
                self.trigger_status_event(
                    context,
                    [("code", "NetStream.Play.Stop"), ("level", "status")],
                );
                self.call_play_complete(context);
            }

            // Check if AVM code in the event handler invoked stream.play() and replaced the source.
            if Gc::ptr_eq(source, self.source()) {
                self.trigger_status_event(
                    context,
                    [("code", "NetStream.Buffer.Empty"), ("level", "status")],
                );

                if is_end_of_video {
                    self.pause(context, false);
                } else {
                    // Timffle: wait for `bufferTime` seconds again before
                    // resuming; Flash sends `Buffer.Full` once more then.
                    source.buffering.set(true);
                }
            }
        }

        if error {
            //TODO: Fire an error event at AS.
            self.pause(context, false);
        }
    }

    // Timffle: the members below back the `flash.net.NetStream` API.

    /// Timffle: seconds of data buffered ahead of the playhead
    /// (`NetStream.bufferLength`).
    pub fn buffer_length(self) -> f64 {
        let source = self.source();
        let stats = self.buffer_stats();
        match stats.end_ts {
            Some(end) => ((end as f64 - source.stream_time.get()) / 1000.0).max(0.0),
            None => 0.0,
        }
    }

    /// Timffle: seconds of already played data kept for `inBufferSeek`
    /// (`NetStream.backBufferLength`): 0 unless `inBufferSeek` is set, else
    /// the data behind the playhead, at most `backBufferTime`.
    pub fn back_buffer_length(self) -> f64 {
        if !self.0.in_buffer_seek.get() {
            return 0.0;
        }
        let source = self.source();
        let stats = self.buffer_stats();
        match stats.start_ts {
            Some(start) => ((source.stream_time.get() - start as f64) / 1000.0)
                .max(0.0)
                .min(self.0.back_buffer_time.get().max(0.0)),
            None => 0.0,
        }
    }

    pub fn in_buffer_seek(self) -> bool {
        self.0.in_buffer_seek.get()
    }

    pub fn set_in_buffer_seek(self, value: bool) {
        self.0.in_buffer_seek.set(value);
    }

    pub fn back_buffer_time(self) -> f64 {
        self.0.back_buffer_time.get()
    }

    pub fn set_back_buffer_time(self, value: f64) {
        self.0.back_buffer_time.set(value);
    }

    pub fn audio_codec(self) -> u32 {
        self.source().audio_codec.get()
    }

    pub fn video_codec(self) -> u32 {
        self.source().video_codec.get()
    }

    pub fn decoded_frames(self) -> u32 {
        self.source().decoded_frames.get()
    }

    pub fn dropped_frames(self) -> u32 {
        self.source().dropped_frames.get()
    }

    pub fn current_fps(self) -> f64 {
        self.source().current_fps.get()
    }

    pub fn url(self) -> Option<String> {
        self.0.url.borrow().clone()
    }

    pub fn metadata(self) -> Option<Avm2Object<'gc>> {
        self.0.metadata.get()
    }

    pub fn xmp_data(self) -> Option<Avm2Object<'gc>> {
        self.0.xmp_data.get()
    }

    /// Timffle: (current download B/s, max download B/s, playback B/s).
    pub fn rates(self) -> (f64, f64, f64) {
        let source = self.source();
        (
            source.current_bps.get(),
            source.max_bps.get(),
            source.playback_bps.get(),
        )
    }

    /// Timffle: see [`Self::rates`]; called once per tick with the elapsed ms.
    fn sample_rates(self, dt_ms: f64) {
        let source = self.source();
        let elapsed = source.rate_elapsed.get() + dt_ms;
        if elapsed < 1000.0 {
            source.rate_elapsed.set(elapsed);
            return;
        }
        let loaded = source.buffer.borrow().len();
        let seconds = elapsed / 1000.0;
        let current = loaded.saturating_sub(source.rate_bytes_last.get()) as f64 / seconds;
        source.current_bps.set(current);
        source.max_bps.set(source.max_bps.get().max(current));
        source
            .playback_bps
            .set(source.rate_processed.get() as f64 / seconds);
        source.rate_bytes_last.set(loaded);
        source.rate_processed.set(0);
        source.rate_elapsed.set(0.0);
    }

    /// Timffle: scan the FLV tags in the buffer (see [`BufferStats`]).
    pub fn buffer_stats(self) -> BufferStats {
        let source = self.source();
        let mut stats = BufferStats::default();
        if !matches!(
            &*source.stream_type.borrow(),
            Some(NetStreamType::Flv { .. })
        ) {
            return stats;
        }
        let slice = source.buffer.borrow().to_full_slice();
        let buffer = slice.data();
        // The FLV header's DataOffset field says where the first tag starts.
        let data_offset = buffer
            .get(5..9)
            .map(|b| u32::from_be_bytes([b[0], b[1], b[2], b[3]]) as usize)
            .filter(|&o| o >= 9)
            .unwrap_or(9);
        let play_offset = source.offset.get();
        let mut reader = FlvReader::from_parts(&buffer, data_offset);
        loop {
            let position = reader.stream_position().unwrap_or(0) as usize;
            let Ok(tag) = FlvTag::parse(&mut reader) else {
                break;
            };
            let ahead = position >= play_offset;
            let end = reader.stream_position().unwrap_or(0) as usize;
            // 4 bytes previous tag size + 11 bytes tag header.
            let payload = end.saturating_sub(position).saturating_sub(15);
            if stats.start_ts.is_none() {
                stats.start_ts = Some(tag.timestamp);
            }
            stats.end_ts = Some(stats.end_ts.map_or(tag.timestamp, |t| t.max(tag.timestamp)));
            let (total, ahead_bytes, ahead_end) = match tag.data {
                FlvTagData::Audio(_) => (
                    &mut stats.audio_bytes,
                    &mut stats.audio_ahead_bytes,
                    &mut stats.audio_end,
                ),
                FlvTagData::Video(_) => (
                    &mut stats.video_bytes,
                    &mut stats.video_ahead_bytes,
                    &mut stats.video_end,
                ),
                FlvTagData::Script(_) => (
                    &mut stats.data_bytes,
                    &mut stats.data_ahead_bytes,
                    &mut stats.data_end,
                ),
                FlvTagData::Invalid(_) => continue,
            };
            *total += payload;
            if ahead {
                *ahead_bytes += payload;
                *ahead_end = Some(ahead_end.map_or(tag.timestamp, |t| t.max(tag.timestamp)));
            }
        }
        stats
    }

    pub fn sound_transform(self) -> SoundTransform {
        self.0.sound_transform.get()
    }

    /// Timffle: `NetStream.soundTransform` setter: stored and applied to the
    /// sound currently playing.
    pub fn set_sound_transform(self, context: &mut UpdateContext<'gc>, transform: SoundTransform) {
        self.0.sound_transform.set(transform);
        if let Some(instance) = self.source().sound_instance.get() {
            self.apply_sound_transform(context, instance);
        }
    }

    fn apply_sound_transform(
        self,
        context: &mut UpdateContext<'gc>,
        instance: SoundInstanceHandle,
    ) {
        let transform = self.0.sound_transform.get();
        if self.0.attached_to.get().is_some() {
            // Sounds routed through a MovieClip (AVM1 `attachAudio`) mix with
            // the clip's own transform in the audio manager.
            context
                .audio_manager
                .set_local_sound_transform(instance, transform);
        } else {
            context
                .audio
                .set_sound_transform(instance, transform.into());
        }
    }

    /// Timffle: `NetStream.close()`: stop playing, drop the buffer and the
    /// sound, time back to 0. The last frame stays on screen (Flash's
    /// `close()` does not blank the `Video`; `dispose()` does).
    pub fn close(self, context: &mut UpdateContext<'gc>) {
        self.pause(context, false);
        // Timffle: a stream stays in Data Generation Mode after `close()`: Flash
        // Player 32 still takes `appendBytes()` there (measured,
        // tests/tests/swfs/avm2/netstream_local_events).
        let data_generation = self.source().data_generation.get();
        self.reset_buffer(context);
        self.source().data_generation.set(data_generation);
        self.0.url.replace(None);
        StreamManager::deactivate(context, self);
    }

    /// Timffle: `NetStream.dispose()`: `close()` plus the displayed frame is
    /// dropped.
    pub fn dispose(self, context: &mut UpdateContext<'gc>) {
        self.close(context);
        self.0.last_decoded_bitmap.replace(None);
        self.0
            .decoded_frame_serial
            .set(self.0.decoded_frame_serial.get().wrapping_add(1));
        self.0.metadata_size.set(None);
        if let Some(mc) = self.0.attached_to.get() {
            mc.invalidate_cached_bitmap();
        }
        *context.needs_render = true;
    }

    pub fn is_data_generation(self) -> bool {
        self.source().data_generation.get()
    }

    /// Timffle: `NetStream.appendBytes()` in Data Generation Mode: the bytes
    /// join the buffer as if downloaded; false outside that mode.
    pub fn append_bytes(self, context: &mut UpdateContext<'gc>, data: &[u8]) -> bool {
        let source = self.source();
        if !source.data_generation.get() {
            return false;
        }
        let mut owned = data.to_vec();
        source.buffer.borrow_mut().append(&mut owned);
        if source.expected_length.get().is_some() {
            source
                .expected_length
                .set(Some(source.buffer.borrow().len()));
        }
        StreamManager::activate(context, self);
        true
    }

    /// Timffle: `NetStream.appendBytesAction()`. `RESET_BEGIN` empties the
    /// buffer and expects a new file (header) next; `RESET_SEEK` empties it
    /// and expects tags from a seekable position, time continuing from the
    /// first tag's timestamp; `END_SEQUENCE` marks the end of the data so the
    /// stream can finish with `NetStream.Play.Stop`.
    pub fn append_bytes_action(self, context: &mut UpdateContext<'gc>, action: &str) -> bool {
        let source = self.source();
        if !source.data_generation.get() {
            return false;
        }
        match action {
            "resetBegin" => {
                self.reset_buffer(context);
                let source = self.source();
                source.data_generation.set(true);
                source.expected_length.set(Some(0));
            }
            "resetSeek" => {
                let stream_type = source.stream_type.borrow().clone();
                let stream_time = source.stream_time.get();
                self.reset_buffer(context);
                let source = self.source();
                source.data_generation.set(true);
                source.expected_length.set(Some(0));
                source.stream_time.set(stream_time);
                if let Some(NetStreamType::Flv {
                    header,
                    video_stream,
                    frame_id,
                }) = stream_type
                {
                    source.stream_type.replace(Some(NetStreamType::Flv {
                        header,
                        video_stream,
                        frame_id,
                    }));
                    source.resync_time.set(true);
                }
            }
            "endSequence" => {
                source.expected_length.set(None);
                StreamManager::activate(context, self);
            }
            _ => return false,
        }
        true
    }

    /// Timffle: `NetStream.step(frames)`: move `frames` video frames forward
    /// (positive) or back (negative) inside the buffer and show that frame.
    /// Needs `inBufferSeek`; returns false when the target frame is not in the
    /// buffer (Flash then does nothing, no `NetStream.Step.Notify`).
    pub fn step(self, context: &mut UpdateContext<'gc>, frames: i32) -> bool {
        if !self.0.in_buffer_seek.get() || frames == 0 {
            return false;
        }
        let source = self.source();
        if !matches!(
            &*source.stream_type.borrow(),
            Some(NetStreamType::Flv { .. })
        ) {
            return false;
        }
        self.pause(context, false);
        let slice = source.buffer.borrow().to_full_slice();
        let buffer = slice.data();

        // Find the target video tag.
        let mut reader = FlvReader::from_parts(&buffer, source.offset.get());
        let mut remaining = frames.unsigned_abs();
        let target_pos;
        if frames > 0 {
            loop {
                let pos = reader.stream_position().unwrap_or(0);
                let Ok(tag) = FlvTag::parse(&mut reader) else {
                    return false;
                };
                if matches!(tag.data, FlvTagData::Video(_)) {
                    remaining -= 1;
                    if remaining == 0 {
                        target_pos = pos;
                        break;
                    }
                }
            }
        } else {
            loop {
                if FlvTag::skip_back(&mut reader).is_err() {
                    return false;
                }
                let pos = reader.stream_position().unwrap_or(0);
                let Ok(tag) = FlvTag::parse(&mut reader) else {
                    return false;
                };
                reader.seek(SeekFrom::Start(pos)).ok();
                if matches!(tag.data, FlvTagData::Video(_)) {
                    remaining -= 1;
                    if remaining == 0 {
                        target_pos = pos;
                        break;
                    }
                }
            }
        }

        // Decoding starts at the keyframe at or before the target when going
        // back; going forward the decoder continues from where it is.
        let mut decode_from = source.offset.get() as u64;
        if frames < 0 {
            let mut reader = FlvReader::from_parts(&buffer, target_pos as usize);
            loop {
                let pos = reader.stream_position().unwrap_or(0);
                match FlvTag::parse(&mut reader) {
                    Ok(FlvTag {
                        data:
                            FlvTagData::Video(FlvVideoData {
                                frame_type: FlvFrameType::Keyframe,
                                ..
                            }),
                        ..
                    }) => {
                        decode_from = pos;
                        break;
                    }
                    Ok(_) => {}
                    Err(_) => return false,
                }
                reader.seek(SeekFrom::Start(pos)).ok();
                if FlvTag::skip_back(&mut reader).is_err() {
                    decode_from = pos;
                    break;
                }
            }
        }

        let mut reader = FlvReader::from_parts(&buffer, decode_from as usize);
        let mut target_time = source.stream_time.get();
        loop {
            let pos = reader.stream_position().unwrap_or(0);
            let Ok(tag) = FlvTag::parse(&mut reader) else {
                break;
            };
            let end = reader.stream_position().unwrap_or(0) as usize;
            let tag_needs_preloading = end >= source.preload_offset.get();
            match tag.data {
                FlvTagData::Video(video_data) => {
                    self.flv_video_tag(context, &slice, video_data, tag_needs_preloading);
                }
                FlvTagData::Script(script_data) if tag_needs_preloading => {
                    self.flv_script_tag(context, script_data, true);
                }
                _ => {}
            }
            if pos == target_pos {
                target_time = tag.timestamp as f64;
                source.offset.set(end);
                source
                    .preload_offset
                    .set(max(end, source.preload_offset.get()));
                break;
            }
        }
        source.stream_time.set(target_time);
        source.fps_window.set((target_time, 0));
        true
    }

    pub fn last_decoded_bitmap(self) -> Option<BitmapInfo> {
        self.0.last_decoded_bitmap.borrow().clone()
    }

    /// Timffle: see `NetStreamData::decoded_frame_serial`.
    pub fn decoded_frame_serial(self) -> u64 {
        self.0.decoded_frame_serial.get()
    }

    /// Timffle: see `NetStreamData::metadata_size`.
    pub fn metadata_size(self) -> Option<(u16, u16)> {
        self.0.metadata_size.get()
    }

    fn store_decoded_frame(self, bitmap_info: BitmapInfo) {
        self.0.last_decoded_bitmap.replace(Some(bitmap_info));
        self.0
            .decoded_frame_serial
            .set(self.0.decoded_frame_serial.get().wrapping_add(1));
        // Timffle: `decodedFrames` and the `currentFPS` window.
        let source = self.source();
        source
            .decoded_frames
            .set(source.decoded_frames.get().wrapping_add(1));
        let (start, n) = source.fps_window.get();
        source.fps_window.set((start, n + 1));
    }

    /// Trigger a status event on the stream.
    pub fn trigger_status_event<'a>(
        self,
        context: &mut UpdateContext<'gc>,
        values: impl IntoIterator<Item = (&'a str, &'a str)>,
    ) {
        let object = self.0.avm_object.get();
        match object {
            Some(NetStreamKind::Avm1(object)) => {
                let root = context.stage.root_clip().expect("root");
                let mut activation = Avm1Activation::from_nothing(
                    context,
                    Avm1ActivationIdentifier::root("[NetStream Status Event]"),
                    root,
                );
                let object_proto = activation.prototypes().object;
                let info_object = Avm1Object::new(&activation.context.strings, Some(object_proto));

                for (key, value) in values {
                    let key = AvmString::new_utf8(activation.gc(), key);
                    let value = AvmString::new_utf8(activation.gc(), value);

                    info_object
                        .set(key, value, &mut activation)
                        .expect("valid set");
                }

                if let Err(e) = object.call_method(
                    istr!("onStatus"),
                    &[info_object.into()],
                    &mut activation,
                    Avm1ExecutionReason::Special,
                ) {
                    tracing::error!(
                        "Got error when dispatching AVM1 onStatus event from NetStream: {}",
                        e
                    );
                }
            }
            Some(NetStreamKind::Avm2(object)) => {
                let domain = context.avm2.stage_domain();
                let mut activation = Avm2Activation::from_domain(context, domain);
                let net_status_event = Avm2EventObject::net_status_event(&mut activation, values);
                Avm2::dispatch_event(activation.context, net_status_event, object.into());
            }
            None => {}
        }
    }

    /// Timffle: after `NetStream.Play.Stop` of a played file, Flash Player 32
    /// calls the client's `onPlayStatus` with `NetStream.Play.Complete`
    /// (measured, tests/tests/swfs/avm2/netstream_local_events). A client
    /// without that method is skipped (AVM2 only; the AVM1 order was not
    /// measured).
    fn call_play_complete(self, context: &mut UpdateContext<'gc>) {
        if !matches!(self.0.avm_object.get(), Some(NetStreamKind::Avm2(_))) {
            return;
        }
        let Some(client) = self.client() else {
            return;
        };
        let mut activation = Avm2Activation::from_nothing(context);
        let name = AvmString::new_utf8(activation.gc(), "onPlayStatus");
        let client = Avm2Value::from(client);
        if !client.has_public_property(name, &mut activation) {
            return;
        }
        let info = crate::avm2::object::ScriptObject::new_object(activation.context);
        let info_value = Avm2Value::from(info);
        let code = AvmString::new_utf8(activation.gc(), "NetStream.Play.Complete");
        let level = AvmString::new_utf8(activation.gc(), "status");
        let _ = info_value.set_public_property(
            AvmString::new_utf8(activation.gc(), "code"),
            code.into(),
            &mut activation,
        );
        let _ = info_value.set_public_property(
            AvmString::new_utf8(activation.gc(), "level"),
            level.into(),
            &mut activation,
        );
        if let Err(e) = client.call_public_property(
            name,
            FunctionArgs::from_slice(&[info_value]),
            &mut activation,
        ) {
            tracing::error!("Got error when calling onPlayStatus on a NetStream client: {e:?}");
        }
    }

    fn handle_script_data(
        self,
        avm_object: Option<NetStreamKind<'gc>>,
        context: &mut UpdateContext<'gc>,
        variable_name: &[u8],
        variable_data: FlvValue,
    ) -> Result<(), Avm2Error<'gc>> {
        match avm_object {
            Some(NetStreamKind::Avm1(object)) => {
                let avm_string_name = AvmString::new_utf8_bytes(context.gc(), variable_name);
                let activation_name = format!("[FLV {avm_string_name}]");

                let root = context.stage.root_clip().expect("root");
                let mut activation = Avm1Activation::from_nothing(
                    context,
                    Avm1ActivationIdentifier::root(&activation_name),
                    root,
                );

                let avm1_object_value = variable_data.to_avm1_value(&mut activation);

                if let Err(e) = object.call_method(
                    avm_string_name,
                    &[avm1_object_value],
                    &mut activation,
                    Avm1ExecutionReason::Special,
                ) {
                    tracing::error!(
                        "Got error when dispatching AVM1 {} script data handler from NetStream: {}",
                        avm_string_name,
                        e,
                    );
                }
            }
            Some(NetStreamKind::Avm2(_)) => {
                let mut activation = Avm2Activation::from_nothing(context);
                let client_object = self
                    .client()
                    .expect("Client should be initialized if script data is being accessed");

                let data_object = variable_data.to_avm2_value(activation.context);
                // Timffle: remembered for `NetStreamInfo.metaData` / `xmpData`.
                if let Some(obj) = data_object.as_object() {
                    let mc = activation.gc();
                    if variable_name == b"onMetaData" {
                        unlock!(Gc::write(mc, self.0), NetStreamData, metadata).set(Some(obj));
                    } else if variable_name == b"onXMPData" {
                        unlock!(Gc::write(mc, self.0), NetStreamData, xmp_data).set(Some(obj));
                    }
                }
                let args = &[data_object];

                Avm2Value::from(client_object).call_public_property(
                    AvmString::new_utf8_bytes(activation.gc(), variable_name),
                    FunctionArgs::from_slice(args),
                    &mut activation,
                )?;
            }
            None => {}
        };

        Ok(())
    }
}
