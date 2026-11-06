package flash.media {
    import flash.display.BitmapData;
    import flash.events.EventDispatcher;
    import flash.geom.Rectangle;
    import flash.utils.ByteArray;

    // Timffle: Flash Player on a desktop without a camera. This player has
    // no video capture pipeline on any platform, so `names` is empty and
    // `getCamera()` is null (the AS3 reference: "If no cameras are available
    // or installed, the method returns null"; Flash Player 32 under Wine
    // answers null too). `isSupported` describes the platform, not the
    // devices: Flash Player 32 reports true on a desktop without a camera
    // (measured), and so does this player.
    //
    // `new Camera()` does not throw in Flash Player 32: it makes a Camera that
    // is attached to no device. Such an object answers 0, false or null from
    // every getter and ignores every setter (measured on Flash Player 32,
    // tests/tests/swfs/avm2/stagevideo_bounds); the copy methods still check
    // for null arguments (TypeError #2007). Because `getCamera()` is always
    // null here, that is the only kind of Camera this player can have.
    public final class Camera extends EventDispatcher {
        public function Camera() {
            super();
        }

        public static function getCamera(name:String = null):Camera {
            // No camera is installed: null, and the hardware is rescanned on
            // the next call (there is nothing to find).
            return null;
        }

        [API("667")]
        public static function get isSupported():Boolean {
            return true;
        }

        public static function get names():Array {
            return [];
        }

        // No frame is ever captured, so the copy methods only check their
        // arguments and write nothing.
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
        }

        // The settings of a Camera without a device do not change.
        public function setKeyFrameInterval(keyFrameInterval:int):void {
        }

        public function setLoopback(compress:Boolean = false):void {
        }

        public function setMode(width:int, height:int, fps:Number, favorArea:Boolean = true):void {
        }

        public function setMotionLevel(motionLevel:int, timeout:int = 2000):void {
        }

        public function setQuality(bandwidth:int, quality:int):void {
        }

        // Declared by Flash Player's playerglobal but not documented in the
        // reference; nothing to show a cursor in.
        [API("688")]
        public function setCursor(value:Boolean):void {
        }

        public function get activityLevel():Number {
            return 0;
        }

        public function get bandwidth():int {
            return 0;
        }

        public function get currentFPS():Number {
            return 0;
        }

        public function get fps():Number {
            return 0;
        }

        public function get height():int {
            return 0;
        }

        public function get index():int {
            return 0;
        }

        public function get keyFrameInterval():int {
            return 0;
        }

        public function get loopback():Boolean {
            return false;
        }

        public function get motionLevel():int {
            return 0;
        }

        public function get motionTimeout():int {
            return 0;
        }

        public function get muted():Boolean {
            return false;
        }

        public function get name():String {
            return null;
        }

        // The reference: "On desktop platforms, the position is always
        // CameraPosition.UNKNOWN" (CameraPosition is an AIR-only class).
        [API("674")]
        public function get position():String {
            return "unknown";
        }

        public function get quality():int {
            return 0;
        }

        public function get width():int {
            return 0;
        }
    }
}
