/** Probe (no golden): flash.desktop.Clipboard, flash.accessibility.Accessibility and
 *  flash.debugger.enterDebugger in Flash Player (not AIR). Three phases: outside any user event,
 *  inside a mouse click (the harness driver sends a real click through XTest), and inside the
 *  Event.PASTE handler (the driver presses Ctrl+V). Members are reached by name so AIR-only ones
 *  are visible without Haxe externs. Build with -swf-version 32, run in the standalone projector
 *  served over HTTP. */
import flash.Lib;
import flash.display.Sprite;
import flash.events.Event;
import flash.events.MouseEvent;
import flash.events.KeyboardEvent;
import flash.text.TextField;
import flash.text.TextFieldType;

class D50ClipAcc {
	static var clipCls:Dynamic;
	static var clip:Dynamic;
	static var qn:Dynamic;
	static var phase = "p1";
	static var clicked = false;
	static var pasted = false;

	static function step(label:String, f:Void->Void) {
		try {
			f();
		} catch (e:flash.errors.Error) {
			H.log(phase + " " + label + " THREW " + qn(e) + " #" + e.errorID + " " + e.message);
		}
	}

	static function show(label:String, v:Dynamic) {
		H.log(phase + " " + label + " (" + qn(v) + ") = " + Std.string(v));
	}

	static function formats() {
		var f:Array<Dynamic> = clip.formats;
		H.log(phase + " formats (" + qn(f) + ") len=" + f.length + " [" + f.join(",") + "]" + " same=" + (clip.formats == f));
	}

	static function handler(fmt:String):Dynamic {
		H.log(phase + " handler called for " + fmt);
		return "from-handler-" + fmt;
	}

	static function accessibility() {
		var acc:Dynamic = untyped __global__["flash.accessibility.Accessibility"];
		step("Accessibility.active", function() show("Accessibility.active", acc.active));
		step("Accessibility.updateProperties()", function() show("updateProperties", acc.updateProperties()));
		step("Accessibility.sendEvent(sprite,0,0x8005)", function() show("sendEvent", acc.sendEvent(Lib.current, 0, 0x8005)));
		step("Accessibility.sendEvent(sprite,1,0x800E,true)", function() show("sendEvent2", acc.sendEvent(Lib.current, 1, 0x800E, true)));
		step("Accessibility.sendEvent(null,0,0)", function() show("sendEvent null", acc.sendEvent(null, 0, 0)));
	}

	static function debugger() {
		step("enterDebugger lookup", function() {
			var f:Dynamic = untyped __global__["flash.debugger.enterDebugger"];
			show("enterDebugger", f);
			show("enterDebugger()", f());
			show("enterDebugger(1,2)", f(1, 2));
		});
	}

	static function clipboardCalls() {
		step("formats", formats);
		step("hasFormat(TEXT)", function() show("hasFormat(TEXT)", clip.hasFormat("air:text")));
		step("hasFormat(bogus)", function() show("hasFormat(bogus)", clip.hasFormat("bogus")));
		step("hasFormat(null)", function() show("hasFormat(null)", clip.hasFormat(null)));
		step("getData(TEXT)", function() show("getData(TEXT)", clip.getData("air:text")));
		step("getData(TEXT,cloneOnly)", function() show("getData(TEXT,cloneOnly)", clip.getData("air:text", "cloneOnly")));
		step("getData(TEXT,bogus)", function() show("getData(TEXT,bogus)", clip.getData("air:text", "bogus")));
		step("getData(null)", function() show("getData(null)", clip.getData(null)));
		step("getData(bogus)", function() show("getData(bogus)", clip.getData("bogus")));
		step("clearData(TEXT)", function() show("clearData(TEXT)", clip.clearData("air:text")));
		step("clearData(null)", function() show("clearData(null)", clip.clearData(null)));
		step("clear()", function() show("clear()", clip.clear()));
		step("setData(TEXT,hello)", function() show("setData(TEXT,hello)", clip.setData("air:text", "hello")));
		step("setData(TEXT,123)", function() show("setData(TEXT,123)", clip.setData("air:text", 123)));
		step("setData(TEXT,null)", function() show("setData(TEXT,null)", clip.setData("air:text", null)));
		step("setData(null,x)", function() show("setData(null,x)", clip.setData(null, "x")));
		step("setData(HTML,<b>x</b>)", function() show("setData(HTML)", clip.setData("air:html", "<b>x</b>")));
		step("setData(URL,http://example.com/)", function() show("setData(URL)", clip.setData("air:url", "http://example.com/")));
		step("setData(RTF,ByteArray)", function() {
			var ba:Dynamic = Type.createInstance(untyped __global__["flash.utils.ByteArray"], []);
			ba.writeUTFBytes("{\\rtf1 x}");
			show("setData(RTF)", clip.setData("air:rtf", ba));
		});
		step("setData(BITMAP,BitmapData)", function() {
			var bd:Dynamic = Type.createInstance(untyped __global__["flash.display.BitmapData"], [2, 2]);
			show("setData(BITMAP)", clip.setData("air:bitmap", bd));
		});
		step("setData(FILE_LIST,[])", function() show("setData(FILE_LIST)", clip.setData("air:file list", [])));
		step("setData(custom,{a:1})", function() show("setData(custom)", clip.setData("custom", {a: 1})));
		step("setData(custom2,{a:1},false)", function() show("setData(custom2,false)", clip.setData("custom2", {a: 1}, false)));
		step("formats after sets", formats);
		step("hasFormat(TEXT) after", function() show("hasFormat(TEXT) after", clip.hasFormat("air:text")));
		step("hasFormat(custom) after", function() show("hasFormat(custom) after", clip.hasFormat("custom")));
		step("getData(TEXT) after", function() show("getData(TEXT) after", clip.getData("air:text")));
		step("getData(custom) after", function() show("getData(custom) after", clip.getData("custom")));
		step("setDataHandler(TEXT,fn)", function() show("setDataHandler(TEXT)", clip.setDataHandler("air:text", handler)));
		step("setDataHandler(custom3,fn)", function() show("setDataHandler(custom3)", clip.setDataHandler("custom3", handler)));
		step("setDataHandler(custom4,null)", function() show("setDataHandler(custom4,null)", clip.setDataHandler("custom4", null)));
		step("setDataHandler(null,fn)", function() show("setDataHandler(null,fn)", clip.setDataHandler(null, handler)));
		step("formats after handlers", formats);
		step("clearData(TEXT) after", function() show("clearData(TEXT) after", clip.clearData("air:text")));
		step("formats after clearData", formats);
		step("clear() after", function() show("clear() after", clip.clear()));
		step("formats after clear", formats);
		step("setData(TEXT,pasteme)", function() show("setData(TEXT,pasteme)", clip.setData("air:text", "pasteme")));
		step("setData(custom,{b:2})", function() show("setData(custom,{b:2})", clip.setData("custom", {b: 2})));
		step("setDataHandler(custom3,fn) 2", function() show("setDataHandler(custom3) 2", clip.setDataHandler("custom3", handler)));
		step("formats end", formats);
	}

	static function main() {
		H.init("d50clipacc", 60000);
		qn = untyped __global__["flash.utils.getQualifiedClassName"];
		clipCls = untyped __global__["flash.desktop.Clipboard"];
		step("new Clipboard()", function() show("new Clipboard()", Type.createInstance(clipCls, [])));
		step("generalClipboard", function() {
			clip = clipCls.generalClipboard;
			show("generalClipboard", clip);
			H.log("generalClipboard same=" + (clipCls.generalClipboard == clip));
		});
		step("supportsFilePromise", function() show("supportsFilePromise", clip.supportsFilePromise));
		step("constructor", function() show("constructor", clip.constructor));
		var fmts:Dynamic = untyped __global__["flash.desktop.ClipboardFormats"];
		step("ClipboardFormats", function() H.log("formats consts: " + fmts.TEXT_FORMAT + " " + fmts.HTML_FORMAT + " " + fmts.RICH_TEXT_FORMAT + " " + fmts.URL_FORMAT + " " + fmts.BITMAP_FORMAT + " " + fmts.FILE_LIST_FORMAT + " " + fmts.FILE_PROMISE_LIST_FORMAT));
		accessibility();
		debugger();
		clipboardCalls();
		H.log("# p1 done; waiting for click");

		var tf = new TextField();
		tf.type = TextFieldType.INPUT;
		tf.width = 400;
		tf.height = 300;
		tf.border = true;
		tf.text = "focus me";
		Lib.current.addChild(tf);
		Lib.current.stage.focus = tf;

		Lib.current.stage.addEventListener(MouseEvent.CLICK, function(e:MouseEvent) {
			if (clicked) return;
			clicked = true;
			phase = "p2";
			H.log("# click received at " + e.stageX + "," + e.stageY + " target=" + qn(e.target));
			accessibility();
			clipboardCalls();
			Lib.current.stage.focus = tf;
			H.log("# p2 done; waiting for paste, focus=" + qn(Lib.current.stage.focus));
			haxe.Timer.delay(function() {
				if (!pasted) {
					H.log("# no paste received");
					H.done();
				}
			}, 15000);
		});
		Lib.current.stage.addEventListener(KeyboardEvent.KEY_DOWN, function(e:KeyboardEvent) {
			H.log("# keyDown code=" + e.keyCode + " ctrl=" + e.ctrlKey + " target=" + qn(e.target));
		});
		var onPaste = function(e:Event) {
			if (pasted) return;
			pasted = true;
			phase = "p3";
			H.log("# paste event type=" + e.type + " target=" + qn(e.target) + " current=" + qn(e.currentTarget) + " phase=" + e.eventPhase + " tf.text=" + tf.text);
			clipboardCalls();
			step("getData(custom3) in paste", function() show("getData(custom3)", clip.getData("custom3")));
			step("getData(custom3,cloneOnly) in paste", function() show("getData(custom3,cloneOnly)", clip.getData("custom3", "cloneOnly")));
			step("getData(custom,originalOnly) in paste", function() show("getData(custom,originalOnly)", clip.getData("custom", "originalOnly")));
			step("getData(custom,cloneOnly) in paste", function() show("getData(custom,cloneOnly)", clip.getData("custom", "cloneOnly")));
			haxe.Timer.delay(function() {
				phase = "p4";
				H.log("# after paste (next frame) tf.text=" + tf.text);
				step("getData(TEXT) after paste", function() show("getData(TEXT) after paste", clip.getData("air:text")));
				step("hasFormat(TEXT) after paste", function() show("hasFormat(TEXT) after paste", clip.hasFormat("air:text")));
				step("formats after paste", formats);
				H.done();
			}, 100);
		};
		tf.addEventListener(Event.PASTE, onPaste);
		Lib.current.stage.addEventListener(Event.PASTE, onPaste);
		haxe.Timer.delay(function() {
			if (!clicked) {
				H.log("# no click received");
				H.done();
			}
		}, 25000);
	}
}
