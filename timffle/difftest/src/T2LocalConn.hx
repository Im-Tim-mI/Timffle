import flash.events.AsyncErrorEvent;
import flash.events.Event;
import flash.events.SecurityErrorEvent;
import flash.events.StatusEvent;
import flash.net.LocalConnection;
import flash.utils.ByteArray;

/** LocalConnection inside one SWF over http://: delivery timing, AMF argument
 * round-trips, the 40 KB limit, client errors, and connection-name/domain rules.
 * Upstream ruffle tests cover basic connect/send/close from file:// only. */
class T2LocalConn {
	static var frame = 0;
	static var tx:LocalConnection;
	static var rx:LocalConnection;
	static var rxName = "t2rx";

	/** Logged lines prefixed with the frame offset since the current step began. */
	static var stepFrame = 0;

	static function at():String
		return "[f+" + (frame - stepFrame) + "]";

	static function waitFrames(n:Int, f:Void->Void) {
		var target = frame + n;
		var l:Event->Void = null;
		l = function(_) {
			if (frame >= target) {
				flash.Lib.current.stage.removeEventListener(Event.ENTER_FRAME, l);
				U.guard("frames", f)();
			}
		};
		flash.Lib.current.stage.addEventListener(Event.ENTER_FRAME, l);
	}

	static function events(lc:LocalConnection, name:String) {
		lc.addEventListener(StatusEvent.STATUS, function(e:StatusEvent) {
			H.log(at() + " " + name + " status level=" + e.level + " code=" + e.code + " bubbles=" + e.bubbles + " targetIsLc=" + (e.target == lc));
		});
		lc.addEventListener(AsyncErrorEvent.ASYNC_ERROR, function(e:AsyncErrorEvent) {
			H.log(at() + " " + name + " asyncError text=" + e.text + " errorID=" + e.errorID + " error=" + H.err(e.error));
		});
		lc.addEventListener(SecurityErrorEvent.SECURITY_ERROR, function(e:SecurityErrorEvent) {
			H.log(at() + " " + name + " securityError text=" + e.text);
		});
	}

	/** A client whose method `name` logs every received argument. */
	static function recorder(label:String, ?methods:Array<String>):Dynamic {
		var c:Dynamic = {};
		if (methods == null)
			methods = ["m"];
		for (m in methods) {
			Reflect.setField(c, m, Reflect.makeVarArgs(function(args:Array<Dynamic>) {
				H.log(at() + " " + label + "." + m + " called argc=" + args.length);
				for (i in 0...args.length)
					H.log("    arg" + i + "=" + U.repr(args[i]));
				return null;
			}));
		}
		return c;
	}

	static function send(lc:LocalConnection, conn:String, method:String, args:Array<Dynamic>) {
		var desc = "send(" + U.repr(conn) + "," + U.repr(method) + ", " + args.length + " args)";
		try {
			var a:Array<Dynamic> = [conn, method];
			untyped lc.send.apply(lc, a.concat(args));
			H.log(at() + " " + desc + " returned");
		} catch (e:Dynamic) {
			H.log(at() + " " + desc + " THREW " + H.err(e));
		}
	}

	static function connect(lc:LocalConnection, name:Dynamic, label:String) {
		try {
			lc.connect(name);
			H.log(label + ".connect(" + U.repr(name) + ") ok");
		} catch (e:Dynamic) {
			H.log(label + ".connect(" + U.repr(name) + ") THREW " + H.err(e));
		}
	}

	static function close(lc:LocalConnection, label:String) {
		try {
			lc.close();
			H.log(label + ".close() ok");
		} catch (e:Dynamic) {
			H.log(label + ".close() THREW " + H.err(e));
		}
	}

	/** Step that runs `act` and then waits `n` frames for deliveries/events. */
	static function fstep(name:String, n:Int, act:Void->Void) {
		U.step(name, function(next) {
			stepFrame = frame;
			act();
			H.log(at() + " end of action");
			waitFrames(n, next);
		});
	}

	static function main() {
		H.init("t2localconn", 90000);
		flash.Lib.current.stage.addEventListener(Event.ENTER_FRAME, function(_) frame++);
		tx = new LocalConnection();
		rx = new LocalConnection();
		events(tx, "tx");
		events(rx, "rx");

		U.step("basics", function(next) {
			H.log("isSupported=" + LocalConnection.isSupported);
			H.log("domain=" + rx.domain);
			H.log("client===lc by default: " + (rx.client == rx));
			H.attempt("isPerUser", function() H.log("isPerUser=" + untyped rx.isPerUser));
			H.attempt("allowDomain('*')", function() {
				rx.allowDomain("*");
				H.log("allowDomain('*') ok");
			});
			H.attempt("allowDomain()", function() {
				rx.allowDomain();
				H.log("allowDomain() ok");
			});
			H.attempt("allowInsecureDomain('a','b')", function() {
				rx.allowInsecureDomain("a", "b");
				H.log("allowInsecureDomain ok");
			});
			next();
		});

		U.step("connect rules", function(next) {
			var a = new LocalConnection(), b = new LocalConnection();
			connect(a, "t2dup", "a");
			connect(b, "t2dup", "b");
			connect(a, "t2other", "a(again)");
			close(a, "a");
			connect(b, "t2dup", "b(after a closed)");
			close(b, "b");
			close(b, "b");
			connect(a, null, "a");
			connect(a, "", "a");
			connect(a, "has:colon", "a");
			connect(a, "_underscore", "a");
			close(a, "a");
			next();
		});

		fstep("delivery timing: one message to a connected client", 6, function() {
			rx.client = recorder("rx");
			connect(rx, rxName, "rx");
			send(tx, rxName, "m", [1]);
			H.log(at() + " after send");
		});

		fstep("five sends in one frame keep order", 6, function() {
			for (i in 0...5)
				send(tx, rxName, "m", [i]);
		});

		fstep("send to an unconnected name", 6, function() {
			send(tx, "t2nobody", "m", []);
		});

		// cyclic objects/arrays live in T3LcCycle: they crash ruffle 0.7.1
		fstep("AMF argument round-trip", 8, function() {
			var holes:Array<Dynamic> = [];
			holes[3] = "x";
			var ba = new ByteArray();
			ba.writeUTFBytes("bytes!");
			var vec = new flash.Vector<Int>();
			vec.push(7);
			vec.push(-8);
			var shared:Dynamic = {v: 1};
			send(tx, rxName, "m", [
				untyped __global__["int"](-5), 4294967295.0, 0.5, Math.NaN, Math.POSITIVE_INFINITY, true, null,
				untyped __global__["undefined"], "中文 é", new Date(2020, 0, 2, 3, 4, 5)
			]);
			send(tx, rxName, "m", [holes, ba, vec, {a: shared, b: shared}]);
			send(tx, rxName, "m", [untyped __global__["XML"]("<a b='1'><c/></a>")]);
			send(tx, rxName, "m", [new ArgThing(3)]);
		});

		fstep("40 KB payload limit", 8, function() {
			var c:Dynamic = {};
			c.len = function(s:String) H.log(at() + " rx.len got string of length " + s.length);
			rx.client = c;
			for (n in [40000, 40900, 40960, 41000, 100000])
				send(tx, rxName, "len", [StringTools.lpad("", "x", n)]);
		});

		fstep("method missing on client", 6, function() {
			send(tx, rxName, "nope", [1]);
		});

		fstep("protected / odd method names", 6, function() {
			for (m in ["send", "connect", "close", "", null])
				send(tx, rxName, m, []);
		});

		fstep("client set to null / primitive", 8, function() {
			H.attempt("client=null", function() {
				rx.client = null;
				H.log("client=null ok");
			});
			// client = 5 lives in T3LcCrash: it panics ruffle 0.7.1
			H.log("client now " + U.repr(rx.client == rx ? "<lc>" : rx.client));
			send(tx, rxName, "m", [1]);
		});

		fstep("connection-name prefixes and case", 8, function() {
			rx.client = recorder("rx");
			var d = rx.domain;
			for (n in [d + ":" + rxName, "localhost:" + rxName, "127.0.0.1:" + rxName, "other.example:" + rxName, rxName.toUpperCase()])
				send(tx, n, "m", [n]);
		});

		fstep("underscore names are domain-free", 8, function() {
			var u = new LocalConnection();
			events(u, "u");
			u.client = recorder("u");
			connect(u, "_t2u", "u");
			send(tx, "_t2u", "m", ["plain"]);
			send(tx, rx.domain + ":_t2u", "m", ["prefixed"]);
			waitFrames(6, function() close(u, "u"));
		});

		fstep("receiver sends to itself", 6, function() {
			send(rx, rxName, "m", ["loopback"]);
		});

		fstep("send then close receiver in the same frame", 6, function() {
			send(tx, rxName, "m", ["racing close"]);
			close(rx, "rx");
		});

		fstep("send after receiver closed", 6, function() {
			send(tx, rxName, "m", ["after close"]);
		});

		fstep("client method throws an Error", 8, function() {
			var c:Dynamic = {};
			c.boom = function() {
				H.log(at() + " boom called");
				throw new flash.errors.Error("boom!", 42);
			};
			rx.client = c;
			connect(rx, rxName, "rx");
			send(tx, rxName, "boom", []);
		});

		U.run();
	}
}

/** Sent without registerClassAlias: arrives as a plain Object. */
class ArgThing {
	public var n:Int;

	public function new(n:Int)
		this.n = n;
}
