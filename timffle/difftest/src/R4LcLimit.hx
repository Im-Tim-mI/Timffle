import flash.events.Event;
import flash.net.LocalConnection;

/** LocalConnection.send size limit (ArgumentError #2084).
 * For each case, binary-search the longest string argument that send() accepts,
 * and check that one more character is rejected. send() throws synchronously,
 * so each search completes inside one frame; one case runs per frame. */
class R4LcLimit {
	static var tx:LocalConnection;
	static var rx:LocalConnection;

	static function repeat(unit:String, n:Int):String {
		var s = "";
		var chunk = unit;
		while (n > 0) {
			if (n & 1 == 1)
				s += chunk;
			chunk += chunk;
			n >>= 1;
		}
		return s;
	}

	/** null if accepted, else the errorID. */
	static function trySend(conn:String, method:String, args:Array<Dynamic>):Null<Int> {
		try {
			var a:Array<Dynamic> = [conn, method];
			untyped tx.send.apply(tx, a.concat(args));
			return null;
		} catch (e:flash.errors.Error) {
			return e.errorID;
		}
	}

	/** Longest n (in units) for which send(conn, method, ...before, repeat(unit, n), ...after) is accepted. */
	static function search(name:String, conn:String, method:String, unit:String, before:Array<Dynamic>, after:Array<Dynamic>) {
		function ok(n:Int)
			return trySend(conn, method, before.concat([repeat(unit, n)]).concat(after)) == null;
		var lo = 0, hi = 50000;
		if (!ok(lo)) {
			Out.line(name + ": even an empty string is rejected");
			return;
		}
		if (ok(hi)) {
			Out.line(name + ": " + hi + " accepted (no limit found)");
			return;
		}
		while (hi - lo > 1) {
			var mid = (lo + hi) >> 1;
			if (ok(mid))
				lo = mid;
			else
				hi = mid;
		}
		var err = trySend(conn, method, before.concat([repeat(unit, lo + 1)]).concat(after));
		Out.line(name + ": max accepted=" + lo + " units; " + (lo + 1) + " -> #" + err);
	}

	static function main() {
		Out.start("r4lc_limit");
		tx = new LocalConnection();
		rx = new LocalConnection();
		rx.client = {len: function(s:Dynamic) {}};
		rx.connect("r4rx");
		var long20 = "abcdefghijklmnopqrst";
		var cases:Array<Void->Void> = [
			function() search("base: conn=r4rx method=len", "r4rx", "len", "a", [], []),
			function() search("conn +20 chars (no receiver)", "r4rx" + long20, "len", "a", [], []),
			function() search("conn r4zz (no receiver, same length)", "r4zz", "len", "a", [], []),
			function() search("method +20 chars", "r4rx", "len" + long20, "a", [], []),
			function() search("underscore conn _r4", "_r4", "len", "a", [], []),
			function() search("domain-prefixed conn", rx.domain + ":r4rx", "len", "a", [], []),
			function() search("3-byte UTF-8 char", "r4rx", "len", "中", [], []),
			function() search("extra Number arg before", "r4rx", "len", "a", [1.5], []),
			function() search("extra 10-char string after", "r4rx", "len", "a", [], ["0123456789"]),
			function() search("extra object arg after", "r4rx", "len", "a", [], [{k: 1}]),
            function() { rx.close(); search("same name after close", "r4rx", "len", "a", [], []); },
            function() { rx.connect("r4rx"); search("same name reconnected", "r4rx", "len", "a", [], []); },
		];
		var frame = 0;
		flash.Lib.current.stage.addEventListener(Event.ENTER_FRAME, function(_) {
			frame++;
			if (frame < 2)
				return;
			var i = frame - 2;
			if (i < cases.length)
				cases[i]();
			else if (i == cases.length + 2) {
				Out.line("done");
				Out.finish();
			}
		});
	}
}
