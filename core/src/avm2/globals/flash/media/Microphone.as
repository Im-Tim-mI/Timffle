package flash.media {
    import flash.events.EventDispatcher;

    // Timffle: Flash Player on a machine without a microphone. This player
    // has no audio capture pipeline on any platform, so `isSupported` is
    // false, `names` is empty and `getMicrophone()`/`getEnhancedMicrophone()`
    // return null (the AS3 reference: null "if no microphones are installed"
    // and "when enhanced audio fails to initialize"). Microphone objects only
    // come from those two methods, so `new Microphone()` is
    // `ArgumentError #2012` like the other player-created classes. The
    // instance members are nevertheless real: the reference's defaults
    // (Nellymoser at 8 kHz, gain 50, silence level 10 for 2000 ms, Speex
    // quality 6 with 2 frames per packet and -30 dB noise suppression, no
    // echo suppression, muted, activity -1) with the documented validation.
    public final class Microphone extends EventDispatcher {
        private var _codec:String = SoundCodec.NELLYMOSER;
        private var _rate:int = 8;
        private var _gain:Number = 50;
        private var _encodeQuality:int = 6;
        private var _framesPerPacket:int = 2;
        private var _noiseSuppressionLevel:int = -30;
        private var _enableVAD:Boolean = false;
        private var _silenceLevel:Number = 10;
        private var _silenceTimeout:int = 2000;
        private var _useEchoSuppression:Boolean = false;
        private var _loopBack:Boolean = false;
        private var _soundTransform:SoundTransform = new SoundTransform();
        private var _enhancedOptions:MicrophoneEnhancedOptions = null;

        public function Microphone() {
            throw new ArgumentError("Error #2012: Microphone$ class cannot be instantiated.", 2012);
        }

        [API("672")]
        public static function getEnhancedMicrophone(index:int = -1):Microphone {
            return null;
        }

        public static function getMicrophone(index:int = -1):Microphone {
            return null;
        }

        [API("667")]
        public static function get isSupported():Boolean {
            return false;
        }

        public static function get names():Array {
            return [];
        }

        public function setLoopBack(isLooped:Boolean = true):void {
            this._loopBack = isLooped;
        }

        // The reference: level 0 through 100; a timeout of -1 means 2000 ms.
        public function setSilenceLevel(silenceLevel:Number, timeout:int = -1):void {
            if (silenceLevel != silenceLevel) {
                silenceLevel = 0;
            }
            this._silenceLevel = Math.max(0, Math.min(100, silenceLevel));
            this._silenceTimeout = timeout < 0 ? 2000 : timeout;
        }

        public function setUseEchoSuppression(isEchoSuppressed:Boolean):void {
            this._useEchoSuppression = isEchoSuppressed;
        }

        // "Always -1" while muted, and this microphone is always muted.
        public function get activityLevel():Number {
            return -1;
        }

        public function get codec():String {
            return this._codec;
        }

        // The reference: the SoundCodec constants; Speex always captures at
        // 16 kHz. Any other string is not an accepted value (#2008).
        public function set codec(codec:String):void {
            if (codec == null) {
                Error.throwError(TypeError, 2007, "codec");
            }
            if (codec != SoundCodec.NELLYMOSER && codec != SoundCodec.SPEEX
                && codec != SoundCodec.PCMA && codec != SoundCodec.PCMU) {
                Error.throwError(ArgumentError, 2008, "codec");
            }
            this._codec = codec;
            if (codec == SoundCodec.SPEEX) {
                this._rate = 16;
            }
        }

        public function get enableVAD():Boolean {
            return this._enableVAD;
        }

        public function set enableVAD(isEnabled:Boolean):void {
            this._enableVAD = isEnabled;
        }

        public function get encodeQuality():int {
            return this._encodeQuality;
        }

        // The reference: 0 through 10.
        public function set encodeQuality(quality:int):void {
            this._encodeQuality = Math.max(0, Math.min(10, quality));
        }

        [API("672")]
        public function get enhancedOptions():MicrophoneEnhancedOptions {
            return this._enhancedOptions;
        }

        // Stored; "ignored for non-enhanced Microphone instances", and no
        // enhanced instance can exist here.
        [API("672")]
        public function set enhancedOptions(params:MicrophoneEnhancedOptions):void {
            this._enhancedOptions = params;
        }

        public function get framesPerPacket():int {
            return this._framesPerPacket;
        }

        // At least one 20 ms frame per packet.
        public function set framesPerPacket(fpp:int):void {
            this._framesPerPacket = Math.max(1, fpp);
        }

        public function get gain():Number {
            return this._gain;
        }

        // The reference: "Valid values are 0 through 100".
        public function set gain(gain:Number):void {
            if (gain != gain) {
                gain = 0;
            }
            this._gain = Math.max(0, Math.min(100, gain));
        }

        // Position in `Microphone.names`: there is no entry for this device.
        public function get index():int {
            return -1;
        }

        // Access to the (absent) microphone is never granted.
        public function get muted():Boolean {
            return true;
        }

        public function get name():String {
            return "";
        }

        public function get noiseSuppressionLevel():int {
            return this._noiseSuppressionLevel;
        }

        // Maximum attenuation in dB "as a negative number"; 0 disables it.
        public function set noiseSuppressionLevel(level:int):void {
            this._noiseSuppressionLevel = Math.min(0, level);
        }

        public function get rate():int {
            return this._rate;
        }

        // The reference: 5, 8, 11, 22 and 44 kHz (16 kHz since Flash Player
        // 10). Other values go to the next supported rate above, the way the
        // default is chosen when the device lacks 8 kHz; Speex stays at 16.
        public function set rate(level:int):void {
            if (this._codec == SoundCodec.SPEEX) {
                return;
            }
            var rates:Array = [5, 8, 11, 16, 22, 44];
            var chosen:int = 44;
            for (var i:int = 0; i < rates.length; i++) {
                if (level <= rates[i]) {
                    chosen = rates[i];
                    break;
                }
            }
            this._rate = chosen;
        }

        public function get silenceLevel():Number {
            return this._silenceLevel;
        }

        public function get silenceTimeout():int {
            return this._silenceTimeout;
        }

        public function get soundTransform():SoundTransform {
            return this._soundTransform;
        }

        public function set soundTransform(tf:SoundTransform):void {
            if (tf == null) {
                Error.throwError(TypeError, 2007, "soundTransform");
            }
            this._soundTransform = tf;
        }

        public function get useEchoSuppression():Boolean {
            return this._useEchoSuppression;
        }
    }
}
