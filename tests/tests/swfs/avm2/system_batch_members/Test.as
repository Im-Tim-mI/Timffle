package {
    import flash.display.Loader;
    import flash.display.Sprite;
    import flash.events.Event;
    import flash.events.IOErrorEvent;
    import flash.events.SecurityErrorEvent;
    import flash.events.StatusEvent;
    import flash.net.SharedObject;
    import flash.net.URLRequest;
    import flash.profiler.profile;
    import flash.profiler.showRedrawRegions;
    import flash.system.ApplicationInstaller;
    import flash.system.ApplicationInstallerMode;
    import flash.system.AuthorizedFeatures;
    import flash.system.Capabilities;
    import flash.system.IME;
    import flash.system.IMEConversionMode;
    import flash.system.Security;
    import flash.system.SecurityDomain;
    import flash.system.System;
    import flash.system.SystemUpdater;
    import flash.system.SystemUpdaterType;
    import flash.utils.ByteArray;
    import flash.utils.getQualifiedClassName;

    public class Test extends Sprite {
        private static function tryCall(name:String, fn:Function):void {
            try {
                fn();
                trace(name + ": no error");
            } catch (e:Error) {
                trace(name + ": " + getQualifiedClassName(e) + " " + e.message + " (" + e.errorID + ")");
            }
        }

        public function Test() {
            trace("// flash.profiler");
            profile(true);
            profile(false);
            showRedrawRegions(true);
            showRedrawRegions(false, 0x00FF00);
            trace("profile/showRedrawRegions: no error");

            trace("// flash.system.IME");
            trace("IME.isSupported: " + IME.isSupported);
            trace("Capabilities.hasIME: " + Capabilities.hasIME);
            trace("IME.enabled: " + IME.enabled);
            trace("IME.conversionMode: " + IME.conversionMode);
            trace("System.ime is IME: " + (System.ime is IME));
            tryCall("IME.enabled = true", function():void { IME.enabled = true; });
            tryCall("IME.enabled = false", function():void { IME.enabled = false; });
            tryCall("IME.conversionMode = KOREAN", function():void { IME.conversionMode = IMEConversionMode.KOREAN; });
            tryCall("IME.doConversion()", function():void { IME.doConversion(); });
            tryCall("IME.setCompositionString()", function():void { IME.setCompositionString("abc"); });
            tryCall("IME.compositionAbandoned()", function():void { IME.compositionAbandoned(); });
            tryCall("IME.compositionSelectionChanged()", function():void { IME.compositionSelectionChanged(0, 1); });
            trace("IME.enabled after: " + IME.enabled);
            trace("IME.conversionMode after: " + IME.conversionMode);

            trace("// flash.system.Security");
            trace("exactSettings: " + Security.exactSettings);
            Security.exactSettings = false;
            trace("exactSettings after = false: " + Security.exactSettings);
            Security.exactSettings = true;
            trace("exactSettings after = true: " + Security.exactSettings);
            var so:SharedObject = SharedObject.getLocal("exactSettingsTest");
            trace("getLocal: " + (so != null));
            tryCall("exactSettings = true after use", function():void { Security.exactSettings = true; });
            tryCall("exactSettings = false after use", function():void { Security.exactSettings = false; });
            trace("exactSettings: " + Security.exactSettings);
            trace("disableAVM1Loading: " + Security.disableAVM1Loading);
            tryCall("loadPolicyFile(null)", function():void { Security.loadPolicyFile(null); });
            tryCall("loadPolicyFile(http)", function():void { Security.loadPolicyFile("http://localhost:1/crossdomain.xml"); });
            tryCall("loadPolicyFile(http) again", function():void { Security.loadPolicyFile("http://localhost:1/crossdomain.xml"); });
            tryCall("loadPolicyFile(xmlsocket)", function():void { Security.loadPolicyFile("xmlsocket://localhost:843"); });
            tryCall("showSettings()", function():void { Security.showSettings(); });
            tryCall("showSettings(privacy)", function():void { Security.showSettings("privacy"); });
            tryCall("showSettings(bogus)", function():void { Security.showSettings("bogus"); });

            trace("// flash.system.SecurityDomain");
            trace("domainID: " + SecurityDomain.currentDomain.domainID);
            trace("domainID type: " + typeof SecurityDomain.currentDomain.domainID);

            trace("// flash.system.ApplicationInstaller");
            trace("INSTALL_ONLY: " + ApplicationInstallerMode.INSTALL_ONLY);
            trace("INSTALL_WITH_SHORTCUTS: " + ApplicationInstallerMode.INSTALL_WITH_SHORTCUTS);
            trace("SHORTCUTS_ONLY: " + ApplicationInstallerMode.SHORTCUTS_ONLY);
            tryCall("new ApplicationInstaller()", function():void { new ApplicationInstaller(); });
            tryCall("ApplicationInstaller.iconDigest(null)", function():void { ApplicationInstaller.iconDigest(null); });
            tryCall("ApplicationInstaller.iconDigest(bytes)", function():void { ApplicationInstaller.iconDigest(new ByteArray()); });
            tryCall("ApplicationInstaller.stringsDigest(null)", function():void { ApplicationInstaller.stringsDigest(null); });
            tryCall("ApplicationInstaller.stringsDigest(xml)", function():void { ApplicationInstaller.stringsDigest(<strings/>); });
            tryCall("new AuthorizedFeatures()", function():void { new AuthorizedFeatures(); });

            trace("// flash.system.SystemUpdater");
            var updater:SystemUpdater = new SystemUpdater();
            tryCall("update(bogus)", function():void { updater.update("bogus"); });
            updater.addEventListener(StatusEvent.STATUS, function(e:StatusEvent):void {
                trace("updater status: " + e.code + " / " + e.level);
            });
            updater.addEventListener(Event.COMPLETE, function(e:Event):void {
                trace("updater complete");
            });
            tryCall("update(DRM)", function():void { updater.update(SystemUpdaterType.DRM); });
            tryCall("update(SYSTEM) while pending", function():void { updater.update(SystemUpdaterType.SYSTEM); });
            var cancelled:SystemUpdater = new SystemUpdater();
            cancelled.addEventListener(StatusEvent.STATUS, function(e:StatusEvent):void {
                trace("cancelled updater status (should not happen)");
            });
            // Flash Player 32 runs one update in the whole player: the DRM update above is
            // still pending, so this is Error #2202 (measured).
            tryCall("update on another instance", function():void { cancelled.update(SystemUpdaterType.SYSTEM); });
            cancelled.cancel();
            cancelled.cancel();
            trace("cancel(): no error");
            // Last, because a null type leaves the updater busy for good (measured).
            tryCall("update(null)", function():void { new SystemUpdater().update(null); });

            trace("// Security.disableAVM1Loading");
            Security.disableAVM1Loading = true;
            trace("disableAVM1Loading: " + Security.disableAVM1Loading);
            var loader:Loader = new Loader();
            loader.contentLoaderInfo.addEventListener(SecurityErrorEvent.SECURITY_ERROR, function(e:SecurityErrorEvent):void {
                trace("securityError: " + e.text + " (" + e.errorID + ")");
                trace("content after block: " + loader.content);
                Security.disableAVM1Loading = false;
                trace("disableAVM1Loading: " + Security.disableAVM1Loading);
                loader.load(new URLRequest("avm1.swf"));
            });
            loader.contentLoaderInfo.addEventListener(IOErrorEvent.IO_ERROR, function(e:IOErrorEvent):void {
                trace("ioError: " + e.text);
            });
            loader.contentLoaderInfo.addEventListener(Event.COMPLETE, function(e:Event):void {
                trace("complete: content is " + getQualifiedClassName(loader.content));
            });
            loader.load(new URLRequest("avm1.swf"));
            trace("load(avm1.swf) started");
        }
    }
}
