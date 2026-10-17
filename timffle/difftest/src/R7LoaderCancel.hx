import flash.display.Loader;
import flash.events.Event;
import flash.events.IOErrorEvent;
import flash.events.ProgressEvent;
import flash.net.URLRequest;

/**
 * Loader.close() and calling Loader.load() again while the previous load is still running.
 *
 * A game's queued loader reuses one Loader for every resource and, on a timeout or when the queue
 * is reprioritized, calls unload() + close() and loads the next item into the same Loader. Flash drops
 * the old request for good; Ruffle used to deliver its late answer as the result of the *new* item.
 *
 * Each case has its own Loader; all run side by side and are reported in order at the end.
 * Only events whose timing and order match between the players are recorded (no open/progress).
 */
class R7LoaderCancel {
	static var cases:Array<{n:String, l:Loader, log:Array<String>}> = [];

	static function base(u:String):String {
		if (u == null)
			return "null";
		return u.substr(u.lastIndexOf("/") + 1);
	}

	static function asset(f:String, delay:Float, tag:String):URLRequest
		return new URLRequest(H.BASE + "/asset/" + f + ".swf?delay=" + delay + "&c=" + tag);

	static function mk(name:String):{l:Loader, log:Array<String>} {
		var l = new Loader();
		var log:Array<String> = [];
		var info = l.contentLoaderInfo;
		for (t in ["init", "complete", "unload", "httpStatus"]) {
			info.addEventListener(t, function(e:Event) {
				log.push(t == "init" || t == "complete" ? t + " " + base(info.url) + " " + info.width + "x" + info.height + " content=" + (l.content != null) : t);
			});
		}
		info.addEventListener(IOErrorEvent.IO_ERROR, function(e:IOErrorEvent) log.push("ioError"));
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

	/** What such a queued loader does to switch the shared Loader to another item. */
	static function switchTo(c:{l:Loader, log:Array<String>}, req:URLRequest) {
		c.l.unload();
		attempt(c.log, "close()", function() c.l.close());
		c.l.load(req);
	}

	static function main() {
		H.init("r7loader_cancel", 30000);

		var c = mk("close-only");
		c.l.load(asset("assetA", 1.0, "close-only"));
		later(250, function() attempt(c.log, "close()", function() c.l.close()));

		var c = mk("close-then-load");
		c.l.load(asset("assetA", 1.0, "close-then-load"));
		later(250, function() {
			attempt(c.log, "close()", function() c.l.close());
			c.l.load(asset("assetB", 0, "close-then-load"));
		});

		var c = mk("load-again-without-close");
		c.l.load(asset("assetA", 1.0, "load-again"));
		later(250, function() c.l.load(asset("assetB", 0, "load-again")));

		// The old request answers (0.7 s) long before the new one (1.5 s): its answer must not show up.
		var c = mk("late-answer-of-closed-load");
		c.l.load(asset("assetA", 0.7, "late"));
		later(200, function() switchTo(c, asset("assetB", 1.5, "late")));

		// Three items in a row, as when the queue is reprioritized twice: only the last one completes.
		var c = mk("queue-switch-twice");
		c.l.load(asset("assetA", 0.7, "q1"));
		later(200, function() switchTo(c, asset("assetB", 1.5, "q2")));
		later(400, function() switchTo(c, asset("assetA", 0.2, "q3")));

		var c = mk("retry-same-url");
		c.l.load(asset("assetA", 1.2, "retry"));
		later(300, function() switchTo(c, asset("assetA", 1.2, "retry-2")));

		var c = mk("close-idle");
		attempt(c.log, "close()", function() c.l.close());

		var c = mk("close-after-complete");
		c.l.contentLoaderInfo.addEventListener(Event.COMPLETE, function(_) {
			later(150, function() attempt(c.log, "close() after complete", function() c.l.close()));
		});
		c.l.load(asset("assetB", 0, "after-complete"));

		var c = mk("close-in-open");
		c.l.contentLoaderInfo.addEventListener(Event.OPEN, function(_) attempt(c.log, "close() in open", function() c.l.close()));
		c.l.load(asset("assetA", 0.3, "in-open"));

		var c = mk("close-in-progress");
		var once = false;
		c.l.contentLoaderInfo.addEventListener(ProgressEvent.PROGRESS, function(_) {
			if (!once) {
				once = true;
				attempt(c.log, "close() in progress", function() c.l.close());
			}
		});
		c.l.load(asset("assetA", 0.3, "in-progress"));

		var c = mk("close-in-complete");
		c.l.contentLoaderInfo.addEventListener(Event.COMPLETE, function(_) attempt(c.log, "close() in complete", function() c.l.close()));
		c.l.load(asset("assetB", 0, "in-complete"));

		var c = mk("load-in-ioerror");
		c.l.contentLoaderInfo.addEventListener(IOErrorEvent.IO_ERROR, function(_) c.l.load(asset("assetB", 0, "after-ioerror")));
		c.l.load(new URLRequest(H.BASE + "/data/404"));

		// Everything such a queued loader does when a load completes, inside the complete handler itself.
		var c = mk("next-item-in-complete");
		var n = 0;
		c.l.contentLoaderInfo.addEventListener(Event.COMPLETE, function(_) {
			if (n++ == 0)
				switchTo(c, asset("assetB", 0.2, "next-2"));
		});
		c.l.load(asset("assetA", 0.2, "next-1"));

		var c = mk("load-in-open");
		var opened = 0;
		c.l.contentLoaderInfo.addEventListener(Event.OPEN, function(_) {
			if (opened++ == 0)
				c.l.load(asset("assetB", 0, "in-open-2"));
		});
		c.l.load(asset("assetA", 0.5, "in-open-1"));

		var c = mk("close-after-ioerror");
		c.l.contentLoaderInfo.addEventListener(IOErrorEvent.IO_ERROR, function(_) {
			later(100, function() attempt(c.log, "close() after ioError", function() c.l.close()));
		});
		c.l.load(new URLRequest(H.BASE + "/data/404"));

		var c = mk("close-twice");
		c.l.load(asset("assetA", 1.0, "twice"));
		later(250, function() {
			attempt(c.log, "close() #1", function() c.l.close());
			attempt(c.log, "close() #2", function() c.l.close());
		});

		later(3300, function() {
			for (k in cases) {
				H.log("== " + k.n);
				for (s in k.log)
					H.log("  " + s);
				var i = k.l.contentLoaderInfo;
				// What Flash reports for a failed load's url and bytesLoaded varies from run to run.
				if (k.n == "close-after-ioerror")
					H.log("  final: content=" + (k.l.content != null) + " numChildren=" + k.l.numChildren);
				else
					H.log("  final: bytesLoaded=" + (i.bytesLoaded > 0 ? ">0" : "0") + " url=" + base(i.url) + " content=" + (k.l.content != null)
						+ " numChildren=" + k.l.numChildren);
			}
			H.done();
		});
	}
}
