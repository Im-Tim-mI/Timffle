package flash.globalization {
    import flash.globalization.LastOperationStatus;

    // Timffle: implemented for real. Flash Player parses locale ID names
    // with the OS locale service; here the BCP 47 / UTS #35 parser lives in
    // locale_id.rs together with a likely-subtags table for the guessed
    // script and region (reported with `usingFallbackWarning`, as Flash does).
    [API("667")]
    public final class LocaleID {
        public static const DEFAULT:String = "i-default";

        [Ruffle(NativeAccessible)]
        private var _name:String;

        [Ruffle(NativeAccessible)]
        private var _lastOperationStatus:String = LastOperationStatus.NO_ERROR;

        public function LocaleID(name:String) {
            if (name == null) {
                throw new ArgumentError("Error #2004: One of the parameters is invalid.", 2004);
            }
            this.init(name);
        }

        private native function init(name:String):void;

        public function get lastOperationStatus():String {
            return this._lastOperationStatus;
        }

        public function get name():String {
            return this._name;
        }

        public static native function determinePreferredLocales(
            want:Vector.<String>,
            have:Vector.<String>,
            keyword:String = "userinterface"
        ):Vector.<String>;

        public native function getKeysAndValues():Object;

        public native function getLanguage():String;

        public native function getRegion():String;

        public native function getScript():String;

        public native function getVariant():String;

        public native function isRightToLeft():Boolean;
    }
}
