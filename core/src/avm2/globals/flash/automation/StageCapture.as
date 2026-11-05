package flash.automation {
    import flash.display.BitmapData;
    import flash.events.EventDispatcher;
    import flash.geom.Rectangle;

    // Timffle: `flash.automation` only acts in the automation-enabled Flash Player. In the
    // normal player a StageCapture captures nothing: `capture()` writes no file and
    // dispatches no `capture` event, `captureBitmapData()` has no capture to return (null),
    // `cancel()` has nothing to cancel. The settings (`captureSource`, `clipRect`,
    // `fileNameBase`) are stored as documented; `capturePTS` is the presentation time of the
    // last capture, which never happened (0). An unknown capture type or source is #2008
    // like the other enumerated values.
    // No API version mark: Flash Player 32 shows flash.automation to every SWF version
    // (playerglobal 32.0 has none, avm2/automation_classes runs at SWF 9).
    public class StageCapture extends EventDispatcher {
        public static const CURRENT:String = "current";
        public static const MULTIPLE:String = "multiple";
        public static const NEXT:String = "next";
        public static const RASTER:String = "raster";
        public static const SCREEN:String = "screen";
        public static const STAGE:String = "stage";

        private var _captureSource:String = STAGE;
        private var _clipRect:Rectangle = null;
        private var _fileNameBase:String = "capture";

        public function StageCapture() {
            super();
        }

        public function get capturePTS():Number {
            return 0;
        }

        public function get captureSource():String {
            return this._captureSource;
        }

        public function set captureSource(value:String):void {
            if (value != STAGE && value != SCREEN && value != RASTER) {
                throw new ArgumentError("Error #2008: Parameter captureSource must be one of the accepted values.", 2008);
            }
            this._captureSource = value;
        }

        public function get clipRect():Rectangle {
            return this._clipRect;
        }

        public function set clipRect(value:Rectangle):void {
            this._clipRect = value;
        }

        public function get fileNameBase():String {
            return this._fileNameBase;
        }

        public function set fileNameBase(value:String):void {
            this._fileNameBase = value;
        }

        public function cancel():void {
            // No capture is ever in progress.
        }

        public function capture(type:String):void {
            if (type != CURRENT && type != NEXT && type != MULTIPLE) {
                throw new ArgumentError("Error #2008: Parameter type must be one of the accepted values.", 2008);
            }
            // Not an automation player: nothing is captured and no event is dispatched.
        }

        public function captureBitmapData():BitmapData {
            return null;
        }
    }
}
