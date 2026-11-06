package flash.system {
    import flash.events.EventDispatcher;
    import flash.events.StatusEvent;
    import flash.utils.clearTimeout;
    import flash.utils.setTimeout;

    // Timffle: `SystemUpdater` fetches the Adobe Access (DRM) module or a new
    // player from Adobe's update servers. This player has no DRM module and
    // no self-updater (and the servers are gone), so it is Flash Player on a
    // platform the updater does not support. The argument checks are the ones
    // Flash Player 32 makes (measured, timffle/difftest/src/S4System.hx): only
    // one update runs at a time in the whole player -- any `update()` while one
    // is running, on any instance, is `Error #2202`; a type that is not a
    // `SystemUpdaterType` value is `Error #2205`; a null type is `Error #2203`
    // and, as in Flash, leaves the updater busy. A valid type ends the update
    // the documented way, asynchronously -- on the next event-loop turn, as a
    // failed download would -- with a `status` event, code
    // "DRM.UpdateFailedNotSupported" ("the platform or architecture is
    // unsupported"), level "error", which frees the updater (not measured: the
    // real player would contact Adobe). `cancel()` drops this instance's pending
    // update silently -- the `cancel` event is for the user's cancel in the
    // player's own update dialog, which never appears here.
    [API("667")]
    public class SystemUpdater extends EventDispatcher {
        private static var _busy:Boolean = false;
        private var _pending:uint = 0;
        private var _active:Boolean = false;

        public function SystemUpdater() {
            super();
        }

        public function update(type:String):void {
            if (_busy) {
                throw new Error("Error #2202: Only one SystemUpdater action is allowed at a time.", 2202);
            }
            if (type == null) {
                _busy = true;
                throw new Error("Error #2203: The requested SystemUpdater action cannot be completed.", 2203);
            }
            if (type != SystemUpdaterType.DRM && type != SystemUpdaterType.SYSTEM) {
                throw new Error("Error #2205: Invalid update type " + type + ".", 2205);
            }
            _busy = true;
            this._active = true;
            var self:SystemUpdater = this;
            this._pending = setTimeout(function():void {
                self._active = false;
                _busy = false;
                self.dispatchEvent(new StatusEvent(StatusEvent.STATUS, false, false, "DRM.UpdateFailedNotSupported", "error"));
            }, 0);
        }

        public function cancel():void {
            if (this._active) {
                clearTimeout(this._pending);
                this._active = false;
                _busy = false;
            }
        }
    }
}
