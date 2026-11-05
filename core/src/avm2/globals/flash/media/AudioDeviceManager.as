package flash.media {
    import flash.errors.IllegalOperationError;
    import flash.events.EventDispatcher;

    // Timffle: audio output device selection (Flash Player 27+ on Windows and
    // macOS). This player plays through the one output the browser or
    // operating system gives it and has no device enumeration, so it answers
    // like Flash Player on a platform where the feature is not enabled:
    // `isSupported` false, no device names, no selected device (-1), and
    // never an `audioOutputChange` event. The singleton still exists through
    // `audioDeviceManager` (the reference says clients must use it, so the
    // constructor is `ArgumentError #2012` like other player-created
    // classes), and setting `selectedDeviceIndex` keeps the reference's
    // user-invoked-action restriction: `IllegalOperationError #2176` outside
    // a mouse or keyboard event; inside one there is no device to switch to,
    // so nothing changes.
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
            return false;
        }

        public function get deviceNames():Array {
            return [];
        }

        public function get selectedDeviceIndex():int {
            return -1;
        }

        public function set selectedDeviceIndex(value:int):void {
            if (!AudioDeviceManager.isUserInvoked()) {
                Error.throwError(IllegalOperationError, 2176);
            }
        }

        private static native function isUserInvoked():Boolean;
    }
}
