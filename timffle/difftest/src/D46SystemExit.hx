/** Probe (no golden): System.pause()/resume()/exit() in the standalone Flash Player 32 projector
 *  (remote sandbox: served over HTTP). Each risky call is made only after the lines so far were
 *  reported, so a call that stops the player still leaves a partial report; a later report
 *  overwrites it. Build with -swf-version 32. */
import flash.events.Event;
import flash.net.URLLoader;
import flash.net.URLRequest;
import flash.net.URLRequestMethod;

class D46SystemExit {
	static var sys:Dynamic;
	static var lines:Array<String> = [];

	static function log(s:String) {
		lines.push(s);
		flash.Lib.trace(s);
	}

	static function step(label:String, f:Void->Void) {
		try {
			f();
		} catch (e:flash.errors.Error) {
			log(label + " THREW " + e.name + " #" + e.errorID + " " + e.message);
		}
	}

	static function report(then:Void->Void) {
		var req = new URLRequest(H.BASE + "/report?runner=flash&test=d46systemexit");
		req.method = URLRequestMethod.POST;
		req.contentType = "text/plain";
		req.data = lines.join("\n");
		var l = new URLLoader();
		l.addEventListener(Event.COMPLETE, function(_) then());
		l.load(req);
	}

	static function main() {
		sys = untyped __global__["flash.system.System"];
		log("# test=d46systemexit");
		log("sandboxType=" + untyped __global__["flash.system.Security"].sandboxType);
		var enterFrames = 0;
		flash.Lib.current.addEventListener(Event.ENTER_FRAME, function(_) enterFrames++);
		report(function() {
			step("resume before pause", function() { sys.resume(); log("resume() before pause ok"); });
			step("pause", function() { sys.pause(); log("pause() returned"); });
			var ef = enterFrames;
			haxe.Timer.delay(function() {
				log("timer after pause fired; enterFrames advanced by " + (enterFrames - ef));
				step("resume", function() { sys.resume(); log("resume() ok"); });
				report(function() {
					step("exit(0)", function() { sys.exit(0); log("exit(0) returned"); });
					haxe.Timer.delay(function() {
						log("still alive after exit(0)");
						report(function() {
							log("# done");
							report(function() flash.Lib.fscommand("quit"));
						});
					}, 300);
				});
			}, 500);
		});
	}
}
