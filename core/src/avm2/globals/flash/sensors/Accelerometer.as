package flash.sensors {
    import flash.events.EventDispatcher;

    // Timffle: Flash Player on a device without an accelerometer. `isSupported` is false; the
    // reference says `muted` is true when access to the sensor is unavailable, and an
    // unsupported sensor never changes state, so no `status` event is ever dispatched (the
    // reference: "On such devices, an Accelerometer object never dispatches a status event").
    // `setRequestedUpdateInterval` keeps its documented validation (ArgumentError for a
    // negative interval) and is otherwise a hint with nothing to apply it to.
    [API("667")]
    public class Accelerometer extends EventDispatcher {
        public static function get isSupported():Boolean {
            return false;
        }

        public function setRequestedUpdateInterval(interval:Number):void {
            if (interval < 0) {
                throw new ArgumentError("Error #2004: One of the parameters is invalid.", 2004);
            }
        }

        public function get muted():Boolean {
            return true;
        }
    }
}
