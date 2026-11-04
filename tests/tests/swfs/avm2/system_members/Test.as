package {
import flash.display.Sprite;
import flash.system.IME;
import flash.system.System;
import flash.utils.getQualifiedClassName;

// The flash.system.System members that were missing or stubs. Expected values are those of
// the standalone Flash Player 32.0.0.465 (timffle/difftest/src/D44System.hx, D46SystemExit.hx):
// ime is one IME instance, processCPUUsage 0, vmVersion "2.1 sec cyclone", pause()/resume()
// keep the release player running, memory figures are 4 KiB pages with free+total <= private,
// disposeXML cuts the tree below the node, exit() raises #2017 outside local-trusted.
public class Test extends Sprite {
    public function Test() {
        step("ime", function():void {
            trace(getQualifiedClassName(System.ime) + " same=" + (System.ime == System.ime) + " isSupported=" + IME.isSupported);
            trace("hasEventListener=" + System.ime.hasEventListener("imeComposition"));
        });
        step("processCPUUsage", function():void { trace(System.processCPUUsage); });
        step("vmVersion", function():void { trace(System.vmVersion); });
        step("useCodePage", function():void {
            trace(System.useCodePage);
            System.useCodePage = true;
            trace(System.useCodePage);
            System.useCodePage = false;
            trace(System.useCodePage);
        });
        // The figures are process-wide and the test runner shares its process with other
        // tests, so only per-value properties are checked (not growth or free+total<=private).
        step("memory", function():void {
            var f:Number = System.freeMemory, p:Number = System.privateMemory, t:Number = System.totalMemoryNumber;
            trace("total>0 " + (t > 0) + " free>=0 " + (f >= 0) + " private>0 " + (p > 0));
            trace("pages " + (f % 4096) + " " + (t % 4096) + " " + (p % 4096) + " totalMemory>0 " + (System.totalMemory > 0) + " " + (System.totalMemory % 4096));
        });
        step("disposeXML", function():void {
            var root:XML = <root><a id="1">t</a><b><c/></b></root>;
            var a:XML = root.a[0], b:XML = root.b[0], c:XML = b.c[0], attr:XML = a.attributes()[0];
            System.disposeXML(root);
            trace(root.toXMLString());
            trace("root.children=" + root.children().length() + " a.parent=" + a.parent() + " a.children=" + a.children().length()
                + " a.attributes=" + a.attributes().length() + " b.children=" + b.children().length() + " c.parent=" + c.parent()
                + " attr.parent==a " + (attr.parent() == a));
            var r2:XML = <r><a><b/></a><c/></r>;
            var a2:XML = r2.a[0], b2:XML = a2.b[0];
            System.disposeXML(a2);
            trace(r2.toXMLString().split("\n").join(" ") + " a2.parent==r2 " + (a2.parent() == r2) + " b2.parent=" + b2.parent());
            System.disposeXML(null);
            var t:XML = new XML("hello");
            System.disposeXML(t);
            trace("text '" + t.toXMLString() + "' " + t.nodeKind());
        });
        step("pauseForGCIfCollectionImminent", function():void {
            System.pauseForGCIfCollectionImminent();
            System.pauseForGCIfCollectionImminent(0);
            System.pauseForGCIfCollectionImminent(1);
            System.pauseForGCIfCollectionImminent(-5);
            System.pauseForGCIfCollectionImminent(NaN);
            System.gc();
            trace("ok");
        });
        step("pause/resume", function():void { System.resume(); System.pause(); System.resume(); trace("ok"); });
        step("exit", function():void { System.exit(0); trace("returned"); });
    }

    static function step(label:String, f:Function):void {
        trace("// " + label);
        try {
            f();
        } catch (e:Error) {
            trace(e.name + " #" + e.errorID + ": " + e.message);
        }
    }
}
}
