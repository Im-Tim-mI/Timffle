package flash.globalization {
    import flash.globalization.LastOperationStatus;

    // Timffle: implemented for real with full Unicode case mapping plus the
    // Turkish/Azeri and Lithuanian special rules (string_tools.rs). The
    // locale falls back as Flash documents it (`usingFallbackWarning` /
    // `usingDefaultWarning`).
    [API("667")]
    public final class StringTools {
        private var _requestedLocaleIDName:String;

        [Ruffle(NativeAccessible)]
        private var _actualLocaleIDName:String;

        [Ruffle(NativeAccessible)]
        private var _lastOperationStatus:String = LastOperationStatus.NO_ERROR;

        public function StringTools(requestedLocaleIDName:String) {
            if (requestedLocaleIDName == null) {
                throw new ArgumentError("Error #2004: One of the parameters is invalid.", 2004);
            }
            this._requestedLocaleIDName = requestedLocaleIDName;
            this.init(requestedLocaleIDName);
        }

        private native function init(requestedLocaleIDName:String):void;

        public function get actualLocaleIDName():String {
            return this._actualLocaleIDName;
        }

        public function get lastOperationStatus():String {
            return this._lastOperationStatus;
        }

        public function get requestedLocaleIDName():String {
            return this._requestedLocaleIDName;
        }

        public function toLowerCase(s:String):String {
            // Timffle: Flash 32 throws TypeError #2007 for a null string (measured).
            if (s == null) {
                throw new TypeError("Error #2007: Parameter s must be non-null.", 2007);
            }
            return this.nativeToLowerCase(s);
        }

        public function toUpperCase(s:String):String {
            // Timffle: Flash 32 throws TypeError #2007 for a null string (measured).
            if (s == null) {
                throw new TypeError("Error #2007: Parameter s must be non-null.", 2007);
            }
            return this.nativeToUpperCase(s);
        }

        private native function nativeToLowerCase(s:String):String;
        private native function nativeToUpperCase(s:String):String;

        public static native function getAvailableLocaleIDNames():Vector.<String>;
    }
}
