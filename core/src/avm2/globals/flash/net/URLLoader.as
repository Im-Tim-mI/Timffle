package flash.net {
    import flash.errors.IOError;
    import flash.events.EventDispatcher;
    import flash.net.URLRequest;

    public class URLLoader extends EventDispatcher {
        [Ruffle(NativeAccessible)]
        public var data:*;

        [Ruffle(NativeAccessible)]
        public var dataFormat:String = "text";

        [Ruffle(NativeAccessible)]
        public var bytesLoaded:uint;

        [Ruffle(NativeAccessible)]
        public var bytesTotal:uint;

        // Bumped by `load()` and `close()`. A download only touches this object
        // while its generation is still current, so a closed or replaced
        // download delivers no further data or events.
        [Ruffle(NativeAccessible)]
        private var _generation:uint = 0;

        // `true` from `load()` until `close()`: like Flash, `close()` only succeeds
        // while a stream is open, even when the load has long since completed or failed.
        private var _open:Boolean = false;

        public function URLLoader(request:URLRequest = null) {
            if (request != null) {
                this.load(request);
            }
        }

        public function load(request:URLRequest):void {
            this._generation++;
            this._open = true;
            this._load(request, this._generation);
        }

        private native function _load(request:URLRequest, generation:uint):void;

        public function close():void {
            if (!this._open) {
                throw new IOError("Error #2029: This URLStream object does not have a stream opened.", 2029);
            }
            this._generation++;
            this._open = false;
        }
    }
}
