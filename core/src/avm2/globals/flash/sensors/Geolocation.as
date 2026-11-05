package flash.sensors {
    import flash.events.EventDispatcher;

    // Timffle: Flash Player on a device without a location sensor. `isSupported` is false and
    // `muted` is true ("when the sensor becomes unavailable, muted is true"); nothing ever
    // changes, so no `status` or `update` event is dispatched. `setRequestedUpdateInterval`
    // keeps its documented validation (ArgumentError for a negative interval; an interval
    // <= 0 "has no effect") and is otherwise a hint with no sensor to apply it to.
    [API("668")]
    public class Geolocation extends EventDispatcher {
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
