package flash.net.drm {
    import flash.utils.ByteArray;

    // Timffle: a license voucher. Vouchers only come from the Adobe Access module
    // (`DRMManager.loadVoucher` -> drmStatus), which this player does not have, so
    // no instance is ever created (the class stays abstract); the getters read the
    // stored fields of an empty voucher (null, no dates) and `toByteArray()` gives
    // its (empty) serialized form.
    [API("667")]
    [Ruffle(Abstract)]
    public final class DRMVoucher {
        private var _licenseID:String = null;
        private var _offlineLeaseEndDate:Date = null;
        private var _offlineLeaseStartDate:Date = null;
        private var _playbackTimeWindow:DRMPlaybackTimeWindow = null;
        private var _policies:Object = null;
        private var _policyID:String = null;
        private var _serverURL:String = null;
        private var _voucherEndDate:Date = null;
        private var _voucherStartDate:Date = null;
        private var _raw:ByteArray = null;

        [API("690")]
        public function get licenseID():String {
            return this._licenseID;
        }

        public function get offlineLeaseEndDate():Date {
            return this._offlineLeaseEndDate;
        }

        public function get offlineLeaseStartDate():Date {
            return this._offlineLeaseStartDate;
        }

        public function get playbackTimeWindow():DRMPlaybackTimeWindow {
            return this._playbackTimeWindow;
        }

        public function get policies():Object {
            return this._policies;
        }

        [API("690")]
        public function get policyID():String {
            return this._policyID;
        }

        public function get serverURL():String {
            return this._serverURL;
        }

        public function get voucherEndDate():Date {
            return this._voucherEndDate;
        }

        public function get voucherStartDate():Date {
            return this._voucherStartDate;
        }

        [API("674")]
        public function toByteArray():ByteArray {
            var result:ByteArray = new ByteArray();
            if (this._raw != null) {
                result.writeBytes(this._raw);
                result.position = 0;
            }
            return result;
        }
    }
}
