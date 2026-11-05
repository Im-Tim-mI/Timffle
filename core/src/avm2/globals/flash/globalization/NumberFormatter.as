package flash.globalization {
    // Timffle: implemented for real. The number conventions of the actual
    // locale come from the compiled-in locale table (locale_data.rs) and the
    // formatting/parsing rules from the Adobe reference live in
    // number_format.rs. Property setters report `invalidAttrValue` /
    // `illegalArgumentError` instead of throwing, as the LastOperationStatus
    // reference documents for `negativeNumberFormat = 9` and `"3;"`.
    [API("667")]
    public final class NumberFormatter {
        [Ruffle(NativeAccessible)]
        private var _actualLocaleIDName:String;
        [Ruffle(NativeAccessible)]
        private var _decimalSeparator:String = ".";
        [Ruffle(NativeAccessible)]
        private var _digitsType:uint = NationalDigitsType.EUROPEAN;
        [Ruffle(NativeAccessible)]
        // Timffle: Flash 32 on Windows starts at the system setting (2 for every locale measured).
        private var _fractionalDigits:int = 2;
        [Ruffle(NativeAccessible)]
        private var _groupingPattern:String = "3;*";
        [Ruffle(NativeAccessible)]
        private var _groupingSeparator:String = ",";
        [Ruffle(NativeAccessible)]
        private var _lastOperationStatus:String = LastOperationStatus.NO_ERROR;
        [Ruffle(NativeAccessible)]
        private var _leadingZero:Boolean = true;
        private var _localeIDName:String;
        [Ruffle(NativeAccessible)]
        private var _negativeNumberFormat:uint = 1;
        [Ruffle(NativeAccessible)]
        private var _negativeSymbol:String = "-";
        [Ruffle(NativeAccessible)]
        private var _trailingZeros:Boolean = true;
        [Ruffle(NativeAccessible)]
        private var _useGrouping:Boolean = true;

        private static function throwNonNull(name:String) {
            throw new TypeError("Error #2007: Parameter " + name + " must be non-null.", 2007);
        }

        public function NumberFormatter(requestedLocaleIDName:String) {
            if (requestedLocaleIDName == null) {
                throwNonNull("requestedLocaleIDName");
            }
            this._localeIDName = requestedLocaleIDName;
            this.init(requestedLocaleIDName);
        }

        private native function init(requestedLocaleIDName:String):void;

        public function get actualLocaleIDName():String {
            return this._actualLocaleIDName;
        }

        public function get decimalSeparator():String {
            return this._decimalSeparator;
        }
        public function set decimalSeparator(value:String):void {
            if (value == null) {
                throwNonNull("decimalSeparator");
            }
            this._decimalSeparator = value;
            this._lastOperationStatus = LastOperationStatus.NO_ERROR;
        }

        public function get digitsType():uint {
            return this._digitsType;
        }
        public function set digitsType(value:uint):void {
            this._digitsType = value;
            this._lastOperationStatus = LastOperationStatus.NO_ERROR;
        }

        public function get fractionalDigits():int {
            return this._fractionalDigits;
        }
        public function set fractionalDigits(value:int):void {
            // Timffle: Flash 32 rejects a negative value with illegalArgumentError (measured).
            if (value < 0) {
                this._lastOperationStatus = LastOperationStatus.ILLEGAL_ARGUMENT_ERROR;
                return;
            }
            this._fractionalDigits = value;
            this._lastOperationStatus = LastOperationStatus.NO_ERROR;
        }

        public function get groupingPattern():String {
            return this._groupingPattern;
        }
        public function set groupingPattern(value:String):void {
            if (value == null) {
                throwNonNull("groupingPattern");
            }
            if (!isValidGroupingPattern(value)) {
                this._lastOperationStatus = LastOperationStatus.ILLEGAL_ARGUMENT_ERROR;
                return;
            }
            this._groupingPattern = value;
            this._lastOperationStatus = LastOperationStatus.NO_ERROR;
        }

        // Timffle: shared with CurrencyFormatter. A pattern is a list of
        // positive group sizes separated by ";", optionally ending in "*".
        internal static function isValidGroupingPattern(value:String):Boolean {
            var parts:Array = value.split(";");
            if (parts.length == 0) {
                return false;
            }
            var numbers:int = 0;
            for (var i:int = 0; i < parts.length; i++) {
                var part:String = parts[i];
                if (part == "*") {
                    if (i != parts.length - 1 || numbers == 0) {
                        return false;
                    }
                } else if (/^[0-9]+$/.test(part) && int(part) > 0) {
                    numbers++;
                } else {
                    return false;
                }
            }
            return numbers > 0;
        }

        public function get groupingSeparator():String {
            return this._groupingSeparator;
        }
        public function set groupingSeparator(value:String):void {
            if (value == null) {
                throwNonNull("groupingSeparator");
            }
            this._groupingSeparator = value;
            this._lastOperationStatus = LastOperationStatus.NO_ERROR;
        }

        public function get lastOperationStatus():String {
            return this._lastOperationStatus;
        }

        public function get leadingZero():Boolean {
            return this._leadingZero;
        }
        public function set leadingZero(value:Boolean):void {
            this._leadingZero = value;
            this._lastOperationStatus = LastOperationStatus.NO_ERROR;
        }

        public function get negativeNumberFormat():uint {
            return this._negativeNumberFormat;
        }
        public function set negativeNumberFormat(value:uint):void {
            if (value > 4) {
                this._lastOperationStatus = LastOperationStatus.INVALID_ATTR_VALUE;
                return;
            }
            this._negativeNumberFormat = value;
            this._lastOperationStatus = LastOperationStatus.NO_ERROR;
        }

        public function get negativeSymbol():String {
            return this._negativeSymbol;
        }
        public function set negativeSymbol(value:String):void {
            if (value == null) {
                throwNonNull("negativeSymbol");
            }
            // Timffle: Flash 32 (Windows) keeps the operating system's negative sign: any new
            // value, even the current one, is refused with unsupportedError (measured).
            this._lastOperationStatus = LastOperationStatus.UNSUPPORTED_ERROR;
        }

        public function get requestedLocaleIDName():String {
            return this._localeIDName;
        }

        public function get trailingZeros():Boolean {
            return this._trailingZeros;
        }
        public function set trailingZeros(value:Boolean):void {
            this._trailingZeros = value;
            this._lastOperationStatus = LastOperationStatus.NO_ERROR;
        }

        public function get useGrouping():Boolean {
            return this._useGrouping;
        }
        public function set useGrouping(value:Boolean):void {
            this._useGrouping = value;
            this._lastOperationStatus = LastOperationStatus.NO_ERROR;
        }

        public native function formatInt(value:int):String;

        public native function formatNumber(value:Number):String;

        public native function formatUint(value:uint):String;

        public static native function getAvailableLocaleIDNames():Vector.<String>;

        public function parse(parseString:String):NumberParseResult {
            if (parseString == null) {
                throwNonNull("parseString");
            }
            var found:Array = this.nativeParse(parseString);
            if (found == null) {
                return new NumberParseResult();
            }
            return new NumberParseResult(found[0], found[1], found[2]);
        }

        private native function nativeParse(parseString:String):Array;

        public native function parseNumber(parseString:String):Number;
    }
}
