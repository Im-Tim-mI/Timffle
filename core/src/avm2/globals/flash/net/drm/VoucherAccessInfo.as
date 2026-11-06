package flash.net.drm {
    // Timffle: one way of obtaining a voucher for a DRMContentData. The only instance
    // this player ever makes is the default entry of an empty DRMContentData
    // (`getVoucherAccessInfo()` always returns at least that one): no name, no
    // domain, no policy, no device group, and the authentication method is unknown
    // (null) because no metadata was parsed.
    [API("667")]
    public final class VoucherAccessInfo {
        private var _displayName:String = null;
        private var _authenticationMethod:String = null;
        private var _domain:String = null;
        private var _policyID:String = null;
        private var _deviceGroup:DRMDeviceGroup = null;

        public function get displayName():String {
            return this._displayName;
        }

        public function get authenticationMethod():String {
            return this._authenticationMethod;
        }

        public function get domain():String {
            return this._domain;
        }

        [API("690")]
        public function get policyID():String {
            return this._policyID;
        }

        [API("692")]
        public function get deviceGroup():DRMDeviceGroup {
            return this._deviceGroup;
        }
    }
}
