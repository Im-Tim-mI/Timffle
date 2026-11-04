package flash.media {
    import flash.display.DisplayObject
    import flash.net.NetStream

    [Ruffle(InstanceAllocator)]
    public class Video extends DisplayObject {
        private var _deblocking:int;
        private var _smoothing:Boolean;

        public function Video(width:int = 320, height:int = 240) {
            this.init(width, height);
        }

        private native function init(width:int, height:int);

        public function get deblocking():int {
            return this._deblocking;
        }

        public function set deblocking(value:int):void {
            this._deblocking = value;
        }

        public function get smoothing():Boolean {
            return this._smoothing;
        }

        public function set smoothing(value:Boolean):void {
            this._smoothing = value;
        }

        // Timffle: `videoWidth`/`videoHeight` are the size of the stream's
        // frames (0 before anything arrived; an FLV's metadata size until the
        // first frame is decoded; kept after `attachNetStream(null)`), not the
        // Video object's size. Measured on Flash Player 32
        // (timffle/difftest/src/D60Media.hx).
        public native function get videoWidth():int;
        public native function get videoHeight():int;

        public native function attachNetStream(netStream:NetStream):void;

        // Timffle: there is no camera to attach (`Camera.getCamera()` is null
        // on this player, as on a machine without one); Flash accepts
        // `attachCamera(null)` silently and so does this.
        public function attachCamera(camera:Camera):void {
        }

        // Timffle: clears the displayed image, not the stream (the next decoded
        // frame shows again); `videoWidth`/`videoHeight` keep their values.
        public native function clear():void;
    }
}
