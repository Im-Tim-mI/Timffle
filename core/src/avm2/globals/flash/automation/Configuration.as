package flash.automation {
    // Timffle: `flash.automation` only acts in the automation-enabled Flash Player. The
    // normal Flash Player 32 (measured) has no device configuration -- `deviceConfiguration`
    // is null and setting it has no effect -- and reports its automation status as the
    // text "Status = 3\r\n".
    // No API version mark: Flash Player 32 shows flash.automation to every SWF version
    // (playerglobal 32.0 has none, avm2/automation_classes runs at SWF 9).
    public class Configuration {
        public static function get deviceConfiguration():String {
            return null;
        }

        public static function set deviceConfiguration(value:String):void {
        }

        public static function get testAutomationConfiguration():String {
            return "Status = 3\r\n";
        }
    }
}
