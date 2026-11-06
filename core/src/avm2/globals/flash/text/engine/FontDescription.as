package flash.text.engine {
    [API("662")]
    [Ruffle(InstanceAllocator)]
    public final class FontDescription {
        public function FontDescription(
            fontName:String = "_serif",
            fontWeight:String = "normal",
            fontPosture:String = "normal",
            fontLookup:String = "device",
            renderingMode:String = "cff",
            cffHinting:String = "horizontalStem"
        ) {
            this.fontName = fontName;
            this.fontWeight = fontWeight;
            this.fontPosture = fontPosture;
            this.fontLookup = fontLookup;
            this.renderingMode = renderingMode;
            this.cffHinting = cffHinting;
        }

        public native function get fontName():String;
        public native function set fontName(value:String):void;

        public native function get fontWeight():String;
        public native function set fontWeight(value:String):void;

        public native function get fontPosture():String;
        public native function set fontPosture(value:String):void;

        public native function get fontLookup():String;
        public native function set fontLookup(value:String):void;

        public native function get renderingMode():String;
        public native function set renderingMode(value:String):void;

        public native function get cffHinting():String;
        public native function set cffHinting(value:String):void;

        public native function get locked():Boolean;
        public native function set locked(value:Boolean):void;

        public function clone():FontDescription {
            return new FontDescription(
                this.fontName,
                this.fontWeight,
                this.fontPosture,
                this.fontLookup,
                this.renderingMode,
                this.cffHinting
            );
        }

        // Timffle: true when an embedded CFF font (embedAsCFF / DefineFont4)
        // with this name, weight and posture is available to the text engine.
        public static function isFontCompatible(fontName:String, fontWeight:String, fontPosture:String):Boolean {
            checkFontArgs(fontName, fontWeight, fontPosture);
            return isFontCompatibleNative(fontName, fontWeight == FontWeight.BOLD, fontPosture == FontPosture.ITALIC);
        }

        // Timffle: true when the player can provide a device font for this
        // name, weight and posture (the backend resolves it, or falls back to
        // a bundled default font as Flash falls back to the OS default).
        [API("674")]
        public static function isDeviceFontCompatible(fontName:String, fontWeight:String, fontPosture:String):Boolean {
            checkFontArgs(fontName, fontWeight, fontPosture);
            return isDeviceFontCompatibleNative(fontName, fontWeight == FontWeight.BOLD, fontPosture == FontPosture.ITALIC);
        }

        private static function checkFontArgs(fontName:String, fontWeight:String, fontPosture:String):void {
            if (fontName == null) {
                throw new TypeError("Error #2007: Parameter fontName must be non-null.", 2007);
            }
            if (fontWeight != FontWeight.NORMAL && fontWeight != FontWeight.BOLD) {
                throw new ArgumentError("Error #2008: Parameter fontWeight must be one of the accepted values.", 2008);
            }
            if (fontPosture != FontPosture.NORMAL && fontPosture != FontPosture.ITALIC) {
                throw new ArgumentError("Error #2008: Parameter fontPosture must be one of the accepted values.", 2008);
            }
        }

        private static native function isFontCompatibleNative(fontName:String, bold:Boolean, italic:Boolean):Boolean;
        private static native function isDeviceFontCompatibleNative(fontName:String, bold:Boolean, italic:Boolean):Boolean;
    }
}
