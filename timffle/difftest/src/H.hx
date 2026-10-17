import flash.Lib;
import flash.events.Event;
import flash.events.IOErrorEvent;
import flash.net.URLLoader;
import flash.net.URLRequest;
import flash.net.URLRequestMethod;

/** Shared test helper: collects result lines and POSTs them to the harness server. */
class H {
	public static inline var BASE = "http://127.0.0.1:18765";

	static var lines:Array<String> = [];
	static var test = "unknown";
	static var runner = "unknown";
	static var finished = false;

	public static function init(name:String, watchdogMs:Int = 25000) {
		test = name;
		var parts = Lib.current.loaderInfo.url.split("/t/");
		if (parts.length > 1)
			runner = parts[1].split("/")[0];
		log("# test=" + name);
		haxe.Timer.delay(function() {
			log("!! WATCHDOG TIMEOUT");
			done();
		}, watchdogMs);
	}

	public static function log(s:String) {
		lines.push(s);
		Lib.trace(s);
	}

	public static function err(e:Dynamic):String {
		var cls:String = untyped __global__["flash.utils.getQualifiedClassName"](e);
		if (Std.isOfType(e, flash.errors.Error)) {
			var er:flash.errors.Error = e;
			return "Error#" + er.errorID + " " + cls;
		}
		return "thrown:" + cls + ":" + Std.string(e);
	}

	/** Run f and record (instead of propagating) anything it throws. */
	public static function attempt(label:String, f:Void->Void) {
		try {
			f();
		} catch (e:Dynamic) {
			log(label + " THREW " + err(e));
		}
	}

	public static function done() {
		if (finished)
			return;
		finished = true;
		log("# done");
		var req = new URLRequest(BASE + "/report?runner=" + runner + "&test=" + test);
		req.method = URLRequestMethod.POST;
		req.contentType = "text/plain";
		req.data = lines.join("\n");
		var l = new URLLoader();
		l.addEventListener(Event.COMPLETE, function(_) Lib.fscommand("quit"));
		l.addEventListener(IOErrorEvent.IO_ERROR, function(_) Lib.fscommand("quit"));
		l.load(req);
	}
}
