package flash.system {
    // Timffle: every member is implemented in capabilities.rs from one host description
    // (`core/src/system_properties.rs`, shared with AVM1's System.capabilities). The flags
    // describe what Timffle really provides: Flash Player's own constant capabilities
    // (audio, MP3, streaming/embedded video, the built-in audio/video encoders, TLS) are true;
    // features the player does not have on this host (accessibility aids, an IME, printing,
    // FMS screen broadcast/playback, the debugger build, Acrobat embedding, a touchscreen,
    // multichannel audio) report exactly what Flash Player reports on a machine without them.
    // serverString uses the field order of Flash Player 32 (measured on 32.0.0.465).
    [Ruffle(Abstract)]
    public final class Capabilities {
        // Undocumented. Flash Player 32.0.0.465 returns 37 for every SWF.
        public native static function get _internal():uint;

        public native static function get avHardwareDisable():Boolean;

        // Added in Flash Player 32 / AIR 32; Ruffle's API versioning stops at AIR 29, so
        // this is visible to every SWF version.
        public native static function get cpuAddressSize():Number;

        [API("665")]
        public native static function get cpuArchitecture():String;

        public native static function get hasAccessibility():Boolean;

        public native static function get hasAudio():Boolean;

        public native static function get hasAudioEncoder():Boolean;

        public native static function get hasEmbeddedVideo():Boolean;

        public native static function get hasIME():Boolean;

        public native static function get hasMP3():Boolean;

        public native static function get hasPrinting():Boolean;

        public native static function get hasScreenBroadcast():Boolean;

        public native static function get hasScreenPlayback():Boolean;

        public native static function get hasStreamingAudio():Boolean;

        public native static function get hasStreamingVideo():Boolean;

        public native static function get hasTLS():Boolean;

        public native static function get hasVideoEncoder():Boolean;

        public native static function get isDebugger():Boolean;

        public native static function get isEmbeddedInAcrobat():Boolean;

        public native static function get language():String;

        public native static function get localFileReadDisable():Boolean;

        public native static function get manufacturer():String;

        [API("662")]
        public native static function get maxLevelIDC():String;

        public native static function get os():String;

        public native static function get pixelAspectRatio():Number;

        public native static function get playerType():String;

        public native static function get screenColor():String;

        public native static function get screenDPI():Number;

        public native static function get screenResolutionY():Number;

        public native static function get screenResolutionX():Number;

        public native static function get serverString():String;

        [API("665")]
        public native static function get supports32BitProcesses():Boolean;

        [API("665")]
        public native static function get supports64BitProcesses():Boolean;

        [API("667")]
        public native static function get touchscreenType():String;

        public native static function get version():String;

        [API("674")]
        public native static function hasMultiChannelAudio(type:String):Boolean;
    }
}
