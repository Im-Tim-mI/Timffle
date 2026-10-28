import flash.display.MovieClip;
import flash.events.Event;

// Timffle: a script-initiated gotoAndStop on a SWF 9 timeline clip must construct the
// new keyframe's children and run their frame-1 scripts in the same frame, as real Flash does.
class Test extends MovieClip {
    public static var f:Int = 0;
    public static var dir:Dir;
    public static var stopped:Bool = false;
    // Referenced so Haxe compiles the symbol-bound classes (they are only reached through SymbolClass).
    static var keep:Array<Class<Dynamic>> = [BodyA, BodyB, BodyC];

    public function new() {
        super();
        out("Test ctor");
        dir = new Dir();
        addChild(dir);
        out("Dir added, currentLabel=" + dir.currentLabel + " child=" + childName());
        addEventListener(Event.ENTER_FRAME, onEnter);
        addEventListener("frameConstructed", onConstructed);
        addEventListener("exitFrame", onExit);
        flash.Lib.current.addFrameScript(4, rootScript5);
    }

    static function childName():String {
        return dir.numChildren > 0 ? Std.string(Type.getClassName(Type.getClass(dir.getChildAt(0)))) : "none";
    }

    function onEnter(e:Event) {
        if (stopped) return;
        f++;
        out("enterFrame f=" + f + " dir=" + dir.currentLabel + " child=" + childName());
        if (f == 2) { dir.gotoAndStop("b"); out("goto b (enterFrame) f=" + f + " child=" + childName()); }
        if (f == 8) { dir.gotoAndStop("a"); out("goto a (enterFrame) f=" + f + " child=" + childName()); }
        if (f == 12) {
            stopped = true;
            removeEventListener(Event.ENTER_FRAME, onEnter);
            removeEventListener("frameConstructed", onConstructed);
            removeEventListener("exitFrame", onExit);
            flash.Lib.current.stop();
            out("done");
        }
    }

    static var script5Ran = false;
    static var exitGotoDone = false;
    function rootScript5() {
        // In SWF 10+ the nested goto frame runs the stage's frame scripts again, which would
        // re-enter this script forever; record the re-entry and bail out.
        if (script5Ran) { out("root framescript re-entered f=" + f); return; }
        script5Ran = true;
        out("root framescript f=" + f);
        dir.gotoAndStop("c");
        out("goto c (framescript) f=" + f + " child=" + childName());
    }

    function onConstructed(e:Event) {
        if (stopped) return;
        out("frameConstructed f=" + f + " child=" + childName());
    }

    function onExit(e:Event) {
        if (stopped) return;
        out("exitFrame f=" + f + " child=" + childName());
        // One-shot: in SWF 10+ the nested goto frame broadcasts exitFrame again.
        if (f == 10 && !exitGotoDone) { exitGotoDone = true; dir.gotoAndStop("b"); out("goto b (exitFrame) f=" + f + " child=" + childName()); }
    }

    static var buf:Array<String> = [];
    public static function out(s:String) {
        #if harness
        buf.push(s);
        if (s == "done") {
            var req = new flash.net.URLRequest("http://127.0.0.1:18765/report?runner=flash&test=REPORTNAME");
            req.method = flash.net.URLRequestMethod.POST; req.contentType = "text/plain";
            req.data = buf.join("\n") + "\n";
            new flash.net.URLLoader().load(req);
        }
        #else
        flash.Lib.trace(s);
        #end
    }

    static function main() { flash.Lib.current.addChild(new Test()); }
}
