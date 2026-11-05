/** Golden (d66drawfilters): BitmapData.draw(source) applies the filters of the drawn object
 *  itself and of its children, at the filtered object's place. A 10x10 white square at (10,10)
 *  inside a Sprite, drawn into a 40x40 black bitmap. For row 15 and column 15 it prints the first
 *  and last index whose blue value is above 16 and above 128 (the raw values differ by a few
 *  levels between players' blur implementations; RAW=1 prints them). */
import flash.display.BitmapData;
import flash.display.Shape;
import flash.display.Sprite;
import flash.filters.BitmapFilter;
import flash.filters.BlurFilter;
import flash.filters.ColorMatrixFilter;
import flash.filters.DropShadowFilter;
import flash.filters.GlowFilter;
import flash.geom.Matrix;

class D66DrawFilters {
	static function square():Shape {
		var s = new Shape();
		s.graphics.beginFill(0xFFFFFF);
		s.graphics.drawRect(10, 10, 10, 10);
		s.graphics.endFill();
		return s;
	}

	static function extent(v:Array<Int>, t:Int):String {
		var a = -1, b = -1;
		for (i in 0...v.length) if (v[i] > t) { if (a < 0) a = i; b = i; }
		return a + ".." + b;
	}

	static function dump(label:String, bd:BitmapData) {
		var r:Array<Int> = [];
		for (x in 0...40) r.push(Std.int(bd.getPixel(x, 15) & 0xFF));
		var c:Array<Int> = [];
		for (y in 0...40) c.push(Std.int(bd.getPixel(15, y) & 0xFF));
		H.log(label + " row15 >16 " + extent(r, 16) + " >128 " + extent(r, 128) + "  col15 >16 " + extent(c, 16) + " >128 " + extent(c, 128));
		#if RAW
		H.log("~ " + label + " row15 " + r.join(","));
		H.log("~ " + label + " col15 " + c.join(","));
		#end
	}

	static function run(label:String, filters:Array<BitmapFilter>, onChild:Bool, m:Matrix) {
		try {
			var holder = new Sprite();
			var sq = square();
			holder.addChild(sq);
			if (onChild) sq.filters = filters; else holder.filters = filters;
			holder.x = 100; // ignored by draw
			var bd = new BitmapData(40, 40, false, 0);
			bd.draw(holder, m);
			dump(label, bd);
		} catch (e:flash.errors.Error) {
			H.log(label + " THREW " + e.errorID);
		}
	}

	static function main() {
		H.init("d66drawfilters", 20000);
		var id = new Matrix();
		var t = new Matrix(); t.translate(3, 2);
		var s = new Matrix(); s.scale(1.5, 1.5);
		run("none", [], false, id);
		run("blur4q1-self", [new BlurFilter(4, 4, 1)], false, id);
		run("blur4q1-child", [new BlurFilter(4, 4, 1)], true, id);
		run("blur4q3-self", [new BlurFilter(4, 4, 3)], false, id);
		run("blur4q3-self-t32", [new BlurFilter(4, 4, 3)], false, t);
		run("blur4q1-self-s15", [new BlurFilter(4, 4, 1)], false, s);
		run("blur4q1-child-s15", [new BlurFilter(4, 4, 1)], true, s);
		run("cmf-self", [new ColorMatrixFilter([0.5,0,0,0,0, 0,0.5,0,0,0, 0,0,0.5,0,0, 0,0,0,1,0])], false, id);
		run("glow-self", [new GlowFilter(0xFF0000, 1, 6, 6, 2, 1)], false, id);
		run("shadow-self", [new DropShadowFilter(4, 45, 0x0000FF, 1, 0, 0, 1, 1)], false, id);
		H.done();
	}
}
