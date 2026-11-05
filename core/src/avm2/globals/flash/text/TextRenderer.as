package flash.text {
    // Timffle: real settings store for the advanced (CSM) anti-aliasing knobs.
    //
    // Flash Player keeps these as global settings of its text rasteriser; this
    // player's glyph rasteriser has no continuous-stroke-modulation stage, so the
    // values are validated and remembered exactly as Flash does (every getter
    // returns what was set, `setAdvancedAntiAliasingTable` replaces the table of
    // the same font/style/colour) but they do not change how glyphs are drawn.
    // Flash Player itself ignores them on platforms without the CSM rasteriser.
    //
    // `antiAliasType` is the undocumented static property that playerglobal
    // still declares (the pre-`TextField.antiAliasType` global switch): it takes
    // the two `AntiAliasType` values and starts at "normal".
    public final class TextRenderer {
        private static var _antiAliasType:String = AntiAliasType.NORMAL;
        private static var _displayMode:String = TextDisplayMode.DEFAULT;
        private static var _maxLevel:int = 4;
        // "fontName|fontStyle|colorType" -> Array of CSMSettings
        private static var _tables:Object = {};

        public static function get antiAliasType():String {
            return _antiAliasType;
        }

        public static function set antiAliasType(value:String):void {
            if (value == null) {
                Error.throwError(TypeError, 2007, "antiAliasType");
            }
            if (value != AntiAliasType.NORMAL && value != AntiAliasType.ADVANCED) {
                Error.throwError(ArgumentError, 2008, "antiAliasType");
            }
            _antiAliasType = value;
        }

        public static function get displayMode():String {
            return _displayMode;
        }

        public static function set displayMode(value:String):void {
            if (value == null) {
                Error.throwError(TypeError, 2007, "displayMode");
            }
            if (value != TextDisplayMode.DEFAULT && value != TextDisplayMode.LCD && value != TextDisplayMode.CRT) {
                Error.throwError(ArgumentError, 2008, "displayMode");
            }
            _displayMode = value;
        }

        public static function get maxLevel():int {
            return _maxLevel;
        }

        // The reference: "The only acceptable values are 3, 4, and 7"; the
        // default is 4.
        public static function set maxLevel(value:int):void {
            if (value != 3 && value != 4 && value != 7) {
                Error.throwError(ArgumentError, 2008, "maxLevel");
            }
            _maxLevel = value;
        }

        public static function setAdvancedAntiAliasingTable(
            fontName:String,
            fontStyle:String,
            colorType:String,
            advancedAntiAliasingTable:Array
        ):void {
            if (fontName == null) {
                Error.throwError(TypeError, 2007, "fontName");
            }
            if (fontStyle == null) {
                Error.throwError(TypeError, 2007, "fontStyle");
            }
            if (colorType == null) {
                Error.throwError(TypeError, 2007, "colorType");
            }
            if (advancedAntiAliasingTable == null) {
                Error.throwError(TypeError, 2007, "advancedAntiAliasingTable");
            }
            if (fontStyle != FontStyle.REGULAR && fontStyle != FontStyle.BOLD
                && fontStyle != FontStyle.ITALIC && fontStyle != FontStyle.BOLD_ITALIC) {
                Error.throwError(ArgumentError, 2008, "fontStyle");
            }
            if (colorType != TextColorType.DARK_COLOR && colorType != TextColorType.LIGHT_COLOR) {
                Error.throwError(ArgumentError, 2008, "colorType");
            }
            var table:Array = [];
            for (var i:int = 0; i < advancedAntiAliasingTable.length; i++) {
                var entry:* = advancedAntiAliasingTable[i];
                if (!(entry is CSMSettings)) {
                    Error.throwError(ArgumentError, 2008, "advancedAntiAliasingTable");
                }
                table.push(entry);
            }
            _tables[fontName + "|" + fontStyle + "|" + colorType] = table;
        }
    }
}
