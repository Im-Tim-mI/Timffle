import flash.Lib;
import flash.display.Shape;

/**
 * Where is the decision boundary of `hitTestPoint(x, y, true)` for a filled shape? A rectangle whose edge sits at
 * `E` (moved in steps of one twip, 1/20 px) is tested at the integer point (10, 10): for each side, the range of E
 * for which the point is a hit. A slanted edge at 45 degrees and at other slopes likewise. Real Flash decides in
 * whole pixels (see d14hit_sample), so this shows which part of the pixel it looks at.
 * Exploration: prints what the player does, no golden.
 */
class D15HitEdge {
	static var PX = 10;
	static var PY = 10;

	static function main() {
		H.init("d15hit_edge", 40000);
		sweepRect("left edge at E (fill to its right)", function(g, e) g.drawRect(e, -50, 100, 100));
		sweepRect("right edge at E (fill to its left)", function(g, e) g.drawRect(e - 100, -50, 100, 100));
		sweepRect("top edge at E (fill below it)", function(g, e) g.drawRect(-50, e, 100, 100), true);
		sweepRect("bottom edge at E (fill above it)", function(g, e) g.drawRect(-50, e - 100, 100, 100), true);
		for (slope in [1.0, 0.5, 2.0, 0.25, 4.0]) {
			sweepSlanted(slope, false);
			sweepSlanted(slope, true);
		}
		H.done();
	}

	static function hit(draw:flash.display.Graphics->Void, x:Int = 10, y:Int = 10):Bool {
		var s = new Shape();
		s.graphics.beginFill(0x000000, 1);
		draw(s.graphics);
		s.graphics.endFill();
		Lib.current.addChild(s);
		var r = s.hitTestPoint(x, y, true);
		Lib.current.removeChild(s);
		return r;
	}

	static function range(label:String, values:Array<Float>, hits:Array<Bool>) {
		// report the maximal runs of hits as E ranges
		var runs = [];
		var start = -1;
		for (i in 0...values.length) {
			if (hits[i] && start < 0)
				start = i;
			if ((!hits[i] || i == values.length - 1) && start >= 0) {
				var end = hits[i] ? i : i - 1;
				runs.push(values[start] + ".." + values[end]);
				start = -1;
			}
		}
		H.log(label + ": hit for E in " + (runs.length == 0 ? "never" : runs.join(" ; ")));
	}

	static function sweepRect(label:String, make:flash.display.Graphics->Float->Void, ?vertical:Bool) {
		var vals = [];
		var hits = [];
		for (k in 0...41) {
			var e = 9.0 + k * 0.05;
			e = Math.round(e * 20) / 20;
			vals.push(e);
			hits.push(hit(function(g) make(g, e)));
		}
		range(label + " (point 10,10)", vals, hits);
	}

	// A half-plane under the line through (10 + c, 10 - slope*..), i.e. a big triangle whose edge has the given
	// slope and passes at horizontal offset c from the tested point. flip: fill on the other side.
	static function sweepSlanted(slope:Float, flip:Bool) {
		var vals = [];
		var hits = [];
		for (k in 0...41) {
			var c = -1.0 + k * 0.05;
			c = Math.round(c * 20) / 20;
			vals.push(c);
			hits.push(hit(function(g) {
				// the line passes through (10 + c, 10) with direction (1, slope); a polygon on one side of it
				var x0 = 10 + c - 60, y0 = 10 - 60 * slope;
				var x1 = 10 + c + 60, y1 = 10 + 60 * slope;
				if (!flip) {
					g.moveTo(x0, y0);
					g.lineTo(x1, y1);
					g.lineTo(x1, y1 + 300);
					g.lineTo(x0, y0 + 300);
				} else {
					g.moveTo(x0, y0);
					g.lineTo(x1, y1);
					g.lineTo(x1, y1 - 300);
					g.lineTo(x0, y0 - 300);
				}
				g.lineTo(x0, y0);
			}));
		}
		range("slope " + slope + (flip ? " fill above the line" : " fill below the line") + " offset c of the line from the point", vals, hits);
	}
}
