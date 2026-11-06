/** Probe: Worker / MessageChannel / Mutex / Condition on the primordial worker of Flash Player 32,
 *  SecurityDomain.domainID, ApplicationInstaller / SystemUpdater reachability, Security.disableAVM1Loading.
 *  The blocking calls (receive(true) on an empty channel, Condition.wait() with no notifier) are timed;
 *  times go on "~" lines (ignored by compare.py) plus a coarse bucket on a normal line.
 *  Builds with -D harness (Flash) or without (Ruffle test). Sections: -D s4parts=<letters>. */
import flash.concurrent.Condition;
import flash.concurrent.Mutex;
import flash.system.*;
import flash.utils.ByteArray;

class S4System {
	static function step(label:String, f:Void->Void) {
		try {
			f();
		} catch (e:flash.errors.Error) {
			Out.line(label + " THREW " + e.name + " #" + e.errorID);
		}
	}

	static function qn(o:Dynamic):String {
		return o == null ? "null" : untyped __global__["flash.utils.getQualifiedClassName"](o);
	}

	static function bucket(ms:Float):String {
		return ms < 1000 ? "<1s" : ms < 10000 ? "1-10s" : ms < 20000 ? "10-20s" : ">20s";
	}

	static function timed(label:String, f:Void->Void) {
		var t0 = flash.Lib.getTimer();
		try {
			f();
			var dt = flash.Lib.getTimer() - t0;
			Out.line(label + " returned");
			Out.line("~ " + label + " after " + bucket(dt) + " ms=" + dt);
		} catch (e:flash.errors.Error) {
			var dt = flash.Lib.getTimer() - t0;
			Out.line(label + " THREW " + qn(e) + " #" + e.errorID);
			Out.line("~ " + label + " after " + bucket(dt) + " ms=" + dt);
		}
	}

	static function worker() {
		Out.line("// Worker");
		Out.line("Worker.isSupported=" + Worker.isSupported + " WorkerDomain.isSupported=" + WorkerDomain.isSupported);
		var w = Worker.current;
		Out.line("current=" + qn(w) + " isPrimordial=" + w.isPrimordial + " state=" + w.state);
		step("start", function() {
			w.start();
			Out.line("start() ok state=" + w.state);
		});
		step("terminate", function() Out.line("terminate()=" + w.terminate()));
		step("createWorker null", function() Out.line("createWorker(null)=" + qn(WorkerDomain.current.createWorker(null))));
		step("createWorker junk", function() {
			var b = new ByteArray();
			b.writeUTFBytes("not a swf");
			var nw = WorkerDomain.current.createWorker(b);
			Out.line("createWorker(junk)=" + qn(nw) + (nw != null ? " state=" + nw.state + " isPrimordial=" + nw.isPrimordial : ""));
			if (nw != null) {
				step("junk start", function() {
					nw.start();
					Out.line("junk start ok state=" + nw.state);
				});
				step("junk terminate", function() {
					var r = nw.terminate();
					// The state right after terminate() is racy in Flash (running or terminated).
					Out.line("junk terminate()=" + r + " state settled=" + (Std.string(nw.state) == "running" || Std.string(nw.state) == "terminated"));
				});
			}
		});
		step("listWorkers", function() {
			var v = WorkerDomain.current.listWorkers();
			Out.line("listWorkers length=" + v.length + " first is current=" + (v[0] == w));
		});
		step("shared null key", function() {
			w.setSharedProperty(null, 1);
			Out.line("setSharedProperty(null) ok get=" + w.getSharedProperty(null));
		});
		step("shared copy", function() {
			var o = {a: 1};
			w.setSharedProperty("o", o);
			var back = w.getSharedProperty("o");
			Out.line("shared copy same=" + (back == o) + " twice same=" + (w.getSharedProperty("o") == back) + " missing=" + w.getSharedProperty("missing"));
			var m = new Mutex();
			w.setSharedProperty("m", m);
			Out.line("mutex by reference=" + (w.getSharedProperty("m") == m) + " worker by reference=" + ({w.setSharedProperty("w", w); w.getSharedProperty("w") == w;}));
		});
	}

	static function channel() {
		Out.line("// MessageChannel");
		var w = Worker.current;
		step("self channel", function() {
			var c = w.createMessageChannel(w);
			Out.line("channel=" + qn(c) + " state=" + c.state + " messageAvailable=" + c.messageAvailable);
			var events = [];
			c.addEventListener("channelMessage", function(_) events.push("channelMessage"));
			c.addEventListener("channelState", function(_) events.push("channelState:" + c.state));
			c.send({x: 1});
			Out.line("after send messageAvailable=" + c.messageAvailable + " events in send=" + events.length);
			var r:Dynamic = c.receive();
			Out.line("receive x=" + r.x + " messageAvailable=" + c.messageAvailable);
			Out.line("receive empty=" + c.receive());
			timed("receive(true) empty", function() Out.line("receive(true) empty=" + c.receive(true)));
			c.send("one", 1);
			timed("send over queueLimit 1", function() c.send("two", 1));
			Out.line("queue: " + c.receive() + "," + c.receive());
			c.send("late");
			c.close();
			Out.line("after close state=" + c.state + " events=" + events.join(","));
			step("send after close", function() {
				c.send("x");
				Out.line("send after close ok");
			});
			step("receive after close", function() Out.line("receive after close=" + c.receive() + " state=" + c.state));
			haxe.Timer.delay(function() Out.line("next frame events=" + events.join(",") + " state=" + c.state), 50);
		});
		step("channel to null", function() Out.line("createMessageChannel(null)=" + qn(w.createMessageChannel(null))));
	}

	static function concurrent() {
		Out.line("// Mutex / Condition");
		Out.line("Mutex.isSupported=" + Mutex.isSupported + " Condition.isSupported=" + Condition.isSupported);
		var m:Mutex = null;
		step("new Mutex", function() {
			m = new Mutex();
			Out.line("new Mutex ok");
		});
		if (m == null)
			return;
		step("unlock without lock", function() {
			m.unlock();
			Out.line("unlock without lock ok");
		});
		step("lock twice", function() {
			m.lock();
			m.lock();
			Out.line("tryLock while owned=" + m.tryLock());
			m.unlock();
			m.unlock();
			m.unlock();
			Out.line("three unlocks ok");
			m.unlock();
			Out.line("fourth unlock ok");
		});
		step("Condition(null)", function() {
			var c = new Condition(null);
			Out.line("Condition(null) ok mutex=" + qn(c.mutex));
		});
		var c = new Condition(m);
		Out.line("condition mutex same=" + (c.mutex == m));
		step("notify unowned", function() {
			c.notify();
			Out.line("notify unowned ok");
		});
		step("notifyAll unowned", function() {
			c.notifyAll();
			Out.line("notifyAll unowned ok");
		});
		step("wait unowned", function() Out.line("wait unowned=" + c.wait(10)));
		m.lock();
		step("notify owned", function() {
			c.notify();
			c.notifyAll();
			Out.line("notify/notifyAll owned ok");
		});
		step("wait(-2)", function() Out.line("wait(-2)=" + c.wait(-2)));
		m.unlock();
	}

	/** Each blocking wait in its own frame: Flash allows one catchable script timeout per frame. */
	static function waits(done:Void->Void) {
		var cases:Array<Dynamic> = [300.0, 0.0, "notify+300", -1.0, 20000.0, "none"]; // wait(14000) measured once: returns true after 14 s
		function next() {
			if (cases.length == 0) {
				done();
				return;
			}
			var t:Dynamic = cases.shift();
			var m2 = new Mutex();
			var c2 = new Condition(m2);
			m2.lock();
			var label = "wait(" + t + ")";
			timed(label, function() {
				var r = if (t == "none") c2.wait() else if (t == "notify+300") {
					c2.notify();
					c2.wait(300);
				} else c2.wait(t);
				Out.line(label + "=" + r);
			});
			var depth = 0;
			try {
				while (depth < 5) {
					m2.unlock();
					depth++;
				}
			} catch (e:flash.errors.Error) {}
			Out.line("after " + label + " held depth=" + depth);
			haxe.Timer.delay(next, 100);
		}
		next();
	}

	static function timeoutKind() {
		var m2 = new Mutex();
		var c2 = new Condition(m2);
		m2.lock();
		try {
			c2.wait(-1);
		} catch (e:Dynamic) {
			Out.line("timeout error class=" + qn(e) + " is ScriptTimeoutError=" + Std.isOfType(e, flash.errors.ScriptTimeoutError));
		}
	}

	static function security() {
		Out.line("// SecurityDomain / installer / updater / Security");
		step("domainID", function() {
			var id = SecurityDomain.currentDomain.domainID;
			Out.line("domainID type=" + untyped __typeof__(id) + " length=" + (id == null ? -1 : id.length) + " looks hex=" + (id != null && ~/^[0-9a-fA-F]+$/.match(id)) + " is url=" + (id != null && id.indexOf("://") > 0));
			Out.line("~ domainID=" + id);
			Out.line("domainID stable=" + (SecurityDomain.currentDomain.domainID == id) + " same object=" + (SecurityDomain.currentDomain == SecurityDomain.currentDomain));
		});
		step("new SecurityDomain", function() Out.line("new SecurityDomain=" + qn(untyped __new__(SecurityDomain))));
		var ad = flash.Lib.current.loaderInfo.applicationDomain;
		Out.line("ApplicationInstaller defined=" + ad.hasDefinition("flash.system.ApplicationInstaller") + " AuthorizedFeatures=" + ad.hasDefinition("flash.system.AuthorizedFeatures") + " SystemUpdater=" + ad.hasDefinition("flash.system.SystemUpdater"));
		if (ad.hasDefinition("flash.system.ApplicationInstaller")) {
			step("new ApplicationInstaller", function() {
				var C:Dynamic = ad.getDefinition("flash.system.ApplicationInstaller");
				var i:Dynamic = untyped __new__(C);
				Out.line("new ApplicationInstaller=" + qn(i));
			});
		}
		if (ad.hasDefinition("flash.system.AuthorizedFeatures")) {
			step("new AuthorizedFeatures", function() {
				var C:Dynamic = ad.getDefinition("flash.system.AuthorizedFeatures");
				var i:Dynamic = untyped __new__(C);
				Out.line("new AuthorizedFeatures=" + qn(i));
				step("createApplicationInstaller", function() Out.line("createApplicationInstaller=" + qn(i.createApplicationInstaller(null, null))));
			});
		}
		Out.line("disableAVM1Loading default=" + Security.disableAVM1Loading);
		step("set disableAVM1Loading", function() {
			Security.disableAVM1Loading = true;
			Out.line("after set=" + Security.disableAVM1Loading);
			Security.disableAVM1Loading = false;
			Out.line("after reset=" + Security.disableAVM1Loading);
		});
	}

	static function updater(done:Void->Void) {
		Out.line("// SystemUpdater (bad arguments only; no real update request)");
		var ad = flash.Lib.current.loaderInfo.applicationDomain;
		if (!ad.hasDefinition("flash.system.SystemUpdater")) {
			done();
			return;
		}
		var C:Dynamic = ad.getDefinition("flash.system.SystemUpdater");
		var u:Dynamic = null;
		step("new SystemUpdater", function() {
			u = untyped __new__(C);
			Out.line("new SystemUpdater=" + qn(u));
		});
		if (u != null) {
			step("fresh update(bogus)", function() {
				u.update("bogus");
				Out.line("update(bogus) ok");
			});
			step("same update(bogus) again", function() {
				u.update("bogus");
				Out.line("update(bogus) again ok");
			});
			step("cancel idle", function() {
				u.cancel();
				Out.line("cancel ok");
			});
			step("after cancel update(bogus)", function() {
				u.update("bogus");
				Out.line("update(bogus) after cancel ok");
			});
		}
		var u2:Dynamic = untyped __new__(C);
		step("second instance update(null)", function() {
			u2.update(null);
			Out.line("u2 update(null) ok");
		});
		step("second instance update(bogus)", function() {
			u2.update("bogus");
			Out.line("u2 update(bogus) ok");
		});
		var u3:Dynamic = untyped __new__(C);
		step("third instance update(bogus)", function() {
			u3.update("bogus");
			Out.line("u3 update(bogus) ok");
		});
		done();
	}

	static function main() {
		var parts:String = #if s4parts haxe.macro.Compiler.getDefine("s4parts") #else "wmcsuW" #end;
		#if harness
		H.init(#if s4name haxe.macro.Compiler.getDefine("s4name") #else "s4system" #end, 240000);
		#end
		if (parts.indexOf("w") >= 0) worker();
		if (parts.indexOf("m") >= 0) channel();
		if (parts.indexOf("c") >= 0) concurrent();
		if (parts.indexOf("s") >= 0) security();
		haxe.Timer.delay(function() {
			var fin = function() {
				if (parts.indexOf("u") >= 0)
					updater(Out.finish);
				else
					Out.finish();
			};
			if (parts.indexOf("t") >= 0)
				haxe.Timer.delay(timeoutKind, 1);
			if (parts.indexOf("W") >= 0)
				waits(fin);
			else
				haxe.Timer.delay(fin, parts.indexOf("t") >= 0 ? 20000 : 1);
		}, 200);
	}
}
