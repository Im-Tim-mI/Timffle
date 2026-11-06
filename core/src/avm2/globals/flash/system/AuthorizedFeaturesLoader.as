package flash.system {
    import flash.events.ErrorEvent;
    import flash.events.EventDispatcher;
    import flash.utils.ByteArray;
    import flash.utils.setTimeout;

    // Timffle: the loader that asks Adobe's authorization service for an
    // `AuthorizedFeatures` token (Adobe Primetime: HLS through AVStream, the
    // disk cache, the application installer). This player contacts no
    // authorization service, so it behaves like Flash Player 32 when the
    // service cannot be reached (measured with the network blocked):
    // `loadAuthorizedFeatures()` returns and an `ErrorEvent.ERROR` with
    // `Error #3727` ("Failed to obtain authorization token") follows
    // asynchronously. `loadAuthorizedFeaturesFromData()` cannot validate any
    // signed token and fails the same way; Flash Player 32 does not throw for
    // a null ByteArray. `authorizedFeatures` stays null: no token ever exists,
    // which is exactly what `AuthorizedFeatures` assumes.
    [API("688")]
    public final class AuthorizedFeaturesLoader extends EventDispatcher {
        private var _authorizedFeatures:AuthorizedFeatures = null;

        public function AuthorizedFeaturesLoader() {
            super();
        }

        public function get authorizedFeatures():AuthorizedFeatures {
            return this._authorizedFeatures;
        }

        public function loadAuthorizedFeatures():void {
            this.fail();
        }

        public function loadAuthorizedFeaturesFromData(data:ByteArray):void {
            this.fail();
        }

        // The authorization service is asynchronous, so the failure is too:
        // listeners added right after the call still receive it.
        private function fail():void {
            var self:AuthorizedFeaturesLoader = this;
            setTimeout(function():void {
                self.dispatchEvent(new ErrorEvent(ErrorEvent.ERROR, false, false,
                    "Error #3727: Failed to obtain authorization token.", 3727));
            }, 0);
        }
    }
}
