package flash.system {
    import flash.errors.IllegalOperationError;
    import flash.events.EventDispatcher;
    import flash.utils.ByteArray;

    // Timffle: Flash Player 11.3's "install an AIR application from this SWF"
    // feature. An installer comes only from
    // `AuthorizedFeatures.createApplicationInstaller()`, and an
    // `AuthorizedFeatures` token only from Adobe's authorization service,
    // which this player never contacts (see AuthorizedFeatures.as). So this
    // is Flash Player without an authorized token: the class is created by
    // the runtime only, so `new ApplicationInstaller()` is `ArgumentError
    // #2012` (like `AuthorizedFeatures` and `SecurityDomain`), and no
    // instance ever exists. Should one be reached anyway, `isInstalled` is
    // false, and `install()` checks its `mode` (`ArgumentError #2008`) and
    // then reports the missing installer module as `IllegalOperationError
    // #2014` ("Feature is not available at this time"). The two static
    // digests describe the strings/icon to the authorization service; the
    // digest algorithm is undocumented and could not be measured, so instead
    // of a made-up digest they report the feature as unavailable (#2014) —
    // after the usual null check (`TypeError #2007`).
    [API("680")]
    public final class ApplicationInstaller extends EventDispatcher {
        public function ApplicationInstaller() {
            throw new ArgumentError("Error #2012: ApplicationInstaller$ class cannot be instantiated.", 2012);
        }

        public function get isInstalled():Boolean {
            return false;
        }

        public function install(mode:String = "install_with_shortcuts"):void {
            if (mode != ApplicationInstallerMode.INSTALL_ONLY
                && mode != ApplicationInstallerMode.INSTALL_WITH_SHORTCUTS
                && mode != ApplicationInstallerMode.SHORTCUTS_ONLY) {
                throw new ArgumentError("Error #2008: Parameter mode must be one of the accepted values.", 2008);
            }
            throw new IllegalOperationError("Error #2014: Feature is not available at this time.", 2014);
        }

        public static function iconDigest(icon:ByteArray):String {
            if (icon == null) {
                throw new TypeError("Error #2007: Parameter icon must be non-null.", 2007);
            }
            throw new IllegalOperationError("Error #2014: Feature is not available at this time.", 2014);
        }

        public static function stringsDigest(strings:XML):String {
            if (strings == null) {
                throw new TypeError("Error #2007: Parameter strings must be non-null.", 2007);
            }
            throw new IllegalOperationError("Error #2014: Feature is not available at this time.", 2014);
        }
    }
}
