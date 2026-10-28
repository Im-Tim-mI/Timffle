import flash.Lib;
import flash.display.Loader;
import flash.display.Sprite;
import flash.events.Event;
import flash.net.URLRequest;

/** Loads child/loaded.swf N times one after the other, like a game that reloads a panel SWF:
 * each copy is shown for a frame, then removed, unloaded and dropped before the next load starts.
 * Nothing forces a collection; the Rust test (tests/tests/library_pacing) ticks the player normally
 * and watches how many movie libraries pile up before the paced collector releases them. */
class Test {
	static inline var N = 12;
	static var root:Sprite;
	static var current:Loader;
	static var started = 0;
	static var frame = 0;
	static var phase = "load";

	static function startLoad() {
		var l = new Loader();
		var i = started++;
		l.contentLoaderInfo.addEventListener(Event.COMPLETE, function(_) {
			// Away from (0,0): the player keeps the display object under the mouse referenced.
			l.x = 100;
			l.y = 100;
			root.addChild(l);
			current = l;
			var cls:Dynamic = l.contentLoaderInfo.applicationDomain.getDefinition("Child");
			Out.line("loaded " + i + " count=" + cls.bump() + " content=" + Std.string(l.content != null));
			phase = "release";
		});
		l.load(new URLRequest("child/loaded.swf"));
	}

	/** See timffle_library_release/Test.hx: the Haxe runtime of every loaded copy patches shared
	 * playerglobal prototypes, which keeps the last copy alive. Drop the patches at the end. */
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
				if (frame > 300) {
					Out.line("timeout: only " + started + " loads finished");
					phase = "end";
				}
			case "release":
				root.removeChild(current);
				current.unload();
				current = null;
				Out.line("released " + (started - 1));
				if (started < N) {
					phase = "load";
					startLoad();
				} else {
					dropHaxeBootPatches();
					Out.line("done");
					phase = "end";
				}
			case "end":
		}
	}

	static function main() {
		root = Lib.current;
		Out.start("timffle_library_pacing");
		root.addEventListener(Event.ENTER_FRAME, onFrame);
		startLoad();
	}
}
