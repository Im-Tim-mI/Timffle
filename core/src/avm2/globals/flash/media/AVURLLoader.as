package flash.media {
    import flash.net.URLLoader;
    import flash.net.URLRequest;

    // Timffle: the Adobe Primetime variant of URLLoader (Flash Player 19+):
    // a URLLoader that can also send a cookie header, usable once
    // `AuthorizedFeatures.enableAVURLLoader()` has enabled it with a token
    // from Adobe's authorization service. This player contacts no such
    // service, so no AVURLLoader is ever enabled, and `load()` fails the
    // way the un-enabled sibling `AVLoader.load()` does on the real Flash
    // Player 32 (`Error #2037`, "Functions called in incorrect sequence",
    // measured with timffle/difftest/src/D51DisplayMisc.hx): the enabling
    // call had to come first. Everything else is the plain URLLoader
    // (`close()` is #2029 with nothing open; `cookieHeader` is stored).
    [API("688")]
    public class AVURLLoader extends URLLoader {
        public var stream:AVURLStream = null;
        private var _cookieHeader:String = null;

        public function AVURLLoader(request:URLRequest = null) {
            super(request);
        }

        override public function addEventListener(type:String, listener:Function, useCapture:Boolean = false, priority:int = 0, useWeakReference:Boolean = false):void {
            super.addEventListener(type, listener, useCapture, priority, useWeakReference);
        }

        override public function close():void {
            super.close();
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
