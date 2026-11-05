package flash.printing {
    import flash.display.Sprite;
    import flash.events.EventDispatcher;
    import flash.geom.Rectangle;

    // Timffle: Flash Player on a platform without printing (the reference's "mobile devices
    // or AIR for TV" case; `Capabilities.hasPrinting` is false here too). `isSupported` is
    // false, `start()` returns false ("the user cancels or an error occurs") and no job is
    // ever active, so the members documented as "available only after a call to start()"
    // (pageWidth/pageHeight/paperWidth/paperHeight) stay 0, `addPage()` throws the
    // documented Error (#2057, the page could not be added) and `send()` "does not succeed"
    // silently. `orientation` is the stored setting (validated against PrintJobOrientation,
    // #2008); the default page orientation of a job that cannot start is portrait.
    public class PrintJob extends EventDispatcher {
        private var _orientation:String = PrintJobOrientation.PORTRAIT;

        public function PrintJob() {
            super();
        }

        [API("667")]
        public static function get isSupported():Boolean {
            return false;
        }

        public function get orientation():String {
            return this._orientation;
        }

        public function set orientation(value:String):void {
            if (value != PrintJobOrientation.PORTRAIT && value != PrintJobOrientation.LANDSCAPE) {
                throw new ArgumentError("Error #2008: Parameter orientation must be one of the accepted values.", 2008);
            }
            this._orientation = value;
        }

        public function get pageHeight():int {
            return 0;
        }

        public function get pageWidth():int {
            return 0;
        }

        public function get paperHeight():int {
            return 0;
        }

        public function get paperWidth():int {
            return 0;
        }

        public function start():Boolean {
            // No printer and no print dialog: the job cannot start.
            return false;
        }

        public function addPage(sprite:Sprite, printArea:Rectangle = null, options:PrintJobOptions = null, frameNum:int = 0):void {
            // start() was not successful, so no page can be added.
            throw new Error("Error #2057: The page could not be added to the print job.", 2057);
        }

        public function send():void {
            // Nothing was started: the documented "does not succeed" case, no exception.
        }
    }
}
