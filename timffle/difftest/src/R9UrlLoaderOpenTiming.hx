import flash.events.Event;
import flash.events.IOErrorEvent;
import flash.net.URLLoader;
import flash.net.URLRequest;

/**
 * When a URLLoader dispatches `open`: with the response headers, not with the end of the body.
 *
 * A game's queued loader starts a 5 second timer for every download and only the `open` event
 * stops it. A player that opens a download only after the last byte has arrived makes the game give
 * up on (and cancel) every text download that takes longer than 5 seconds.
 *
 * The harness server sends the headers at once and the body only after `delay` seconds; the timer
 * markers show on which side of the body the `open` event falls. Only the order of the events is
 * recorded (no progress, no httpStatus).
 *
 * Not covered: Flash also dispatches `open` (and `progress`) for an HTTP error response such as a 404,
 * before `httpStatus` and `ioError`; Ruffle's fetch layer does not keep the body of an error response.
 */
class R9UrlLoaderOpenTiming {
	static var cases:Array<{n:String, l:URLLoader, log:Array<String>}> = [];

	static function req(v:String, delay:Float):URLRequest
		return new URLRequest(H.BASE + "/data/text?v=" + v + "&delay=" + delay);

	static function dat(l:URLLoader):String
		return l.data == null ? "null" : Std.string(l.data);

	static function mk(name:String):{l:URLLoader, log:Array<String>} {
		var l = new URLLoader();
		var log:Array<String> = [];
		l.addEventListener(Event.OPEN, function(_) log.push("open"));
		l.addEventListener(Event.COMPLETE, function(_) log.push("complete data=" + dat(l)));
		l.addEventListener(IOErrorEvent.IO_ERROR, function(_) log.push("ioError"));
		cases.push({n: name, l: l, log: log});
		return {l: l, log: log};
	}

	static function later(ms:Int, f:Void->Void)
		haxe.Timer.delay(f, ms);

	static function marker(c:{l:URLLoader, log:Array<String>}, ms:Int)
		later(ms, function() c.log.push("-- " + ms + " ms"));

	static function main() {
		H.init("r9urlloader_open_timing", 30000);

		// The body takes a second: `open` comes first, the 500 ms marker next, `complete` last.
		var c = mk("open-before-body");
		c.l.load(req("AAA", 1.0));
		marker(c, 500);

		// Closing between `open` and the end of the body: no `complete` ever follows.
		var c = mk("close-between-open-and-body");
		c.l.load(req("AAA", 1.2));
		later(500, function() {
			c.log.push("-- 500 ms");
			try {
				c.l.close();
				c.log.push("close() ok");
			} catch (e:Dynamic) {
				c.log.push("close() THREW " + H.err(e));
			}
		});
		marker(c, 1500);

		// Replacing a download whose body is still pending: the first one has opened, the second one
		// completes, the first one is never heard of again.
		var c = mk("replace-between-open-and-body");
		c.l.load(req("AAA", 1.0));
		later(500, function() {
			c.log.push("-- 500 ms");
			c.l.load(req("BBB", 0));
		});
		marker(c, 1500);

		// What such a loader does, with the 5 seconds scaled down to 400 ms: arm a timer when the
		// download starts, stop it on `open`, give up (close) when it fires.
		var c = mk("queued-loader-style-timeout");
		var giveUp = haxe.Timer.delay(function() {
			c.log.push("gave up: no open within 400 ms");
			try {
				c.l.close();
			} catch (e:Dynamic) {}
		}, 400);
		c.l.addEventListener(Event.OPEN, function(_) giveUp.stop());
		c.l.load(req("AAA", 0.8));

		later(3300, function() {
			for (k in cases) {
				H.log("== " + k.n);
				for (s in k.log)
					H.log("  " + s);
				H.log("  final: data=" + dat(k.l));
			}
			H.done();
		});
	}
}
