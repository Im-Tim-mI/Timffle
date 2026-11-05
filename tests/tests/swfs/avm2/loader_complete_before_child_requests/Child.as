package {
    import flash.display.MovieClip;
    import flash.events.Event;
    import flash.net.URLLoader;
    import flash.net.URLRequest;

    public class Child extends MovieClip {
        private var data:URLLoader = new URLLoader();

        public function Child() {
            trace("child constructed");
            data.addEventListener(Event.COMPLETE, onData);
            data.load(new URLRequest("data.txt"));
            stop();
        }

        private function onData(e:Event):void {
            trace("child data: " + data.data);
        }
    }
}
