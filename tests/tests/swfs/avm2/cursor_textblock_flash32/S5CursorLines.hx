/** Probe: Mouse.registerCursor argument errors in Flash Player 32, and TextBlock.createTextLine
 *  break opportunities / bidiLevel on representative sentences (spaces, punctuation, hyphen, ZWSP,
 *  CJK, Hebrew RTL). Widths are derived from measured textWidth of prefixes, so the result does
 *  not depend on the device font. Builds with -D harness (Flash) or without (Ruffle test). */
import flash.display.BitmapData;
import flash.geom.Point;
import flash.text.engine.*;
import flash.ui.Mouse;
import flash.ui.MouseCursorData;

class S5CursorLines {
	static function step(label:String, f:Void->Void) {
		try {
			f();
		} catch (e:flash.errors.Error) {
			Out.line(label + " THREW " + e.name + " #" + e.errorID);
		}
	}

	static function cd(w:Int, h:Int, frames:Int = 1):MouseCursorData {
		var d = new MouseCursorData();
		var v = new flash.Vector<BitmapData>();
		for (i in 0...frames) v.push(new BitmapData(w, h, true, 0xFF00FF00));
		d.data = v;
		return d;
	}

	static function cursors() {
		Out.line("// Mouse.registerCursor");
		Out.line("supportsCursor=" + Mouse.supportsCursor + " supportsNativeCursor=" + Mouse.supportsNativeCursor + " cursor=" + Mouse.cursor);
		step("ok 16x16", function() {
			Mouse.registerCursor("c16", cd(16, 16));
			Out.line("registered c16");
		});
		step("ok 32x32", function() {
			Mouse.registerCursor("c32", cd(32, 32));
			Out.line("registered c32");
		});
		step("33x33", function() {
			Mouse.registerCursor("c33", cd(33, 33));
			Out.line("registered c33");
		});
		step("64x8", function() {
			Mouse.registerCursor("c64", cd(64, 8));
			Out.line("registered c64x8");
		});
		step("name null", function() {
			Mouse.registerCursor(null, cd(8, 8));
			Out.line("registered null name");
		});
		step("cursor null", function() {
			Mouse.registerCursor("cn", null);
			Out.line("registered null cursor");
		});
		step("data null", function() {
			Mouse.registerCursor("dn", new MouseCursorData());
			Out.line("registered null data");
		});
		step("data empty", function() {
			var d = new MouseCursorData();
			d.data = new flash.Vector<BitmapData>();
			Mouse.registerCursor("de", d);
			Out.line("registered empty data");
		});
		step("disposed", function() {
			var d = cd(8, 8);
			d.data[0].dispose();
			Mouse.registerCursor("dd", d);
			Out.line("registered disposed");
		});
		step("builtin name arrow", function() {
			Mouse.registerCursor("arrow", cd(8, 8));
			Out.line("registered arrow");
		});
		step("builtin name auto", function() {
			Mouse.registerCursor("auto", cd(8, 8));
			Out.line("registered auto");
		});
		step("hotSpot null", function() {
			var d = cd(8, 8);
			d.hotSpot = null;
			Out.line("hotSpot after null=" + d.hotSpot);
			Mouse.registerCursor("hn", d);
			Out.line("registered hotSpot null");
		});
		step("hotSpot negative", function() {
			var d = cd(8, 8);
			d.hotSpot = new Point(-3, -4);
			Mouse.registerCursor("hneg", d);
			Out.line("registered hotSpot negative hotSpot=" + d.hotSpot);
		});
		step("hotSpot outside", function() {
			var d = cd(8, 8);
			d.hotSpot = new Point(20, 20);
			Mouse.registerCursor("hout", d);
			Out.line("registered hotSpot outside");
		});
		step("frames mixed size", function() {
			var d = new MouseCursorData();
			var v = new flash.Vector<BitmapData>();
			v.push(new BitmapData(8, 8));
			v.push(new BitmapData(16, 16));
			d.data = v;
			Mouse.registerCursor("mixed", d);
			Out.line("registered mixed sizes");
		});
		step("frameRate", function() {
			var d = cd(8, 8, 2);
			Out.line("frameRate default=" + d.frameRate);
			d.frameRate = -5;
			Out.line("frameRate after -5=" + d.frameRate);
			Mouse.registerCursor("fr", d);
			Out.line("registered negative frameRate");
		});
		step("set cursor c16", function() {
			Mouse.cursor = "c16";
			Out.line("cursor after c16=" + Mouse.cursor);
		});
		step("set cursor c33", function() {
			Mouse.cursor = "c33";
			Out.line("cursor after c33=" + Mouse.cursor);
		});
		step("set cursor unknown", function() {
			Mouse.cursor = "nope";
			Out.line("cursor after nope=" + Mouse.cursor);
		});
		step("unregister unknown", function() {
			Mouse.unregisterCursor("nope");
			Out.line("unregister unknown ok cursor=" + Mouse.cursor);
		});
		step("unregister current", function() {
			Mouse.cursor = "c16";
			Mouse.unregisterCursor("c16");
			Out.line("unregister current ok cursor=" + Mouse.cursor);
		});
		Mouse.cursor = "auto";
	}

	static var fmt:ElementFormat;

	static function block(s:String, level:Int = 0):TextBlock {
		var b = new TextBlock(new TextElement(s, fmt.clone()));
		b.bidiLevel = level;
		return b;
	}

	static function prefixWidth(s:String, n:Int, level:Int = 0):Float {
		var l = block(s.substr(0, n), level).createTextLine(null, 100000);
		return l == null ? 0 : l.textWidth;
	}

	/** Lay out s at `width`, report each line's raw length (in UTF-16 units). */
	static function lines(label:String, s:String, width:Float, level:Int = 0, fit:Bool = false) {
		var b = block(s, level);
		var out = [];
		var prev:TextLine = null;
		var guard = 0;
		while (guard++ < 40) {
			var l = b.createTextLine(prev, width, 0, fit);
			if (l == null)
				break;
			out.push(l.rawTextLength + (l.textBlockBeginIndex + l.rawTextLength == s.length ? "" : ""));
			prev = l;
		}
		Out.line(label + " -> lines=[" + out.join(",") + "] result=" + b.textLineCreationResult);
	}

	/** Width that just fits the first n characters (their measured width + 0.5). */
	static function fitW(s:String, n:Int, level:Int = 0):Float {
		return prefixWidth(s, n, level) + 0.5;
	}

	static var parts:String = #if s5parts haxe.macro.Compiler.getDefine("s5parts") #else "clj b" #end;

	static function isCjk(s:String):Bool {
		for (i in 0...s.length)
			if (s.charCodeAt(i) >= 0x3000)
				return true;
		return false;
	}

	static function textLines() {
		Out.line("// TextBlock line breaking");
		fmt = new ElementFormat(new FontDescription(), 20);
		// For each width that just fits the first n characters, the length of the first line:
		// the last break opportunity at or before n (or an emergency break). Only the first
		// line is reported, so the result does not depend on the font's glyph widths.
		var cases:Array<Array<String>> = [
			["spaces", "aa bb cc"],
			["comma", "aa,bb cc"],
			["period", "aa.bb cc"],
			["hyphen", "aa-bb-cc"],
			["slash", "aa/bb cc"],
			["zwsp", "aa\u200Bbb cc"],
			["nbsp", "aa\u00A0bb cc"],
			["open paren", "aa (bb) cc"],
			["question", "aa? bb!cc"],
			["tab", "aa\tbb cc"],
			["digits", "12,345.6 78"],
			["url", "a/b.c?d=e"],
			["cjk", "中文字測試"],
			["cjk punct", "中文，測試。排版"],
			["cjk open", "中「文」字"],
			["cjk latin", "中文ab字"],
			["kana", "あいうえ"],
			["small kana", "あっあゃあー"],
		];
		for (c in cases) {
			var s:String = c[1];
			if (parts.indexOf(isCjk(s) ? "j" : "l") < 0)
				continue;
			step(c[0], function() {
				var firsts = [];
				for (n in 1...s.length + 1) {
					var l = block(s).createTextLine(null, fitW(s, n));
					firsts.push(l == null ? "-" : "" + l.rawTextLength);
				}
				Out.line(c[0] + " first line at n=1.." + s.length + ": " + firsts.join(","));
			});
		}
		if (parts.indexOf("l") >= 0) step("fitSomething", function() {
			lines("tiny width fitSomething=false", "abc def", 1);
			lines("tiny width fitSomething=true", "abc def", 1, 0, true);
		});
	}

	static function atomLevels(l:TextLine):String {
		var a = [];
		for (i in 0...l.atomCount) a.push("" + l.getAtomBidiLevel(i));
		return a.join("");
	}

	static function bidi() {
		Out.line("// TextBlock bidiLevel");
		var heb = "שלום";
		var samples:Array<Array<Dynamic>> = [
			["latin L0", "abc def", 0],
			["latin L1", "abc def", 1],
			["hebrew L0", heb + " " + heb, 0],
			["hebrew L1", heb + " " + heb, 1],
			["mixed L0", "ab " + heb + " cd", 0],
			["mixed L1", "ab " + heb + " cd", 1],
			["digits in hebrew L1", heb + " 123 " + heb, 1],
			["parens L1", "(" + heb + ")", 1],
			["level 2", "abc", 2],
		];
		for (sm in samples) {
			step(sm[0], function() {
				var b = block(sm[1], sm[2]);
				var l = b.createTextLine(null, 100000);
				Out.line(sm[0] + " bidiLevel=" + b.bidiLevel + " atoms=" + l.atomCount + " levels=" + atomLevels(l));
			});
		}
		step("bidiLevel -1", function() {
			var b = block("abc");
			b.bidiLevel = -1;
			Out.line("bidiLevel after -1=" + b.bidiLevel);
		});
		step("bidiLevel 200", function() {
			var b = block("abc");
			b.bidiLevel = 200;
			Out.line("bidiLevel after 200=" + b.bidiLevel);
			var l = b.createTextLine(null, 1000);
			Out.line("level 200 levels=" + atomLevels(l));
		});
		step("rtl wrap", function() {
			var s = heb + " " + heb + " " + heb;
			var l = block(s, 1).createTextLine(null, fitW(s, 9, 1));
			Out.line("hebrew L1 wrap first line=" + l.rawTextLength);
		});
	}

	static function main() {
		Out.start(#if s5name haxe.macro.Compiler.getDefine("s5name") #else "s5cursorlines" #end);
		if (parts.indexOf("c") >= 0)
			cursors();
		fmt = new ElementFormat(new FontDescription(), 20);
		if (parts.indexOf("l") >= 0 || parts.indexOf("j") >= 0)
			textLines();
		if (parts.indexOf("b") >= 0)
			bidi();
		Out.finish();
	}
}
