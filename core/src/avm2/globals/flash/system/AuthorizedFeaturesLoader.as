package flash.system {
    import flash.events.ErrorEvent;
    import flash.events.EventDispatcher;
    import flash.utils.ByteArray;
    import flash.utils.setTimeout;

    // Timffle: the loader that asks Adobe's authorization service for an
    // `AuthorizedFeatures` token (Adobe Primetime: HLS through AVStream, the
    // disk cache, the application installer). This player contacts no
    // authorization service, so it behaves like Flash Player on a machine that
    // cannot reach the service: `loadAuthorizedFeatures()` fails
    // asynchronously with the documented `error` event (ErrorEvent.ERROR),
    // `loadAuthorizedFeaturesFromData()` cannot validate any signed token
    // and fails the same way (a null ByteArray is `TypeError #2007` like any
    // non-null parameter), and `authorizedFeatures` stays null: no token
    // ever exists, which is exactly what `AuthorizedFeatures` assumes.
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
            this.fail("Error #2032: Stream Error.");
        }

        public function loadAuthorizedFeaturesFromData(data:ByteArray):void {
            if (data == null) {
                throw new TypeError("Error #2007: Parameter data must be non-null.", 2007);
            }
            this.fail("Error #2032: Stream Error.");
        }

        // The authorization service is asynchronous, so the failure is too:
        // listeners added right after the call still receive it.
        private function fail(text:String):void {
            var self:AuthorizedFeaturesLoader = this;
            setTimeout(function():void {
                self.dispatchEvent(new ErrorEvent(ErrorEvent.ERROR, false, false, text));
            }, 0);
        }
    }
}
