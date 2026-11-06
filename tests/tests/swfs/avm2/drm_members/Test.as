package {
    import flash.display.Sprite;
    import flash.events.DRMAuthenticationErrorEvent;
    import flash.events.DRMDeviceGroupErrorEvent;
    import flash.events.DRMErrorEvent;
    import flash.events.DRMReturnVoucherErrorEvent;
    import flash.events.DRMStatusEvent;
    import flash.events.DRMAuthenticationCompleteEvent;
    import flash.net.drm.AddToDeviceGroupSetting;
    import flash.net.drm.DRMContentData;
    import flash.net.drm.DRMDeviceGroup;
    import flash.net.drm.DRMManager;
    import flash.net.drm.DRMPlaybackTimeWindow;
    import flash.net.drm.DRMVoucher;
    import flash.net.drm.LoadVoucherSetting;
    import flash.net.drm.VoucherAccessInfo;
    import flash.utils.ByteArray;
    import flash.utils.getQualifiedClassName;

    public class Test extends Sprite {
        public function Test() {
            trace("// DRMManager");
            trace("isSupported: " + DRMManager.isSupported);
            var manager:DRMManager = DRMManager.getDRMManager();
            trace("getDRMManager: " + manager);
            trace("singleton: " + (DRMManager.getDRMManager() == manager));
            try {
                new DRMManager();
            } catch (e:Error) {
                trace("new DRMManager(): " + getQualifiedClassName(e) + " #" + e.errorID);
            }
            trace("networkIdleTimeout: " + DRMManager.networkIdleTimeout);
            DRMManager.networkIdleTimeout = 30;
            trace("networkIdleTimeout: " + DRMManager.networkIdleTimeout);

            manager.addEventListener(DRMAuthenticationErrorEvent.AUTHENTICATION_ERROR, function(e:DRMAuthenticationErrorEvent):void {
                trace("authenticationError: #" + e.errorID + " sub " + e.subErrorID + " " + e.serverURL + " " + e.domain + " '" + e.text + "'");
            });
            manager.addEventListener(DRMAuthenticationCompleteEvent.AUTHENTICATION_COMPLETE, function(e:DRMAuthenticationCompleteEvent):void {
                trace("authenticationComplete (unexpected)");
            });
            manager.addEventListener(DRMErrorEvent.DRM_ERROR, function(e:DRMErrorEvent):void {
                trace("drmError: #" + e.errorID + " sub " + e.subErrorID + " contentData " + e.contentData + " systemUpdateNeeded " + e.systemUpdateNeeded + " drmUpdateNeeded " + e.drmUpdateNeeded);
            });
            manager.addEventListener(DRMStatusEvent.DRM_STATUS, function(e:DRMStatusEvent):void {
                trace("drmStatus (unexpected)");
            });
            manager.addEventListener(DRMReturnVoucherErrorEvent.RETURN_VOUCHER_ERROR, function(e:DRMReturnVoucherErrorEvent):void {
                trace("returnVoucherError: #" + e.errorID + " " + e.serverURL + " " + e.licenseID + " " + e.policyID);
            });
            manager.addEventListener(DRMDeviceGroupErrorEvent.ADD_TO_DEVICE_GROUP_ERROR, function(e:DRMDeviceGroupErrorEvent):void {
                trace("addToDeviceGroupError: #" + e.errorID + " " + (e.deviceGroup ? e.deviceGroup.name : null) + " drmUpdateNeeded " + e.drmUpdateNeeded);
            });
            manager.addEventListener(DRMDeviceGroupErrorEvent.REMOVE_FROM_DEVICE_GROUP_ERROR, function(e:DRMDeviceGroupErrorEvent):void {
                trace("removeFromDeviceGroupError: #" + e.errorID + " " + (e.deviceGroup ? e.deviceGroup.name : null));
            });

            try {
                manager.authenticate(null, "d", "u", "p");
            } catch (e:Error) {
                trace("authenticate(null): " + getQualifiedClassName(e) + " #" + e.errorID);
            }
            manager.authenticate("https://drm.example/", "domain", "user", "pass");
            trace("authenticate: queued");

            var data:DRMContentData = new DRMContentData();
            try {
                manager.loadVoucher(data, "bogus");
            } catch (e:Error) {
                trace("loadVoucher(bogus): " + getQualifiedClassName(e) + " #" + e.errorID);
            }
            try {
                manager.loadVoucher(null, LoadVoucherSetting.ALLOW_SERVER);
            } catch (e:Error) {
                trace("loadVoucher(null): " + getQualifiedClassName(e) + " #" + e.errorID);
            }
            manager.loadVoucher(data, LoadVoucherSetting.ALLOW_SERVER);
            manager.loadPreviewVoucher(data);
            trace("loadVoucher/loadPreviewVoucher: queued");

            try {
                manager.returnVoucher(null, true, "l", "p");
            } catch (e:Error) {
                trace("returnVoucher(null url): " + getQualifiedClassName(e) + " #" + e.errorID);
            }
            try {
                manager.returnVoucher("https://drm.example/", true, null, null);
            } catch (e:Error) {
                trace("returnVoucher(no ids): " + getQualifiedClassName(e) + " #" + e.errorID);
            }
            manager.returnVoucher("https://drm.example/", true, "license", null);
            trace("returnVoucher: queued");

            var group:DRMDeviceGroup = new DRMDeviceGroup();
            trace("deviceGroup: " + group.serverURL + " " + group.authenticationMethod + " " + group.domain + " " + group.name);
            group.name = "family";
            trace("deviceGroup.name: " + group.name);
            try {
                manager.addToDeviceGroup(null);
            } catch (e:Error) {
                trace("addToDeviceGroup(null): " + getQualifiedClassName(e) + " #" + e.errorID);
            }
            manager.addToDeviceGroup(group, true);
            manager.removeFromDeviceGroup(group);
            trace("addToDeviceGroup/removeFromDeviceGroup: queued");

            try {
                manager.storeVoucher(null);
            } catch (e:Error) {
                trace("storeVoucher(null): " + getQualifiedClassName(e) + " #" + e.errorID);
            }
            manager.storeVoucher(new ByteArray());
            trace("storeVoucher: queued");
            try {
                manager.setAuthenticationToken(null, "d", null);
            } catch (e:Error) {
                trace("setAuthenticationToken(null): " + getQualifiedClassName(e) + " #" + e.errorID);
            }
            manager.setAuthenticationToken("https://drm.example/", "domain", new ByteArray());
            manager.setAuthenticationToken("https://drm.example/", "domain", null);
            manager.resetDRMVouchers();
            trace("setAuthenticationToken/resetDRMVouchers ok");

            trace("// DRMContentData");
            trace("serverURL: " + data.serverURL);
            trace("authenticationMethod: " + data.authenticationMethod);
            trace("licenseID: " + data.licenseID);
            trace("domain: " + data.domain);
            trace("getVoucherAccessInfo: " + data.getVoucherAccessInfo());
            var info:VoucherAccessInfo = new VoucherAccessInfo();
            trace("VoucherAccessInfo: " + info.displayName + " " + info.authenticationMethod + " " + info.domain + " " + info.policyID + " " + info.deviceGroup);
            var bytes:ByteArray = new ByteArray();
            bytes.writeUTFBytes("not drm metadata");
            try {
                trace("new DRMContentData(bytes): " + new DRMContentData(bytes).serverURL);
            } catch (e:Error) {
                trace("new DRMContentData(bytes): " + getQualifiedClassName(e) + " #" + e.errorID);
            }

            trace("// data classes");
            try {
                new DRMVoucher();
            } catch (e:Error) {
                trace("new DRMVoucher(): " + getQualifiedClassName(e) + " #" + e.errorID);
            }
            try {
                new DRMPlaybackTimeWindow();
            } catch (e:Error) {
                trace("new DRMPlaybackTimeWindow(): " + getQualifiedClassName(e) + " #" + e.errorID);
            }
            trace("AddToDeviceGroupSetting: " + AddToDeviceGroupSetting.ALLOW_SERVER + " " + AddToDeviceGroupSetting.FORCE_REFRESH + " " + AddToDeviceGroupSetting.LOCAL_ONLY);
            trace("LoadVoucherSetting: " + LoadVoucherSetting.ALLOW_SERVER + " " + LoadVoucherSetting.FORCE_REFRESH + " " + LoadVoucherSetting.LOCAL_ONLY);
            trace("// waiting for the events");
        }
    }
}
