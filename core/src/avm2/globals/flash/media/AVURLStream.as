package flash.media {
    import flash.net.URLRequest;
    import flash.net.URLStream;

    // Timffle: the Adobe Primetime variant of URLStream (Flash Player 19+),
    // usable once `AuthorizedFeatures.enableAVURLStream()` has enabled it
    // with a token from Adobe's authorization service. This player contacts
    // no such service, so no AVURLStream is ever enabled and `load()` fails
    // like the un-enabled `AVLoader.load()` on the real Flash Player 32
    // (`Error #2037`, "Functions called in incorrect sequence"; see
    // AVURLLoader.as). The rest is the plain URLStream; `cookieHeader` is
    // stored.
    [API("688")]
    public class AVURLStream extends URLStream {
        private var _cookieHeader:String = null;

        public function AVURLStream() {
            super();
        }

        override public function load(request:URLRequest):void {
            if (request == null) {
                Error.throwError(TypeError, 2007, "request");
            }
            Error.throwError(Error, 2037);
        }

        public function set cookieHeader(value:String):void {
            this._cookieHeader = value;
        }
    }
}
