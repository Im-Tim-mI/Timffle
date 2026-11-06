package flash.media {
    import flash.events.EventDispatcher;

    // Timffle: the Adobe Primetime player built into Flash Player 19+. An
    // AVStream plays only after `AuthorizedFeatures.enableHLSPlayback()` has
    // been called with a token from Adobe's authorization service; this
    // player contacts no such service, so no stream is ever enabled: Flash
    // Player without the feature. The transport calls answer with the codes
    // Flash Player 32 gives such a stream (measured,
    // tests/tests/swfs/avm2/av_drm_arguments): `play()`
    // `AVResult.PLAYBACK_NOT_ENABLED` (57), `pause()` `SUCCESS` and
    // `resume()` true, the seeks `GENERIC_ERROR` (6), `fastForward`/`rewind`
    // `INVALID_OPERATION` (19), `step` `INVALID_WITH_AUDIO_ONLY_FILE` (21).
    // The stream never leaves `AVPlayState.UNINITIALIZED`, nothing is decoded
    // (no frames, no buffer, no live point; `frameTime` is -1e-9 as in Flash)
    // and the decoder/render types stay `AVStream.UNDEFINED`. The stream
    // settings are stored like any NetStream's; a null source or caption
    // style is `TypeError #2007`.
    [API("688")]
    public class AVStream extends EventDispatcher {
        public static const HARDWARE:String = "hardware";
        // Note: This is not a typo.
        public static const SOFTWARE:String = "sofware";
        public static const UNDEFINED:String = "undefined";

        private var _source:AVSource;
        private var _bufferTime:Number = 0;
        private var _initialBufferTime:Number = 0;
        private var _backBufferTime:Number = 0;
        private var _volume:Number = 1;
        private var _useHardwareDecoder:Boolean = true;
        private var _captionsEnabled:Boolean = false;
        private var _captionStyle:AVCaptionStyle = null;
        private var _disposed:Boolean = false;

        public function AVStream(source:AVSource) {
            super();
            if (source == null) {
                Error.throwError(TypeError, 2007, "source");
            }
            this._source = source;
        }

        private function notEnabled():AVResult {
            return new AVResult(AVResult.PLAYBACK_NOT_ENABLED);
        }

        public function dispose():void {
            this._disposed = true;
            this._source = null;
        }

        public function fastForward(rate:Number):AVResult {
            return new AVResult(AVResult.INVALID_OPERATION);
        }

        public function pause():AVResult {
            return new AVResult(AVResult.SUCCESS);
        }

        public function play():AVResult {
            return this.notEnabled();
        }

        // Boolean in Flash's playerglobal; Flash Player 32 answers true.
        public function resume():Boolean {
            return true;
        }

        public function rewind(rate:Number):AVResult {
            return new AVResult(AVResult.INVALID_OPERATION);
        }

        public function seek(offset:Number, inBufferSeek:Boolean = true):AVResult {
            return new AVResult(AVResult.GENERIC_ERROR);
        }

        public function seekToKeyFrame(offset:Number, inBufferSeek:Boolean = true):AVResult {
            return new AVResult(AVResult.GENERIC_ERROR);
        }

        public function seekToLivePoint():AVResult {
            return new AVResult(AVResult.GENERIC_ERROR);
        }

        public function seekToLocalTime(periodIndex:int, time:Number):AVResult {
            return new AVResult(AVResult.GENERIC_ERROR);
        }

        // Nothing is playing, so there is no speed to change.
        public function setPlaySpeed(speed:Number, reserved:Number):void {
        }

        public function step(frames:int):AVResult {
            return new AVResult(AVResult.INVALID_WITH_AUDIO_ONLY_FILE);
        }

        public function get backBufferLength():Number {
            return 0;
        }

        public function set backBufferTime(value:Number):void {
            this._backBufferTime = value;
        }

        public function get bufferLength():Number {
            return 0;
        }

        public function set bufferTime(value:Number):void {
            this._bufferTime = value;
        }

        public function set captionStyle(value:AVCaptionStyle):void {
            if (value == null) {
                Error.throwError(TypeError, 2007, "captionStyle");
            }
            this._captionStyle = value;
        }

        public function get captionsEnabled():Boolean {
            return this._captionsEnabled;
        }

        public function set captionsEnabled(value:Boolean):void {
            this._captionsEnabled = value;
        }

        public function get clientLivePoint():Number {
            return 0;
        }

        public function get currentFPS():Number {
            return 0;
        }

        public function get decoderType():String {
            return AVStream.UNDEFINED;
        }

        public function get droppedFrames():int {
            return 0;
        }

        public function get frameTime():Number {
            return -1e-9;
        }

        public function set initialBufferTime(value:Number):void {
            this._initialBufferTime = value;
        }

        public function get playState():AVPlayState {
            return new AVPlayState(AVPlayState.UNINITIALIZED);
        }

        public function get renderType():String {
            return AVStream.UNDEFINED;
        }

        public function get time():Number {
            return 0;
        }

        public function get useHardwareDecoder():Boolean {
            return this._useHardwareDecoder;
        }

        public function set useHardwareDecoder(value:Boolean):void {
            this._useHardwareDecoder = value;
        }

        public function get volume():Number {
            return this._volume;
        }

        // 0 through 1 like `SoundTransform.volume`'s useful range; NaN is 0.
        public function set volume(value:Number):void {
            if (value != value) {
                value = 0;
            }
            this._volume = Math.max(0, Math.min(1, value));
        }
    }
}
