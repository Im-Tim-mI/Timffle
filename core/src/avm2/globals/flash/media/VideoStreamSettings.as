package flash.media {
    // Timffle: the encoder settings a publishing NetStream would use. Flash
    // Player 32 stores the requested values and clamps them (measured with
    // timffle/difftest/src/D60Media.hx): every property starts at -1 ("same
    // as the Camera"); `setKeyFrameInterval` keeps -1 and clamps anything else
    // to 1..300; `setMode` keeps -1 for width/height and raises other values
    // below 1 to 1, fps keeps -1 and clamps other values (incl. NaN) to at
    // least 0; `setQuality` keeps -1, clamps other values to at least 0 and
    // quality to at most 100. Publishing needs a Camera, which this player
    // does not have, so the values are only ever read back.
    [API("674")]
    public class VideoStreamSettings {
        private var _bandwidth:int = -1;
        private var _codec:String = "Sorenson";
        private var _fps:Number = -1;
        private var _height:int = -1;
        private var _keyFrameInterval:int = -1;
        private var _quality:int = -1;
        private var _width:int = -1;

        public function setKeyFrameInterval(keyFrameInterval:int):void {
            if (keyFrameInterval == -1) {
                this._keyFrameInterval = -1;
            } else {
                this._keyFrameInterval = Math.min(Math.max(keyFrameInterval, 1), 300);
            }
        }

        public function setMode(width:int, height:int, fps:Number):void {
            this._width = width == -1 ? -1 : Math.max(width, 1);
            this._height = height == -1 ? -1 : Math.max(height, 1);
            if (fps == -1) {
                this._fps = -1;
            } else if (isNaN(fps) || fps < 0) {
                this._fps = 0;
            } else {
                this._fps = fps;
            }
        }

        public function setQuality(bandwidth:int, quality:int):void {
            this._bandwidth = bandwidth == -1 ? -1 : Math.max(bandwidth, 0);
            this._quality = quality == -1 ? -1 : Math.min(Math.max(quality, 0), 100);
        }

        public function get bandwidth():int {
            return this._bandwidth;
        }

        public function get codec():String {
            return this._codec;
        }

        public function get fps():Number {
            return this._fps;
        }

        public function get height():int {
            return this._height;
        }

        public function get keyFrameInterval():int {
            return this._keyFrameInterval;
        }

        public function get quality():int {
            return this._quality;
        }

        public function get width():int {
            return this._width;
        }
    }
}
