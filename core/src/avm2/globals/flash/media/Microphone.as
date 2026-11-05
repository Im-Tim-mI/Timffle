package flash.media {
    import flash.events.EventDispatcher;

    // Timffle: Flash Player on a machine without a microphone. This player
    // has no audio capture pipeline on any platform, so `isSupported` is
    // false, `names` is empty and `getMicrophone()`/`getEnhancedMicrophone()`
    // return null (the AS3 reference: null "if no microphones are installed"
    // and "when enhanced audio fails to initialize"). Flash Player 32 reports
    // `isSupported` true on a desktop; this player keeps false.
    //
    // `new Microphone()` does not throw in Flash Player 32: it makes a
    // Microphone attached to no device, which answers 0, false or null from
    // every getter (a SoundTransform from `soundTransform`) and ignores every
    // setter; only a null `codec` or `soundTransform` is TypeError #2007
    // (measured on Flash Player 32, tests/tests/swfs/avm2/stagevideo_bounds).
    // That is the only kind of Microphone this player can have.
    public final class Microphone extends EventDispatcher {
        public function Microphone() {
            super();
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

        // The settings of a Microphone without a device do not change.
        public function setLoopBack(isLooped:Boolean = true):void {
        }

        public function setSilenceLevel(silenceLevel:Number, timeout:int = -1):void {
        }

        public function setUseEchoSuppression(isEchoSuppressed:Boolean):void {
        }

        public function set codec(codec:String):void {
            if (codec == null) {
                Error.throwError(TypeError, 2007, "codec");
            }
        }

        public function set enableVAD(isEnabled:Boolean):void {
        }

        public function set encodeQuality(quality:int):void {
        }

        [API("672")]
        public function get enhancedOptions():MicrophoneEnhancedOptions {
            return null;
        }

        [API("672")]
        public function set enhancedOptions(params:MicrophoneEnhancedOptions):void {
        }

        public function set framesPerPacket(fpp:int):void {
        }

        public function set gain(gain:Number):void {
        }

        public function set noiseSuppressionLevel(level:int):void {
        }

        public function set rate(level:int):void {
        }

        public function get soundTransform():SoundTransform {
            return new SoundTransform();
        }

        public function set soundTransform(tf:SoundTransform):void {
            if (tf == null) {
                Error.throwError(TypeError, 2007, "soundTransform");
            }
        }

        public function get activityLevel():Number {
            return 0;
        }

        public function get codec():String {
            return null;
        }

        public function get enableVAD():Boolean {
            return false;
        }

        public function get encodeQuality():int {
            return 0;
        }

        public function get framesPerPacket():int {
            return 0;
        }

        public function get gain():Number {
            return 0;
        }

        public function get index():int {
            return 0;
        }

        public function get muted():Boolean {
            return false;
        }

        public function get name():String {
            return null;
        }

        public function get noiseSuppressionLevel():int {
            return 0;
        }

        public function get rate():int {
            return 0;
        }

        public function get silenceLevel():Number {
            return 0;
        }

        public function get silenceTimeout():int {
            return 0;
        }

        public function get useEchoSuppression():Boolean {
            return false;
        }
    }
}
