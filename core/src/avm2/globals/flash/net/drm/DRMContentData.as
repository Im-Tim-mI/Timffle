package flash.net.drm {
    import flash.utils.ByteArray;

    // Timffle: the DRM metadata of a protected file. Parsing the metadata is done by
    // the Adobe Access module, which this player does not have, so no metadata is
    // ever read: like Flash Player 32 with bytes that are not DRM metadata, the
    // constructor accepts any ByteArray (or none), every property is null and
    // `getVoucherAccessInfo()` is null (measured, tests/tests/swfs/avm2/av_drm_arguments).
    [API("667")]
    public class DRMContentData {
        private var _serverURL:String = null;
        private var _authenticationMethod:String = null;
        private var _licenseID:String = null;
        private var _domain:String = null;

        [API("667")]
        public function DRMContentData(rawData:ByteArray = null) {
        }

        public function get serverURL():String {
            return this._serverURL;
        }

        public function get authenticationMethod():String {
            return this._authenticationMethod;
        }

        public function get licenseID():String {
            return this._licenseID;
        }

        public function get domain():String {
            return this._domain;
        }

        [API("667")]
        public function getVoucherAccessInfo():Vector.<VoucherAccessInfo> {
            return null;
        }
    }
}
