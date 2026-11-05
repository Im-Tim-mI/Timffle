package flash.media {
    import flash.events.EventDispatcher;

    // Timffle: the Adobe Primetime player built into Flash Player 19+. An
    // AVStream plays only after `AuthorizedFeatures.enableHLSPlayback()` has
    // been called with a token from Adobe's authorization service; this
    // player contacts no such service, so no stream is ever enabled: Flash
    // Player without the feature. Every transport call therefore answers
    // with the result code the API has for exactly that state,
    // `AVResult.PLAYBACK_NOT_ENABLED` (57), the stream never leaves
    // `AVPlayState.UNINITIALIZED`, nothing is decoded (no frames, no
    // buffer, no live point) and the decoder/render types stay
    // `AVStream.UNDEFINED`. The stream settings (`bufferTime`,
    // `initialBufferTime`, `backBufferTime`, `volume`, `useHardwareDecoder`,
    // `captionsEnabled`, `captionStyle`) are stored like any NetStream's so
    // that a player's configuration round-trips. A null source is
    // `TypeError #2007`, the usual answer of Flash's natives to a missing
    // required object.
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
            return this.notEnabled();
        }

        public function pause():AVResult {
            return this.notEnabled();
        }

        public function play():AVResult {
            return this.notEnabled();
        }

        // Boolean in Flash's playerglobal: whether playback resumed.
        public function resume():Boolean {
            return false;
        }

        public function rewind(rate:Number):AVResult {
            return this.notEnabled();
        }

        public function seek(offset:Number, inBufferSeek:Boolean = true):AVResult {
            return this.notEnabled();
        }

        public function seekToKeyFrame(offset:Number, inBufferSeek:Boolean = true):AVResult {
            return this.notEnabled();
        }

        public function seekToLivePoint():AVResult {
            return this.notEnabled();
        }

        public function seekToLocalTime(periodIndex:int, time:Number):AVResult {
            return this.notEnabled();
        }

        // Nothing is playing, so there is no speed to change.
        public function setPlaySpeed(speed:Number, reserved:Number):void {
        }

        public function step(frames:int):AVResult {
            return this.notEnabled();
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
            return 0;
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
