/** Probe: flash.ui / ByteArray atomics / automation / GameInput / PrintJob / GeolocationEvent /
 *  flash.sampler in Flash Player 32 — initial Keyboard.capsLock/numLock, ContextMenu.link,
 *  atomicCompareAndSwapLength with a negative length, error codes of the automation, game input and
 *  printing classes (PrintJob.start() is never called: it would open a modal dialog),
 *  GeolocationEvent.toString() field order, flash.sampler on the release player.
 *  Builds with -D harness (Flash) or without (Ruffle test). */
import flash.Lib;
import flash.automation.*;
import flash.events.GeolocationEvent;
import flash.net.URLRequest;
import flash.printing.*;
import flash.ui.*;
import flash.utils.ByteArray;

class S3Misc {
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

	static function keyboard() {
		Out.line("// Keyboard");
		Out.line("capsLock=" + Keyboard.capsLock + " numLock=" + Keyboard.numLock + " hasVirtualKeyboard=" + Keyboard.hasVirtualKeyboard + " physicalKeyboardType=" + Keyboard.physicalKeyboardType);
		step("isAccessible", function() Out.line("isAccessible=" + Keyboard.isAccessible()));
	}

	static function contextMenu() {
		Out.line("// ContextMenu");
		var cm = new ContextMenu();
		Out.line("link default=" + qn(cm.link) + " isSupported=" + ContextMenu.isSupported + " items=" + cm.customItems.length + " clipboardMenu=" + cm.clipboardMenu + " clipboardItems=" + qn(cm.clipboardItems));
		step("set link", function() {
			var r = new URLRequest("http://example.com/x");
			cm.link = r;
			Out.line("link after set same=" + (cm.link == r) + " url=" + cm.link.url);
			r.url = "http://example.com/y";
			Out.line("link after mutate url=" + cm.link.url);
			cm.link = null;
			Out.line("link after null=" + qn(cm.link));
		});
		step("link data", function() {
			var r = new URLRequest("http://example.com/x");
			r.data = "a=b";
			cm.link = r;
			Out.line("link with data accepted url=" + cm.link.url);
			var r2 = new URLRequest(null);
			cm.link = r2;
			Out.line("link with null url accepted=" + (cm.link == r2));
		});
		Lib.current.contextMenu = cm;
		Out.line("assigned to root: same=" + (Lib.current.contextMenu == cm));
	}

	static function atomics() {
		Out.line("// ByteArray atomics");
		var b = new ByteArray();
		b.length = 16;
		Out.line("shareable default=" + b.shareable);
		step("casLength ok", function() Out.line("casLength(16,8)=" + b.atomicCompareAndSwapLength(16, 8) + " length=" + b.length));
		step("casLength mismatch", function() Out.line("casLength(16,4)=" + b.atomicCompareAndSwapLength(16, 4) + " length=" + b.length));
		step("casLength negative new", function() Out.line("casLength(8,-1)=" + b.atomicCompareAndSwapLength(8, -1) + " length=" + b.length));
		step("casLength negative expected", function() Out.line("casLength(-1,4)=" + b.atomicCompareAndSwapLength(-1, 4) + " length=" + b.length));
		step("casLength big", function() Out.line("casLength(8,1000000)=" + b.atomicCompareAndSwapLength(8, 1000000) + " length=" + b.length));
		b.length = 16;
		step("casInt ok", function() Out.line("casInt(0,0,7)=" + b.atomicCompareAndSwapIntAt(0, 0, 7) + " again=" + b.atomicCompareAndSwapIntAt(0, 0, 9) + " byte0=" + b[0]));
		step("casInt unaligned", function() Out.line("casInt(1,0,7)=" + b.atomicCompareAndSwapIntAt(1, 0, 7)));
		step("casInt negative", function() Out.line("casInt(-4,0,7)=" + b.atomicCompareAndSwapIntAt(-4, 0, 7)));
		step("casInt past end", function() Out.line("casInt(16,0,7)=" + b.atomicCompareAndSwapIntAt(16, 0, 7)));
		step("casInt last", function() Out.line("casInt(12,0,7)=" + b.atomicCompareAndSwapIntAt(12, 0, 7)));
		step("casInt 13", function() Out.line("casInt(13,0,7)=" + b.atomicCompareAndSwapIntAt(13, 0, 7)));
		step("shareable set", function() {
			b.shareable = true;
			Out.line("shareable after set=" + b.shareable);
		});
	}

	static function automation() {
		Out.line("// flash.automation");
		step("ActionGenerator", function() {
			var g = new ActionGenerator();
			Out.line("ActionGenerator ok");
			step("generateAction null", function() {
				g.generateAction(null);
				Out.line("generateAction(null) ok");
			});
			step("generateAction mouse", function() {
				var m = new MouseAutomationAction(MouseAutomationAction.MOUSE_MOVE, 10, 10);
				Out.line("mouse action type=" + m.type + " x=" + m.stageX + " y=" + m.stageY + " delta=" + m.delta);
				g.generateAction(m);
				Out.line("generateAction(mouse) ok");
			});
			step("generateActions null", function() {
				g.generateActions(null);
				Out.line("generateActions(null) ok");
			});
			step("generateActions vector", function() {
				var v = new flash.Vector<AutomationAction>();
				v.push(new KeyboardAutomationAction(KeyboardAutomationAction.KEY_DOWN, 65));
				g.generateActions(cast v);
				Out.line("generateActions(vector) ok");
			});
			step("mouse bad type", function() {
				var m = new MouseAutomationAction(cast "bogus", 1, 2);
				Out.line("mouse bogus type=" + m.type);
			});
			step("keyboard bad type", function() {
				var k = new KeyboardAutomationAction(cast "bogus", 65);
				Out.line("keyboard bogus type=" + k.type + " code=" + k.keyCode);
			});
			step("action type set", function() {
				var m = new MouseAutomationAction(MouseAutomationAction.MOUSE_DOWN, 1, 2);
				m.type = "zzz";
				Out.line("type after set zzz=" + m.type);
			});
		});
		step("Configuration", function() {
			Out.line("deviceConfiguration=[" + Configuration.deviceConfiguration + "] testAutomationConfiguration=[" + Configuration.testAutomationConfiguration + "]");
			Configuration.deviceConfiguration = "abc";
			Out.line("deviceConfiguration after set=[" + Configuration.deviceConfiguration + "]");
			step("deviceConfiguration null", function() {
				Configuration.deviceConfiguration = null;
				Out.line("deviceConfiguration after null=[" + Configuration.deviceConfiguration + "]");
			});
		});
		step("StageCapture", function() {
			var sc = new StageCapture();
			Out.line("capturePTS=" + sc.capturePTS + " captureSource=" + sc.captureSource + " clipRect=" + sc.clipRect + " fileNameBase=" + sc.fileNameBase);
			step("captureBitmapData", function() Out.line("captureBitmapData=" + qn(sc.captureBitmapData())));
			step("capture bogus", function() {
				sc.capture("bogus");
				Out.line("capture(bogus) ok");
			});
			step("capture null", function() {
				sc.capture(null);
				Out.line("capture(null) ok");
			});
			step("capture nextFrame", function() {
				sc.capture(StageCapture.NEXT);
				Out.line("capture(nextFrame) ok");
			});
			step("captureSource bogus", function() {
				sc.captureSource = "bogus";
				Out.line("captureSource after bogus=" + sc.captureSource);
			});
			step("captureSource null", function() {
				sc.captureSource = null;
				Out.line("captureSource after null=" + sc.captureSource);
			});
			step("fileNameBase null", function() {
				sc.fileNameBase = null;
				Out.line("fileNameBase after null=" + sc.fileNameBase);
			});
			step("cancel", function() {
				sc.cancel();
				Out.line("cancel ok");
			});
		});
	}

	static function gameInput() {
		Out.line("// GameInput");
		var gi = new GameInput();
		Out.line("isSupported=" + GameInput.isSupported + " numDevices=" + GameInput.numDevices);
		step("getDeviceAt(0)", function() Out.line("getDeviceAt(0)=" + qn(GameInput.getDeviceAt(0))));
		step("getDeviceAt(-1)", function() Out.line("getDeviceAt(-1)=" + qn(GameInput.getDeviceAt(-1))));
		step("new GameInputDevice", function() Out.line("new GameInputDevice=" + qn(new GameInputDevice())));
		step("new GameInputControl", function() Out.line("new GameInputControl=" + qn(new GameInputControl())));
	}

	static function printing() {
		Out.line("// PrintJob");
		Out.line("hasPrinting=" + flash.system.Capabilities.hasPrinting + " isSupported=" + PrintJob.isSupported + " isActive=" + untyped PrintJob.isActive);
		step("new PrintJob", function() {
			var pj:Dynamic = new PrintJob();
			Out.line("orientation typeof=" + untyped __typeof__(pj.orientation) + " isNull=" + (pj.orientation == null));
			Out.line("pageWidth=" + pj.pageWidth + " pageHeight=" + pj.pageHeight + " paperWidth=" + pj.paperWidth + " paperHeight=" + pj.paperHeight + " orientation=" + pj.orientation + " isActive=" + untyped PrintJob.isActive);
			step("addPage before start", function() {
				pj.addPage(Lib.current);
				Out.line("addPage before start ok");
			});
			step("addPage null", function() {
				pj.addPage(null);
				Out.line("addPage(null) ok");
			});
			step("send before start", function() {
				pj.send();
				Out.line("send before start ok");
			});
			step("terminate before start", function() {
				pj.terminate();
				Out.line("terminate before start ok");
			});
			step("orientation bogus", function() {
				pj.orientation = "bogus";
				Out.line("orientation after bogus=" + pj.orientation);
			});
			step("orientation landscape", function() {
				pj.orientation = PrintJobOrientation.LANDSCAPE;
				Out.line("orientation after landscape=" + pj.orientation);
			});
			step("orientation null", function() {
				pj.orientation = null;
				Out.line("orientation after null=" + pj.orientation);
			});
			step("addPage options bad", function() {
				var o:Dynamic = new PrintJobOptions(true);
				o.printMethod = "bogus";
				Out.line("printMethod after bogus=" + o.printMethod + " pixelsPerInch=" + o.pixelsPerInch + " printAsBitmap=" + o.printAsBitmap);
			});
			step("air members", function() Out.line("supportsPageSetupDialog? " + untyped __in__("supportsPageSetupDialog", pj) + " selectPaperSize? " + untyped __in__("selectPaperSize", pj) + " terminate? " + untyped __in__("terminate", pj) + " isActive? " + untyped __in__("isActive", PrintJob)));
		});
	}

	static function geolocation() {
		Out.line("// GeolocationEvent");
		var ad = flash.Lib.current.loaderInfo.applicationDomain;
		var names = ["flash.events.GeolocationEvent", "flash.sensors.Geolocation", "flash.sensors.Accelerometer", "flash.events.AccelerometerEvent", "flash.events.StatusEvent"];
		Out.line(names.map(function(n) return n + "=" + ad.hasDefinition(n)).join(" "));
		if (ad.hasDefinition("flash.events.GeolocationEvent")) {
			step("geo full", function() {
				var C:Dynamic = ad.getDefinition("flash.events.GeolocationEvent");
				var e:Dynamic = untyped __new__(C, "update", false, false, 1.5, 2.5, 3.5, 4.5, 5.5, 6.5, 7.5, 8.5);
				Out.line("toString=" + e.toString());
				Out.line("clone=" + e.clone().toString());
				var d:Dynamic = untyped __new__(C, "custom");
				Out.line("defaults=" + d.toString());
			});
		}
		if (ad.hasDefinition("flash.sensors.Geolocation")) {
			step("Geolocation", function() {
				var G:Dynamic = ad.getDefinition("flash.sensors.Geolocation");
				Out.line("Geolocation.isSupported=" + G.isSupported);
			});
		}
	}

	static function sf(name:String):Dynamic {
		return flash.Lib.current.loaderInfo.applicationDomain.getDefinition("flash.sampler." + name);
	}

	/** Iterate an object with for..in names (works on Array and on iterable host objects). */
	static function memberList(names:Dynamic):Array<String> {
		var out = [];
		if (names == null)
			return out;
		var keys:Array<Dynamic> = untyped __keys__(names);
		for (k in keys) {
			var q:Dynamic = names[k];
			out.push(q == null ? "null" : (q.uri != null && q.uri != "" ? q.uri + "::" : "") + Std.string(q.localName != null ? q.localName : q));
		}
		return out;
	}

	static function sampler() {
		Out.line("// flash.sampler");
		step("samples", function() {
			sf("startSampling")();
			var o = {a: 1, b: "x"};
			var samples:Dynamic = sf("getSamples")();
			Out.line("getSamples=" + qn(samples) + " isNull=" + (samples == null) + " isUndefined=" + (untyped __typeof__(samples) == "undefined"));
			var qa = new flash.utils.QName("", "a");
			Out.line("getSampleCount=" + sf("getSampleCount")() + " getSize=" + sf("getSize")(o) + " getInvocationCount=" + sf("getInvocationCount")(o, qa) + " getGetterInvocationCount=" + sf("getGetterInvocationCount")(o, qa) + " getSetterInvocationCount=" + sf("getSetterInvocationCount")(o, qa) + " isGetterSetter=" + sf("isGetterSetter")(o, qa));
		});
		step("getMemberNames obj", function() {
			var o = {a: 1, b: "x"};
			var names:Dynamic = sf("getMemberNames")(o, true);
			Out.line("getMemberNames obj=" + qn(names) + " isArray=" + Std.isOfType(names, Array));
			var list = memberList(names);
			list.sort(function(a, b) return a < b ? -1 : a > b ? 1 : 0);
			Out.line("names=" + list.join(","));
		});
		step("getMemberNames Sprite", function() {
			var sp = new flash.display.Sprite();
			var list = memberList(sf("getMemberNames")(sp, true));
			var as3 = list.filter(function(n) return n.indexOf("http://adobe.com/AS3/2006/builtin") == 0).length;
			Out.line("getMemberNames(Sprite,true) count>50=" + (list.length > 50) + " as3ns=" + as3 + " has x=" + (list.indexOf("x") >= 0) + " has addChild=" + (list.indexOf("addChild") >= 0) + " has hasOwnProperty=" + (list.filter(function(n) return n.indexOf("hasOwnProperty") >= 0).length));
			var l2 = memberList(sf("getMemberNames")(sp, false));
			Out.line("getMemberNames(Sprite,false) count=" + l2.length + " first=" + l2.slice(0, 3).join(","));
		});
		step("saved this", function() {
			Out.line("getSavedThis=" + qn(sf("getSavedThis")(function() {})) + " getLexicalScopes=" + qn(sf("getLexicalScopes")(function() {})) + " getMasterString=" + qn(sf("getMasterString")("abc".substr(1))));
		});
		step("other", function() {
			sf("stopSampling")();
			sf("clearSamples")();
			sf("pauseSampling")();
			sf("sampleInternalAllocs")(true);
			sf("setSamplerCallback")(function() {});
			Out.line("other sampler calls ok");
		});
		step("getMemberNames null", function() Out.line("getMemberNames(null)=" + qn(sf("getMemberNames")(null, true))));
		step("getSize null", function() Out.line("getSize(null)=" + sf("getSize")(null)));
		step("getInvocationCount null", function() Out.line("getInvocationCount(null,null)=" + sf("getInvocationCount")(null, null)));
		step("Sample new", function() Out.line("new Sample=" + qn(untyped __new__(__global__["flash.sampler.Sample"]))));
		step("NewObjectSample new", function() Out.line("new NewObjectSample=" + qn(untyped __new__(__global__["flash.sampler.NewObjectSample"]))));
		step("StackFrame new", function() Out.line("new StackFrame=" + qn(untyped __new__(__global__["flash.sampler.StackFrame"]))));
	}

	static function main() {
		var parts:String = #if s3parts haxe.macro.Compiler.getDefine("s3parts") #else "kcabgpqs" #end;
		Out.start(#if s3name haxe.macro.Compiler.getDefine("s3name") #else "s3misc" #end);
		if (parts.indexOf("k") >= 0) keyboard();
		if (parts.indexOf("c") >= 0) contextMenu();
		if (parts.indexOf("a") >= 0) atomics();
		if (parts.indexOf("b") >= 0) automation();
		if (parts.indexOf("g") >= 0) gameInput();
		if (parts.indexOf("p") >= 0) printing();
		if (parts.indexOf("q") >= 0) geolocation();
		if (parts.indexOf("s") >= 0) sampler();
		Out.finish();
	}
}
