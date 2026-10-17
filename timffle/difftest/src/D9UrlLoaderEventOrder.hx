import flash.events.Event;
import flash.events.HTTPStatusEvent;
import flash.events.IOErrorEvent;
import flash.events.ProgressEvent;
import flash.events.SecurityErrorEvent;
import flash.net.URLLoader;
import flash.net.URLRequest;

/** Exploration only (not a golden): every event a URLLoader dispatches, in order, with timer markers. */
class D9UrlLoaderEventOrder {
	static var cases:Array<{n:String, l:URLLoader, log:Array<String>}> = [];

	static function mk(name:String):{l:URLLoader, log:Array<String>} {
		var l = new URLLoader();
		var log:Array<String> = [];
		l.addEventListener(Event.OPEN, function(_) log.push("open"));
		l.addEventListener(HTTPStatusEvent.HTTP_STATUS, function(e:HTTPStatusEvent) log.push("httpStatus " + e.status));
		l.addEventListener(ProgressEvent.PROGRESS, function(e:ProgressEvent) log.push("progress " + e.bytesLoaded + "/" + e.bytesTotal));
		l.addEventListener(Event.COMPLETE, function(_) log.push("complete data=" + l.data));
		l.addEventListener(IOErrorEvent.IO_ERROR, function(_) log.push("ioError"));
		l.addEventListener(SecurityErrorEvent.SECURITY_ERROR, function(_) log.push("securityError"));
		cases.push({n: name, l: l, log: log});
		return {l: l, log: log};
	}

	static function marker(c:{l:URLLoader, log:Array<String>}, ms:Int)
		haxe.Timer.delay(function() c.log.push("-- " + ms + " ms"), ms);

	static function main() {
		H.init("d9urlloader_event_order", 30000);

		var c = mk("ok-delayed-body");
		c.l.load(new URLRequest(H.BASE + "/data/text?v=AAA&delay=1.0"));
		marker(c, 500);

		var c = mk("ok-instant");
		c.l.load(new URLRequest(H.BASE + "/data/text?v=AAA&delay=0"));

		var c = mk("http-404");
		c.l.load(new URLRequest(H.BASE + "/data/404"));

		var c = mk("refused-connection");
		c.l.load(new URLRequest("http://127.0.0.1:18767/data/text"));

		haxe.Timer.delay(function() {
			for (k in cases) {
				H.log("== " + k.n);
				for (s in k.log)
					H.log("  " + s);
			}
			H.done();
		}, 3300);
	}
}
