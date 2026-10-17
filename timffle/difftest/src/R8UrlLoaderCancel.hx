import flash.events.Event;
import flash.events.HTTPStatusEvent;
import flash.events.IOErrorEvent;
import flash.events.ProgressEvent;
import flash.net.URLLoader;
import flash.net.URLRequest;

/**
 * URLLoader.close() and calling URLLoader.load() again while the previous load is still running.
 * Same hazard as R7LoaderCancel: a queued loader reuses one URLLoader for its text/binary items.
 *
 * Only events whose timing and order match between the players are recorded (no open, and no ioError data).
 */
class R8UrlLoaderCancel {
	static var cases:Array<{n:String, l:URLLoader, log:Array<String>}> = [];

	static function req(v:String, delay:Float):URLRequest
		return new URLRequest(H.BASE + "/data/text?v=" + v + "&delay=" + delay);

	static function dat(l:URLLoader):String
		return l.data == null ? "null" : Std.string(l.data);

	static function mk(name:String):{l:URLLoader, log:Array<String>} {
		var l = new URLLoader();
		var log:Array<String> = [];
		l.addEventListener(Event.COMPLETE, function(e:Event) log.push("complete data=" + dat(l) + " loaded=" + l.bytesLoaded));
		l.addEventListener(IOErrorEvent.IO_ERROR, function(e:IOErrorEvent) log.push("ioError"));
		cases.push({n: name, l: l, log: log});
		return {l: l, log: log};
	}

	static function later(ms:Int, f:Void->Void)
		haxe.Timer.delay(f, ms);

	static function attempt(log:Array<String>, label:String, f:Void->Void) {
		try {
			f();
			log.push(label + " ok");
		} catch (e:Dynamic) {
			log.push(label + " THREW " + H.err(e));
		}
	}

	/** What such a queued loader does to switch the shared URLLoader to another item. */
	static function switchTo(c:{l:URLLoader, log:Array<String>}, r:URLRequest) {
		attempt(c.log, "close()", function() c.l.close());
		c.l.load(r);
	}

	static function main() {
		H.init("r8urlloader_cancel", 30000);

		var c = mk("close-only");
		c.l.load(req("AAA", 1.0));
		later(250, function() attempt(c.log, "close()", function() c.l.close()));

		var c = mk("close-then-load");
		c.l.load(req("AAA", 1.0));
		later(250, function() switchTo(c, req("BBB", 0)));

		var c = mk("load-again-without-close");
		c.l.load(req("AAA", 1.0));
		later(250, function() c.l.load(req("BBB", 0)));

		// The old request answers (0.7 s) long before the new one (1.5 s): its answer must not show up.
		var c = mk("late-answer-of-closed-load");
		c.l.load(req("AAA", 0.7));
		later(200, function() switchTo(c, req("BBB", 1.5)));

		var c = mk("queue-switch-twice");
		c.l.load(req("AAA", 0.7));
		later(200, function() switchTo(c, req("BBB", 1.5)));
		later(400, function() switchTo(c, req("CCC", 0.2)));

		var c = mk("retry-same-url");
		c.l.load(req("AAA", 1.2));
		later(300, function() switchTo(c, req("AAA", 1.2)));

		var c = mk("close-idle");
		attempt(c.log, "close()", function() c.l.close());

		// Unlike Loader, a URLLoader still has its stream open after it completed or failed.
		var c = mk("close-after-complete");
		c.l.addEventListener(Event.COMPLETE, function(_) {
			later(150, function() {
				attempt(c.log, "close() after complete", function() c.l.close());
				attempt(c.log, "close() again", function() c.l.close());
			});
		});
		c.l.load(req("BBB", 0));

		var c = mk("close-in-open");
		c.l.addEventListener(Event.OPEN, function(_) attempt(c.log, "close() in open", function() c.l.close()));
		c.l.load(req("AAA", 0.3));

		var c = mk("close-in-progress");
		c.l.addEventListener(ProgressEvent.PROGRESS, function(_) attempt(c.log, "close() in progress", function() c.l.close()));
		c.l.load(req("AAA", 0.3));

		var c = mk("close-in-httpStatus");
		c.l.addEventListener(HTTPStatusEvent.HTTP_STATUS, function(_) attempt(c.log, "close() in httpStatus", function() c.l.close()));
		c.l.load(req("AAA", 0.3));

		var c = mk("close-in-complete");
		c.l.addEventListener(Event.COMPLETE, function(_) attempt(c.log, "close() in complete", function() c.l.close()));
		c.l.load(req("BBB", 0));

		var c = mk("load-in-ioerror");
		c.l.addEventListener(IOErrorEvent.IO_ERROR, function(_) c.l.load(req("BBB", 0)));
		c.l.load(new URLRequest(H.BASE + "/data/404"));

		// Everything such a queued loader does when a load completes, inside the complete handler itself.
		var c = mk("next-item-in-complete");
		var n = 0;
		c.l.addEventListener(Event.COMPLETE, function(_) {
			if (n++ == 0)
				switchTo(c, req("BBB", 0.2));
		});
		c.l.load(req("AAA", 0.2));

		var c = mk("load-in-open");
		var opened = 0;
		c.l.addEventListener(Event.OPEN, function(_) {
			if (opened++ == 0)
				c.l.load(req("BBB", 0));
		});
		c.l.load(req("AAA", 0.5));

		var c = mk("close-after-ioerror");
		c.l.addEventListener(IOErrorEvent.IO_ERROR, function(_) {
			later(100, function() attempt(c.log, "close() after ioError", function() c.l.close()));
		});
		c.l.load(new URLRequest(H.BASE + "/data/404"));

		var c = mk("close-twice");
		c.l.load(req("AAA", 1.0));
		later(250, function() {
			attempt(c.log, "close() #1", function() c.l.close());
			attempt(c.log, "close() #2", function() c.l.close());
		});

		// A finished load's data survives starting (and closing) the next one.
		var c = mk("data-kept-after-closed-reload");
		c.l.addEventListener(Event.COMPLETE, function(_) {
			if (c.log.length == 1) {
				c.l.load(req("CCC", 1.0));
				later(150, function() attempt(c.log, "close()", function() c.l.close()));
			}
		});
		c.l.load(req("AAA", 0));

		later(3300, function() {
			for (k in cases) {
				H.log("== " + k.n);
				for (s in k.log)
					H.log("  " + s);
				// Ruffle does not expose the body of an error response as `data` (a separate difference).
				if (k.n != "close-after-ioerror")
					H.log("  final: data=" + dat(k.l) + " loaded=" + k.l.bytesLoaded);
			}
			H.done();
		});
	}
}
