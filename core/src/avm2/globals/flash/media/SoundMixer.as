package flash.media {
    import flash.utils.ByteArray;

    public final class SoundMixer {
        // Timffle: `audioPlaybackMode` and `useSpeakerphoneForVoice` are the
        // mobile audio-session settings. On desktop and TV players (and here)
        // they change nothing audible; Flash Player 32 stores whatever is
        // assigned without validation and reads null before the first
        // assignment (measured with timffle/difftest/src/D60Media.hx; the
        // Boolean getter here reads false instead of null). Adobe lists them as
        // AIR 3.0 (API 675), but Flash Player 32 has them for SWF 13+ content,
        // so they carry the SWF 13 version like `MovieClip.isPlaying`.
        private static var _audioPlaybackMode:String = null;
        private static var _useSpeakerphoneForVoice:Boolean = false;

        [API("674")]
        public static function get audioPlaybackMode():String {
            return _audioPlaybackMode;
        }

        [API("674")]
        public static function set audioPlaybackMode(value:String):void {
            _audioPlaybackMode = value;
        }

        [API("674")]
        public static function get useSpeakerphoneForVoice():Boolean {
            return _useSpeakerphoneForVoice;
        }

        [API("674")]
        public static function set useSpeakerphoneForVoice(value:Boolean):void {
            _useSpeakerphoneForVoice = value;
        }

        public static native function get soundTransform():SoundTransform;
        public static native function set soundTransform(value:SoundTransform):void;

        public static native function get bufferTime():int;
        public static native function set bufferTime(value:int):void;

        public static native function stopAll():void;
        public static native function areSoundsInaccessible():Boolean

        public static native function computeSpectrum(
            outputArray:ByteArray,
            FFTMode:Boolean = false,
            stretchFactor:int = 0
        ):void;
    }
}
