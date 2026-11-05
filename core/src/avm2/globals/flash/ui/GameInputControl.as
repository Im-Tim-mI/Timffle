package flash.ui {
    import flash.events.EventDispatcher;

    // Timffle: Flash Player without game input devices (`GameInput.isSupported` false,
    // `numDevices` 0). Controls are only created by the runtime for a device, so no instance
    // can exist; the members are those documented for one and the class, like the other
    // runtime-only classes, cannot be instantiated from ActionScript (#2012).
    [API("688")]
    public dynamic class GameInputControl extends EventDispatcher {
        private var _device:GameInputDevice;
        private var _id:String;
        private var _minValue:Number = 0;
        private var _maxValue:Number = 0;
        private var _value:Number = 0;

        public function GameInputControl() {
            throw new ArgumentError("Error #2012: GameInputControl$ class cannot be instantiated.", 2012);
        }

        public function get device():GameInputDevice {
            return this._device;
        }

        public function get id():String {
            return this._id;
        }

        public function get maxValue():Number {
            return this._maxValue;
        }

        public function get minValue():Number {
            return this._minValue;
        }

        public function get value():Number {
            if (this._device == null || !this._device.enabled) {
                throw new Error("Error #2037: Functions called in incorrect sequence, or earlier call was unsuccessful.", 2037);
            }
            return this._value;
        }
    }
}
