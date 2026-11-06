package flash.media {
    import flash.events.EventDispatcher;

    // Timffle: audio output device selection (Flash Player 27+ on Windows and
    // macOS). This player plays through the one output the browser or
    // operating system gives it and has no device enumeration, so it answers
    // like Flash Player 32 with an empty device list (measured on a machine
    // without audio devices): `isSupported` true, no device names,
    // `selectedDeviceIndex` 0, and never an `audioOutputChange` event. The
    // singleton exists through `audioDeviceManager`; the
    // constructor is `ArgumentError #2012` (measured on Flash Player 32,
    // tests/tests/swfs/avm2/stagevideo_bounds). Flash Player 32 accepts a new
    // `selectedDeviceIndex` outside a mouse or keyboard event too (it does not
    // apply the user-invoked-action rule here) and answers an index outside
    // `deviceNames` with `RangeError #1125` (measured with two devices: 5, -1
    // and -2 throw); with no device every index is outside the list.
    [API("724")]
    public final class AudioDeviceManager extends EventDispatcher {
        private static var _instance:AudioDeviceManager = null;
        private static var _creating:Boolean = false;

        public function AudioDeviceManager() {
            super();
            if (!AudioDeviceManager._creating) {
                throw new ArgumentError("Error #2012: AudioDeviceManager$ class cannot be instantiated.", 2012);
            }
        }

        public static function get audioDeviceManager():AudioDeviceManager {
            if (AudioDeviceManager._instance == null) {
                AudioDeviceManager._creating = true;
                AudioDeviceManager._instance = new AudioDeviceManager();
                AudioDeviceManager._creating = false;
            }
            return AudioDeviceManager._instance;
        }

        public static function get isSupported():Boolean {
            return true;
        }

        public function get deviceNames():Array {
            return [];
        }

        public function get selectedDeviceIndex():int {
            return 0;
        }

        public function set selectedDeviceIndex(value:int):void {
            Error.throwError(RangeError, 1125, value, this.deviceNames.length);
        }
    }
}
