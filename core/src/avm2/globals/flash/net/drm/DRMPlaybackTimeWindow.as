package flash.net.drm {
    // Timffle: the playback window of a voucher. Vouchers only come from the Adobe
    // Access module (`DRMManager.loadVoucher`), which this player does not have, so
    // no instance is ever created (the class stays abstract); the getters answer for
    // a window that has not started: null dates, period 0.
    [API("667")]
    [Ruffle(Abstract)]
    public final class DRMPlaybackTimeWindow {
        private var _startDate:Date = null;
        private var _endDate:Date = null;
        private var _period:uint = 0;

        public function get endDate():Date {
            return this._endDate;
        }

        public function get period():uint {
            return this._period;
        }

        public function get startDate():Date {
            return this._startDate;
        }
    }
}
