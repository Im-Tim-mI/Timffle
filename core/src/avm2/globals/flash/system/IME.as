package flash.system {
    import flash.events.EventDispatcher;

    // Timffle: this player has no input method editor to drive
    // (`Capabilities.hasIME` false, `IME.isSupported` false): Chinese input
    // reaches the focused text field through the browser's or OS's own
    // composition, which the `IME` class does not control. The AS3 Reference
    // says that without an active IME "calls to IME methods or properties,
    // other than Capabilities.hasIME, will fail": every setter and method
    // throws `Error #2063: Error attempting to execute IME command.` (the
    // runtime error for a failed IME command), while the getters still
    // answer — `enabled` false and `conversionMode`
    // `IMEConversionMode.UNKNOWN`, the read-only value the Reference gives
    // for a mode the player cannot determine. `System.ime` (system.rs)
    // makes the one instance of this abstract class.
    [Ruffle(Abstract)]
    public final class IME extends EventDispatcher {
        private static function imeError():Error {
            return new Error("Error #2063: Error attempting to execute IME command.", 2063);
        }

        public static function get isSupported():Boolean {
            return false;
        }

        public static function get enabled():Boolean {
            return false;
        }

        public static function set enabled(value:Boolean):void {
            throw imeError();
        }

        public static function get conversionMode():String {
            return IMEConversionMode.UNKNOWN;
        }

        public static function set conversionMode(value:String):void {
            throw imeError();
        }

        public static function compositionAbandoned():void {
            throw imeError();
        }

        public static function compositionSelectionChanged(start:int, end:int):void {
            throw imeError();
        }

        public static function doConversion():void {
            throw imeError();
        }

        public static function setCompositionString(composition:String):void {
            throw imeError();
        }
    }
}
