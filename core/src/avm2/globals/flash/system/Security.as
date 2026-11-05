package flash.system {
    [Ruffle(Abstract)]
    public final class Security {
        public static native function get pageDomain():String;
        public static native function get sandboxType():String;

        // Timffle: see security.rs for the four members below.
        public static native function get exactSettings():Boolean;
        public static native function set exactSettings(value:Boolean):void;
        [API("667")]
        public static native function get disableAVM1Loading():Boolean;
        [API("667")]
        public static native function set disableAVM1Loading(value:Boolean):void;

        public static native function allowDomain(...domains):void;
        public static native function allowInsecureDomain(...domains):void;
        public static native function loadPolicyFile(url:String):void;
        public static native function showSettings(panel:String = "default"):void;

        [API("661")]
        public static const APPLICATION:String = "application";
        public static const LOCAL_TRUSTED:String = "localTrusted";
        public static const LOCAL_WITH_FILE:String = "localWithFile";
        public static const LOCAL_WITH_NETWORK:String = "localWithNetwork";
        public static const REMOTE:String = "remote";
    }
}
