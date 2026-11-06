/** Probe (no golden): how Flash Player 32 combines drawRect/lineTo, drawPath and drawTriangles
 *  sub-paths inside one fill (winding rule per group), plus readGraphicsData of mixed fills. */
import flash.Lib;
import flash.display.*;

class D57Winding {
	static var qn:Dynamic;

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

	static function sample(label:String, s:DisplayObject, pts:Array<Array<Int>>) {
		var bd = new BitmapData(60, 60, true, 0x00000000);
		bd.draw(s);
		var out = [];
		for (p in pts) out.push(p[0] + "," + p[1] + "=" + StringTools.hex(bd.getPixel32(p[0], p[1]), 8));
		H.log(label + " " + out.join(" "));
	}

	static function sq(g:Graphics, x:Float, y:Float, ccw:Bool = false) {
		g.moveTo(x, y);
		if (ccw) { g.lineTo(x, y + 30); g.lineTo(x + 30, y + 30); g.lineTo(x + 30, y); }
		else { g.lineTo(x + 30, y); g.lineTo(x + 30, y + 30); g.lineTo(x, y + 30); }
		g.lineTo(x, y);
	}

	static function pathSq(g:Graphics, x:Float, y:Float, w:String, ccw:Bool = false) {
		var d = ccw ? [x, y, x, y + 30, x + 30, y + 30, x + 30, y, x, y] : [x, y, x + 30, y, x + 30, y + 30, x, y + 30, x, y];
		g.drawPath(I([1, 2, 2, 2, 2]), V(d), cast w);
	}

	static function tri(g:Graphics, x:Float, y:Float) {
		g.drawTriangles(V([x, y, x + 10, y, x + 10, y + 10]));
	}

	static function vec(v:Dynamic):String {
		if (v == null) return "null";
		var out = [];
		var len:Int = v.length;
		for (i in 0...len) out.push(Std.string(v[i]));
		return "[" + out.join(",") + "]";
	}

	static function dump(label:String, g:Graphics) {
		var v:Dynamic = g.readGraphicsData(true);
		var parts = [];
		var len:Int = v.length;
		for (i in 0...len) {
			var d:Dynamic = v[i];
			var c:String = qn(d);
			if (c == "flash.display::GraphicsPath") parts.push("Path" + vec(d.commands) + d.winding);
			else parts.push(c.split("::")[1]);
		}
		H.log(label + " " + parts.join(" "));
	}

	static function run() {
		var pts = [[20, 20], [5, 5], [35, 35]];
		// a: drawRect x2 overlapping
		var s = new Shape();
		s.graphics.beginFill(0xFF0000);
		s.graphics.drawRect(0, 0, 30, 30); s.graphics.drawRect(10, 10, 30, 30);
		s.graphics.endFill();
		sample("a drawRect x2", s, pts);
		dump("a", s.graphics);
		// b: lineTo squares x2 then drawTriangles elsewhere
		s = new Shape();
		s.graphics.beginFill(0xFF0000);
		sq(s.graphics, 0, 0); sq(s.graphics, 10, 10); tri(s.graphics, 45, 0);
		s.graphics.endFill();
		sample("b lineTo x2 then tri", s, pts);
		dump("b", s.graphics);
		// c: drawTriangles then lineTo squares x2
		s = new Shape();
		s.graphics.beginFill(0xFF0000);
		tri(s.graphics, 45, 0); sq(s.graphics, 0, 0); sq(s.graphics, 10, 10);
		s.graphics.endFill();
		sample("c tri then lineTo x2", s, pts);
		dump("c", s.graphics);
		// c2: lineTo square, drawTriangles elsewhere, lineTo square overlapping the first
		s = new Shape();
		s.graphics.beginFill(0xFF0000);
		sq(s.graphics, 0, 0); tri(s.graphics, 45, 0); sq(s.graphics, 10, 10);
		s.graphics.endFill();
		sample("c2 sq tri sq", s, pts);
		dump("c2", s.graphics);
		// d: drawPath evenOdd x2 overlapping (separate calls)
		s = new Shape();
		s.graphics.beginFill(0xFF0000);
		pathSq(s.graphics, 0, 0, "evenOdd"); pathSq(s.graphics, 10, 10, "evenOdd");
		s.graphics.endFill();
		sample("d path eo x2", s, pts);
		dump("d", s.graphics);
		// d2: drawPath nonZero x2 same direction
		s = new Shape();
		s.graphics.beginFill(0xFF0000);
		pathSq(s.graphics, 0, 0, "nonZero"); pathSq(s.graphics, 10, 10, "nonZero");
		s.graphics.endFill();
		sample("d2 path nz x2 cw", s, pts);
		dump("d2", s.graphics);
		// e: drawPath nonZero then drawPath evenOdd overlapping
		s = new Shape();
		s.graphics.beginFill(0xFF0000);
		pathSq(s.graphics, 0, 0, "nonZero"); pathSq(s.graphics, 10, 10, "evenOdd");
		s.graphics.endFill();
		sample("e path nz then eo", s, pts);
		dump("e", s.graphics);
		// f: lineTo square, drawPath nonZero overlapping ccw
		s = new Shape();
		s.graphics.beginFill(0xFF0000);
		sq(s.graphics, 0, 0); pathSq(s.graphics, 10, 10, "nonZero", true);
		s.graphics.endFill();
		sample("f sq then path nz ccw", s, pts);
		dump("f", s.graphics);
		// f2: lineTo square cw, lineTo square ccw overlapping
		s = new Shape();
		s.graphics.beginFill(0xFF0000);
		sq(s.graphics, 0, 0); sq(s.graphics, 10, 10, true);
		s.graphics.endFill();
		sample("f2 sq cw + sq ccw", s, pts);
		// g: triangles overlapping squares: lineTo square then triangle overlapping it
		s = new Shape();
		s.graphics.beginFill(0xFF0000);
		sq(s.graphics, 0, 0);
		s.graphics.drawTriangles(V([10, 10, 50, 10, 50, 50]));
		s.graphics.endFill();
		sample("g sq then tri overlap", s, [[20, 15], [5, 5], [40, 40]]);
		dump("g", s.graphics);
		// h: drawRect x2 overlapping then drawPath evenOdd elsewhere
		s = new Shape();
		s.graphics.beginFill(0xFF0000);
		s.graphics.drawRect(0, 0, 30, 30); s.graphics.drawRect(10, 10, 30, 30);
		pathSq(s.graphics, 45, 45, "evenOdd");
		s.graphics.endFill();
		sample("h rect x2 then path eo", s, pts);
		dump("h", s.graphics);
		// i: drawTriangles x2 calls: cw + ccw overlapping (separate calls)
		s = new Shape();
		s.graphics.beginFill(0xFF0000);
		s.graphics.drawTriangles(V([0, 0, 40, 0, 40, 40]));
		s.graphics.drawTriangles(V([0, 0, 40, 40, 40, 0]));
		s.graphics.endFill();
		sample("i tri cw + tri ccw calls", s, [[30, 10], [20, 15]]);
		// j: lineTo square cw, then drawPath nonZero square cw overlapping
		s = new Shape();
		s.graphics.beginFill(0xFF0000);
		sq(s.graphics, 0, 0); pathSq(s.graphics, 10, 10, "nonZero");
		s.graphics.endFill();
		sample("j sq then path nz cw", s, pts);
		// k: drawPath evenOdd then lineTo square overlapping
		s = new Shape();
		s.graphics.beginFill(0xFF0000);
		pathSq(s.graphics, 0, 0, "evenOdd"); sq(s.graphics, 10, 10);
		s.graphics.endFill();
		sample("k path eo then sq", s, pts);
		dump("k", s.graphics);
		// l: lineTo x2 overlapping, then endFill, beginFill + drawRect: separate fills
		s = new Shape();
		s.graphics.beginFill(0xFF0000);
		sq(s.graphics, 0, 0);
		s.graphics.beginFill(0xFF0000);
		sq(s.graphics, 10, 10);
		s.graphics.endFill();
		sample("l two beginFill", s, pts);
		dump("l", s.graphics);
	}

	static function main() {
		H.init("d57winding", 20000);
		qn = untyped __global__["flash.utils.getQualifiedClassName"];
		try { run(); } catch (e:flash.errors.Error) { H.log("THREW " + qn(e) + " #" + e.errorID); }
		H.done();
	}
}
