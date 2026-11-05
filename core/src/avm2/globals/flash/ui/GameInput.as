package flash.ui {
    import flash.events.EventDispatcher;

    [API("688")]
    public final class GameInput extends EventDispatcher {
        // Timffle: Flash Player 32 on Windows reports game input as supported even with no
        // controller attached (numDevices 0), measured; devices would come from the runtime.
        public static function get isSupported():Boolean {
            return true;
        }

        public static function get numDevices():int {
            return 0;
        }

        public static function getDeviceAt(index:int):GameInputDevice {
            throw new RangeError("Error #1506: The specified range is invalid.", 1506);
        }
    }
}
