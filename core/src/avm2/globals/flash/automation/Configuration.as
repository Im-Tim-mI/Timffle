package flash.automation {
    // Timffle: `flash.automation` only acts in the automation-enabled Flash Player. In the
    // normal player there is no test-automation configuration: `testAutomationConfiguration`
    // is empty and `deviceConfiguration` is a stored string that configures nothing (the
    // reference documents both as plain String properties; the values an automation player
    // would report are not public).
    [API("667")]
    public class Configuration {
        private static var _deviceConfiguration:String = "";

        public static function get deviceConfiguration():String {
            return _deviceConfiguration;
        }

        public static function set deviceConfiguration(value:String):void {
            _deviceConfiguration = value;
        }

        public static function get testAutomationConfiguration():String {
            return "";
        }
    }
}
