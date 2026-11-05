package flash.net.drm {
    import flash.events.EventDispatcher;
    import flash.events.DRMAuthenticationErrorEvent;
    import flash.events.DRMDeviceGroupErrorEvent;
    import flash.events.DRMErrorEvent;
    import flash.events.DRMReturnVoucherErrorEvent;
    import flash.utils.ByteArray;
    import flash.utils.setTimeout;

    // Timffle: Flash Player without the Adobe Access (Flash Access) DRM module. The
    // singleton exists and `isSupported` is false; every operation that needs the
    // module fails asynchronously with its documented error event carrying runtime
    // error 3344 "Missing Flash Access module" (`drmUpdateNeeded` true, as the module
    // would be installed by `SystemUpdater`): `authenticate` -> authenticationError,
    // `loadVoucher`/`loadPreviewVoucher`/`storeVoucher` -> drmError,
    // `returnVoucher` -> returnVoucherError, `addToDeviceGroup` /
    // `removeFromDeviceGroup` -> addToDeviceGroupError / removeFromDeviceGroupError.
    // Argument checks run synchronously first, as in Flash Player 32 (measured,
    // tests/tests/swfs/avm2/av_drm_arguments): `loadVoucher` with a null content
    // data or a setting that is not a LoadVoucherSetting, `loadPreviewVoucher(null)`
    // and `returnVoucher` without a server or without both ids throw an
    // ArgumentError with errorID 0 and no text; `authenticate`, `addToDeviceGroup`,
    // `removeFromDeviceGroup`, `storeVoucher` and `setAuthenticationToken` accept
    // null arguments. Flash Player 32 itself has the Adobe Access module (its
    // `isSupported` is true), so the events of a player without it could not be
    // measured; error 3344 comes from the runtime error list.
    [API("667")]
    public final class DRMManager extends EventDispatcher {
        private static var _instance:DRMManager = null;
        private static var _constructing:Boolean = false;
        private static var _networkIdleTimeout:Number = 0;
        private var _tokens:Object = {};

        public function DRMManager() {
            if (!DRMManager._constructing) {
                throw new ArgumentError("Error #2012: DRMManager$ class cannot be instantiated.", 2012);
            }
        }

        public static function getDRMManager():DRMManager {
            if (DRMManager._instance == null) {
                DRMManager._constructing = true;
                DRMManager._instance = new DRMManager();
                DRMManager._constructing = false;
            }
            return DRMManager._instance;
        }

        [API("667")]
        public static function get isSupported():Boolean {
            return false;
        }

        public static function get networkIdleTimeout():Number {
            return DRMManager._networkIdleTimeout;
        }

        public static function set networkIdleTimeout(value:Number):void {
            DRMManager._networkIdleTimeout = value;
        }

        [API("674")]
        public function addToDeviceGroup(deviceGroup:DRMDeviceGroup, forceRefresh:Boolean = false):void {
            this.fail(new DRMDeviceGroupErrorEvent(DRMDeviceGroupErrorEvent.ADD_TO_DEVICE_GROUP_ERROR, false, false,
                "Missing Flash Access module.", 3344, 0, deviceGroup, false, true));
        }

        public function authenticate(serverURL:String, domain:String, username:String, password:String):void {
            this.fail(new DRMAuthenticationErrorEvent(DRMAuthenticationErrorEvent.AUTHENTICATION_ERROR, false, false,
                "Missing Flash Access module.", 3344, 0, serverURL, domain));
        }

        [API("667")]
        public function loadPreviewVoucher(contentData:DRMContentData):void {
            if (contentData == null) {
                throw new ArgumentError();
            }
            this.fail(new DRMErrorEvent(DRMErrorEvent.DRM_ERROR, false, false,
                "Missing Flash Access module.", 3344, 0, contentData, false, true));
        }

        public function loadVoucher(contentData:DRMContentData, setting:String):void {
            if (contentData == null) {
                throw new ArgumentError();
            }
            if (setting != LoadVoucherSetting.ALLOW_SERVER && setting != LoadVoucherSetting.FORCE_REFRESH
                && setting != LoadVoucherSetting.LOCAL_ONLY) {
                throw new ArgumentError();
            }
            this.fail(new DRMErrorEvent(DRMErrorEvent.DRM_ERROR, false, false,
                "Missing Flash Access module.", 3344, 0, contentData, false, true));
        }

        [API("674")]
        public function removeFromDeviceGroup(deviceGroup:DRMDeviceGroup):void {
            this.fail(new DRMDeviceGroupErrorEvent(DRMDeviceGroupErrorEvent.REMOVE_FROM_DEVICE_GROUP_ERROR, false, false,
                "Missing Flash Access module.", 3344, 0, deviceGroup, false, true));
        }

        // Deletes every locally cached voucher; there is no cache here, nothing fails.
        public function resetDRMVouchers():void {
        }

        [API("690")]
        public function returnVoucher(inServerURL:String, immediateCommit:Boolean, licenseID:String, policyID:String):void {
            if (inServerURL == null || (licenseID == null && policyID == null)) {
                throw new ArgumentError();
            }
            this.fail(new DRMReturnVoucherErrorEvent(DRMReturnVoucherErrorEvent.RETURN_VOUCHER_ERROR, false, false,
                "Missing Flash Access module.", 3344, 0, inServerURL, licenseID, policyID));
        }

        // The token cache of the (absent) module: kept per server and domain so a
        // later `authenticate` could use it; null clears the entry.
        public function setAuthenticationToken(serverUrl:String, domain:String, token:ByteArray):void {
            var key:String = serverUrl + "\n" + domain;
            if (token == null) {
                delete this._tokens[key];
            } else {
                this._tokens[key] = token;
            }
        }

        [API("674")]
        public function storeVoucher(voucher:ByteArray):void {
            this.fail(new DRMErrorEvent(DRMErrorEvent.DRM_ERROR, false, false,
                "Missing Flash Access module.", 3344, 0, null, false, true));
        }

        // Timffle: the module answers asynchronously and in call order ("calls are
        // queued"): the failures wait in a queue that one timer drains on the next
        // timer tick.
        private var _pending:Array = [];

        private function fail(event:flash.events.Event):void {
            this._pending.push(event);
            if (this._pending.length == 1) {
                var self:DRMManager = this;
                setTimeout(function():void {
                    var events:Array = self._pending;
                    self._pending = [];
                    for each (var pending:flash.events.Event in events) {
                        self.dispatchEvent(pending);
                    }
                }, 0);
            }
        }
    }
}
