package flash.media {
    import flash.display.BitmapData;
    import flash.events.EventDispatcher;
    import flash.geom.Rectangle;
    import flash.utils.ByteArray;

    // Timffle: Flash Player on a machine without a camera. This player has
    // no video capture pipeline on any platform, so `isSupported` is false,
    // `names` is empty and `getCamera()` is null (the AS3 reference: "If no
    // cameras are available or installed, the method returns null"; Flash
    // Player 32 under Wine answers null too, timffle/difftest/src/D60Media.hx).
    // Camera objects only come from `getCamera()`, so `new Camera()` is
    // `ArgumentError #2012` like the other player-created classes. The
    // instance members are nevertheless real: they hold the values a Camera
    // has right after `getCamera()` per the reference (160x120 at 15 fps,
    // bandwidth 16384, quality 0, key frame interval 15, motion level 50 for
    // 2000 ms, muted, no activity) and the setters validate and clamp the
    // way the reference documents.
    public final class Camera extends EventDispatcher {
        private var _width:int = 160;
        private var _height:int = 120;
        private var _fps:Number = 15;
        private var _bandwidth:int = 16384;
        private var _quality:int = 0;
        private var _keyFrameInterval:int = 15;
        private var _loopback:Boolean = false;
        private var _motionLevel:int = 50;
        private var _motionTimeout:int = 2000;
        private var _cursor:Boolean = false;

        public function Camera() {
            throw new ArgumentError("Error #2012: Camera$ class cannot be instantiated.", 2012);
        }

        public static function getCamera(name:String = null):Camera {
            // No camera is installed: null, and the hardware is rescanned on
            // the next call (there is nothing to find).
            return null;
        }

        [API("667")]
        public static function get isSupported():Boolean {
            return false;
        }

        public static function get names():Array {
            return [];
        }

        // The last captured frame. No camera ever captures one here, so the
        // copy methods only validate their arguments: the reference documents
        // TypeError for a null `rect`/`destination` and ArgumentError
        // (kInvalidBitmapDataError, #2015) for a `drawToBitmapData` target
        // smaller than the capture size; nothing is written because there is
        // no frame to copy (never fake video).
        [API("682")]
        public function copyToByteArray(rect:Rectangle, destination:ByteArray):void {
            if (rect == null) {
                Error.throwError(TypeError, 2007, "rect");
            }
            if (destination == null) {
                Error.throwError(TypeError, 2007, "destination");
            }
        }

        [API("682")]
        public function copyToVector(rect:Rectangle, destination:Vector.<uint>):void {
            if (rect == null) {
                Error.throwError(TypeError, 2007, "rect");
            }
            if (destination == null) {
                Error.throwError(TypeError, 2007, "destination");
            }
        }

        [API("682")]
        public function drawToBitmapData(destination:BitmapData):void {
            if (destination == null) {
                Error.throwError(TypeError, 2007, "destination");
            }
            // `width`/`height` of a disposed BitmapData throw #2015 themselves.
            if (destination.width < this._width || destination.height < this._height) {
                throw new ArgumentError("Error #2015: Invalid BitmapData.", 2015);
            }
        }

        // The reference: "1 through 48".
        public function setKeyFrameInterval(keyFrameInterval:int):void {
            this._keyFrameInterval = Math.max(1, Math.min(48, keyFrameInterval));
        }

        public function setLoopback(compress:Boolean = false):void {
            this._loopback = compress;
        }

        // The runtime picks the closest native mode; without hardware the
        // requested mode is kept as is (a frame rate below zero makes no
        // sense and is clamped to 0, NaN too).
        public function setMode(width:int, height:int, fps:Number, favorArea:Boolean = true):void {
            this._width = Math.max(0, width);
            this._height = Math.max(0, height);
            this._fps = fps > 0 ? fps : 0;
        }

        // The reference: motion level 0 through 100, timeout in milliseconds.
        public function setMotionLevel(motionLevel:int, timeout:int = 2000):void {
            this._motionLevel = Math.max(0, Math.min(100, motionLevel));
            this._motionTimeout = Math.max(0, timeout);
        }

        // The reference: bandwidth in bytes per second (0 = unlimited),
        // quality 1 through 100 (0 = vary to stay within the bandwidth).
        public function setQuality(bandwidth:int, quality:int):void {
            this._bandwidth = Math.max(0, bandwidth);
            this._quality = Math.max(0, Math.min(100, quality));
        }

        // Declared by Flash Player's playerglobal but not documented in the
        // reference; stored (it would only matter while capturing).
        [API("688")]
        public function setCursor(value:Boolean):void {
            this._cursor = value;
        }

        // -1 until `Video.attachCamera()` starts a session (never, here).
        public function get activityLevel():Number {
            return -1;
        }

        public function get bandwidth():int {
            return this._bandwidth;
        }

        // The actual capture rate: nothing is being captured.
        public function get currentFPS():Number {
            return 0;
        }

        public function get fps():Number {
            return this._fps;
        }

        public function get height():int {
            return this._height;
        }

        // Position in `Camera.names`: there is no entry for this camera.
        public function get index():int {
            return -1;
        }

        public function get keyFrameInterval():int {
            return this._keyFrameInterval;
        }

        public function get loopback():Boolean {
            return this._loopback;
        }

        public function get motionLevel():int {
            return this._motionLevel;
        }

        public function get motionTimeout():int {
            return this._motionTimeout;
        }

        // Access to the (absent) camera is never granted.
        public function get muted():Boolean {
            return true;
        }

        public function get name():String {
            return "";
        }

        // The reference: "On desktop platforms, the position is always
        // CameraPosition.UNKNOWN" (CameraPosition is an AIR-only class).
        [API("674")]
        public function get position():String {
            return "unknown";
        }

        public function get quality():int {
            return this._quality;
        }

        public function get width():int {
            return this._width;
        }
    }
}
