package {
    import flash.display.*;
    import flash.events.*;
    import flash.net.*;
    public class C extends MovieClip {
        public var f:int = 0;
        public function C() {
            trace("    C ctor");
            addEventListener(Event.ENTER_FRAME, function(e:Event):void { f++; trace("    C enterFrame " + f); if (f == 1) go("C f1"); });
            var u:URLLoader = new URLLoader();
            u.addEventListener("open", function(e:Event):void { trace("    [C-url ctor] open (cf=" + f + ")"); });
            u.addEventListener("complete", function(e:Event):void { trace("    [C-url ctor] complete (cf=" + f + ")"); });
            u.load(new URLRequest("a.txt"));
            var l:Loader = new Loader();
            l.contentLoaderInfo.addEventListener("open", function(e:Event):void { trace("    [C-ldr ctor] open (cf=" + f + ")"); });
            l.contentLoaderInfo.addEventListener("init", function(e:Event):void { trace("    [C-ldr ctor] init (cf=" + f + ")"); });
            l.contentLoaderInfo.addEventListener("complete", function(e:Event):void { trace("    [C-ldr ctor] complete (cf=" + f + ")"); });
            l.load(new URLRequest("a.swf"));
        }
        public function go(w:String):void {
            var u:URLLoader = new URLLoader();
            u.addEventListener("open", function(e:Event):void { trace("    [C-url f1] open (cf=" + f + ")"); });
            u.addEventListener("complete", function(e:Event):void { trace("    [C-url f1] complete (cf=" + f + ")"); });
            u.load(new URLRequest("a.txt"));
        }
    }
}
