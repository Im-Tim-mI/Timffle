/** Probe (no golden): flash.system.System members Ruffle still stubs or lacks (ime, pause/resume,
 *  processCPUUsage, useCodePage, vmVersion, disposeXML, memory getters, exit). Members are read by
 *  name so AIR-only ones are reachable without Haxe externs. Build with -swf-version 32, run in the
 *  standalone Flash Player 32 projector (served over HTTP, i.e. the remote sandbox). */
class D44System {
	static var sys:Dynamic;

	// catch flash.errors.Error only: Haxe's catch(e:Dynamic) wrapper aborts in the release player
	static function step(label:String, f:Void->Void) {
		try {
			f();
		} catch (e:flash.errors.Error) {
			H.log(label + " THREW " + e.name + " #" + e.errorID + " " + e.message);
		}
	}

	static function main() {
		H.init("d44system");
		sys = untyped __global__["flash.system.System"];
		var qn:Dynamic = untyped __global__["flash.utils.getQualifiedClassName"];
		for (n in ["ime", "processCPUUsage", "useCodePage", "vmVersion", "freeMemory", "privateMemory",
				"totalMemoryNumber", "totalMemory"]) {
			step(n, function() {
				var v:Dynamic = Reflect.field(sys, n);
				H.log(n + " (" + qn(v) + ") = " + Std.string(v));
			});
		}
		step("ime same", function() H.log("ime same = " + (sys.ime == sys.ime)));
		step("ime is IME class", function() {
			var ime:Dynamic = untyped __global__["flash.system.IME"];
			H.log("ime == IME class: " + (sys.ime == ime) + ", ime.isSupported=" + ime.isSupported + ", ime.enabled=" + ime.enabled);
		});
		step("ime.hasEventListener", function() H.log("ime.hasEventListener(imeComposition) = " + sys.ime.hasEventListener("imeComposition")));
		for (v in [true, false, true]) {
			step("useCodePage=" + v, function() { sys.useCodePage = v; H.log("useCodePage=" + v + " -> " + sys.useCodePage); });
		}
		step("useCodePage=false", function() sys.useCodePage = false);
		step("memory relation", function() {
			var f:Float = sys.freeMemory, p:Float = sys.privateMemory, t:Float = sys.totalMemoryNumber;
			H.log("free<=private " + (f <= p) + ", total<=private " + (t <= p) + ", total+free<=private " + (t + f <= p) + ", free%4096=" + (f % 4096) + ", total%4096=" + (t % 4096) + ", private%4096=" + (p % 4096));
		});
		step("alloc then memory", function() {
			var keep = [];
			for (i in 0...200000) keep.push({a: i, b: "x" + i});
			H.log("after 200k objects: total=" + sys.totalMemoryNumber + " free=" + sys.freeMemory + " private=" + sys.privateMemory + " keep=" + keep.length);
		});
		step("disposeXML", function() {
			var xml:Dynamic = untyped __global__["XML"];
			var root:Dynamic = Type.createInstance(xml, ["<root><a id='1'>t</a><b><c/></b></root>"]);
			var a:Dynamic = untyped root.a[0];
			var b:Dynamic = untyped root.b[0];
			var c:Dynamic = untyped b.c[0];
			var attr:Dynamic = untyped a.attributes()[0];
			H.log("before: a.parent==root " + (untyped a.parent() == root) + ", root.children=" + untyped root.children().length());
			sys.disposeXML(root);
			H.log("after root: " + root.toXMLString());
			H.log("after root.children().length()=" + untyped root.children().length() + " root.name()=" + root.name());
			H.log("after a: '" + a.toXMLString() + "' a.parent()=" + untyped a.parent() + " a.children=" + untyped a.children().length() + " a.attributes=" + untyped a.attributes().length() + " a.name=" + a.name());
			H.log("after b: '" + b.toXMLString() + "' b.parent()=" + untyped b.parent() + " c: '" + c.toXMLString() + "' c.parent()=" + untyped c.parent());
			H.log("after attr: '" + attr.toXMLString() + "' attr.parent()=" + untyped attr.parent() + " attr.name()=" + attr.name());
			H.log("root.a.length=" + untyped root.a.length());
		});
		step("disposeXML(child only)", function() {
			var xml:Dynamic = untyped __global__["XML"];
			var root:Dynamic = Type.createInstance(xml, ["<r><a><b/></a><c/></r>"]);
			var a:Dynamic = untyped root.a[0];
			sys.disposeXML(a);
			H.log("root after child dispose: " + root.toXMLString() + " children=" + untyped root.children().length() + " a.parent()=" + untyped a.parent());
		});
		step("disposeXML(null)", function() { sys.disposeXML(null); H.log("disposeXML(null) ok"); });
		step("disposeXML(text node)", function() {
			var xml:Dynamic = untyped __global__["XML"];
			var t:Dynamic = Type.createInstance(xml, ["hello"]);
			sys.disposeXML(t);
			H.log("text after dispose: '" + t.toXMLString() + "' nodeKind=" + t.nodeKind());
		});
		step("pauseForGCIfCollectionImminent()", function() { sys.pauseForGCIfCollectionImminent(); H.log("pauseForGC() ok"); });
		step("pauseForGCIfCollectionImminent(0)", function() { sys.pauseForGCIfCollectionImminent(0); H.log("pauseForGC(0) ok"); });
		step("pauseForGCIfCollectionImminent(1)", function() { sys.pauseForGCIfCollectionImminent(1); H.log("pauseForGC(1) ok"); });
		step("pauseForGCIfCollectionImminent(-5)", function() { sys.pauseForGCIfCollectionImminent(-5); H.log("pauseForGC(-5) ok"); });
		step("pauseForGCIfCollectionImminent(NaN)", function() { sys.pauseForGCIfCollectionImminent(Math.NaN); H.log("pauseForGC(NaN) ok"); });
		step("gc", function() { sys.gc(); H.log("gc ok total=" + sys.totalMemoryNumber); });
		H.log("vmVersion again = " + sys.vmVersion);
		// exit()/pause()/resume() are probed by D46SystemExit (they may end the player).
		haxe.Timer.delay(function() H.done(), 300);
	}
}
