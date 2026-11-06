package flash.globalization {
    // Timffle: implemented for real. Style patterns, month/weekday names and
    // the first weekday come from the compiled-in locale table
    // (locale_data.rs); the LDML pattern renderer and the pattern syntax
    // check (`patternSyntaxError`) live in date_time_formatter.rs.
    [API("667")]
    public final class DateTimeFormatter {
        [Ruffle(NativeAccessible)]
        private var _actualLocaleIDName:String;
        [Ruffle(NativeAccessible)]
        private var _dateStyle:String;
        [Ruffle(NativeAccessible)]
        private var _dateTimePattern:String;
        [Ruffle(NativeAccessible)]
        private var _lastOperationStatus:String = LastOperationStatus.NO_ERROR;
        private var _localeIDName:String;
        [Ruffle(NativeAccessible)]
        private var _timeStyle:String;

        private static function throwNonNull(name:String) {
            throw new TypeError("Error #2007: Parameter " + name + " must be non-null.", 2007);
        }

        public function DateTimeFormatter(requestedLocaleIDName:String, dateStyle:String = "long", timeStyle:String = "long") {
            if (requestedLocaleIDName == null) {
                throwNonNull("requestedLocaleIDName");
            }

            this._localeIDName = requestedLocaleIDName;
            this.init(requestedLocaleIDName);
            var status:String = this._lastOperationStatus;
            this.setDateTimeStyles(dateStyle, timeStyle);
            // The constructor reports the locale fallback, not the style change.
            this._lastOperationStatus = status;
        }

        private native function init(requestedLocaleIDName:String):void;

        public function get actualLocaleIDName():String {
            return this._actualLocaleIDName;
        }

        public function get lastOperationStatus():String {
            return this._lastOperationStatus;
        }

        public function get requestedLocaleIDName():String {
            return this._localeIDName;
        }

        public function format(dateTime:Date):String {
            if (dateTime == null) {
                throwNonNull("dateTime");
            }
            return this.nativeFormat(dateTime);
        }

        public function formatUTC(dateTime:Date):String {
            if (dateTime == null) {
                throwNonNull("dateTime");
            }
            return this.nativeFormatUTC(dateTime);
        }

        private native function nativeFormat(dateTime:Date):String;
        private native function nativeFormatUTC(dateTime:Date):String;

        public static native function getAvailableLocaleIDNames():Vector.<String>;

        public function getDateStyle():String {
            return this._dateStyle;
        }

        public function getDateTimePattern():String {
            return this._dateTimePattern;
        }

        public native function getFirstWeekday():int;

        public function getMonthNames(nameStyle:String = "full", context:String = "standalone"):Vector.<String> {
            if (nameStyle == null) {
                throwNonNull("nameStyle");
            }
            if (context == null) {
                throwNonNull("context");
            }
            return this.nativeGetMonthNames(nameStyle, context);
        }

        public function getTimeStyle():String {
            return this._timeStyle;
        }

        public function getWeekdayNames(nameStyle:String = "full", context:String = "standalone"):Vector.<String> {
            if (nameStyle == null) {
                throwNonNull("nameStyle");
            }
            if (context == null) {
                throwNonNull("context");
            }
            return this.nativeGetWeekdayNames(nameStyle, context);
        }

        private native function nativeGetMonthNames(nameStyle:String, context:String):Vector.<String>;
        private native function nativeGetWeekdayNames(nameStyle:String, context:String):Vector.<String>;

        public function setDateTimePattern(pattern:String):void {
            if (pattern == null) {
                throwNonNull("pattern");
            }
            this.nativeSetDateTimePattern(pattern);
        }

        public function setDateTimeStyles(dateStyle:String, timeStyle:String):void {
            if (dateStyle == null) {
                throwNonNull("dateStyle");
            }
            if (timeStyle == null) {
                throwNonNull("timeStyle");
            }
            this.nativeSetDateTimeStyles(dateStyle, timeStyle);
        }

        private native function nativeSetDateTimePattern(pattern:String):void;
        private native function nativeSetDateTimeStyles(dateStyle:String, timeStyle:String):void;
    }
}
