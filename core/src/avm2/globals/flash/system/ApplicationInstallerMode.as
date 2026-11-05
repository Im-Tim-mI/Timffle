package flash.system {
    // Timffle: the `mode` values of `ApplicationInstaller.install()`
    // (Flash Player 11.3).
    [API("680")]
    public final class ApplicationInstallerMode {
        public static const INSTALL_ONLY:String = "install_only";
        public static const INSTALL_WITH_SHORTCUTS:String = "install_with_shortcuts";
        public static const SHORTCUTS_ONLY:String = "shortcuts_only";
    }
}
