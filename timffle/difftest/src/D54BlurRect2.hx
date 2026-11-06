/** Probe (no golden): BlurFilter generateFilterRect expansion at exact-integer boundaries and
 *  for tiny blur values at every quality (Flash Player 32). */
import flash.display.BitmapData;
import flash.filters.BlurFilter;
import flash.geom.Rectangle;

class D54BlurRect2 {
	static function main() {
		H.init("d54blurrect2", 20000);
		var bd = new BitmapData(2000, 2000, true, 0xFF00FF00);
		var src = new Rectangle(500, 500, 100, 100);
		var e = function(b:Float, q:Int):Int {
			var r = bd.generateFilterRect(src, new BlurFilter(b, 0, q));
			return Std.int(500 - r.x);
		}
		var line = "exact:";
		var cs:Array<Array<Float>> = [[5, 2], [25, 2], [45, 2], [65, 2], [15, 3], [35, 3], [55, 3], [3, 5], [7, 5], [2.5, 8], [0.75, 12], [1.5, 15], [10, 12], [20, 12], [4, 7], [8, 7]];
		for (c in cs)
			line += " q" + c[1] + "b" + c[0] + "=" + e(c[0], Std.int(c[1]));
		H.log(line);
		for (q in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]) {
			line = "small q" + q + ":";
			for (b in [0, 0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 3])
				line += " " + b + "=" + e(b, q);
			H.log(line);
		}
		for (q in [5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]) {
			line = "mid q" + q + ":";
			for (b in [4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20])
				line += " " + b + "=" + e(b, q);
			H.log(line);
		}
		H.done();
	}
}
