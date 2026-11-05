package flash.media {
    // Timffle: the defaults the AS3 reference documents (echo path 128 ms,
    // full-duplex mode, non-linear processing on, no voice detected yet);
    // `autoGain` is declared by Flash Player's playerglobal (automatic gain
    // control, off by default) although the reference page omits it.
    [API("672")]
    public final class MicrophoneEnhancedOptions {
        public var echoPath:int = 128;
        public var isVoiceDetected:int = -1;
        public var mode:String = MicrophoneEnhancedMode.FULL_DUPLEX;
        public var nonLinearProcessing:Boolean = true;
        public var autoGain:Boolean = false;
    }
}
