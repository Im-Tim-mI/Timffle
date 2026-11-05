package flash.globalization {
    // Timffle: implemented for real. The currency of the actual locale (ISO
    // code, symbol, fraction digits, positive/negative layouts) comes from the
    // compiled-in locale table (locale_data.rs); formatting and parsing live
    // in currency_formatter.rs / number_format.rs and follow the layout
    // tables of the Adobe reference.
    [API("667")]
    public final class CurrencyFormatter {
        private var _requestedLocaleIDName:String;
        [Ruffle(NativeAccessible)]
        private var _actualLocaleIDName:String;
        [Ruffle(NativeAccessible)]
        private var _currencyISOCode:String = "USD";
        [Ruffle(NativeAccessible)]
        private var _currencySymbol:String = "$";
        [Ruffle(NativeAccessible)]
        private var _decimalSeparator:String = ".";
        [Ruffle(NativeAccessible)]
        private var _digitsType:uint = NationalDigitsType.EUROPEAN;
        [Ruffle(NativeAccessible)]
        private var _fractionalDigits:int = 2;
        [Ruffle(NativeAccessible)]
        private var _groupingPattern:String = "3;*";
        [Ruffle(NativeAccessible)]
        private var _groupingSeparator:String = ",";
        [Ruffle(NativeAccessible)]
        private var _lastOperationStatus:String = LastOperationStatus.NO_ERROR;
        [Ruffle(NativeAccessible)]
        private var _leadingZero:Boolean = true;
        [Ruffle(NativeAccessible)]
        private var _negativeCurrencyFormat:uint = 1;
        [Ruffle(NativeAccessible)]
        private var _negativeSymbol:String = "-";
        [Ruffle(NativeAccessible)]
        private var _positiveCurrencyFormat:uint = 0;
        [Ruffle(NativeAccessible)]
        private var _trailingZeros:Boolean = true;
        [Ruffle(NativeAccessible)]
        private var _useGrouping:Boolean = true;

        private static function throwNonNull(name:String) {
            throw new TypeError("Error #2007: Parameter " + name + " must be non-null.", 2007);
        }

        public function CurrencyFormatter(requestedLocaleIDName:String) {
            if (requestedLocaleIDName == null) {
                throwNonNull("requestedLocaleIDName");
            }
            this._requestedLocaleIDName = requestedLocaleIDName;
            this.init(requestedLocaleIDName);
        }

        private native function init(requestedLocaleIDName:String):void;

        public function get actualLocaleIDName():String {
            return this._actualLocaleIDName;
        }

        public function get currencyISOCode():String {
            return this._currencyISOCode;
        }

        public function get currencySymbol():String {
            return this._currencySymbol;
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
            if (!NumberFormatter.isValidGroupingPattern(value)) {
                this._lastOperationStatus = LastOperationStatus.ILLEGAL_ARGUMENT_ERROR;
                return;
            }
            this._groupingPattern = value;
            this._lastOperationStatus = LastOperationStatus.NO_ERROR;
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

        public function get negativeCurrencyFormat():uint {
            return this._negativeCurrencyFormat;
        }

        public function set negativeCurrencyFormat(value:uint):void {
            if (value > 15) {
                this._lastOperationStatus = LastOperationStatus.INVALID_ATTR_VALUE;
                return;
            }
            this._negativeCurrencyFormat = value;
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

        public function get positiveCurrencyFormat():uint {
            return this._positiveCurrencyFormat;
        }

        public function set positiveCurrencyFormat(value:uint):void {
            if (value > 3) {
                this._lastOperationStatus = LastOperationStatus.INVALID_ATTR_VALUE;
                return;
            }
            this._positiveCurrencyFormat = value;
            this._lastOperationStatus = LastOperationStatus.NO_ERROR;
        }

        public function get requestedLocaleIDName():String {
            return this._requestedLocaleIDName;
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

        public native function format(value:Number, withCurrencySymbol:Boolean = false):String;

        public native function formattingWithCurrencySymbolIsSafe(requestedISOCode:String):Boolean;

        public function parse(inputString:String):CurrencyParseResult {
            if (inputString == null) {
                throwNonNull("inputString");
            }
            var found:Array = this.nativeParse(inputString);
            if (found == null) {
                // Timffle: Flash 32 returns an empty currency string, not null.
                return new CurrencyParseResult(NaN, "");
            }
            return new CurrencyParseResult(found[0], found[1]);
        }

        private native function nativeParse(inputString:String):Array;

        public native function setCurrency(currencyISOCode:String, currencySymbol:String):void;

        public static native function getAvailableLocaleIDNames():Vector.<String>;
    }
}
