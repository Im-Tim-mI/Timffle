package flash.ui {
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
        // Timffle: whether the host can show the bitmap cursors of `registerCursor()`
        // (web: CSS `cursor: url()`, desktop: a winit custom cursor). On a host without
        // them the registry and `Mouse.cursor` still work, like Flash Player on a
        // configuration without native cursors; only the pointer image stays built in.
        public static native function get supportsNativeCursor():Boolean;

        // Timffle: real: copies the MouseCursorData frames (at most 32x32, straight RGBA),
        // hot spot and frame rate into the player's registry and, through the UiBackend,
        // onto the host pointer when `Mouse.cursor` names it. See mouse.rs for the errors.
        public static native function registerCursor(name:String, cursor:MouseCursorData):void;
        public static native function unregisterCursor(name:String):void;
    }
}
