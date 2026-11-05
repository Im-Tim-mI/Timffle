package flash.media {
    import flash.events.EventDispatcher;

    // Timffle: the base of the Adobe Primetime (HLS/DASH) media sources that
    // Flash Player 19+ ships behind an `AuthorizedFeatures` token. This
    // player contacts no authorization server (see AuthorizedFeatures.as),
    // so no source ever becomes playable; `dispose()` releases what little a
    // source holds and is idempotent, as in Flash.
    [API("688")]
    public class AVSource extends EventDispatcher {
        private var _disposed:Boolean = false;

        public function AVSource() {
            super();
        }

        public function dispose():void {
            this._disposed = true;
        }
    }
}
