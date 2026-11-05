/** Probe: text members in Flash Player 32 — Font.enumerateFonts(true), TextSnapshot run boxes of a
 *  loaded SWF with static text (static.swf = tests/.../static_text/test.swf), TextRenderer error codes,
 *  TextField.getImageReference with a loaded <img>, getRawText/getXMLText/insertXMLText.
 *  Builds with -D harness (Flash) or without (Ruffle test; loads static.swf relative to the test). */
import flash.Lib;
import flash.display.*;
import flash.events.Event;
import flash.events.IOErrorEvent;
import flash.net.URLRequest;
import flash.system.ApplicationDomain;
import flash.system.LoaderContext;
import flash.text.*;

class S2Text {
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

	static function n(x:Float):String {
		return "" + (Math.round(x * 100) / 100);
	}

	static function base():String {
		#if harness
		return H.BASE + "/asset/";
		#else
		return "";
		#end
	}

	static function fonts() {
		Out.line("// Font.enumerateFonts");
		var dev = Font.enumerateFonts(true);
		var emb = Font.enumerateFonts(false);
		var dnames = [];
		for (f in dev) dnames.push(f.fontName);
		Out.line("device count>20=" + (dev.length > 20) + " embedded=" + emb.length);
		var sorted = dnames.copy();
		sorted.sort(function(a, b) return a < b ? -1 : a > b ? 1 : 0);
		Out.line("device[0] type=" + (dev.length > 0 ? Std.string(dev[0].fontType) : "-") + " style=" + (dev.length > 0 ? Std.string(dev[0].fontStyle) : "-") + " sorted=" + (dnames.join("|") == sorted.join("|")));
		Out.line("has Arial=" + (dnames.indexOf("Arial") >= 0) + " has _sans=" + (dnames.indexOf("_sans") >= 0) + " has Times New Roman=" + (dnames.indexOf("Times New Roman") >= 0));
		var dup = false;
		for (i in 1...dnames.length) if (dnames[i] == dnames[i - 1]) dup = true;
		Out.line("duplicates=" + dup + " all regular=" + Lambda.foreach(dev, function(f) return f.fontStyle == FontStyle.REGULAR));
		Out.line("hasGlyphs on device font: " + (dev.length > 0 ? "" + dev[0].hasGlyphs("A") : "-"));
	}

	static function renderer() {
		Out.line("// TextRenderer");
		Out.line("defaults antiAliasType=" + TextRenderer.antiAliasType + " displayMode=" + TextRenderer.displayMode + " maxLevel=" + TextRenderer.maxLevel);
		step("displayMode bogus", function() {
			TextRenderer.displayMode = cast "bogus";
			Out.line("displayMode after bogus=" + TextRenderer.displayMode);
		});
		step("displayMode null", function() {
			TextRenderer.displayMode = null;
			Out.line("displayMode after null=" + TextRenderer.displayMode);
		});
		step("displayMode lcd", function() {
			TextRenderer.displayMode = TextDisplayMode.LCD;
			Out.line("displayMode after lcd=" + TextRenderer.displayMode);
			TextRenderer.displayMode = TextDisplayMode.DEFAULT;
		});
		step("maxLevel 5", function() {
			TextRenderer.maxLevel = 5;
			Out.line("maxLevel after 5=" + TextRenderer.maxLevel);
		});
		step("maxLevel 7", function() {
			TextRenderer.maxLevel = 7;
			Out.line("maxLevel after 7=" + TextRenderer.maxLevel);
		});
		step("maxLevel 0", function() {
			TextRenderer.maxLevel = 0;
			Out.line("maxLevel after 0=" + TextRenderer.maxLevel);
		});
		step("maxLevel -1", function() {
			TextRenderer.maxLevel = -1;
			Out.line("maxLevel after -1=" + TextRenderer.maxLevel);
			TextRenderer.maxLevel = 4;
		});
		step("antiAliasType bogus", function() {
			TextRenderer.antiAliasType = cast "bogus";
			Out.line("antiAliasType after bogus=" + TextRenderer.antiAliasType);
		});
		step("antiAliasType advanced", function() {
			TextRenderer.antiAliasType = AntiAliasType.ADVANCED;
			Out.line("antiAliasType after advanced=" + TextRenderer.antiAliasType);
		});
		for (v in ["normal", "default", "off", "advanced", "bogus", null]) {
			step("antiAliasType " + v, function() {
				TextRenderer.antiAliasType = cast v;
				Out.line("antiAliasType after " + v + "=" + TextRenderer.antiAliasType);
			});
		}
		for (v in ["default", "crt", "lcd", "LCD", ""]) {
			step("displayMode " + v, function() {
				TextRenderer.displayMode = cast v;
				Out.line("displayMode after " + v + "=" + TextRenderer.displayMode);
			});
		}
		for (v in [3, 4, 8, 7, 100]) {
			step("maxLevel " + v, function() {
				TextRenderer.maxLevel = v;
				Out.line("maxLevel after " + v + "=" + TextRenderer.maxLevel);
			});
		}
		step("table null style", function() {
			TextRenderer.setAdvancedAntiAliasingTable("Arial", null, TextColorType.DARK_COLOR, [new CSMSettings(12, 0, 0)]);
			Out.line("table null style accepted");
		});
		step("table null colorType", function() {
			TextRenderer.setAdvancedAntiAliasingTable("Arial", FontStyle.REGULAR, null, [new CSMSettings(12, 0, 0)]);
			Out.line("table null colorType accepted");
		});
		step("table null entry", function() {
			TextRenderer.setAdvancedAntiAliasingTable("Arial", FontStyle.REGULAR, TextColorType.DARK_COLOR, [null]);
			Out.line("table null entry accepted");
		});
		step("table ok", function() {
			TextRenderer.setAdvancedAntiAliasingTable("Arial", FontStyle.REGULAR, TextColorType.DARK_COLOR, [new CSMSettings(12, 0, 0)]);
			Out.line("table ok");
		});
		step("table bad style", function() {
			TextRenderer.setAdvancedAntiAliasingTable("Arial", cast "bogus", TextColorType.DARK_COLOR, [new CSMSettings(12, 0, 0)]);
			Out.line("table bad style accepted");
		});
		step("table bad colorType", function() {
			TextRenderer.setAdvancedAntiAliasingTable("Arial", FontStyle.REGULAR, cast "bogus", [new CSMSettings(12, 0, 0)]);
			Out.line("table bad colorType accepted");
		});
		step("table bad entry", function() {
			TextRenderer.setAdvancedAntiAliasingTable("Arial", FontStyle.REGULAR, TextColorType.DARK_COLOR, [1, 2]);
			Out.line("table bad entry accepted");
		});
		step("table null name", function() {
			TextRenderer.setAdvancedAntiAliasingTable(null, FontStyle.REGULAR, TextColorType.DARK_COLOR, [new CSMSettings(12, 0, 0)]);
			Out.line("table null name accepted");
		});
		step("table null table", function() {
			TextRenderer.setAdvancedAntiAliasingTable("Arial", FontStyle.REGULAR, TextColorType.DARK_COLOR, null);
			Out.line("table null table accepted");
		});
		step("table empty", function() {
			TextRenderer.setAdvancedAntiAliasingTable("Arial", FontStyle.REGULAR, TextColorType.DARK_COLOR, []);
			Out.line("table empty accepted");
		});
	}

	static function xmlText() {
		Out.line("// getRawText/getXMLText/insertXMLText");
		var tf = new TextField();
		tf.width = 300;
		Lib.current.addChild(tf);
		tf.htmlText = "<p>Hello <b>bold</b> <i>it</i></p><p>second</p>";
		Out.line("text=[" + tf.text + "] len=" + tf.length);
		step("getRawText", function() Out.line("raw=[" + tf.getRawText() + "]"));
		step("getXMLText()", function() Out.line("xml=[" + tf.getXMLText() + "]"));
		step("getXMLText(2,5)", function() Out.line("xml(2,5)=[" + tf.getXMLText(2, 5) + "]"));
		step("getXMLText(6,10)", function() Out.line("xml(6,10)=[" + tf.getXMLText(6, 10) + "]"));
		step("getXMLText(5,2)", function() Out.line("xml(5,2)=[" + tf.getXMLText(5, 2) + "]"));
		step("getXMLText(-3,100)", function() Out.line("xml(-3,100)=[" + tf.getXMLText(-3, 100) + "]"));
		step("getXMLText(100,200)", function() Out.line("xml(100,200)=[" + tf.getXMLText(100, 200) + "]"));
		Out.line("htmlText=[" + tf.htmlText + "]");
		step("insertXMLText(0,5)", function() {
			tf.insertXMLText(0, 5, "<b>Bye</b>");
			Out.line("after insert text=[" + tf.text + "] html=[" + tf.htmlText + "]");
		});
		step("insertXMLText(2,2) plain", function() {
			tf.insertXMLText(2, 2, "zz");
			Out.line("after insert2 text=[" + tf.text + "] html=[" + tf.htmlText + "]");
		});
		step("insertXMLText(0,1) pasting", function() {
			tf.insertXMLText(0, 1, "<i>P</i>", true);
			Out.line("after insert3 text=[" + tf.text + "] html=[" + tf.htmlText + "]");
		});
		step("insertXMLText(5,2) reversed", function() {
			tf.insertXMLText(5, 2, "R");
			Out.line("after insert4 text=[" + tf.text + "]");
		});
		step("insertXMLText(-1,1)", function() {
			tf.insertXMLText(-1, 1, "N");
			Out.line("after insert5 text=[" + tf.text + "]");
		});
		step("insertXMLText(100,200)", function() {
			tf.insertXMLText(100, 200, "E");
			Out.line("after insert6 text=[" + tf.text + "]");
		});
		step("insertXMLText null", function() {
			tf.insertXMLText(0, 1, null);
			Out.line("after insert7 text=[" + tf.text + "]");
		});
		step("getXMLText plain field", function() {
			var p = new TextField();
			p.text = "plain\ntext";
			Out.line("plain xml=[" + p.getXMLText() + "] raw=[" + p.getRawText() + "]");
		});
		step("xml special chars", function() {
			var p = new TextField();
			p.text = "a<b>&\"c'";
			Out.line("special xml=[" + p.getXMLText() + "]");
		});
		step("xml multiline", function() {
			var p = new TextField();
			p.multiline = true;
			p.htmlText = "<p align='center'><font size='20' color='#ff0000' face='_sans'>one</font></p><p>two <u>u</u> <a href='http://x/' target='_blank'>link</a></p>";
			Out.line("multiline text=[" + p.text.split("\r").join("\\r").split("\n").join("\\n") + "]");
			Out.line("multiline xml=[" + p.getXMLText().split("\r").join("\\r") + "]");
			Out.line("multiline raw=[" + p.getRawText().split("\r").join("\\r").split("\n").join("\\n") + "]");
		});
		step("insertXMLText roundtrip", function() {
			var p = new TextField();
			p.width = 300;
			p.htmlText = "abc <b>def</b>";
			var x = p.getXMLText(4, 7);
			p.insertXMLText(0, 1, x);
			Out.line("roundtrip text=[" + p.text + "] html=[" + p.htmlText + "]");
		});
		step("insertXMLText minimal", function() {
			var p = new TextField();
			p.text = "hello";
			p.insertXMLText(1, 3, "<flashrichtext version=\"1\"><textformat bold=\"true\">(XY)</textformat></flashrichtext>");
			Out.line("minimal text=[" + p.text + "] html=[" + p.htmlText + "]");
		});
		step("insertXMLText no parens", function() {
			var p = new TextField();
			p.text = "hello";
			p.insertXMLText(0, 0, "<flashrichtext version=\"1\"><textformat>XY</textformat></flashrichtext>");
			Out.line("no parens text=[" + p.text + "]");
		});
		step("insertXMLText empty", function() {
			var p = new TextField();
			p.text = "hello";
			p.insertXMLText(0, 5, "<flashrichtext version=\"1\"></flashrichtext>");
			Out.line("empty rich text=[" + p.text + "]");
		});
		step("insertXMLText reversed", function() {
			var p = new TextField();
			p.text = "hello";
			p.insertXMLText(4, 1, "<flashrichtext version=\"1\"><textformat>(Z)</textformat></flashrichtext>");
			Out.line("reversed text=[" + p.text + "]");
		});
		step("insertXMLText past end", function() {
			var p = new TextField();
			p.text = "hello";
			p.insertXMLText(10, 20, "<flashrichtext version=\"1\"><textformat>(Z)</textformat></flashrichtext>");
			Out.line("past end text=[" + p.text + "]");
		});
		step("insertXMLText two runs", function() {
			var p = new TextField();
			p.text = "hello";
			p.insertXMLText(5, 5, "<flashrichtext version=\"1\"><textformat italic=\"true\" size=\"20\">(A)</textformat><textformat color=\"255\">(B)</textformat></flashrichtext>");
			Out.line("two runs text=[" + p.text + "] html=[" + p.htmlText + "]");
		});
		step("getImageReference unknown", function() Out.line("img unknown=" + qn(tf.getImageReference("nope"))));
		step("getImageReference null", function() Out.line("img null=" + qn(tf.getImageReference(null))));
	}

	static var imgTf:TextField;

	static function images() {
		Out.line("// getImageReference");
		imgTf = new TextField();
		imgTf.width = 300;
		imgTf.height = 200;
		imgTf.multiline = true;
		Lib.current.addChild(imgTf);
		imgTf.htmlText = "before<img src='" + base() + "static.swf' id='pic' width='50' height='20'/>after<img src='" + base() + "missing.png' id='bad'/>";
		step("immediately", function() Out.line("img immediately=" + qn(imgTf.getImageReference("pic")) + " bad=" + qn(imgTf.getImageReference("bad"))));
		haxe.Timer.delay(function() {
			step("after 2s", function() {
				var o = imgTf.getImageReference("pic");
				Out.line("img after 2s=" + qn(o) + " bad=" + qn(imgTf.getImageReference("bad")));
				if (o != null) {
					var d:DisplayObject = cast o;
					Out.line("img parent=" + qn(d.parent) + " loader? " + Std.isOfType(o, Loader) + " w=" + d.width + " h=" + d.height + " same=" + (imgTf.getImageReference("pic") == o));
					if (Std.isOfType(o, Loader)) {
						var l:Loader = cast o;
						Out.line("img content=" + qn(l.content) + " url tail=" + l.contentLoaderInfo.url.split("/").pop());
					}
				}
			});
			snapshot();
		}, 2000);
	}

	static function snapshot() {
		Out.line("// TextSnapshot");
		var loader = new Loader();
		loader.contentLoaderInfo.addEventListener(Event.COMPLETE, function(_) {
			var c:DisplayObjectContainer = cast loader.content;
			Lib.current.addChild(loader);
			var ts = c.textSnapshot;
			Out.line("charCount=" + ts.charCount + " text=[" + ts.getText(0, 1000) + "] withEndings=[" + ts.getText(0, 1000, true) + "]");
			Out.line("getText(0,38,true)=[" + ts.getText(0, 38, true).split("\r").join("\\r").split("\n").join("\\n") + "] (0,20,true)=[" + ts.getText(0, 20, true).split("\r").join("\\r").split("\n").join("\\n") + "] (0,37,true)=[" + ts.getText(0, 37, true).split("\r").join("\\r") + "] (5,2)=[" + ts.getText(5, 2) + "] (0,0)=[" + ts.getText(0, 0) + "]");
			Out.line("getTextRunInfo(0,0)=" + ts.getTextRunInfo(0, 0).length + " (37,38)=" + ts.getTextRunInfo(37, 38).length + " (38,40)=" + ts.getTextRunInfo(38, 40).length + " (1,1)=" + ts.getTextRunInfo(1, 1).length);
			var runs = ts.getTextRunInfo(0, 2);
			Out.line("runs(0,2)=" + runs.length);
			for (i in 0...runs.length) {
				var r = runs[i];
				Out.line("run " + i + ": indexInRun=" + r.indexInRun + " font=" + r.font + " color=" + StringTools.hex(r.color) + " height=" + r.height + " matrix=[" + n(r.matrix_a) + " " + n(r.matrix_b) + " " + n(r.matrix_c) + " " + n(r.matrix_d) + " " + n(r.matrix_tx) + " " + n(r.matrix_ty) + "] corners=(" + n(r.corner0x) + "," + n(r.corner0y) + ")(" + n(r.corner1x) + "," + n(r.corner1y) + ")(" + n(r.corner2x) + "," + n(r.corner2y) + ")(" + n(r.corner3x) + "," + n(r.corner3y) + ")");
			}
			var last = ts.getTextRunInfo(ts.charCount - 1, ts.charCount);
			if (last.length > 0) {
				var r = last[0];
				Out.line("last run: indexInRun=" + r.indexInRun + " matrix=[" + n(r.matrix_tx) + " " + n(r.matrix_ty) + "] corners=(" + n(r.corner0x) + "," + n(r.corner0y) + ")(" + n(r.corner1x) + "," + n(r.corner1y) + ")(" + n(r.corner2x) + "," + n(r.corner2y) + ")(" + n(r.corner3x) + "," + n(r.corner3y) + ")");
			}
			var r0 = runs[0];
			var cx = (r0.corner0x + r0.corner2x) / 2, cy = (r0.corner0y + r0.corner2y) / 2;
			Out.line("hit centre=" + ts.hitTestTextNearPos(cx, cy) + " above2=" + ts.hitTestTextNearPos(cx, cy - 2) + " below2=" + ts.hitTestTextNearPos(cx, cy + 2) + " above20=" + ts.hitTestTextNearPos(cx, cy - 20) + " far=" + ts.hitTestTextNearPos(cx + 500, cy + 500) + " far maxDistance 1000=" + ts.hitTestTextNearPos(cx + 500, cy + 500, 1000) + " maxDistance 3 at +5=" + ts.hitTestTextNearPos(cx, cy - 5, 3));
			Out.line("bounds of loaded content: " + c.getBounds(c));
			Out.line("getTextRunInfo(5,2).length=" + ts.getTextRunInfo(5, 2).length + " (-3,2)=" + ts.getTextRunInfo(-3, 2).length + " (0,1000)=" + ts.getTextRunInfo(0, 1000).length);
			Out.finish();
		});
		loader.contentLoaderInfo.addEventListener(IOErrorEvent.IO_ERROR, function(e:IOErrorEvent) {
			Out.line("static.swf load failed: " + e.text);
			Out.finish();
		});
		loader.load(new URLRequest(base() + "static.swf"), new LoaderContext(false, new ApplicationDomain()));
	}

	static function main() {
		Out.start("s2text");
		fonts();
		renderer();
		xmlText();
		images();
	}
}
