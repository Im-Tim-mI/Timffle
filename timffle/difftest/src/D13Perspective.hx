import flash.Lib;
import flash.display.BitmapData;
import flash.display.Sprite;
import flash.events.Event;
import flash.geom.PerspectiveProjection;
import flash.geom.Point;
import flash.geom.Rectangle;

/**
 * The 3D character carousel of a game's login page: five nodes on a circle
 * (`x = sin(a) * R`, `z = R - cos(a) * R`, R = 480, a = 0, 72, 144, 216, 288 degrees) inside a container whose
 * `perspectiveProjection.projectionCenter` is (420, -150). Where does every node end up on screen?
 *
 * Each node is a coloured block in 2D (170 x 60 around (480, 342) in its own space, like the page's circles).
 * The bounding box of that colour in `BitmapData.draw(stage)` is the projected position. Variants change the
 * projection (field of view, centre, none, set the way the page does it) and the container's own position and
 * scale. The text lines are verdicts against the textbook model Flash follows (a plane at depth z is scaled by
 * focalLength / (focalLength + z) about the centre, which is a point of the container's own space; the
 * container's matrix applies afterwards); raw measurements are `~` lines, which the comparison ignores.
 */
class D13Perspective extends Sprite {
	static inline var R = 480.0;
	static inline var BLOCK_W = 170.0;
	static inline var BLOCK_H = 60.0;
	static var COLORS = [0xFF0000, 0x00AA00, 0x0000FF, 0xFF00FF, 0x00AAAA];

	// name, container x, y, scale, how the projection is set, field of view (0 = default), centre x, y
	// how: "none" | "before" (centre and fov set, then assigned) | "live" (assigned, then changed through the
	// getter, as the login page does) | "assigned" (a new PerspectiveProjection, left alone)
	static var VARIANTS:Array<Dynamic> = [
		["login-live", 0.0, 0.0, 1.0, "live", 0.0, 420.0, -150.0],
		["login-before", 0.0, 0.0, 1.0, "before", 0.0, 420.0, -150.0],
		["no-projection", 0.0, 0.0, 1.0, "none", 0.0, 0.0, 0.0],
		["assigned-untouched", 0.0, 0.0, 1.0, "assigned", 0.0, 0.0, 0.0],
		["fov90-centre-stage", 0.0, 0.0, 1.0, "before", 90.0, 480.0, 280.0],
		["fov30-centre-stage", 0.0, 0.0, 1.0, "before", 30.0, 480.0, 280.0],
		["offset-scaled", 100.0, 60.0, 0.8, "live", 0.0, 420.0, -150.0],
		["centre-offset", 0.0, 0.0, 1.0, "before", 0.0, 200.0, 100.0],
	];

	var frame = 0;
	var variant = -1;
	var container:Sprite;
	var items:Array<Sprite>;

	public static function main() {
		H.init("d13perspective", 50000);
		Lib.current.addChild(new D13Perspective());
	}

	public function new() {
		super();
		// A backdrop as large as the stage, so that no player clips BitmapData.draw(stage) to the 2D bounds of the nodes.
		graphics.beginFill(0xFFFFFF);
		graphics.drawRect(0, 0, 960, 560);
		graphics.endFill();
		H.log("stage " + Lib.current.stage.stageWidth + "x" + Lib.current.stage.stageHeight + " scaleMode=" + Lib.current.stage.scaleMode);
		addEventListener(Event.ENTER_FRAME, tick);
	}

	function tick(_) {
		frame++;
		if (variant >= 0 && frame % 4 == 3)
			measure();
		if (frame % 4 == 0) {
			variant++;
			if (variant >= VARIANTS.length) {
				removeEventListener(Event.ENTER_FRAME, tick);
				H.done();
				haxe.Timer.delay(function() flash.Lib.fscommand("quit"), 800);
				return;
			}
			build(VARIANTS[variant]);
		}
	}

	function build(v:Array<Dynamic>) {
		if (container != null)
			removeChild(container);
		container = new Sprite();
		container.x = v[1];
		container.y = v[2];
		container.scaleX = container.scaleY = v[3];
		items = [];
		for (i in 0...5) {
			var a = i * 72 * Math.PI / 180;
			var item = new Sprite();
			item.graphics.beginFill(COLORS[i]);
			item.graphics.drawRect(480 - BLOCK_W / 2, 342 - BLOCK_H / 2, BLOCK_W, BLOCK_H);
			item.graphics.endFill();
			item.x = Math.sin(a) * R;
			item.z = R - Math.cos(a) * R;
			items.push(item);
		}
		// like the login page's depth sort: far nodes first, so the near ones are drawn on top
		var order = items.copy();
		order.sort(function(p, q) return p.z > q.z ? -1 : (p.z < q.z ? 1 : 0));
		for (it in order)
			container.addChild(it);
		switch (v[4]) {
			case "before":
				var pp = new PerspectiveProjection();
				if (v[5] > 0)
					pp.fieldOfView = v[5];
				pp.projectionCenter = new Point(v[6], v[7]);
				container.transform.perspectiveProjection = pp;
			case "live":
				container.transform.perspectiveProjection = new PerspectiveProjection();
				if (v[5] > 0)
					container.transform.perspectiveProjection.fieldOfView = v[5];
				container.transform.perspectiveProjection.projectionCenter = new Point(v[6], v[7]);
			case "assigned":
				container.transform.perspectiveProjection = new PerspectiveProjection();
			default:
		}
		addChild(container);
	}

	static function r1(x:Float):String
		return Std.string(Math.round(x * 10) / 10);

	function measure() {
		var v = VARIANTS[variant];
		var st = Lib.current.stage;
		var pp = container.transform.perspectiveProjection;
		// What the projection is, as the player reports it; the expectations below are computed from it.
		var focal = 480 / Math.tan(55 / 2 * Math.PI / 180);
		var cx = 480.0, cy = 280.0;
		if (pp != null) {
			focal = pp.focalLength;
			cx = pp.projectionCenter.x;
			cy = pp.projectionCenter.y;
		}
		H.log("== " + v[0] + ": container (" + v[1] + "," + v[2] + ") scale " + v[3] + " projection " + v[4]);
		H.log("projection reported: " + (pp == null ? "none" : "fov=" + r1(pp.fieldOfView) + " focalLength=" + r1(pp.focalLength) + " centre=(" + r1(pp.projectionCenter.x) + "," + r1(pp.projectionCenter.y) + ")"));
		var bd:BitmapData = null;
		try {
			bd = new BitmapData(st.stageWidth, st.stageHeight, true, 0xFFFFFFFF);
			bd.draw(st);
		} catch (e:Dynamic) {
			H.log("draw THREW " + H.err(e) + " " + Std.string(e).substr(0, 160));
			return;
		}
		var minX = [for (_ in 0...5) 99999];
		var minY = [for (_ in 0...5) 99999];
		var maxX = [for (_ in 0...5) -1];
		var maxY = [for (_ in 0...5) -1];
		for (y in 0...bd.height)
			for (x in 0...bd.width) {
				var c:Int = cast bd.getPixel(x, y);
				if (c == 0xFFFFFF)
					continue;
				for (i in 0...5)
					if (c == COLORS[i]) {
						if (x < minX[i]) minX[i] = x;
						if (y < minY[i]) minY[i] = y;
						if (x > maxX[i]) maxX[i] = x;
						if (y > maxY[i]) maxY[i] = y;
					}
			}
		bd.dispose();
		for (i in 0...5) {
			var it = items[i];
			// expected, from the model
			var s = focal / (focal + it.z);
			var ex = container.x + container.scaleX * (cx + (480 + it.x - cx) * s);
			var ey = container.y + container.scaleY * (cy + (342 - cy) * s);
			var ew = BLOCK_W * s * container.scaleX;
			var eh = BLOCK_H * s * container.scaleY;
			var seen = maxX[i] >= 0;
			var dx = (minX[i] + maxX[i] + 1) / 2;
			var dy = (minY[i] + maxY[i] + 1) / 2;
			var dw = maxX[i] - minX[i] + 1;
			var dh = maxY[i] - minY[i] + 1;
			var gb:Rectangle = it.getBounds(st);
			var drawnOk = seen && Math.abs(dx - ex) <= 1.5 && Math.abs(dy - ey) <= 1.5 && Math.abs(dw - ew) <= 2.5 && Math.abs(dh - eh) <= 2.5;
			var boundsOk = Math.abs(gb.x + gb.width / 2 - ex) <= 2 && Math.abs(gb.y + gb.height / 2 - ey) <= 2 && Math.abs(gb.width - ew) <= 3 && Math.abs(gb.height - eh) <= 3;
			// a point inside the projected block hits it; the node's plain 2D position hits it only if it overlaps
			var ux = container.x + container.scaleX * (480 + it.x);
			var uy = container.y + container.scaleY * 342;
			var plainInside = Math.abs(ux - ex) < ew / 2 - 2 && Math.abs(uy - ey) < eh / 2 - 2;
			var plainOutside = Math.abs(ux - ex) > ew / 2 + 2 || Math.abs(uy - ey) > eh / 2 + 2;
			var hitDrawn = it.hitTestPoint(ex, ey, true);
			var hitPlain = it.hitTestPoint(ux, uy, true);
			var hitOk = hitDrawn && (!plainOutside || !hitPlain) && (!plainInside || hitPlain);
			var under = st.getObjectsUnderPoint(new Point(ex, ey));
			var underOk = false;
			for (o in under)
				if (o == it)
					underOk = true;
			H.log("node " + i + " z=" + r1(it.z) + ": drawn " + (drawnOk ? "ok" : "WRONG") + ", getBounds " + (boundsOk ? "ok" : "WRONG") + ", hitTestPoint " + (hitOk ? "ok" : "WRONG") + ", getObjectsUnderPoint " + (underOk ? "ok" : "WRONG"));
			H.log("~ node " + i + " expected centre=(" + r1(ex) + "," + r1(ey) + ") size " + r1(ew) + "x" + r1(eh) + " | drawn " + (seen ? "centre=(" + r1(dx) + "," + r1(dy) + ") size " + dw + "x" + dh : "nothing") + " | getBounds=(" + r1(gb.x) + "," + r1(gb.y) + "," + r1(gb.width) + "x" + r1(gb.height) + ") | hit at drawn=" + hitDrawn + " at plain=" + hitPlain);
		}
	}
}
