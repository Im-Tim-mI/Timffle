package flash.ui {
    // Timffle: Flash Player on a host without touch input. No touch or gesture input reaches
    // this player as such (`Capabilities.touchscreenType` is "none"; pointer input arrives as
    // mouse events), so the answers are those of desktop Flash Player on a mouse-only machine:
    // no touch points, no touch or gesture events, and no supported gestures -- the reference
    // says `supportedGestures` is null "in an environment that does not support any
    // multi-touch gestures". `inputMode` and `mapTouchToMouse` are stored settings (their
    // effect is on touch events, which never occur); an unknown `inputMode` is #2008 like the
    // other enumerated setters.
    [Ruffle(Abstract)]
    public final class Multitouch {
        private static var _inputMode:String = MultitouchInputMode.GESTURE;
        private static var _mapTouchToMouse:Boolean = true;

        public static function get inputMode():String {
            return _inputMode;
        }

        public static function set inputMode(value:String):void {
            if (value != MultitouchInputMode.NONE && value != MultitouchInputMode.GESTURE && value != MultitouchInputMode.TOUCH_POINT) {
                throw new ArgumentError("Error #2008: Parameter inputMode must be one of the accepted values.", 2008);
            }
            _inputMode = value;
        }

        // AIR 3.0 only (675 = AIR_3_0, hidden from Flash Player SWFs like the reference says).
        [API("675")]
        public static function get mapTouchToMouse():Boolean {
            return _mapTouchToMouse;
        }

        [API("675")]
        public static function set mapTouchToMouse(value:Boolean):void {
            _mapTouchToMouse = value;
        }

        public static function get maxTouchPoints():int {
            return 0;
        }

        public static function get supportedGestures():Vector.<String> {
            return null;
        }

        public static function get supportsGestureEvents():Boolean {
            return false;
        }

        public static function get supportsTouchEvents():Boolean {
            return false;
        }
    }
}
