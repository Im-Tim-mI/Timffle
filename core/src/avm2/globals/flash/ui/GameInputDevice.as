package flash.ui {
    import flash.utils.ByteArray;

    // Timffle: Flash Player without game input devices (`GameInput.isSupported` false,
    // `numDevices` 0). Devices are only created by the runtime (`GameInput.getDeviceAt`,
    // which is always #1506 here), so no instance can exist; the members follow the
    // reference for a device that was removed: `enabled` reads false, `numControls` 0,
    // the control/sample calls fail with the documented errors (RangeError for an index,
    // ArgumentError for a null ByteArray or control list, Error on a disabled device) and the
    // class, like the other runtime-only classes, cannot be instantiated (#2012).
    //
    // The AS3 docs say this is only available in AIR 3.7. That was determined to be a lie.
    [API("688")]
    public final class GameInputDevice {
        public static const MAX_BUFFER_SIZE:int = 32000;

        private var _id:String;
        private var _name:String;
        private var _sampleInterval:int = 0;

        public function GameInputDevice() {
            throw new ArgumentError("Error #2012: GameInputDevice$ class cannot be instantiated.", 2012);
        }

        public function get enabled():Boolean {
            // A removed device always reads false.
            return false;
        }

        public function set enabled(value:Boolean):void {
            // Nothing to enable: there is no device behind this object.
        }

        public function get id():String {
            return this._id;
        }

        public function get name():String {
            return this._name;
        }

        public function get numControls():int {
            return 0;
        }

        public function get sampleInterval():int {
            return this._sampleInterval;
        }

        public function set sampleInterval(value:int):void {
            if (value < 0) {
                throw new RangeError("Error #2006: The supplied index is out of bounds.", 2006);
            }
            // Setting the interval on a disabled device is an Error.
            throw new Error("Error #2037: Functions called in incorrect sequence, or earlier call was unsuccessful.", 2037);
        }

        public function getCachedSamples(data:ByteArray, append:Boolean = false):int {
            if (data == null) {
                throw new ArgumentError("Error #2007: Parameter data must be non-null.", 2007);
            }
            throw new Error("Error #2037: Functions called in incorrect sequence, or earlier call was unsuccessful.", 2037);
        }

        public function getControlAt(i:int):GameInputControl {
            // numControls is 0, so every index is out of range.
            throw new RangeError("Error #2006: The supplied index is out of bounds.", 2006);
        }

        public function startCachingSamples(numSamples:int, controls:Vector.<String>):void {
            if (numSamples <= 0) {
                throw new RangeError("Error #2006: The supplied index is out of bounds.", 2006);
            }
            if (controls == null || controls.length == 0) {
                throw new ArgumentError("Error #2007: Parameter controls must be non-null.", 2007);
            }
            throw new Error("Error #2037: Functions called in incorrect sequence, or earlier call was unsuccessful.", 2037);
        }

        public function stopCachingSamples():void {
            throw new Error("Error #2037: Functions called in incorrect sequence, or earlier call was unsuccessful.", 2037);
        }
    }
}
