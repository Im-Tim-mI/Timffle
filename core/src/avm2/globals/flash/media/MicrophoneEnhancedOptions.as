package flash.media {
    // Timffle: the defaults the AS3 reference documents (echo path 128 ms,
    // full-duplex mode, non-linear processing on, no voice detected yet);
    // `autoGain` is declared by Flash Player's playerglobal although the
    // reference page omits it; in Flash Player 32 it reads false and setting it
    // has no effect.
    [API("672")]
    public final class MicrophoneEnhancedOptions {
        public var echoPath:int = 128;
        public var isVoiceDetected:int = -1;
        public var mode:String = MicrophoneEnhancedMode.FULL_DUPLEX;
        public var nonLinearProcessing:Boolean = true;

        public function get autoGain():Boolean {
            return false;
        }

        public function set autoGain(value:Boolean):void {
        }
    }
}
