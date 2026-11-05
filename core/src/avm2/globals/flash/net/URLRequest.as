package flash.net {
    public final class URLRequest {
        // NOTE - when implementing properties (e.g. `contentType`, `data`, etc.)
        // be sure to also check for them in `URLLoader`

        [Ruffle(NativeAccessible)]
        private var _url:String;

        [Ruffle(NativeAccessible)]
        private var _contentType:String = "application/x-www-form-urlencoded"; // ignored

        [Ruffle(NativeAccessible)]
        private var _requestHeaders:Array = [];

        private var _digest:String;

        [Ruffle(NativeAccessible)]
        private var _method:String = URLRequestMethod.GET;

        [Ruffle(NativeAccessible)]
        private var _data:Object;

        // Timffle: set once a loader has used this request (`useRedirectedURL` needs it).
        [Ruffle(NativeAccessible)]
        private var _loaded:Boolean = false;

        public function URLRequest(url:String = null) {
            this._url = url;
        }

        public function get url():String {
            return this._url;
        }

        public function set url(url:String):void {
            this._url = url;
        }

        public function get method():String {
            return this._method;
        }

        public function set method(value:String):void {
            // The method can apparently either be all upper or lower case, but not mixed.
            if (value !== "GET" && value !== "get" && value !== "POST" && value !== "post") {
                throw new ArgumentError("Error #2008: Parameter method must be one of the accepted values.", 2008);
            }

            // TODO: AIR is supposed to support other methods like PUT or DELETE.
            this._method = value;
        }

        public function get data():Object {
            return this._data;
        }

        public function set data(newData:Object):void {
            this._data = newData;
        }

        public function set contentType(value:String):void {
            this._contentType = value;
        }

        public function get contentType():String {
            return this._contentType;
        }

        public function get requestHeaders():Array {
            return this._requestHeaders;
        }

        public function set requestHeaders(headers:Array):void {
            this._requestHeaders = headers;
        }

        public function get digest():String {
            return this._digest;
        }

        public function set digest(value:String):void {
            this._digest = value;
        }

        // Timffle: Flash Player 32 (measured, timffle/difftest/src/D62Net.hx) only validates the
        // arguments: a null `url` is #2007, a null source is ignored, a source that was never
        // loaded is Error #2037, and a loaded source (redirected or not) leaves `url` unchanged.
        // The player never records a redirected URL (`HTTPStatusEvent.responseURL` is AIR-only),
        // so there is nothing to substitute.
        [API("690")]
        public function useRedirectedURL(sourceRequest:URLRequest, wholeURL:Boolean = false, pattern:* = null, replace:String = null):void {
            if (this._url == null) {
                throw new TypeError("Error #2007: Parameter url must be non-null.", 2007);
            }
            if (sourceRequest == null) {
                return;
            }
            if (!sourceRequest._loaded) {
                throw new Error("Error #2037: Functions called in incorrect sequence, or earlier call was unsuccessful.", 2037);
            }
        }
    }
}
