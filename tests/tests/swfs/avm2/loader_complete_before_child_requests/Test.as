package {
    import flash.display.Loader;
    import flash.display.MovieClip;
    import flash.events.Event;
    import flash.net.URLLoader;
    import flash.net.URLLoaderDataFormat;
    import flash.net.URLRequest;
    import flash.utils.ByteArray;

    // The loaded child's constructor starts a URLLoader. Flash Player constructs the
    // child, runs its first frame and fires the Loader's `init` and `complete` in the
    // same frame, so the child's own request can only complete afterwards
    // (摩爾莊園's TimesArkPanel relies on `init(data)` from the `complete` listener
    // running before its XML arrives). Checked for `Loader.load` and `Loader.loadBytes`.
    public class Test extends MovieClip {
        private var loader:Loader = new Loader();
        private var loader2:Loader = new Loader();
        private var bytes:URLLoader = new URLLoader();

        public function Test() {
            loader.contentLoaderInfo.addEventListener(Event.INIT, onInit);
            loader.contentLoaderInfo.addEventListener(Event.COMPLETE, onComplete);
            addChild(loader);
            trace("load child.swf");
            loader.load(new URLRequest("child.swf"));
        }

        private function onInit(e:Event):void {
            trace("loader init");
        }

        private function onComplete(e:Event):void {
            trace("loader complete");
            bytes.dataFormat = URLLoaderDataFormat.BINARY;
            bytes.addEventListener(Event.COMPLETE, onBytes);
            bytes.load(new URLRequest("child.swf"));
        }

        private function onBytes(e:Event):void {
            trace("loadBytes child.swf");
            loader2.contentLoaderInfo.addEventListener(Event.INIT, onInit2);
            loader2.contentLoaderInfo.addEventListener(Event.COMPLETE, onComplete2);
            addChild(loader2);
            loader2.loadBytes(bytes.data as ByteArray);
        }

        private function onInit2(e:Event):void {
            trace("loader2 init");
        }

        private function onComplete2(e:Event):void {
            trace("loader2 complete");
        }
    }
}
