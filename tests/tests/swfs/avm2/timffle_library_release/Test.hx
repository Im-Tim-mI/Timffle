import flash.Lib;
import flash.display.Loader;
import flash.display.Sprite;
import flash.events.Event;
import flash.net.URLRequest;

/** Loads child/loaded.swf N times, uses each copy, then releases all but one, keeps using the kept copy
 * for a few frames (the Rust side forces a full GC after every tick), then releases that one too.
 * Through the trace output this checks the Flash rules: every load has fresh statics, a symbol class
 * of content that is still referenced keeps working, unload() does not break the other copies.
 * The Rust test (tests/tests/library_release) checks that the libraries of released copies are gone. */
class Test {
	static inline var N = 4;
	static var root:Sprite;
	static var loaders:Array<Loader> = [];
	static var started = 0;
	static var done = 0;
	static var frame = 0;
	static var phase = "load";
	static var usesLeft = 3;

	static function use(l:Loader, label:String) {
		var dom = l.contentLoaderInfo.applicationDomain;
		var cls:Dynamic = dom.getDefinition("Child");
		var n:Int = cls.bump();
		var bd:flash.display.BitmapData = cls.pix();
		Out.line(label + " count=" + n + " pix=" + bd.width + "x" + bd.height + " content=" + Std.string(l.content != null));
	}

	static function startLoad() {
		var l = new Loader();
		var i = started++;
		l.contentLoaderInfo.addEventListener(Event.COMPLETE, function(_) {
			// Away from (0,0): the player keeps the display object under the mouse referenced
			// (hover state), which is not what this test is about.
			l.x = 100 + 30 * i;
			l.y = 100;
			root.addChild(l);
			loaders[i] = l;
			done++;
			use(l, "loaded " + i);
			if (started < N) startLoad();
		});
		l.load(new URLRequest("child/loaded.swf"));
	}

	static function release(l:Loader) {
		root.removeChild(l);
		l.unload();
	}

	/** Every Haxe-built SWF's runtime (flash.Boot and Math.__init__) installs closures on shared
	 * playerglobal objects: Array.prototype, String.prototype, Date, Date.prototype and Math. The last
	 * loaded copy's closures stay installed and, in Flash too, keep that copy's ApplicationDomain
	 * alive. Nothing below needs them any more, so drop them: afterwards nothing references any
	 * loaded copy. */
	static function dropHaxeBootPatches() {
		var aproto:Dynamic = untyped Array.prototype;
		for (f in ["copy", "insert", "contains", "remove", "iterator", "keyValueIterator", "resize", "filterHX", "mapHX", "filter", "map"])
			untyped __delete__(aproto, f);
		var sproto:Dynamic = untyped String.prototype;
		for (f in ["charCodeAtHX", "charCodeAt"])
			untyped __delete__(sproto, f);
		var d:Dynamic = Date;
		for (f in ["now", "fromTime", "fromString"])
			untyped __delete__(d, f);
		untyped __delete__(d.prototype, "toString");
		var m:Dynamic = Math;
		for (f in ["isFinite", "isNaN"])
			untyped __delete__(m, f);
	}

	static function onFrame(_) {
		frame++;
		switch (phase) {
			case "load":
				if (done == N) {
					// Use every copy once more: all N are alive and independent.
					for (i in 0...N) use(loaders[i], "again " + i);
					for (i in 1...N) {
						release(loaders[i]);
						loaders[i] = null;
					}
					Out.line("released " + (N - 1) + " copies, kept 0");
					phase = "keep";
				} else if (frame > 200) {
					Out.line("timeout: only " + done + " loads finished");
					phase = "end";
				}
			case "keep":
				// The kept copy must survive any number of collections.
				use(loaders[0], "kept");
				if (--usesLeft == 0) {
					release(loaders[0]);
					loaders[0] = null;
					Out.line("released the kept copy");
					dropHaxeBootPatches();
					phase = "end";
				}
			case "end":
		}
	}

	static function main() {
		root = Lib.current;
		Out.start("timffle_library_release");
		root.addEventListener(Event.ENTER_FRAME, onFrame);
		startLoad();
	}
}
