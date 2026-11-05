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
    // Timffle: what Flash Player 32 does with each value was measured
    // (timffle/difftest/src/S2Text.hx); none of the setters throws for a value it
    // does not take:
    // - `antiAliasType` (the undocumented static that playerglobal still declares)
    //   starts at "default"; setting "default" keeps "default", any other string
    //   reads back as "off"; null is TypeError #2007.
    // - `displayMode` starts at "crt"; only "lcd" is kept, anything else (also
    //   "default" and null) reads back as "crt".
    // - `maxLevel` keeps 3, 4 and 7 and silently ignores other values.
    public final class TextRenderer {
        private static var _antiAliasType:String = "default";
        private static var _displayMode:String = TextDisplayMode.CRT;
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
            _antiAliasType = value == "default" ? "default" : "off";
        }

        public static function get displayMode():String {
            return _displayMode;
        }

        public static function set displayMode(value:String):void {
            _displayMode = value == TextDisplayMode.LCD ? TextDisplayMode.LCD : TextDisplayMode.CRT;
        }

        public static function get maxLevel():int {
            return _maxLevel;
        }

        public static function set maxLevel(value:int):void {
            if (value == 3 || value == 4 || value == 7) {
                _maxLevel = value;
            }
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
            // A null table is accepted (and stores nothing); style and colour type
            // strings are not checked; an entry that is not a CSMSettings is
            // TypeError #2005 (all measured in Flash Player 32).
            if (advancedAntiAliasingTable == null) {
                return;
            }
            var table:Array = [];
            for (var i:int = 0; i < advancedAntiAliasingTable.length; i++) {
                var entry:* = advancedAntiAliasingTable[i];
                if (!(entry is CSMSettings)) {
                    throw new TypeError("Error #2005: Parameter advancedAntiAliasingTable is of the incorrect type. Should be type CSMSettings.", 2005);
                }
                table.push(entry);
            }
            _tables[fontName + "|" + fontStyle + "|" + colorType] = table;
        }
    }
}
