/** Probe (no golden): BitmapData.generateFilterRect expansion of BlurFilter per blur value and
 *  quality in Flash Player 32 (fine grid, to derive the formula). */
import flash.display.BitmapData;
import flash.filters.BlurFilter;
import flash.filters.GlowFilter;
import flash.geom.Rectangle;

class D53BlurRect {
	static function main() {
		H.init("d53blurrect", 20000);
		var bd = new BitmapData(2000, 2000, true, 0xFF00FF00);
		var src = new Rectangle(500, 500, 100, 100);
		for (q in [1, 2, 3, 4]) {
			var line = "q" + q + ":";
			var b = 0.0;
			while (b <= 16.0) {
				var r = bd.generateFilterRect(src, new BlurFilter(b, 0, q));
				line += " " + b + "=" + (500 - r.x);
				b += 0.25;
			}
			H.log(line);
		}
		for (q in [2, 3, 5, 8, 12, 15]) {
			var line = "big q" + q + ":";
			for (b in [20, 25, 33, 40, 50, 64, 77, 100, 128, 150, 200, 255]) {
				var r = bd.generateFilterRect(src, new BlurFilter(b, 0, q));
				line += " " + b + "=" + (500 - r.x);
			}
			H.log(line);
		}
		var line = "glow q2:";
		for (b in [1, 2, 3, 4, 5, 6, 7, 8, 10]) {
			var r = bd.generateFilterRect(src, new GlowFilter(0xFF0000, 1, b, 0, 1, 2));
			line += " " + b + "=" + (500 - r.x);
		}
		H.log(line);
		line = "blur q2 y:";
		for (b in [1, 2, 3, 4, 5, 6, 7, 8, 10]) {
			var r = bd.generateFilterRect(src, new BlurFilter(0, b, 2));
			line += " " + b + "=" + (500 - r.y);
		}
		H.log(line);
		H.done();
	}
}
