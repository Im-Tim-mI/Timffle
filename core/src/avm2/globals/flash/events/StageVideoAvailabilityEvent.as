package flash.events {
    [API("670")]
    public class StageVideoAvailabilityEvent extends Event {
        public static const STAGE_VIDEO_AVAILABILITY:String = "stageVideoAvailability";

        // Timffle: filled in natively by the Stage when it dispatches the
        // event (null on an event made by ActionScript, as in Flash).
        [Ruffle(NativeAccessible)]
        public const driver:String;
        [Ruffle(NativeAccessible)]
        public const reason:String;

        private var _availability:String;

        public function StageVideoAvailabilityEvent(
            type:String,
            bubbles:Boolean = false,
            cancelable:Boolean = false,
            availability:String = null
        ) {
            super(type, bubbles, cancelable);
            this._availability = availability;
        }

        public function get availability():String {
            return this._availability;
        }
    }
}
