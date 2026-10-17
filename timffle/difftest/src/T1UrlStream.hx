import flash.events.Event;
import flash.events.HTTPStatusEvent;
import flash.events.IOErrorEvent;
import flash.events.ProgressEvent;
import flash.events.SecurityErrorEvent;
import flash.net.URLRequest;
import flash.net.URLStream;
import flash.utils.ByteArray;
import flash.utils.Endian;

/** URLStream progressive delivery: events, partial reads, close/stop mid-stream, errors.
 * Server: /data/slow sends n chunks of `size` bytes with `delay` s between them. */
class T1UrlStream {
	static var B = H.BASE;

	/** Records event order with consecutive progress events collapsed to "progress". */
	static function watch(s:URLStream, ?onProgress:ProgressEvent->Void, ?onEnd:String->Void):Array<String> {
		var order:Array<String> = [];
		function add(n:String) {
			if (n == "progress" && order.length > 0 && (order[order.length - 1] == "progress" || order[order.length - 1] == "progress")) {
				order[order.length - 1] = "progress";
				return;
			}
			order.push(n);
		}
		s.addEventListener(Event.OPEN, function(e:Event) add("open"));
		s.addEventListener(HTTPStatusEvent.HTTP_STATUS, function(e:HTTPStatusEvent) add("httpStatus(" + e.status + ")"));
		s.addEventListener(ProgressEvent.PROGRESS, function(e:ProgressEvent) {
			add("progress");
			if (onProgress != null)
				U.guard("progress", function() onProgress(e))();
		});
		s.addEventListener(Event.COMPLETE, function(e:Event) {
			add("complete");
			if (onEnd != null)
				U.guard("complete", function() onEnd("complete"))();
		});
		s.addEventListener(IOErrorEvent.IO_ERROR, function(e:IOErrorEvent) {
			add("ioError");
			H.log("ioError text=" + e.text + " errorID=" + e.errorID + " bubbles=" + e.bubbles);
			if (onEnd != null)
				U.guard("ioError", function() onEnd("ioError"))();
		});
		s.addEventListener(SecurityErrorEvent.SECURITY_ERROR, function(e:SecurityErrorEvent) {
			add("securityError");
			H.log("securityError text=" + e.text);
			if (onEnd != null)
				U.guard("securityError", function() onEnd("securityError"))();
		});
		return order;
	}

	static function prop(f:Void->Dynamic):String {
		try {
			return Std.string(f());
		} catch (e:Dynamic) {
			return "<" + H.err(e) + ">";
		}
	}

	/** Never throws: each property read is caught separately. */
	static function stateOf(s:URLStream):String
		return "connected=" + prop(function() return s.connected) + " bytesAvailable=" + prop(function() return s.bytesAvailable);

	static function main() {
		H.init("t1urlstream", 90000);

		U.step("initial state of an unopened stream", function(next) {
			var s = new URLStream();
			H.log(stateOf(s) + " endian=" + prop(function() return s.endian) + " objectEncoding=" + prop(function() return s.objectEncoding));
			H.attempt("readByte on unopened", function() H.log("readByte=" + s.readByte()));
			H.attempt("close on unopened", function() {
				s.close();
				H.log("close on unopened ok");
			});
			next();
		});

		U.step("progressive: 4 x 8192 bytes, 0.4 s apart, reading 3000 bytes per progress", function(next) {
			var s = new URLStream();
			var consumed = 0, bad = 0, nProg = 0, partial = 0, lastLoaded = -1.0, nonMono = 0, totalSeen = "";
			var acctOk = true;
			var t0 = flash.Lib.getTimer(), tFirst = -1;
			var inLoad = true;
			function eat(max:Int) {
				var n = Std.int(Math.min(s.bytesAvailable, max));
				if (n == 0)
					return;
				var b = new ByteArray();
				s.readBytes(b, 0, n);
				for (i in 0...n)
					if (b[i] != U.slowByte(consumed + i))
						bad++;
				consumed += n;
			}
			var order:Array<String> = null;
			order = watch(s, function(e) {
				nProg++;
				if (inLoad)
					H.log("progress dispatched synchronously inside load()");
				if (tFirst < 0)
					tFirst = flash.Lib.getTimer() - t0;
				if (e.bytesLoaded < lastLoaded)
					nonMono++;
				lastLoaded = e.bytesLoaded;
				if (e.bytesLoaded < e.bytesTotal)
					partial++;
				if (totalSeen.indexOf("" + e.bytesTotal) < 0)
					totalSeen += "[" + e.bytesTotal + "]";
				if (e.bytesLoaded - consumed != s.bytesAvailable)
					acctOk = false;
				if (nProg == 1)
					H.log("first progress: bytesTotal=" + e.bytesTotal + " connected=" + s.connected + " bubbles=" + e.bubbles);
				eat(3000);
			}, function(kind) {
				H.log("at " + kind + ": connected=" + s.connected + " accounting=" + (s.bytesAvailable == lastLoaded - consumed) + " lastLoaded=" + lastLoaded);
				eat(1 << 30);
				H.log("order=" + order.join(","));
				H.log("progressive (some progress with loaded<total)=" + (partial > 0));
				H.log("multiple progress events=" + (nProg >= 2));
				H.log("bytesTotal values seen=" + totalSeen + " nonMonotonic=" + nonMono);
				H.log("bytesAvailable == loaded - consumed at every progress=" + acctOk);
				H.log("consumed=" + consumed + " badBytes=" + bad);
				H.log("~ progressCount=" + nProg + " firstProgressMs=" + tFirst + " totalMs=" + (flash.Lib.getTimer() - t0));
				U.after(300, function() {
					H.log("300 ms after " + kind + ": " + stateOf(s));
					H.attempt("close after complete", function() {
						s.close();
						H.log("close after complete ok");
					});
					next();
				});
			});
			s.load(new URLRequest(B + "/data/slow?n=4&size=8192&delay=0.4"));
			inLoad = false;
			H.log("right after load(): " + stateOf(s) + " order=" + order.join(","));
		});

		U.step("no Content-Length (3 x 4096)", function(next) {
			var s = new URLStream();
			var totals = "";
			var order:Array<String> = null;
			order = watch(s, function(e) {
				if (totals.indexOf("[" + e.bytesTotal + "]") < 0)
					totals += "[" + e.bytesTotal + "]";
			}, function(kind) {
				H.log("order=" + order.join(",") + " bytesTotal values seen=" + totals + " " + stateOf(s));
				next();
			});
			s.load(new URLRequest(B + "/data/slow?n=3&size=4096&delay=0.3&nolen=1"));
		});

		U.step("close() mid-stream on first progress", function(next) {
			var s = new URLStream();
			var closed = false;
			var order:Array<String> = null;
			var seenAfter:Array<String> = [];
			order = watch(s, function(e) {
				if (closed) {
					seenAfter.push("progress");
					return;
				}
				closed = true;
				H.log("before close: connected=" + s.connected + " availableIsPartial=" + (s.bytesAvailable < 6 * 8192));
				s.close();
				H.log("after close: " + stateOf(s));
				H.attempt("readByte after close", function() H.log("readByte after close=" + s.readByte()));
			}, function(kind) seenAfter.push(kind));
			s.load(new URLRequest(B + "/data/slow?n=6&size=8192&delay=0.4"));
			U.after(3500, function() {
				H.log("order=" + order.join(",") + " eventsAfterClose=[" + seenAfter.join(",") + "] " + stateOf(s));
				next();
			});
		});

		U.step("stop() mid-stream on first progress (FP 11.4 API)", function(next) {
			var s = new URLStream();
			var stopped = false;
			var after:Array<String> = [];
			var order:Array<String> = null;
			order = watch(s, function(e) {
				if (stopped) {
					after.push("progress");
					return;
				}
				stopped = true;
				H.attempt("stop", function() {
					untyped s.stop();
					H.log("after stop: connected=" + s.connected + " availableIsPartial=" + (s.bytesAvailable > 0 && s.bytesAvailable < 49152));
				});
			}, function(kind) after.push(kind));
			s.load(new URLRequest(B + "/data/slow?n=6&size=8192&delay=0.4"));
			U.after(3500, function() {
				H.log("order=" + order.join(",") + " eventsAfterStop=[" + [for (i in 0...after.length) if (i == 0 || after[i] != after[i-1]) after[i]].join(",") + "] " + stateOf(s));
				next();
			});
		});

		U.step("HTTP 404", function(next) {
			var s = new URLStream();
			var order:Array<String> = null;
			order = watch(s, null, function(kind) {
				H.log("order=" + order.join(",") + " " + stateOf(s));
				next();
			});
			s.load(new URLRequest(B + "/data/404"));
		});

		U.step("connection refused (port 18767)", function(next) {
			var s = new URLStream();
			var order:Array<String> = null;
			order = watch(s, null, function(kind) {
				H.log("order=" + order.join(",") + " " + stateOf(s));
				next();
			});
			s.load(new URLRequest("http://127.0.0.1:18767/nothing"));
		});

		U.step("truncated body (Content-Length 16384, server sends 8192 then closes)", function(next) {
			var s = new URLStream();
			var lastLoaded = 0.0, total = 0.0;
			var order:Array<String> = null;
			order = watch(s, function(e) {
				lastLoaded = e.bytesLoaded;
				total = e.bytesTotal;
			}, function(kind) {
				H.log("order=" + order.join(",") + " lastLoaded=" + lastLoaded + " bytesTotal=" + total + " " + stateOf(s));
				next();
			});
			s.load(new URLRequest(B + "/data/slow?n=1&size=8192&delay=0.2&cut=1"));
		});

		U.step("typed reads, endian, EOF", function(next) {
			var s = new URLStream();
			watch(s, null, function(kind) {
				H.log("at " + kind + ": " + stateOf(s));
				H.log("readUnsignedByte=" + s.readUnsignedByte() + " readByte=" + s.readByte());
				H.log("readShort=" + s.readShort() + " readUnsignedShort=" + s.readUnsignedShort());
				H.log("readInt=" + s.readInt() + " readUnsignedInt=" + s.readUnsignedInt());
				s.endian = Endian.LITTLE_ENDIAN;
				H.log("LE readInt=" + s.readInt() + " readUnsignedInt=" + s.readUnsignedInt());
				H.log("LE readDouble=" + s.readDouble() + " readFloat=" + s.readFloat());
				H.log("readBoolean=" + s.readBoolean() + " remaining=" + s.bytesAvailable);
				var b = new ByteArray();
				b.writeUTFBytes("XY");
				s.readBytes(b, 1, 3);
				H.log("readBytes(b,1,3) into 'XY' -> len=" + b.length + " " + U.repr(b));
				H.attempt("readBytes length>available", function() {
					var c = new ByteArray();
					s.readBytes(c, 0, 1000);
					H.log("readBytes 1000 ok len=" + c.length);
				});
				H.log("after over-long readBytes: " + stateOf(s));
				var c = new ByteArray();
				s.readBytes(c);
				H.log("readBytes(c) with length=0 took " + c.length + " -> " + stateOf(s));
				H.attempt("readInt at EOF", function() H.log("readInt at EOF=" + s.readInt()));
				H.log("after EOF read: " + stateOf(s));
				H.attempt("position (11.4)", function() H.log("position=" + untyped s.position + " length=" + untyped s.length));
				next();
			});
			s.load(new URLRequest(B + "/data/blob?size=40"));
		});

		U.step("partial typed read at EOF leaves bytes untouched", function(next) {
			var s = new URLStream();
			watch(s, null, function(kind) {
				H.log("at " + kind + ": " + stateOf(s));
				H.attempt("readInt with 3 bytes", function() H.log("readInt=" + s.readInt()));
				H.log("after failed readInt: " + stateOf(s));
				H.attempt("readUTFBytes(5) with 3 bytes", function() H.log("readUTFBytes=" + s.readUTFBytes(5)));
				H.log("after failed readUTFBytes: " + stateOf(s));
				H.log("readUnsignedByte=" + s.readUnsignedByte());
				next();
			});
			s.load(new URLRequest(B + "/data/blob?size=3"));
		});

		U.step("load() again while the first load is streaming", function(next) {
			var s = new URLStream();
			var reloaded = false, ends = 0, firstByte = -1;
			var order:Array<String> = null;
			order = watch(s, function(e) {
				if (!reloaded) {
					reloaded = true;
					H.log("reloading at first progress; " + "connected=" + s.connected);
					s.load(new URLRequest(B + "/data/blob?size=10"));
					H.log("after second load(): " + stateOf(s));
				}
			}, function(kind) {
				ends++;
				if (ends == 1) {
					firstByte = s.bytesAvailable > 0 ? s.readUnsignedByte() : -1;
					H.log("first end=" + kind + " " + stateOf(s) + " firstByte=" + firstByte + " (blob byte0=" + U.blobByte(0) + ", slow byte0=" + U.slowByte(0) + ")");
				}
			});
			s.load(new URLRequest(B + "/data/slow?n=6&size=8192&delay=0.4"));
			U.after(3500, function() {
				H.log("order=" + order.join(",") + " ends=" + ends + " " + stateOf(s));
				next();
			});
		});

        for (eventName in [Event.OPEN, HTTPStatusEvent.HTTP_STATUS]) {
            var name = eventName;
            U.step("close from " + name + " listener", function(next) {
                var s = new URLStream();
                var order = watch(s);
                s.addEventListener(name, function(e:Event) { s.close(); });
                s.load(new URLRequest(B + "/data/blob?size=10"));
                U.after(500, function() {
                    H.log("order=" + order.join(",") + " " + stateOf(s));
                    next();
                });
            });
        }

		U.run();
	}
}
