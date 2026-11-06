/** Probe (no golden): flash.display.Graphics.readGraphicsData structure, drawTriangles winding/uvt
 *  mapping and drawPath stroke/fill rules in Flash Player 32. Pixels are sampled through
 *  BitmapData.draw + getPixel32 so the result is a text report. Build with -swf-version 32. */
import flash.Lib;
import flash.display.*;
import flash.geom.Matrix;
import flash.geom.Rectangle;

class D55Graphics {
	static var qn:Dynamic;

	static function step(label:String, f:Void->Void) {
		try {
			f();
		} catch (e:flash.errors.Error) {
			H.log(label + " THREW " + qn(e) + " #" + e.errorID + " " + e.message);
		}
	}

	static function n(v:Float):String {
		// round to 3 decimals to keep float noise out of the golden
		var r = Math.round(v * 1000) / 1000;
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
		if (c == "flash.display::GraphicsShaderFill")
			return "Shader(matrix=" + mat(f.matrix) + ")";
		return c;
	}

	static function describe(d:Dynamic):String {
		var c:String = qn(d);
		if (c == "flash.display::GraphicsEndFill") return "EndFill";
		if (c == "flash.display::GraphicsPath")
			return "Path(cmds=" + vec(d.commands) + " data=" + vec(d.data) + " winding=" + d.winding + ")";
		if (c == "flash.display::GraphicsStroke")
			return "Stroke(thickness=" + n(d.thickness) + " hint=" + d.pixelHinting + " scale=" + d.scaleMode + " caps=" + d.caps
				+ " joints=" + d.joints + " miter=" + n(d.miterLimit) + " fill=" + fill(d.fill) + ")";
		if (c == "flash.display::GraphicsTrianglePath")
			return "Triangles(v=" + vec(d.vertices) + " i=" + vec(d.indices) + " uvt=" + vec(d.uvtData) + " cull=" + d.culling + ")";
		return fill(d);
	}

	static function dump(label:String, g:Graphics, recurse:Bool = true) {
		var v:Dynamic = g.readGraphicsData(recurse);
		H.log(label + " n=" + v.length + " " + qn(v));
		var len:Int = v.length;
		for (i in 0...len) H.log("  " + i + ": " + describe(v[i]));
	}

	static function readData() {
		// 1. fill only, unclosed path, shape translated
		var s = new Shape();
		s.x = 100; s.y = 20;
		s.graphics.beginFill(0xFF0000, 0.5);
		s.graphics.moveTo(10, 10);
		s.graphics.lineTo(50, 10);
		s.graphics.lineTo(50, 50);
		s.graphics.endFill();
		dump("r1 fill-unclosed x100y20", s.graphics);
		Lib.current.addChild(s);
		dump("r1b on stage", s.graphics);
		Lib.current.removeChild(s);

		// 2. stroke only
		s = new Shape();
		s.graphics.lineStyle(2, 0x00FF00, 0.75, true, cast "none", cast "square", cast "miter", 7);
		s.graphics.moveTo(0, 0);
		s.graphics.lineTo(20, 0);
		s.graphics.lineTo(20, 20);
		dump("r2 stroke-only", s.graphics);

		// 3. fill + stroke rect, then a second fill
		s = new Shape();
		s.graphics.lineStyle(1, 0x0000FF);
		s.graphics.beginFill(0x00FF00);
		s.graphics.drawRect(0, 0, 30, 20);
		s.graphics.endFill();
		s.graphics.beginFill(0x123456);
		s.graphics.drawRect(40, 0, 10, 10);
		s.graphics.endFill();
		dump("r3 rect-fill-stroke-x2", s.graphics);

		// 4. circle (curves) without stroke
		s = new Shape();
		s.graphics.beginFill(0xFFFFFF);
		s.graphics.drawCircle(50, 50, 20);
		s.graphics.endFill();
		dump("r4 circle", s.graphics);

		// 5. gradient fill with matrix
		s = new Shape();
		var m = new Matrix();
		m.createGradientBox(100, 50, Math.PI / 4, 10, 20);
		s.graphics.beginGradientFill(cast "linear", [0xFF0000, 0x00FF00, 0x0000FF], [1, 0.5, 0], [0, 128, 255], m, cast "reflect", cast "linearRGB", 0.3);
		s.graphics.drawRect(0, 0, 100, 50);
		s.graphics.endFill();
		dump("r5 gradient", s.graphics);
		s = new Shape();
		s.graphics.beginGradientFill(cast "radial", [0xFF0000, 0x0000FF], [1, 1], [0, 255], m, cast "pad", cast "rgb", 0.5);
		s.graphics.drawRect(0, 0, 100, 50);
		s.graphics.endFill();
		dump("r5b radial focal", s.graphics);

		// 6. bitmap fill with matrix, repeat=false smooth=true
		s = new Shape();
		var bd = new BitmapData(8, 4, false, 0xFF00FF);
		var bm = new Matrix(2, 0, 0, 3, 5, 7);
		s.graphics.beginBitmapFill(bd, bm, false, true);
		s.graphics.drawRect(0, 0, 40, 40);
		s.graphics.endFill();
		dump("r6 bitmap", s.graphics);

		// 7. drawPath nonZero + wide/cubic commands
		s = new Shape();
		s.graphics.beginFill(0xFF0000);
		var cmds = new flash.Vector<Int>();
		for (c in [1, 2, 2, 2, 6, 4, 5, 3]) cmds.push(c);
		var data = new flash.Vector<Float>();
		for (d in [0, 0, 20, 0, 20, 20, 0, 20, 5, 5, 10, 10, 0, 0, -1, -1, 30, 30, -1, -1, 40, 40, 45, 45, 50, 40]) data.push(d);
		s.graphics.drawPath(cmds, data, cast "nonZero");
		s.graphics.endFill();
		dump("r7 drawPath nonZero cubic", s.graphics);

		// 8. recurse: sprite with child shape, scaled child
		var sp = new Sprite();
		sp.graphics.beginFill(0x111111);
		sp.graphics.drawRect(0, 0, 10, 10);
		sp.graphics.endFill();
		var ch = new Shape();
		ch.x = 50; ch.scaleX = 2; ch.rotation = 90;
		ch.graphics.beginFill(0x222222);
		ch.graphics.drawRect(0, 0, 10, 10);
		ch.graphics.endFill();
		sp.addChild(ch);
		var ch2 = new Shape();
		ch2.visible = false;
		ch2.graphics.beginFill(0x333333);
		ch2.graphics.drawRect(0, 0, 10, 10);
		ch2.graphics.endFill();
		sp.addChild(ch2);
		dump("r8 recurse=true", sp.graphics, true);
		dump("r8b recurse=false", sp.graphics, false);
		dump("r8c child", ch.graphics);

		// 9. triangles and shader are not included
		s = new Shape();
		s.graphics.beginFill(0xFF0000);
		var v = new flash.Vector<Float>();
		for (d in [0, 0, 10, 0, 10, 10]) v.push(d);
		s.graphics.drawTriangles(v);
		s.graphics.endFill();
		s.graphics.beginFill(0x00FF00);
		s.graphics.drawRect(0, 0, 5, 5);
		s.graphics.endFill();
		dump("r9 triangles", s.graphics);

		// 10. open fill (no endFill) + lineStyle change mid-path + stroke without fill after
		s = new Shape();
		s.graphics.beginFill(0xFF0000);
		s.graphics.lineStyle(3, 0x0000FF);
		s.graphics.moveTo(0, 0);
		s.graphics.lineTo(10, 0);
		s.graphics.lineStyle(5, 0x00FF00);
		s.graphics.lineTo(10, 10);
		dump("r10 open fill, style change", s.graphics);
		s.graphics.endFill();
		dump("r10b after endFill", s.graphics);

		// 11. empty / cleared
		s = new Shape();
		dump("r11 empty", s.graphics);
		s.graphics.beginFill(0xFF0000);
		s.graphics.drawRect(0, 0, 5, 5);
		s.graphics.clear();
		dump("r11b cleared", s.graphics);

		// 12. two-point fill sub-path and lineTo without moveTo
		s = new Shape();
		s.graphics.beginFill(0xFF0000);
		s.graphics.lineTo(10, 0);
		s.graphics.lineTo(10, 10);
		s.graphics.moveTo(20, 20);
		s.graphics.lineTo(30, 20);
		s.graphics.endFill();
		dump("r12 no moveTo + 2pt subpath", s.graphics);

		// 13. drawGraphicsData round trip keeps what?
		s = new Shape();
		var gd = new flash.Vector<IGraphicsData>();
		gd.push(new GraphicsStroke(2, false, cast "normal", cast "round", cast "bevel", 2, new GraphicsSolidFill(0xABCDEF, 0.25)));
		gd.push(new GraphicsSolidFill(0x00FF00, 1));
		var p = new GraphicsPath();
		p.moveTo(0, 0); p.lineTo(20, 0); p.curveTo(20, 20, 0, 20);
		gd.push(p);
		gd.push(new GraphicsEndFill());
		s.graphics.drawGraphicsData(gd);
		dump("r13 drawGraphicsData", s.graphics);
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

	static function triangles() {
		// quadrant bitmap: TL red, TR green, BL blue, BR white (20x20)
		var bd = new BitmapData(20, 20, false, 0xFF0000);
		bd.fillRect(new Rectangle(10, 0, 10, 10), 0x00FF00);
		bd.fillRect(new Rectangle(0, 10, 10, 10), 0x0000FF);
		bd.fillRect(new Rectangle(10, 10, 10, 10), 0xFFFFFF);

		// t1: uv mapping of a 40x40 quad from the bitmap (two triangles)
		var s = new Shape();
		s.graphics.beginBitmapFill(bd);
		var v = new flash.Vector<Float>();
		for (d in [0, 0, 40, 0, 40, 40, 0, 40]) v.push(d);
		var idx = new flash.Vector<Int>();
		for (d in [0, 1, 2, 0, 2, 3]) idx.push(d);
		var uv = new flash.Vector<Float>();
		for (d in [0, 0, 1, 0, 1, 1, 0, 1]) uv.push(d);
		s.graphics.drawTriangles(v, idx, uv);
		s.graphics.endFill();
		sample("t1 uv quad", s, [[5, 5], [35, 5], [5, 35], [35, 35], [15, 25], [25, 15]]);

		// t2: flipped uv (u mirrored) and scaled bitmap region (uv 0..0.5)
		s = new Shape();
		s.graphics.beginBitmapFill(bd);
		uv = new flash.Vector<Float>();
		for (d in [0.5, 0, 0, 0, 0, 0.5, 0.5, 0.5]) uv.push(d);
		s.graphics.drawTriangles(v, idx, uv);
		s.graphics.endFill();
		sample("t2 uv mirrored half", s, [[5, 5], [35, 5], [5, 35], [35, 35], [15, 25], [25, 15]]);

		// t3: uvt with t=1 (same as uv) and t=0.5 everywhere
		s = new Shape();
		s.graphics.beginBitmapFill(bd);
		var uvt = new flash.Vector<Float>();
		for (d in [0, 0, 1, 1, 0, 1, 1, 1, 1, 0, 1, 1]) uvt.push(d);
		s.graphics.drawTriangles(v, idx, uvt);
		s.graphics.endFill();
		sample("t3 uvt t=1", s, [[5, 5], [35, 5], [5, 35], [35, 35]]);
		s = new Shape();
		s.graphics.beginBitmapFill(bd);
		uvt = new flash.Vector<Float>();
		for (d in [0, 0, 0.5, 1, 0, 0.5, 1, 1, 0.5, 0, 1, 0.5]) uvt.push(d);
		s.graphics.drawTriangles(v, idx, uvt);
		s.graphics.endFill();
		sample("t3b uvt t=0.5", s, [[5, 5], [35, 5], [5, 35], [35, 35]]);
		// t3c: perspective: t differs per vertex (right side farther, t=0.5), u pre-multiplied by t
		s = new Shape();
		s.graphics.beginBitmapFill(bd);
		uvt = new flash.Vector<Float>();
		for (d in [0, 0, 1, 0.5, 0, 0.5, 0.5, 0.5, 0.5, 0, 1, 1]) uvt.push(d);
		s.graphics.drawTriangles(v, idx, uvt);
		s.graphics.endFill();
		sample("t3c uvt perspective", s, [[5, 5], [35, 5], [5, 35], [35, 35], [20, 20], [10, 20], [30, 20]]);

		// t4: uv with a bitmap fill matrix (matrix must be ignored)
		s = new Shape();
		s.graphics.beginBitmapFill(bd, new Matrix(2, 0, 0, 2, 10, 10));
		uv = new flash.Vector<Float>();
		for (d in [0, 0, 1, 0, 1, 1, 0, 1]) uv.push(d);
		s.graphics.drawTriangles(v, idx, uv);
		s.graphics.endFill();
		sample("t4 uv with fill matrix", s, [[5, 5], [35, 5], [5, 35], [35, 35]]);

		// t5: bitmap fill without uv: plain fill (matrix applies?)
		s = new Shape();
		s.graphics.beginBitmapFill(bd, new Matrix(2, 0, 0, 2, 0, 0));
		s.graphics.drawTriangles(v, idx);
		s.graphics.endFill();
		sample("t5 bitmap no uv, matrix 2x", s, [[5, 5], [35, 5], [5, 35], [35, 35], [15, 15], [25, 25]]);

		// t6: solid fill with uv data (ignored) + overlap union of opposite orientation
		s = new Shape();
		s.graphics.beginFill(0x00FF00);
		var v2 = new flash.Vector<Float>();
		for (d in [0, 0, 40, 0, 0, 40, 0, 0, 0, 40, 40, 0, 10, 10, 50, 10, 50, 50, 10, 10, 10, 50, 50, 50]) v2.push(d);
		s.graphics.drawTriangles(v2, null, uv);
		s.graphics.endFill();
		sample("t6 solid overlap", s, [[20, 15], [15, 20], [45, 45], [30, 30], [5, 5], [55, 55]]);

		// t7: opposite orientation overlapping triangles with culling none
		s = new Shape();
		s.graphics.beginFill(0xFF0000);
		v2 = new flash.Vector<Float>();
		for (d in [0, 0, 40, 0, 40, 40, 0, 0, 40, 40, 0, 40]) v2.push(d);
		s.graphics.drawTriangles(v2);
		s.graphics.endFill();
		sample("t7 cw+ccw", s, [[30, 10], [10, 30], [20, 20], [20, 19], [20, 21]]);
		// t8: same two triangles both clockwise
		s = new Shape();
		s.graphics.beginFill(0xFF0000);
		v2 = new flash.Vector<Float>();
		for (d in [0, 0, 40, 0, 40, 40, 0, 0, 0, 40, 40, 40]) v2.push(d);
		s.graphics.drawTriangles(v2);
		s.graphics.endFill();
		sample("t8 cw+cw", s, [[30, 10], [10, 30], [20, 20], [20, 19], [20, 21]]);
		// t9: triangles followed by lineTo path in the same fill: even-odd for the path part?
		s = new Shape();
		s.graphics.beginFill(0xFF0000);
		s.graphics.drawRect(0, 0, 30, 30);
		s.graphics.drawRect(10, 10, 30, 30);
		v2 = new flash.Vector<Float>();
		for (d in [20, 20, 50, 20, 50, 50]) v2.push(d);
		s.graphics.drawTriangles(v2);
		s.graphics.drawRect(5, 5, 30, 30);
		s.graphics.endFill();
		sample("t9 mixed", s, [[15, 15], [25, 25], [40, 30], [7, 7], [32, 32], [2, 2]]);
		// t10: stroke with triangles
		s = new Shape();
		s.graphics.lineStyle(4, 0x0000FF);
		s.graphics.beginFill(0xFF0000);
		v2 = new flash.Vector<Float>();
		for (d in [10, 10, 50, 10, 50, 50]) v2.push(d);
		s.graphics.drawTriangles(v2);
		s.graphics.endFill();
		sample("t10 stroke", s, [[30, 10], [50, 30], [30, 30], [40, 20], [10, 10]]);
	}

	static function paths() {
		// p1: drawPath stroke, open sub-path: is the closing edge drawn?
		var s = new Shape();
		s.graphics.lineStyle(4, 0x0000FF);
		var cmds = new flash.Vector<Int>();
		for (c in [1, 2, 2]) cmds.push(c);
		var data = new flash.Vector<Float>();
		for (d in [0, 0, 40, 0, 40, 40]) data.push(d);
		s.graphics.drawPath(cmds, data);
		sample("p1 drawPath stroke open", s, [[20, 0], [40, 20], [20, 20], [10, 10]]);
		// p1b: with a fill active
		s = new Shape();
		s.graphics.lineStyle(4, 0x0000FF);
		s.graphics.beginFill(0xFF0000);
		s.graphics.drawPath(cmds, data);
		s.graphics.endFill();
		sample("p1b drawPath stroke+fill open", s, [[20, 0], [40, 20], [20, 20], [30, 10], [10, 10]]);
		// p1c: same with moveTo/lineTo
		s = new Shape();
		s.graphics.lineStyle(4, 0x0000FF);
		s.graphics.beginFill(0xFF0000);
		s.graphics.moveTo(0, 0); s.graphics.lineTo(40, 0); s.graphics.lineTo(40, 40);
		s.graphics.endFill();
		sample("p1c lineTo stroke+fill open", s, [[20, 0], [40, 20], [20, 20], [30, 10], [10, 10]]);
		// p1d: drawPath stroke, two sub-paths, then endFill: closes which?
		s = new Shape();
		s.graphics.lineStyle(4, 0x0000FF);
		s.graphics.beginFill(0xFF0000);
		cmds = new flash.Vector<Int>();
		for (c in [1, 2, 2, 1, 2, 2]) cmds.push(c);
		data = new flash.Vector<Float>();
		for (d in [0, 0, 20, 0, 20, 20, 30, 30, 50, 30, 50, 50]) data.push(d);
		s.graphics.drawPath(cmds, data);
		s.graphics.endFill();
		sample("p1d two subpaths", s, [[10, 10], [40, 40], [15, 5], [45, 35], [10, 0], [40, 30]]);
		// p2: winding even-odd vs nonzero with two same-direction squares
		for (w in ["evenOdd", "nonZero"]) {
			s = new Shape();
			s.graphics.beginFill(0xFF0000);
			cmds = new flash.Vector<Int>();
			for (c in [1, 2, 2, 2, 2, 1, 2, 2, 2, 2]) cmds.push(c);
			data = new flash.Vector<Float>();
			for (d in [0, 0, 30, 0, 30, 30, 0, 30, 0, 0, 10, 10, 40, 10, 40, 40, 10, 40, 10, 10]) data.push(d);
			s.graphics.drawPath(cmds, data, cast w);
			s.graphics.endFill();
			sample("p2 " + w, s, [[5, 5], [20, 20], [35, 35]]);
		}
		// p3: drawPath then lineTo in the same fill: does the winding stick?
		s = new Shape();
		s.graphics.beginFill(0xFF0000);
		cmds = new flash.Vector<Int>();
		for (c in [1, 2, 2, 2, 2]) cmds.push(c);
		data = new flash.Vector<Float>();
		for (d in [0, 0, 30, 0, 30, 30, 0, 30, 0, 0]) data.push(d);
		s.graphics.drawPath(cmds, data, cast "nonZero");
		s.graphics.moveTo(10, 10); s.graphics.lineTo(40, 10); s.graphics.lineTo(40, 40); s.graphics.lineTo(10, 40); s.graphics.lineTo(10, 10);
		s.graphics.endFill();
		sample("p3 nonZero then lineTo", s, [[5, 5], [20, 20], [35, 35]]);
		// p4: lineTo square then drawPath evenOdd square overlapping
		s = new Shape();
		s.graphics.beginFill(0xFF0000);
		s.graphics.moveTo(0, 0); s.graphics.lineTo(30, 0); s.graphics.lineTo(30, 30); s.graphics.lineTo(0, 30); s.graphics.lineTo(0, 0);
		cmds = new flash.Vector<Int>();
		for (c in [1, 2, 2, 2, 2]) cmds.push(c);
		data = new flash.Vector<Float>();
		for (d in [10, 10, 40, 10, 40, 40, 10, 40, 10, 10]) data.push(d);
		s.graphics.drawPath(cmds, data, cast "nonZero");
		s.graphics.endFill();
		sample("p4 lineTo then nonZero", s, [[5, 5], [20, 20], [35, 35]]);
	}

	static function main() {
		H.init("d55graphics", 30000);
		qn = untyped __global__["flash.utils.getQualifiedClassName"];
		step("readData", readData);
		step("triangles", triangles);
		step("paths", paths);
		H.done();
	}
}
