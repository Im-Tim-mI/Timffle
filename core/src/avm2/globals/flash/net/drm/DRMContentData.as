package flash.net.drm {
    import flash.errors.IllegalOperationError;
    import flash.utils.ByteArray;

    // Timffle: the DRM metadata of a protected file. Parsing the metadata is done by
    // the Adobe Access module, which this player does not have: a DRMContentData
    // built from bytes fails with IllegalOperationError #2014 ("Feature is not
    // available at this time"), the error Flash Player uses for a feature that is
    // not present on the system. An empty DRMContentData (no bytes) is allowed and
    // describes nothing: every property is null and `getVoucherAccessInfo()` returns
    // the single default entry the reference promises.
    [API("667")]
    public class DRMContentData {
        private var _serverURL:String = null;
        private var _authenticationMethod:String = null;
        private var _licenseID:String = null;
        private var _domain:String = null;

        [API("667")]
        public function DRMContentData(rawData:ByteArray = null) {
            if (rawData != null) {
                throw new IllegalOperationError("Error #2014: Feature is not available at this time.", 2014);
            }
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
            var result:Vector.<VoucherAccessInfo> = new Vector.<VoucherAccessInfo>();
            result.push(new VoucherAccessInfo());
            return result;
        }
    }
}
