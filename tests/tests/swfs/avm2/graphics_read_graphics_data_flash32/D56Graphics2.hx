/** Probe (no golden): follow-ups to D55Graphics — readGraphicsData stroke ordering and colour
 *  rounding, gradient matrix quirk, drawTriangles uvt perspective and error cases, drawPath
 *  winding persistence. Build with -swf-version 32. */
import flash.Lib;
import flash.display.*;
import flash.geom.Matrix;
import flash.geom.Rectangle;

class D56Graphics2 {
	static var qn:Dynamic;

	static function step(label:String, f:Void->Void) {
		try {
			f();
		} catch (e:flash.errors.Error) {
			H.log(label + " THREW " + qn(e) + " #" + e.errorID + " " + e.message);
		}
	}

	static function n(v:Float):String {
		var r = Math.round(v * 100000) / 100000;
		return Std.string(r);
	}

	static function mat(m:Matrix):String {
		return m == null ? "null" : "[" + n(m.a) + "," + n(m.b) + "," + n(m.c) + "," + n(m.d) + "," + n(m.tx) + "," + n(m.ty) + "]";
	}

	static function vec(v:Dynamic):String {
		if (v == null) return "null";
		var out = [];
		var len:Int = v.length;
		for (i in 0...len) out.push(n(v[i]));
		return "[" + out.join(",") + "]";
	}

	static function arr(a:Array<Dynamic>):String {
		if (a == null) return "null";
		return "[" + a.map(function(x) return Std.string(x)).join(",") + "]";
	}

	static function fill(f:Dynamic):String {
		if (f == null) return "null";
		var c:String = qn(f);
		if (c == "flash.display::GraphicsSolidFill")
			return "Solid(color=" + StringTools.hex(f.color, 6) + " alpha=" + n(f.alpha) + ")";
		if (c == "flash.display::GraphicsGradientFill")
			return "Gradient(type=" + f.type + " colors=" + arr(f.colors) + " alphas=" + arr(f.alphas) + " ratios=" + arr(f.ratios)
				+ " matrix=" + mat(f.matrix) + " spread=" + f.spreadMethod + " interp=" + f.interpolationMethod + " focal=" + n(f.focalPointRatio) + ")";
		if (c == "flash.display::GraphicsBitmapFill")
			return "Bitmap(" + (f.bitmapData == null ? "null" : f.bitmapData.width + "x" + f.bitmapData.height) + " matrix=" + mat(f.matrix)
				+ " repeat=" + f.repeat + " smooth=" + f.smooth + ")";
		return c;
	}

	static function describe(d:Dynamic):String {
		var c:String = qn(d);
		if (c == "flash.display::GraphicsEndFill") return "EndFill";
		if (c == "flash.display::GraphicsPath")
			return "Path(cmds=" + vec(d.commands) + " data=" + vec(d.data) + " winding=" + d.winding + ")";
		if (c == "flash.display::GraphicsStroke")
			return "Stroke(thickness=" + n(d.thickness) + " fill=" + fill(d.fill) + ")";
		return fill(d);
	}

	static function dump(label:String, g:Graphics, recurse:Bool = true) {
		var v:Dynamic = g.readGraphicsData(recurse);
		H.log(label + " n=" + v.length);
		var len:Int = v.length;
		for (i in 0...len) H.log("  " + i + ": " + describe(v[i]));
	}

	static function readData() {
		// s1: lineStyle BEFORE beginFill, manual closed path
		var s = new Shape();
		s.graphics.lineStyle(1, 0x0000FF);
		s.graphics.beginFill(0x00FF00);
		s.graphics.moveTo(0, 0); s.graphics.lineTo(30, 0); s.graphics.lineTo(30, 20); s.graphics.lineTo(0, 20); s.graphics.lineTo(0, 0);
		s.graphics.endFill();
		dump("s1 style-before-fill closed", s.graphics);
		// s2: lineStyle AFTER beginFill, same path
		s = new Shape();
		s.graphics.beginFill(0x00FF00);
		s.graphics.lineStyle(1, 0x0000FF);
		s.graphics.moveTo(0, 0); s.graphics.lineTo(30, 0); s.graphics.lineTo(30, 20); s.graphics.lineTo(0, 20); s.graphics.lineTo(0, 0);
		s.graphics.endFill();
		dump("s2 style-after-fill closed", s.graphics);
		// s3: lineStyle before beginFill, open path + endFill
		s = new Shape();
		s.graphics.lineStyle(1, 0x0000FF);
		s.graphics.beginFill(0x00FF00);
		s.graphics.moveTo(0, 0); s.graphics.lineTo(30, 0); s.graphics.lineTo(30, 20);
		s.graphics.endFill();
		dump("s3 style-before-fill open", s.graphics);
		// s4: stroke only, closed manually, then drawRect stroke only
		s = new Shape();
		s.graphics.lineStyle(1, 0x0000FF);
		s.graphics.moveTo(0, 0); s.graphics.lineTo(30, 0); s.graphics.lineTo(30, 20); s.graphics.lineTo(0, 20); s.graphics.lineTo(0, 0);
		s.graphics.drawRect(40, 0, 10, 10);
		dump("s4 stroke-only closed + rect", s.graphics);
		// s5: lineStyle before beginFill, drawRect, no endFill, then beginFill again
		s = new Shape();
		s.graphics.lineStyle(1, 0x0000FF);
		s.graphics.beginFill(0x00FF00);
		s.graphics.drawRect(0, 0, 30, 20);
		s.graphics.beginFill(0xFF0000);
		s.graphics.drawRect(40, 0, 10, 10);
		dump("s5 two fills no endFill", s.graphics);
		// s6: lineStyle before beginFill, moveTo first then beginFill
		s = new Shape();
		s.graphics.lineStyle(1, 0x0000FF);
		s.graphics.moveTo(5, 5);
		s.graphics.beginFill(0x00FF00);
		s.graphics.lineTo(30, 5); s.graphics.lineTo(30, 20);
		s.graphics.endFill();
		dump("s6 moveTo before beginFill", s.graphics);
		// s7: fill, then lineStyle(NaN) mid-path to stop stroking
		s = new Shape();
		s.graphics.beginFill(0x00FF00);
		s.graphics.lineStyle(2, 0x0000FF);
		s.graphics.moveTo(0, 0); s.graphics.lineTo(30, 0);
		s.graphics.lineStyle();
		s.graphics.lineTo(30, 20); s.graphics.lineTo(0, 20);
		s.graphics.endFill();
		dump("s7 lineStyle() mid path", s.graphics);
		// s8: drawCircle with stroke before fill
		s = new Shape();
		s.graphics.lineStyle(1, 0x0000FF);
		s.graphics.beginFill(0x00FF00);
		s.graphics.drawCircle(50, 50, 20);
		s.graphics.endFill();
		dump("s8 circle stroke+fill", s.graphics);
		// s9: drawEllipse + drawRoundRect fill only
		s = new Shape();
		s.graphics.beginFill(0x00FF00);
		s.graphics.drawEllipse(0, 0, 40, 20);
		s.graphics.drawRoundRect(0, 30, 40, 20, 10, 6);
		s.graphics.endFill();
		dump("s9 ellipse+roundrect", s.graphics);

		// c1: colour rounding for fills and strokes
		s = new Shape();
		s.graphics.lineStyle(1, 0xFF8040, 0.75);
		s.graphics.beginFill(0xFF8040, 0.75);
		s.graphics.drawRect(0, 0, 10, 10);
		s.graphics.lineStyle(1, 0x10CDAB, 0.3);
		s.graphics.beginFill(0x10CDAB, 0.3);
		s.graphics.drawRect(20, 0, 10, 10);
		s.graphics.lineStyle(1, 0xFFFFFF, 0.5);
		s.graphics.beginFill(0xFFFFFF, 0.5);
		s.graphics.drawRect(40, 0, 10, 10);
		s.graphics.lineStyle(1, 0x7F7F7F, 0.1);
		s.graphics.beginFill(0x7F7F7F, 0.1);
		s.graphics.drawRect(60, 0, 10, 10);
		s.graphics.lineStyle(1, 0x123456, 0);
		s.graphics.beginFill(0x123456, 0);
		s.graphics.drawRect(80, 0, 10, 10);
		s.graphics.endFill();
		dump("c1 colours", s.graphics);

		// g1: gradient/bitmap matrix quirk with an asymmetric matrix
		s = new Shape();
		var m = new Matrix(1, 2, 3, 4, 5, 6);
		s.graphics.beginGradientFill(cast "linear", [0xFF0000, 0x0000FF], [1, 1], [0, 255], m);
		s.graphics.drawRect(0, 0, 10, 10);
		s.graphics.endFill();
		var bd = new BitmapData(8, 4, false, 0xFF00FF);
		s.graphics.beginBitmapFill(bd, m);
		s.graphics.drawRect(0, 0, 10, 10);
		s.graphics.endFill();
		m = new Matrix(0.5, 0, 0, 0.25, 1.5, -2.5);
		s.graphics.beginGradientFill(cast "linear", [0xFF0000, 0x0000FF], [1, 1], [0, 255], m);
		s.graphics.drawRect(0, 0, 10, 10);
		s.graphics.endFill();
		s.graphics.beginGradientFill(cast "linear", [0xFF0000, 0x0000FF], [1, 1], [0, 255], null);
		s.graphics.drawRect(0, 0, 10, 10);
		s.graphics.endFill();
		s.graphics.beginBitmapFill(bd, null);
		s.graphics.drawRect(0, 0, 10, 10);
		s.graphics.endFill();
		dump("g1 matrices", s.graphics);
		// g2: line gradient / line bitmap style read back
		s = new Shape();
		s.graphics.lineStyle(3, 0, 1);
		s.graphics.lineGradientStyle(cast "radial", [0xFF0000, 0x0000FF], [0.5, 1], [10, 200], m, cast "repeat", cast "linearRGB", -0.4);
		s.graphics.moveTo(0, 0); s.graphics.lineTo(20, 0);
		s.graphics.lineBitmapStyle(bd, m, false, true);
		s.graphics.lineTo(20, 20);
		dump("g2 line styles", s.graphics);
	}

	static function px(bd:BitmapData, x:Int, y:Int):String {
		return x + "," + y + "=" + StringTools.hex(bd.getPixel32(x, y), 8);
	}

	static function sample(label:String, s:DisplayObject, pts:Array<Array<Int>>) {
		var bd = new BitmapData(60, 60, true, 0x00000000);
		bd.draw(s);
		var out = [];
		for (p in pts) out.push(px(bd, p[0], p[1]));
		H.log(label + " " + out.join(" "));
	}

	static function row(label:String, s:DisplayObject, y:Int, x0:Int, x1:Int) {
		var bd = new BitmapData(60, 60, true, 0x00000000);
		bd.draw(s);
		var out = [];
		var last:UInt = 0xDEADBEEF;
		for (x in x0...x1) {
			var c = bd.getPixel32(x, y);
			if (c != last) {
				out.push(x + ":" + StringTools.hex(c, 8));
				last = c;
			}
		}
		H.log(label + " y=" + y + " " + out.join(" "));
	}

	static function V(a:Array<Float>):flash.Vector<Float> {
		var v = new flash.Vector<Float>();
		for (d in a) v.push(d);
		return v;
	}

	static function I(a:Array<Int>):flash.Vector<Int> {
		var v = new flash.Vector<Int>();
		for (d in a) v.push(d);
		return v;
	}

	static function triangles() {
		// two-colour bitmap: left half red (u<0.5), right half green
		var bd = new BitmapData(20, 20, false, 0xFF0000);
		bd.fillRect(new Rectangle(10, 0, 10, 10), 0x00FF00);
		bd.fillRect(new Rectangle(0, 10, 10, 10), 0x0000FF);
		bd.fillRect(new Rectangle(10, 10, 10, 10), 0xFFFFFF);
		var quad = V([0, 0, 40, 0, 40, 40, 0, 40]);
		var idx = I([0, 1, 2, 0, 2, 3]);

		// u1: affine reference: uv only
		var s = new Shape();
		s.graphics.beginBitmapFill(bd);
		s.graphics.drawTriangles(quad, idx, V([0, 0, 1, 0, 1, 1, 0, 1]));
		s.graphics.endFill();
		row("u1 uv", s, 10, 0, 40);
		row("u1 uv", s, 30, 0, 40);
		// u2: t=1 left, t=0.25 right, u/v NOT premultiplied
		s = new Shape();
		s.graphics.beginBitmapFill(bd);
		s.graphics.drawTriangles(quad, idx, V([0, 0, 1, 1, 0, 0.25, 1, 1, 0.25, 0, 1, 1]));
		s.graphics.endFill();
		row("u2 t right=0.25", s, 10, 0, 40);
		row("u2 t right=0.25", s, 30, 0, 40);
		// u3: t=1 left, t=4 right
		s = new Shape();
		s.graphics.beginBitmapFill(bd);
		s.graphics.drawTriangles(quad, idx, V([0, 0, 1, 1, 0, 4, 1, 1, 4, 0, 1, 1]));
		s.graphics.endFill();
		row("u3 t right=4", s, 10, 0, 40);
		row("u3 t right=4", s, 30, 0, 40);
		// u4: t=0 on the right (degenerate)
		s = new Shape();
		s.graphics.beginBitmapFill(bd);
		s.graphics.drawTriangles(quad, idx, V([0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 1, 1]));
		s.graphics.endFill();
		row("u4 t right=0", s, 10, 0, 40);
		// u5: smooth + repeat false with uv outside 0..1
		s = new Shape();
		s.graphics.beginBitmapFill(bd, null, false, false);
		s.graphics.drawTriangles(quad, idx, V([-0.5, 0, 1.5, 0, 1.5, 1, -0.5, 1]));
		s.graphics.endFill();
		row("u5 uv -0.5..1.5 norepeat", s, 10, 0, 40);
		s = new Shape();
		s.graphics.beginBitmapFill(bd, null, true, false);
		s.graphics.drawTriangles(quad, idx, V([-0.5, 0, 1.5, 0, 1.5, 1, -0.5, 1]));
		s.graphics.endFill();
		row("u5b uv -0.5..1.5 repeat", s, 10, 0, 40);
		// u6: uvt with a gradient fill (uv ignored?)
		s = new Shape();
		var m = new Matrix();
		m.createGradientBox(40, 40);
		s.graphics.beginGradientFill(cast "linear", [0xFF0000, 0x0000FF], [1, 1], [0, 255], m);
		s.graphics.drawTriangles(quad, idx, V([0, 0, 1, 0, 1, 1, 0, 1]));
		s.graphics.endFill();
		row("u6 gradient+uv", s, 10, 0, 40);
		s = new Shape();
		s.graphics.beginGradientFill(cast "linear", [0xFF0000, 0x0000FF], [1, 1], [0, 255], m);
		s.graphics.drawTriangles(quad, idx);
		s.graphics.endFill();
		row("u6b gradient no uv", s, 10, 0, 40);

		// e1: error cases for uvt lengths
		for (len in [0, 1, 2, 7, 8, 9, 12, 13, 16]) {
			var u = [];
			for (i in 0...len) u.push(0.5);
			var sh = new Shape();
			sh.graphics.beginBitmapFill(bd);
			var label = "e1 uvt len " + len;
			try {
				sh.graphics.drawTriangles(quad, idx, V(u));
				H.log(label + " ok");
			} catch (e:flash.errors.Error) {
				H.log(label + " THREW #" + e.errorID);
			}
		}
		// e2: uvt length checked against vertices even without a bitmap fill?
		var sh = new Shape();
		sh.graphics.beginFill(0xFF0000);
		try {
			sh.graphics.drawTriangles(quad, idx, V([0, 0, 1]));
			H.log("e2 solid uvt len 3 ok");
		} catch (e:flash.errors.Error) {
			H.log("e2 solid uvt len 3 THREW #" + e.errorID);
		}
		sh = new Shape();
		try {
			sh.graphics.drawTriangles(quad, idx, V([0, 0, 1]));
			H.log("e2b nofill uvt len 3 ok");
		} catch (e:flash.errors.Error) {
			H.log("e2b nofill uvt len 3 THREW #" + e.errorID);
		}
		// e3: uvt with no indices
		sh = new Shape();
		sh.graphics.beginBitmapFill(bd);
		try {
			sh.graphics.drawTriangles(V([0, 0, 40, 0, 40, 40]), null, V([0, 0, 1, 0, 1, 1]));
			H.log("e3 uv no indices ok");
		} catch (e:flash.errors.Error) {
			H.log("e3 THREW #" + e.errorID);
		}
		sample("e3 uv no indices", sh, [[30, 10], [20, 5], [35, 30]]);

		// t7: opposite orientation overlapping triangles, culling none
		s = new Shape();
		s.graphics.beginFill(0xFF0000);
		s.graphics.drawTriangles(V([0, 0, 40, 0, 40, 40, 0, 0, 40, 40, 0, 40]));
		s.graphics.endFill();
		sample("t7 cw+ccw", s, [[30, 10], [10, 30], [20, 20], [20, 19], [20, 21]]);
		s = new Shape();
		s.graphics.beginFill(0xFF0000);
		s.graphics.drawTriangles(V([0, 0, 40, 0, 40, 40, 0, 0, 0, 40, 40, 40]));
		s.graphics.endFill();
		sample("t8 cw+cw", s, [[30, 10], [10, 30], [20, 20], [20, 19], [20, 21]]);
		// t8b: big cw + small ccw inside
		s = new Shape();
		s.graphics.beginFill(0xFF0000);
		s.graphics.drawTriangles(V([0, 0, 40, 0, 40, 40, 10, 10, 30, 30, 30, 10]));
		s.graphics.endFill();
		sample("t8b cw + inner ccw", s, [[25, 15], [35, 5], [20, 12]]);
		s = new Shape();
		s.graphics.beginFill(0xFF0000);
		s.graphics.drawTriangles(V([0, 0, 40, 0, 40, 40, 10, 10, 30, 10, 30, 30]));
		s.graphics.endFill();
		sample("t8c cw + inner cw", s, [[25, 15], [35, 5], [20, 12]]);
		// t9: mixed with rects in the same fill
		s = new Shape();
		s.graphics.beginFill(0xFF0000);
		s.graphics.drawRect(0, 0, 30, 30);
		s.graphics.drawRect(10, 10, 30, 30);
		s.graphics.drawTriangles(V([20, 20, 50, 20, 50, 50]));
		s.graphics.drawRect(5, 5, 30, 30);
		s.graphics.endFill();
		sample("t9 mixed", s, [[15, 15], [25, 25], [40, 30], [7, 7], [32, 32], [2, 2], [45, 40]]);
		// t10: stroke with triangles
		s = new Shape();
		s.graphics.lineStyle(4, 0x0000FF);
		s.graphics.beginFill(0xFF0000);
		s.graphics.drawTriangles(V([10, 10, 50, 10, 50, 50]));
		s.graphics.endFill();
		sample("t10 stroke", s, [[30, 10], [50, 30], [30, 30], [40, 20], [10, 10]]);
		// t11: triangles then lineTo continues from where?
		s = new Shape();
		s.graphics.beginFill(0xFF0000);
		s.graphics.drawTriangles(V([10, 10, 50, 10, 50, 50]));
		s.graphics.lineTo(10, 50);
		s.graphics.lineTo(10, 30);
		s.graphics.endFill();
		sample("t11 lineTo after", s, [[12, 45], [30, 40], [30, 15], [12, 20]]);
	}

	static function paths() {
		// w1: drawPath nonZero simple square, then lineTo two overlapping same-direction squares
		var s = new Shape();
		s.graphics.beginFill(0xFF0000);
		s.graphics.drawPath(I([1, 2, 2, 2, 2]), V([50, 0, 58, 0, 58, 8, 50, 8, 50, 0]), cast "nonZero");
		s.graphics.moveTo(0, 0); s.graphics.lineTo(30, 0); s.graphics.lineTo(30, 30); s.graphics.lineTo(0, 30); s.graphics.lineTo(0, 0);
		s.graphics.moveTo(10, 10); s.graphics.lineTo(40, 10); s.graphics.lineTo(40, 40); s.graphics.lineTo(10, 40); s.graphics.lineTo(10, 10);
		s.graphics.endFill();
		sample("w1 nonZero then lineTo overlap", s, [[5, 5], [20, 20], [35, 35], [54, 4]]);
		// w2: lineTo two overlapping squares, then drawPath nonZero (does it apply retroactively?)
		s = new Shape();
		s.graphics.beginFill(0xFF0000);
		s.graphics.moveTo(0, 0); s.graphics.lineTo(30, 0); s.graphics.lineTo(30, 30); s.graphics.lineTo(0, 30); s.graphics.lineTo(0, 0);
		s.graphics.moveTo(10, 10); s.graphics.lineTo(40, 10); s.graphics.lineTo(40, 40); s.graphics.lineTo(10, 40); s.graphics.lineTo(10, 10);
		s.graphics.drawPath(I([1, 2, 2, 2, 2]), V([50, 0, 58, 0, 58, 8, 50, 8, 50, 0]), cast "nonZero");
		s.graphics.endFill();
		sample("w2 lineTo overlap then nonZero", s, [[5, 5], [20, 20], [35, 35], [54, 4]]);
		// w3: drawPath evenOdd square overlapping a lineTo square: do they interact (even-odd across)?
		s = new Shape();
		s.graphics.beginFill(0xFF0000);
		s.graphics.moveTo(0, 0); s.graphics.lineTo(30, 0); s.graphics.lineTo(30, 30); s.graphics.lineTo(0, 30); s.graphics.lineTo(0, 0);
		s.graphics.drawPath(I([1, 2, 2, 2, 2]), V([10, 10, 40, 10, 40, 40, 10, 40, 10, 10]), cast "evenOdd");
		s.graphics.endFill();
		sample("w3 lineTo then evenOdd overlap", s, [[5, 5], [20, 20], [35, 35]]);
		// w4: two drawPath calls, nonZero each, overlapping, same direction then opposite direction
		s = new Shape();
		s.graphics.beginFill(0xFF0000);
		s.graphics.drawPath(I([1, 2, 2, 2, 2]), V([0, 0, 30, 0, 30, 30, 0, 30, 0, 0]), cast "nonZero");
		s.graphics.drawPath(I([1, 2, 2, 2, 2]), V([10, 10, 10, 40, 40, 40, 40, 10, 10, 10]), cast "nonZero");
		s.graphics.endFill();
		sample("w4 nonZero cw + nonZero ccw", s, [[5, 5], [20, 20], [35, 35]]);
		s = new Shape();
		s.graphics.beginFill(0xFF0000);
		s.graphics.drawPath(I([1, 2, 2, 2, 2, 1, 2, 2, 2, 2]), V([0, 0, 30, 0, 30, 30, 0, 30, 0, 0, 10, 10, 10, 40, 40, 40, 40, 10, 10, 10]), cast "nonZero");
		s.graphics.endFill();
		sample("w4b one nonZero call cw+ccw", s, [[5, 5], [20, 20], [35, 35]]);
		// w5: drawPath with stroke, sub-path closed explicitly and endFill
		s = new Shape();
		s.graphics.lineStyle(4, 0x0000FF);
		s.graphics.beginFill(0xFF0000);
		s.graphics.drawPath(I([1, 2, 2]), V([0, 0, 40, 0, 40, 40]));
		s.graphics.lineTo(0, 40);
		s.graphics.endFill();
		sample("w5 drawPath then lineTo stroke close?", s, [[20, 0], [40, 20], [20, 40], [0, 20], [20, 20]]);
		// w6: drawPath stroke sub-path that explicitly returns to start: joined?
		s = new Shape();
		s.graphics.lineStyle(8, 0x0000FF, 1, false, cast "normal", cast "none", cast "miter", 10);
		s.graphics.drawPath(I([1, 2, 2, 2, 2]), V([10, 10, 40, 10, 40, 40, 10, 40, 10, 10]));
		sample("w6 drawPath stroke explicit close corner", s, [[7, 7], [8, 8], [12, 12], [43, 43]]);
		s = new Shape();
		s.graphics.lineStyle(8, 0x0000FF, 1, false, cast "normal", cast "none", cast "miter", 10);
		s.graphics.moveTo(10, 10); s.graphics.lineTo(40, 10); s.graphics.lineTo(40, 40); s.graphics.lineTo(10, 40); s.graphics.lineTo(10, 10);
		sample("w6b lineTo stroke explicit close corner", s, [[7, 7], [8, 8], [12, 12], [43, 43]]);
	}

	static function main() {
		H.init("d56graphics2", 30000);
		qn = untyped __global__["flash.utils.getQualifiedClassName"];
		step("readData", readData);
		step("triangles", triangles);
		step("paths", paths);
		H.done();
	}
}
