package flash.system {
    import flash.events.EventDispatcher;
    import flash.events.StatusEvent;
    import flash.utils.clearTimeout;
    import flash.utils.setTimeout;

    // Timffle: `SystemUpdater` fetches the Adobe Access (DRM) module or a new
    // player from Adobe's update servers. This player has no DRM module and
    // no self-updater (and the servers are gone), so it is Flash Player on a
    // platform the updater does not support: `update()` checks its argument
    // (`type` null `TypeError #2007`, not a `SystemUpdaterType` value
    // `ArgumentError #2008`) and then ends the update the documented way,
    // asynchronously — on the next event-loop turn, as a failed download
    // would — with a `status` event, code "DRM.UpdateFailedNotSupported"
    // ("the platform or architecture is unsupported"), level "error". That
    // event ends the update, so a new one may start; a second `update()`
    // while one is pending is ignored (Flash runs one update at a time; what
    // it does with the second call is not documented). `cancel()` drops a
    // pending update silently — the `cancel` event is for the user's cancel
    // in the player's own update dialog, which never appears here.
    [API("667")]
    public class SystemUpdater extends EventDispatcher {
        private var _pending:uint = 0;
        private var _active:Boolean = false;

        public function SystemUpdater() {
            super();
        }

        public function update(type:String):void {
            if (type == null) {
                throw new TypeError("Error #2007: Parameter type must be non-null.", 2007);
            }
            if (type != SystemUpdaterType.DRM && type != SystemUpdaterType.SYSTEM) {
                throw new ArgumentError("Error #2008: Parameter type must be one of the accepted values.", 2008);
            }
            if (this._active) {
                return;
            }
            this._active = true;
            var self:SystemUpdater = this;
            this._pending = setTimeout(function():void {
                self._active = false;
                self.dispatchEvent(new StatusEvent(StatusEvent.STATUS, false, false, "DRM.UpdateFailedNotSupported", "error"));
            }, 0);
        }

        public function cancel():void {
            if (this._active) {
                clearTimeout(this._pending);
                this._active = false;
            }
        }
    }
}
