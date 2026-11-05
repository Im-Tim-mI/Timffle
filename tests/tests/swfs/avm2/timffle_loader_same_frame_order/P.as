package {
    import flash.display.*;
    import flash.events.*;
    import flash.net.*;
    import flash.media.*;
    import flash.utils.*;
    import flash.system.fscommand;

    public class P extends MovieClip {
        public var f:int = 0;
        public static const AT_DEF:int = 2;
        public static const K_DEF:String = "loader,loader,bytes,bytes,urlloader";
        public var at:int = 0;
        public var kinds:Array;
        public var bytes:ByteArray;
        public function P() {
            var p:Object = loaderInfo.parameters;
            at = int(p.at || AT_DEF);
            kinds = String(p.k || K_DEF).split(",");
            trace("ctor url=" + (loaderInfo.url.indexOf("http") == 0 ? "http" : "file") + " at=" + at + " k=" + kinds);
            addEventListener(Event.ENTER_FRAME, function(e:Event):void { f++; trace("enterFrame " + f); if (f == at) go("enterFrame"); if (f == 12) fscommand("quit"); });
            addEventListener(Event.FRAME_CONSTRUCTED, function(e:Event):void { trace("frameConstructed " + f); if (at == 101 && f == 0) go("frameConstructed0"); });
            addEventListener(Event.EXIT_FRAME, function(e:Event):void { trace("exitFrame " + f); if (at == 100 && f == 0) go("exitFrame0"); if (at == 102 && f == 1) go("exitFrame1"); });
            hook("root", loaderInfo);
            if (at == 0) go("ctor");
            if (at < 0 && at > -100) setTimeout(function():void { trace("timeout fired f=" + f); go("timeout"); }, -at);
        }
        public function log(k:String, s:String):void { trace("  [" + k + "] " + s + " (f=" + f + ")"); }
        public function go(where:String):void {
            trace("go from " + where + " f=" + f);
            for (var i:int = 0; i < kinds.length; i++) start(kinds[i], i);
        }
        public function start(k0:String, idx:int):void {
            var k:String = k0;
            var base:String = loaderInfo.url.substr(0, loaderInfo.url.lastIndexOf("/") + 1);
            if (k == "loader" || k == "bigloader" || k == "child") {
                var l:Loader = new Loader();
                addChild(l);
                hook(k + idx + "(" + l.name + ")", l.contentLoaderInfo);
                l.load(new URLRequest(k == "loader" ? "a.swf" : k == "child" ? "c.swf" : "big.swf"));
            } else if (k == "pair") {
                var p1:Loader = new Loader(); var p2:Loader = new Loader();
                var sp:Sprite = new Sprite();
                trace("pair names " + p1.name + " " + p2.name + " sprite " + sp.name);
                addChild(p1); addChild(p2);
                hook("p1(" + p1.name + ")", p1.contentLoaderInfo); hook("p2(" + p2.name + ")", p2.contentLoaderInfo);
                p2.load(new URLRequest("a.swf"));
                trace("after p2.load: " + new Sprite().name);
                p1.load(new URLRequest("a.swf"));
                trace("after p1.load: " + new Sprite().name);
                p1.load(new URLRequest("a.swf"));
                trace("after p1.load again: " + new Sprite().name);
            } else if (k == "chain") {
                var c1:URLLoader = new URLLoader();
                hook("c1", c1);
                c1.addEventListener("complete", function(e:Event):void {
                    var c2:URLLoader = new URLLoader(); hook("c2", c2); c2.load(new URLRequest("a.txt"));
                    var cl:Loader = new Loader(); addChild(cl); hook("cl", cl.contentLoaderInfo); cl.load(new URLRequest("a.swf"));
                    log("c1", "started c2 and cl from complete");
                });
                c1.load(new URLRequest("a.txt"));
            } else if (k == "urlloader" || k == "bigurl") {
                var u:URLLoader = new URLLoader();
                hook(k, u);
                u.load(new URLRequest(k == "urlloader" ? "a.txt" : "big.swf"));
            } else if (k == "urlstream") {
                var s:URLStream = new URLStream();
                hook(k, s);
                s.load(new URLRequest("a.txt"));
            } else if (k == "sound") {
                var snd:Sound = new Sound();
                hook(k, snd);
                snd.load(new URLRequest("a.mp3"));
            } else if (k == "bytes") {
                if (bytes == null) { bytes = new ByteArray(); for (var i:int = 0; i < H.S.length; i += 2) bytes.writeByte(parseInt(H.S.substr(i, 2), 16)); }
                var lb:Loader = new Loader();
                addChild(lb);
                hook(k + idx + "(" + lb.name + ")", lb.contentLoaderInfo);
                lb.loadBytes(bytes);
            } else if (k == "fetchbytes") {
                var ub:URLLoader = new URLLoader();
                ub.dataFormat = URLLoaderDataFormat.BINARY;
                ub.addEventListener(Event.COMPLETE, function(e:Event):void { bytes = ub.data; log(k, "got bytes " + bytes.length); });
                ub.load(new URLRequest("a.swf"));
            }
            log(k, "started");
        }
        public function hook(k:String, d:EventDispatcher):void {
            for each (var t:String in ["open", "progress", "init", "httpStatus", "complete", "ioError", "securityError", "id3"]) {
                d.addEventListener(t, function(e:Event):void {
                    var extra:String = "";
                    if (e is ProgressEvent) extra = " " + ProgressEvent(e).bytesLoaded + "/" + ProgressEvent(e).bytesTotal;
                    log(k, e.type + extra);
                });
            }
        }
    }
}
