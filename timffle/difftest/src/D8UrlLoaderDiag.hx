import flash.events.Event;
import flash.events.HTTPStatusEvent;
import flash.events.IOErrorEvent;
import flash.events.ProgressEvent;
import flash.net.URLLoader;
import flash.net.URLRequest;

/** Diagnostic (not a regression test): records everything a URLLoader does around close()/load(). */
class D8UrlLoaderDiag {
	static var cases:Array<{n:String, l:URLLoader, log:Array<String>}> = [];
	static var t0:Float;

	static function req(v:String, delay:Float):URLRequest
		return new URLRequest(H.BASE + "/data/text?v=" + v + "&delay=" + delay);

	static function dat(l:URLLoader):String {
		try {
			return l.data == null ? "null" : Std.string(l.data);
		} catch (e:Dynamic) {
			return "THREW " + H.err(e);
		}
	}

	static function mk(name:String):{l:URLLoader, log:Array<String>} {
		var l = new URLLoader();
		var log:Array<String> = [];
		for (t in ["open", "httpStatus", "complete"]) {
			l.addEventListener(t, function(e:Event) {
				log.push(t + " data=" + dat(l) + " loaded=" + l.bytesLoaded + " total=" + l.bytesTotal);
				log.push("~ " + t + " @" + Std.int((haxe.Timer.stamp() - t0) * 1000));
			});
		}
		l.addEventListener(ProgressEvent.PROGRESS, function(e:ProgressEvent) {
			log.push("progress loaded=" + e.bytesLoaded + " total=" + e.bytesTotal);
		});
		l.addEventListener(IOErrorEvent.IO_ERROR, function(e:IOErrorEvent) {
			log.push("ioError data=" + dat(l));
		});
		cases.push({n: name, l: l, log: log});
		return {l: l, log: log};
	}

	static function later(ms:Int, f:Void->Void)
		haxe.Timer.delay(f, ms);

	static function tryDo(log:Array<String>, label:String, f:Void->Void) {
		try {
			f();
			log.push(label + " ok");
		} catch (e:Dynamic) {
			log.push(label + " THREW " + H.err(e));
		}
	}

	static function main() {
		H.init("d8urlloader_diag", 30000);
		t0 = haxe.Timer.stamp();

		var c = mk("u1 close-only");
		c.l.load(req("AAA", 1.0));
		later(250, function() tryDo(c.log, "close()", function() c.l.close()));

		var c = mk("u2 close-reload");
		c.l.load(req("AAA", 1.0));
		later(250, function() {
			tryDo(c.log, "close()", function() c.l.close());
			c.l.load(req("BBB", 0));
		});

		var c = mk("u3 reload-only");
		c.l.load(req("AAA", 1.0));
		later(250, function() c.l.load(req("BBB", 0)));

		var c = mk("u4 stale-shift (close+load, A fast, B slow)");
		c.l.load(req("AAA", 0.7));
		later(200, function() {
			tryDo(c.log, "close()", function() c.l.close());
			c.l.load(req("BBB", 1.5));
		});

		var c = mk("u5 close-idle");
		tryDo(c.log, "close()", function() c.l.close());

		var c = mk("u6 close-after-complete");
		c.l.addEventListener(Event.COMPLETE, function(_) {
			later(150, function() tryDo(c.log, "close() after complete", function() c.l.close()));
		});
		c.l.load(req("BBB", 0));

		var c = mk("u7 close-in-open");
		c.l.addEventListener(Event.OPEN, function(_) tryDo(c.log, "close() in open", function() c.l.close()));
		c.l.load(req("AAA", 0.3));

		var c = mk("u8 close-in-progress");
		c.l.addEventListener(ProgressEvent.PROGRESS, function(_) tryDo(c.log, "close() in progress", function() c.l.close()));
		c.l.load(req("AAA", 0.3));

		var c = mk("u9 close-in-httpStatus");
		c.l.addEventListener(HTTPStatusEvent.HTTP_STATUS, function(_) tryDo(c.log, "close() in httpStatus", function() c.l.close()));
		c.l.load(req("AAA", 0.3));

		var c = mk("u10 close-in-complete");
		c.l.addEventListener(Event.COMPLETE, function(_) tryDo(c.log, "close() in complete", function() c.l.close()));
		c.l.load(req("BBB", 0));

		var c = mk("u11 load-in-ioerror");
		c.l.addEventListener(IOErrorEvent.IO_ERROR, function(_) c.l.load(req("BBB", 0)));
		c.l.load(new URLRequest(H.BASE + "/data/404"));

		var c = mk("u12 reload-in-complete (queued-loader chain)");
		var n12 = 0;
		c.l.addEventListener(Event.COMPLETE, function(_) {
			if (n12++ == 0) {
				tryDo(c.log, "close() in complete", function() c.l.close());
				c.l.load(req("BBB", 0.2));
			}
		});
		c.l.load(req("AAA", 0.2));

		var c = mk("u13 close-after-ioerror");
		c.l.addEventListener(IOErrorEvent.IO_ERROR, function(_) {
			later(100, function() tryDo(c.log, "close() after ioError", function() c.l.close()));
		});
		c.l.load(new URLRequest(H.BASE + "/data/404"));

		var c = mk("u14 close-twice");
		c.l.load(req("AAA", 1.0));
		later(250, function() {
			tryDo(c.log, "close() #1", function() c.l.close());
			tryDo(c.log, "close() #2", function() c.l.close());
		});

		var c = mk("u15 load-in-open");
		var n15 = 0;
		c.l.addEventListener(Event.OPEN, function(_) {
			if (n15++ == 0)
				c.l.load(req("BBB", 0));
		});
		c.l.load(req("AAA", 0.5));

		var c = mk("u16 retry-same-url");
		c.l.load(req("AAA", 1.2));
		later(300, function() {
			tryDo(c.log, "close()", function() c.l.close());
			c.l.load(req("AAA", 1.2));
		});

		var c = mk("u17 data-after-complete-then-reload-close");
		c.l.addEventListener(Event.COMPLETE, function(_) {
			later(100, function() {
				c.l.load(req("CCC", 1.0));
				later(150, function() {
					tryDo(c.log, "close()", function() c.l.close());
					c.log.push("after close: data=" + dat(c.l));
				});
			});
		});
		c.l.load(req("AAA", 0));

		later(3300, function() {
			for (k in cases) {
				H.log("== " + k.n);
				for (s in k.log)
					H.log("  " + s);
				H.log("  final: data=" + dat(k.l) + " loaded=" + k.l.bytesLoaded + " total=" + k.l.bytesTotal);
			}
			H.done();
		});
	}
}
