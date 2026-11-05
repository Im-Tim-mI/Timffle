package flash.ui {
    import __ruffle__.stub_getter;
    import __ruffle__.stub_method;

    [Ruffle(Abstract)]
    public final class Mouse {
        public static native function hide():void;
        public static native function show():void;

        public static native function get cursor():String;
        public static native function set cursor(value:String):void;

        // Timffle: "whether the computer or device displays a persistent cursor": every host
        // this player runs on drives it with a pointer (Capabilities.touchscreenType is
        // "none" -- no touch input reaches the player as touch), and a pointer host shows a
        // cursor, like desktop Flash Player; only a finger-touch device has none.
        public static function get supportsCursor():Boolean {
            return flash.system.Capabilities.touchscreenType != flash.system.TouchscreenType.FINGER;
        }
        public static function get supportsNativeCursor():Boolean {
            stub_getter("flash.ui.Mouse", "supportsNativeCursor");
            return true;
        }

        public static native function registerCursor(name:String, cursor:MouseCursorData):void;
        public static native function unregisterCursor(name:String):void;
    }
}
