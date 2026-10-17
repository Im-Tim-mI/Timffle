import flash.utils.ByteArray;

/** Shared helpers for multi-step tests.
 * Lines starting with "~" carry timing/chunking info that legitimately varies
 * between runs; compare.py ignores them. */
class U {
	static var steps:Array<{name:String, f:(Void->Void)->Void}> = [];

	/** Register a step; f receives `next` and must call it exactly once. */
	public static function step(name:String, f:(Void->Void)->Void) {
		steps.push({name: name, f: f});
	}

	/** Run registered steps in order, then report. */
	public static function run() {
		if (steps.length == 0) {
			H.done();
			return;
		}
		var s = steps.shift();
		H.log("");
		H.log("== " + s.name);
		var called = false;
		var next = function() {
			if (called)
				return;
			called = true;
			haxe.Timer.delay(run, 1);
		};
		haxe.Timer.delay(function() {
			if (!called) {
				H.log("!! step TIMEOUT");
				next();
			}
		}, 15000);
		try {
			s.f(next);
		} catch (e:Dynamic) {
			H.log("step THREW " + H.err(e));
			next();
		}
	}

	public static function after(ms:Int, f:Void->Void) {
		haxe.Timer.delay(guard("timer", f), ms);
	}

	/** Wrap an event-handler body so a throw is logged instead of escaping to the player. */
	public static function guard(label:String, f:Void->Void):Void->Void {
		return function() {
			try {
				f();
			} catch (e:Dynamic) {
				H.log(label + " handler THREW " + H.err(e));
			}
		};
	}

	/** Server body for /data/slow: byte i == (i*7+3)&255. */
	public static function slowByte(i:Int):Int
		return (i * 7 + 3) & 255;

	/** Server body for /data/blob: byte i == (i*13+5)&255. */
	public static function blobByte(i:Int):Int
		return (i * 13 + 5) & 255;

	public static function cls(v:Dynamic):String
		return untyped __global__["flash.utils.getQualifiedClassName"](v);

	/** Deterministic description of an AMF-ish value (object keys sorted). */
	public static function repr(v:Dynamic, depth:Int = 0, ?seen:Array<Dynamic>):String {
		if (seen == null)
			seen = [];
		if (v == null)
			return untyped __global__["String"](v);
		var c = cls(v);
		switch (c) {
			case "String":
				return '"' + v + '"';
			case "int", "uint", "Number", "Boolean":
				return c + ":" + Std.string(v);
			default:
		}
		for (s in seen)
			if (s == v)
				return "<cycle>";
		if (depth > 4)
			return "<deep>";
		seen.push(v);
		var out:String;
		if (Std.isOfType(v, ByteArray)) {
			var b:ByteArray = v;
			var hex = [];
			for (i in 0...Std.int(Math.min(b.length, 8)))
				hex.push(StringTools.hex(b[i], 2));
			out = "ByteArray(len=" + b.length + " pos=" + b.position + " " + hex.join("") + ")";
		} else if (Std.isOfType(v, Date)) {
			out = "Date(" + untyped v.getTime() + ")";
		} else if (c == "XML" || c == "XMLList") {
			out = c + "(" + untyped v.toXMLString() + ")";
		} else if (c == "Array" || c.indexOf("__AS3__.vec::Vector") == 0) {
			var a:Array<Dynamic> = [];
			var len:Int = untyped v.length;
			for (i in 0...len)
				a.push(repr(untyped v[i], depth + 1, seen));
			out = c + "[" + a.join(",") + "]";
		} else {
			var keys = Reflect.fields(v);
			keys.sort(Reflect.compare);
			var parts = [for (k in keys) k + ":" + repr(untyped v[k], depth + 1, seen)];
			out = c + "{" + parts.join(",") + "}";
		}
		seen.pop();
		return out;
	}
}
