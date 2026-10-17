import flash.events.Event;
import flash.net.URLLoader;
import flash.net.URLRequest;
import flash.net.URLRequestMethod;

/**
 * Exploration: how deep can ActionScript recurse? Each depth is reported to the server right away (the page may
 * die at some depth: a Flash stack overflow is a catchable Error #1023, but a WebAssembly one poisons the whole
 * Ruffle core), so the last report names the last depth that worked.
 */
class D11Recursion {
	static var lines:Array<String> = [];
	static var depths = [50, 100, 150, 200, 300, 400, 600, 800, 1200, 1600, 2400, 3200, 5000, 8000, 12000, 20000, 40000];

	static function f(n:Int):Int
		return n == 0 ? 0 : 1 + f(n - 1);

	// the shape of a recursive A* node search: a try/catch around the recursive call and a few locals
	static function g(n:Int):Int {
		var a = n;
		var b = n * 2;
		if (n == 0)
			return 0;
		try {
			return g(n - 1) + (a - a) + (b - b) + 1;
		} catch (e:Dynamic) {
			throw e;
		}
	}

	static function post(done:Bool) {
		var req = new URLRequest(H.BASE + "/report?runner=" + runner() + "&test=" + (done ? "d11recursion" : "d11recursion_progress"));
		req.method = URLRequestMethod.POST;
		req.contentType = "text/plain";
		req.data = lines.join("\n") + (done ? "\n# done" : "");
		var l = new URLLoader();
		l.addEventListener(Event.COMPLETE, function(_) {});
		l.load(req);
	}

	static function runner():String {
		var parts = flash.Lib.current.loaderInfo.url.split("/t/");
		return parts.length > 1 ? parts[1].split("/")[0] : "unknown";
	}

	static function step(i:Int) {
		if (i >= depths.length) {
			post(true);
			haxe.Timer.delay(function() flash.Lib.fscommand("quit"), 800);
			return;
		}
		var d = depths[i];
		var res = "";
		try {
			res = "f(" + d + ")=" + f(d);
		} catch (e:Dynamic) {
			res = "f(" + d + ") THREW " + H.err(e);
		}
		var res2 = "";
		try {
			res2 = "g(" + d + ")=" + g(d);
		} catch (e:Dynamic) {
			res2 = "g(" + d + ") THREW " + H.err(e);
		}
		lines.push(res + "   " + res2);
		post(false);
		haxe.Timer.delay(function() step(i + 1), 400);
	}

	static function main() {
		lines.push("# test=d11recursion");
		step(0);
	}
}
