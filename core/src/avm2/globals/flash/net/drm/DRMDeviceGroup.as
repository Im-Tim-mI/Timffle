package flash.net.drm {
    // Timffle: a device group registration. Without the Adobe Access module no group
    // is ever joined: the registration fields are what the (absent) server set,
    // null; `name` is the one writable field (the reference: set by the application
    // or by the group event on success).
    [API("692")]
    public final class DRMDeviceGroup {
        private var _serverURL:String = null;
        private var _authenticationMethod:String = null;
        private var _domain:String = null;
        private var _name:String = null;

        public function get serverURL():String {
            return this._serverURL;
        }

        public function get authenticationMethod():String {
            return this._authenticationMethod;
        }

        public function get domain():String {
            return this._domain;
        }

        public function get name():String {
            return this._name;
        }

        public function set name(value:String):void {
            this._name = value;
        }
    }
}
