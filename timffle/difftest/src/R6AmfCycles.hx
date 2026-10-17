import flash.utils.ByteArray;
import flash.utils.Dictionary;

/** AMF3 ByteArray round trips of cyclic and shared object graphs.
 * Ruffle used to overflow its stack on cycles, and then (with flash-lso's old
 * AMF3 encoder reference numbering) resolved cycles to the wrong object
 * whenever an XML, Date, ByteArray or numeric Vector was written first. */
class R6AmfCycles {
	static function roundTrip(v:Dynamic):Dynamic {
		var ba = new ByteArray();
		ba.writeObject(v);
		ba.position = 0;
		var r = ba.readObject();
		if (ba.bytesAvailable != 0)
			Out.line("  !! " + ba.bytesAvailable + " bytes left unread");
		return r;
	}

	static function run(name:String, f:Void->String) {
		try {
			Out.line(name + ": " + f());
		} catch (e:flash.errors.Error) {
			Out.line(name + ": threw " + U.cls(e) + " #" + e.errorID);
		}
	}

	/** `[before, c]` where `c` references itself. Dense array elements are written
	 * in index order, so `before` is always serialized ahead of the cycle. */
	static function cycleAfter(before:Dynamic):Array<Dynamic> {
		var c:Dynamic = {};
		c.tag = "c";
		c.self = c;
		return [before, c];
	}

	static function checkCycleAfter(r:Array<Dynamic>):String
		return "r[1].self===r[1] " + (r[1].self == r[1]) + " r[1].self.tag=" + r[1].self.tag + " r[0]=" + U.repr(r[0]);

	static function main() {
		Out.start("r6amf_cycles");

		run("object self-cycle", function() {
			var o:Dynamic = {tag: "o"};
			o.self = o;
			var r:Dynamic = roundTrip(o);
			return "r.self===r " + (r.self == r) + " tag=" + r.tag;
		});
		run("array self-cycle", function() {
			var a:Array<Dynamic> = [1, "two"];
			a.push(a);
			var r:Array<Dynamic> = roundTrip(a);
			return "length=" + r.length + " r[2]===r " + (r[2] == r) + " r[1]=" + r[1];
		});
		run("indirect cycle", function() {
			var p:Dynamic = {tag: "p"};
			p.kid = {tag: "k", parent: p};
			var r:Dynamic = roundTrip(p);
			return "r.kid.parent===r " + (r.kid.parent == r);
		});
		run("shared object", function() {
			var s:Dynamic = {n: 1};
			var r:Dynamic = roundTrip({a: s, b: s});
			return "r.a===r.b " + (r.a == r.b) + " r.a.n=" + r.a.n;
		});
		run("shared array", function() {
			var s:Array<Dynamic> = [7];
			var r:Dynamic = roundTrip({a: s, b: s});
			return "r.a===r.b " + (r.a == r.b) + " r.b[0]=" + r.b[0];
		});
		run("cycle after XML", function() {
			var r:Array<Dynamic> = roundTrip(cycleAfter(new flash.xml.XML("<a b='1'/>")));
			return checkCycleAfter(r);
		});
		run("cycle after Date", function() {
			var r:Array<Dynamic> = roundTrip(cycleAfter(Date.fromTime(1577934245000.0)));
			return checkCycleAfter(r);
		});
		run("cycle after ByteArray", function() {
			var b = new ByteArray();
			b.writeUTFBytes("hi");
			var r:Array<Dynamic> = roundTrip(cycleAfter(b));
			return checkCycleAfter(r);
		});
		run("cycle after Vector.<int>", function() {
			var v = new flash.Vector<Int>();
			v.push(3);
			var r:Array<Dynamic> = roundTrip(cycleAfter(v));
			return checkCycleAfter(r);
		});
		run("Vector.<Object> containing itself", function() {
			var v = new flash.Vector<Dynamic>();
			v.push("x");
			v.push(v);
			var r:Dynamic = roundTrip(v);
			return "length=" + r.length + " r[1]===r " + (r[1] == r) + " r[0]=" + r[0];
		});
		run("Dictionary value cycle", function() {
			var d = new Dictionary();
			untyped d["self"] = d;
			untyped d["n"] = 5;
			var r:Dynamic = roundTrip(d);
			return "class=" + U.cls(r) + " r.self===r " + (untyped r["self"] == r) + " n=" + untyped r["n"];
		});
		run("cycle through Dictionary", function() {
			var o:Dynamic = {tag: "o"};
			var d = new Dictionary();
			untyped d["owner"] = o;
			o.dict = d;
			var r:Dynamic = roundTrip(o);
			return "r.dict.owner===r " + (untyped r.dict["owner"] == r);
		});
		Out.line("done");
		Out.finish();
	}
}
