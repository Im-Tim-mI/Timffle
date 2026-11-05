package flash.ui {
    import flash.geom.Point;
    import flash.display.BitmapData;

    // Timffle: the description of a native cursor, a plain data holder that
    // `Mouse.registerCursor()` reads when the cursor is registered: the frames (`data`, each
    // at most 32x32 pixels -- the size limit is checked at registration, not here, as the
    // reference documents no error for the setters), the animation `frameRate` and the
    // `hotSpot` (default (0,0)). Nothing is validated or copied on assignment, like Flash.
    [API("667")]
    public final class MouseCursorData {
        private var _data:Vector.<BitmapData>;
        private var _frameRate:Number = 0;
        private var _hotSpot:Point = new Point(0, 0);

        public function MouseCursorData() {
        }

        public function get data():Vector.<BitmapData> {
            return this._data;
        }

        public function set data(value:Vector.<BitmapData>):void {
            this._data = value;
        }

        public function get frameRate():Number {
            return this._frameRate;
        }

        public function set frameRate(value:Number):void {
            this._frameRate = value;
        }

        public function get hotSpot():Point {
            return this._hotSpot;
        }

        public function set hotSpot(value:Point):void {
            this._hotSpot = value;
        }
    }
}
