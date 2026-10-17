import flash.display.Loader;
import flash.events.Event;
import flash.events.IOErrorEvent;
import flash.events.ProgressEvent;
import flash.net.URLRequest;

/** Diagnostic (not a regression test): records everything a Loader does around close()/load()/unload(). */
class D7LoaderDiag {
	static var cases:Array<{n:String, l:Loader, log:Array<String>}> = [];
	static var t0:Float;

	static function base(u:String):String {
		if (u == null)
			return "null";
		var i = u.lastIndexOf("/");
		return u.substr(i + 1);
	}

	static function nm(l:Loader):String {
		try {
			return l.content == null ? "null" : "set";
		} catch (e:Dynamic) {
			return "THREW " + H.err(e);
		}
	}

	static function asset(f:String, delay:Float, tag:String):URLRequest
		return new URLRequest(H.BASE + "/asset/" + f + ".swf?delay=" + delay + "&c=" + tag);

	static function mk(name:String):{l:Loader, log:Array<String>} {
		var l = new Loader();
		var log:Array<String> = [];
		var info = l.contentLoaderInfo;
		for (t in ["open", "init", "complete", "unload", "httpStatus"]) {
			info.addEventListener(t, function(e:Event) {
				var extra = (t == "init" || t == "complete") ? " content=" + nm(l) + " infoUrl=" + base(info.url) + " size=" + info.width + "x" + info.height : "";
				log.push(t + extra);
				log.push("~ " + t + " @" + Std.int((haxe.Timer.stamp() - t0) * 1000));
			});
		}
		info.addEventListener(IOErrorEvent.IO_ERROR, function(e:IOErrorEvent) {
			log.push("ioError");
		});
		var progressSeen = 0;
		info.addEventListener(ProgressEvent.PROGRESS, function(e:ProgressEvent) {
			progressSeen++;
			if (progressSeen == 1)
				log.push("progress(first) loaded=" + (e.bytesLoaded > 0 ? ">0" : "0") + " total=" + (e.bytesTotal > 0 ? ">0" : "0"));
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
		H.init("d7loader_diag", 30000);
		t0 = haxe.Timer.stamp();

		var c = mk("c1 close-only");
		c.l.load(asset("assetA", 1.0, "c1"));
		later(250, function() tryDo(c.log, "close()", function() c.l.close()));

		var c = mk("c2 close-reload");
		c.l.load(asset("assetA", 1.0, "c2"));
		later(250, function() {
			tryDo(c.log, "close()", function() c.l.close());
			c.l.load(asset("assetB", 0, "c2"));
		});

		var c = mk("c3 reload-only");
		c.l.load(asset("assetA", 1.0, "c3"));
		later(250, function() c.l.load(asset("assetB", 0, "c3")));

		var c = mk("c4 stale-shift (unload+close+load, A fast, B slow)");
		c.l.load(asset("assetA", 0.7, "c4"));
		later(200, function() {
			c.l.unload();
			tryDo(c.log, "close()", function() c.l.close());
			c.l.load(asset("assetB", 1.5, "c4"));
		});

		var c = mk("c5 retry-same-url");
		c.l.load(asset("assetA", 1.2, "c5"));
		later(300, function() {
			c.l.unload();
			tryDo(c.log, "close()", function() c.l.close());
			c.l.load(asset("assetA", 1.2, "c5r"));
		});

		var c = mk("c6 close-idle");
		tryDo(c.log, "close()", function() c.l.close());

		var c = mk("c7 close-after-complete");
		c.l.contentLoaderInfo.addEventListener(Event.COMPLETE, function(_) {
			later(150, function() tryDo(c.log, "close() after complete", function() c.l.close()));
		});
		c.l.load(asset("assetB", 0, "c7"));

		var c = mk("c8 close-in-open");
		c.l.contentLoaderInfo.addEventListener(Event.OPEN, function(_) tryDo(c.log, "close() in open", function() c.l.close()));
		c.l.load(asset("assetA", 0.3, "c8"));

		var c = mk("c9 close-in-progress");
		var once9 = false;
		c.l.contentLoaderInfo.addEventListener(ProgressEvent.PROGRESS, function(_) {
			if (!once9) {
				once9 = true;
				tryDo(c.log, "close() in progress", function() c.l.close());
			}
		});
		c.l.load(asset("assetA", 0.3, "c9"));

		var c = mk("c10 close-in-complete");
		c.l.contentLoaderInfo.addEventListener(Event.COMPLETE, function(_) tryDo(c.log, "close() in complete", function() c.l.close()));
		c.l.load(asset("assetB", 0, "c10"));

		var c = mk("c11 unload-inflight");
		c.l.load(asset("assetA", 1.0, "c11"));
		later(250, function() tryDo(c.log, "unload()", function() c.l.unload()));

		var c = mk("c12 load-in-ioerror");
		c.l.contentLoaderInfo.addEventListener(IOErrorEvent.IO_ERROR, function(_) c.l.load(asset("assetB", 0, "c12")));
		c.l.load(new URLRequest(H.BASE + "/data/404"));

		var c = mk("c13 reload-in-complete (queued-loader chain)");
		var n13 = 0;
		c.l.contentLoaderInfo.addEventListener(Event.COMPLETE, function(_) {
			if (n13++ == 0) {
				c.l.unload();
				tryDo(c.log, "close() in complete", function() c.l.close());
				c.l.load(asset("assetB", 0.2, "c13b"));
			}
		});
		c.l.load(asset("assetA", 0.2, "c13"));

		var c = mk("c14 load-in-open");
		var n14 = 0;
		c.l.contentLoaderInfo.addEventListener(Event.OPEN, function(_) {
			if (n14++ == 0)
				c.l.load(asset("assetB", 0, "c14b"));
		});
		c.l.load(asset("assetA", 0.5, "c14"));

		var c = mk("c15 close-after-ioerror");
		c.l.contentLoaderInfo.addEventListener(IOErrorEvent.IO_ERROR, function(_) {
			later(100, function() tryDo(c.log, "close() after ioError", function() c.l.close()));
		});
		c.l.load(new URLRequest(H.BASE + "/data/404"));

		var c = mk("c16 close-twice");
		c.l.load(asset("assetA", 1.0, "c16"));
		later(250, function() {
			tryDo(c.log, "close() #1", function() c.l.close());
			tryDo(c.log, "close() #2", function() c.l.close());
		});

		var c = mk("c17 close-then-final-state");
		c.l.load(asset("assetA", 1.0, "c17"));
		later(250, function() tryDo(c.log, "close()", function() c.l.close()));
		later(2800, function() {
			var i = c.l.contentLoaderInfo;
			c.log.push("t=2800 bytesLoaded=" + i.bytesLoaded + " bytesTotal=" + i.bytesTotal + " url=" + base(i.url) + " content=" + nm(c.l)
				+ " numChildren=" + c.l.numChildren);
		});

		later(3300, function() {
			for (k in cases) {
				H.log("== " + k.n);
				for (s in k.log)
					H.log("  " + s);
				var i = k.l.contentLoaderInfo;
				H.log("  final: bytesLoaded=" + (i.bytesLoaded > 0 ? ">0" : "0") + " bytesTotal=" + (i.bytesTotal > 0 ? ">0" : "0") + " url=" + base(i.url)
					+ " content=" + nm(k.l) + " numChildren=" + k.l.numChildren);
			}
			H.done();
		});
	}
}
