package flash.media {
    import flash.events.EventDispatcher;
    import flash.events.StageVideoEvent;
    import flash.geom.Point;
    import flash.geom.Rectangle;
    import flash.net.NetStream;
    import flash.utils.setTimeout;

    // Docs are inaccurate here, StageVideo is available in SWF 10, but not
    // available in FP 10,0,42,34.
    //
    // Timffle: Flash Player on a machine where stage video is unavailable
    // (no hardware video surface: the stage reports
    // `StageVideoAvailability.UNAVAILABLE`). The eight objects in
    // `Stage.stageVideos` are made natively (`new StageVideo()` is #2012) and
    // field initializers never run, so the geometry is created on first use.
    // `viewPort`, `zoom`, `pan` and `depth` are stored with the reference's
    // validation (viewPort x/y within -8192..8191, zoom 1..8 per axis, pan
    // -1..1 per axis, otherwise `RangeError` with the documented text and the
    // last valid value kept). Attaching a NetStream (or AVStream) to an
    // unavailable StageVideo answers, on the next frame, with
    // `StageVideoEvent.RENDER_STATE` carrying
    // `RENDER_STATUS_UNAVAILABLE`, the reference's cue to fall back to a
    // `Video` object; the stream is not taken away from any Video object and
    // nothing is drawn, so `videoWidth`/`videoHeight` stay 0 and no colour
    // space is offered.
    [API("667")]
    [Ruffle(Abstract)]
    public class StageVideo extends EventDispatcher {
        private var _viewPort:Rectangle;
        private var _pan:Point;
        private var _zoom:Point;
        private var _depth:int;

        [API("667")]
        public function attachNetStream(netStream:NetStream):void {
            if (netStream != null) {
                this.reportUnavailable();
            }
        }

        // No Camera object can exist on this player (`Camera.getCamera()` is
        // null), so only `null` ever arrives: it detaches, like Flash.
        [API("682")]
        public function attachCamera(theCamera:Camera):void {
        }

        [API("688")]
        public function attachAVStream(avStream:AVStream):void {
            if (avStream != null) {
                this.reportUnavailable();
            }
        }

        private function reportUnavailable():void {
            var self:StageVideo = this;
            setTimeout(function():void {
                self.dispatchEvent(new StageVideoEvent(
                    StageVideoEvent.RENDER_STATE, false, false,
                    StageVideoEvent.RENDER_STATUS_UNAVAILABLE, null
                ));
            }, 0);
        }

        [API("667")]
        public function get colorSpaces():Vector.<String> {
            return new Vector.<String>();
        }

        [API("667")]
        public function get depth():int {
            return this._depth;
        }

        [API("667")]
        public function set depth(value:int):void {
            this._depth = value;
        }

        [API("667")]
        public function get pan():Point {
            if (!this._pan) {
                this._pan = new Point(0, 0);
            }
            return this._pan.clone();
        }

        [API("667")]
        public function set pan(value:Point):void {
            if (value == null) {
                Error.throwError(TypeError, 2007, "pan");
            }
            if (!(value.x >= -1 && value.x <= 1 && value.y >= -1 && value.y <= 1)) {
                throw new RangeError("The Point value is not valid.");
            }
            this._pan = value.clone();
        }

        [API("667")]
        public function get videoHeight():int {
            return 0;
        }

        [API("667")]
        public function get videoWidth():int {
            return 0;
        }

        [API("667")]
        public function get viewPort():Rectangle {
            if (!this._viewPort) {
                this._viewPort = new Rectangle(0, 0, 0, 0);
            }
            return this._viewPort.clone();
        }

        [API("667")]
        public function set viewPort(value:Rectangle):void {
            if (value == null) {
                Error.throwError(TypeError, 2007, "viewPort");
            }
            if (!(value.x >= -8192 && value.x <= 8191 && value.y >= -8192 && value.y <= 8191
                && value.width >= 0 && value.height >= 0)) {
                throw new RangeError("The Rectangle value is not valid.");
            }
            this._viewPort = value.clone();
        }

        [API("667")]
        public function get zoom():Point {
            if (!this._zoom) {
                this._zoom = new Point(1, 1);
            }
            return this._zoom.clone();
        }

        [API("667")]
        public function set zoom(value:Point):void {
            if (value == null) {
                Error.throwError(TypeError, 2007, "zoom");
            }
            if (!(value.x >= 1 && value.x <= 8 && value.y >= 1 && value.y <= 8)) {
                throw new RangeError("The Point value is not valid.");
            }
            this._zoom = value.clone();
        }
    }
}
