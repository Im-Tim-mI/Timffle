package flash.accessibility {
    import flash.display.DisplayObject;
    import flash.errors.IllegalOperationError;
    import flash.system.Capabilities;

    // Timffle: the behaviour of Flash Player on a machine without an accessibility
    // bridge (no MSAA screen-reader connection, `Capabilities.hasAccessibility` false):
    // `active` stays false and `updateProperties()` / `sendEvent()` throw
    // IllegalOperationError #2014 ("Feature is not available at this time"), measured
    // on the standalone Flash Player 32.0.0.465 (timffle/difftest/src/D50ClipAcc.hx).
    // The player never sets `hasAccessibility`, so the calls always throw; the check
    // is written against the capability so a build with a bridge would pass through.
    [Ruffle(Abstract)]
    public final class Accessibility {
        private static var _active:Boolean;

        public static function sendEvent(source:DisplayObject, childID:uint, eventType:uint, nonHTML:Boolean = false):void {
            Accessibility.checkAvailable();
            // With a bridge this would hand the MSAA event to the screen reader.
        }

        public static function updateProperties():void {
            Accessibility.checkAvailable();
            // With a bridge this would push every accessibilityProperties change.
        }

        public static function get active():Boolean {
            return _active;
        }

        private static function checkAvailable():void {
            if (!Capabilities.hasAccessibility) {
                throw new IllegalOperationError("Error #2014: Feature is not available at this time.", 2014);
            }
        }
    }
}
