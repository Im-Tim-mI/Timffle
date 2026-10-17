import flash.Lib;
import flash.display.BitmapData;
import flash.display.DisplayObject;
import flash.display.Sprite;
import flash.events.Event;
import flash.geom.Matrix3D;
import flash.geom.PerspectiveProjection;
import flash.geom.Point;
import flash.geom.Rectangle;
import flash.geom.Vector3D;

/**
 * Do rotated, scaled and nested 3D display objects end up where the projection puts them, on screen (as
 * `BitmapData.draw(stage)` shows it), for hit tests and in `getBounds`? Each case builds a block of 120 x 80 pixels
 * in some 3D setting. The expected position of any point of the block is computed here from first principles
 * (the matrices of the whole chain, perspective projections inserted after the object that owns them), so the verdict
 * lines are the same in a player that does it right. Stage 960 x 560.
 */
class D19Render3D extends Sprite {
	static inline var W = 120.0;
	static inline var H_ = 80.0;

	var cases:Array<{name:String, build:Sprite->Array<Sprite>}> = [];
	var frame = 0;
	var index = -1;
	var holder:Sprite;
	var leaves:Array<Sprite>;
	var colors:Array<Int>;

	public static function main() {
		H.init("d19render3d", 60000);
		Lib.current.addChild(new D19Render3D());
	}

	static function block(color:Int, x:Float, y:Float):Sprite {
		var s = new Sprite();
		s.graphics.beginFill(color);
		s.graphics.drawRect(0, 0, W, H_);
		s.graphics.endFill();
		s.x = x;
		s.y = y;
		s.name = "c" + color;
		return s;
	}

	public function new() {
		super();
		graphics.beginFill(0xFFFFFF);
		graphics.drawRect(0, 0, 960, 560);
		graphics.endFill();
		cases = [
			{name: "rotationY=45", build: function(h:Sprite) {
				var b = block(0xCC3300, 200, 100);
				b.rotationY = 45;
				h.addChild(b);
				return [b];
			}},
			{name: "rotationX=60", build: function(h:Sprite) {
				var b = block(0xCC3300, 300, 150);
				b.rotationX = 60;
				h.addChild(b);
				return [b];
			}},
			{name: "rotationZ=30 z=50", build: function(h:Sprite) {
				var b = block(0xCC3300, 250, 200);
				b.rotationZ = 30;
				b.z = 50;
				h.addChild(b);
				return [b];
			}},
			{name: "rotation 30/40/20 scale 1.2/0.8/1 z=80", build: function(h:Sprite) {
				var b = block(0xCC3300, 400, 250);
				b.rotationX = 30;
				b.rotationY = 40;
				b.rotationZ = 20;
				b.scaleX = 1.2;
				b.scaleY = 0.8;
				b.z = 80;
				h.addChild(b);
				return [b];
			}},
			{name: "matrix3D appendRotation 35 about (1,1,0)", build: function(h:Sprite) {
				var b = block(0xCC3300, 0, 0);
				var m = new Matrix3D();
				m.appendRotation(35, new Vector3D(1, 1, 0));
				m.appendTranslation(150, 120, 20);
				b.transform.matrix3D = m;
				h.addChild(b);
				return [b];
			}},
			{name: "3D container with a 2D child and a 3D child", build: function(h:Sprite) {
				var c = new Sprite();
				c.x = 100;
				c.y = 50;
				c.rotationY = 30;
				h.addChild(c);
				var a = block(0xCC3300, 80, 40);
				c.addChild(a);
				var b = block(0x0033CC, 20, 150);
				b.rotationX = 45;
				b.z = 30;
				c.addChild(b);
				return [a, b];
			}},
			{name: "projection owner (centre (300,100), fov 70) with rotationY=60 z=100", build: function(h:Sprite) {
				var o = new Sprite();
				var pp = new PerspectiveProjection();
				pp.projectionCenter = new Point(300, 100);
				pp.fieldOfView = 70;
				o.transform.perspectiveProjection = pp;
				h.addChild(o);
				var b = block(0xCC3300, 200, 100);
				b.rotationY = 60;
				b.z = 100;
				o.addChild(b);
				return [b];
			}},
			{name: "nested owners (the inner one 3D itself)", build: function(h:Sprite) {
				var a = new Sprite();
				var ppa = new PerspectiveProjection();
				ppa.projectionCenter = new Point(480, 280);
				a.transform.perspectiveProjection = ppa;
				h.addChild(a);
				var bb = new Sprite();
				bb.x = 100;
				bb.y = 80;
				bb.rotationY = 20;
				bb.z = 50;
				var ppb = new PerspectiveProjection();
				ppb.projectionCenter = new Point(100, 100);
				bb.transform.perspectiveProjection = ppb;
				a.addChild(bb);
				var c = block(0xCC3300, 60, 40);
				c.rotationX = 30;
				c.z = 40;
				bb.addChild(c);
				return [c];
			}},
			{name: "cacheAsBitmap on a rotationY=40 object", build: function(h:Sprite) {
				var b = block(0xCC3300, 220, 120);
				b.rotationY = 40;
				b.cacheAsBitmap = true;
				h.addChild(b);
				return [b];
			}},
			{name: "cacheAsBitmap on a 3D container with a 3D child", build: function(h:Sprite) {
				var c = new Sprite();
				c.x = 150;
				c.y = 90;
				c.rotationX = 25;
				c.cacheAsBitmap = true;
				h.addChild(c);
				var b = block(0xCC3300, 30, 20);
				b.rotationY = 30;
				b.z = 20;
				c.addChild(b);
				return [b];
			}},
			{name: "alpha and a blend mode on a rotated object", build: function(h:Sprite) {
				var b = block(0xCC3300, 260, 150);
				b.rotationX = 40;
				b.rotationZ = 10;
				b.blendMode = flash.display.BlendMode.LAYER;
				h.addChild(b);
				return [b];
			}},
			{name: "scaled and offset 2D container around a 3D child", build: function(h:Sprite) {
				var c = new Sprite();
				c.x = 120;
				c.y = 60;
				c.scaleX = 0.8;
				c.scaleY = 0.8;
				var ppc = new PerspectiveProjection();
				ppc.projectionCenter = new Point(420, -150);
				c.transform.perspectiveProjection = ppc;
				h.addChild(c);
				var b = block(0xCC3300, 300, 400);
				b.rotationY = 35;
				b.rotationX = 15;
				b.z = 200;
				c.addChild(b);
				return [b];
			}},
		];
		addEventListener(Event.ENTER_FRAME, tick);
	}

	function tick(_) {
		frame++;
		if (index >= 0 && frame % 4 == 3)
			check();
		if (frame % 4 == 0) {
			index++;
			if (index >= cases.length) {
				removeEventListener(Event.ENTER_FRAME, tick);
				H.done();
				haxe.Timer.delay(function() flash.Lib.fscommand("quit"), 800);
				return;
			}
			if (holder != null)
				removeChild(holder);
			holder = new Sprite();
			addChild(holder);
			leaves = cases[index].build(holder);
		}
	}

	// ---- the expected position, from the matrices of the chain -------------------------------------------------

	static function local4(d:DisplayObject):Array<Float> {
		var m3 = d.transform.matrix3D;
		if (m3 != null)
			return [for (i in 0...16) m3.rawData[i]];
		var m = d.transform.matrix;
		return [m.a, m.b, 0, 0, m.c, m.d, 0, 0, 0, 0, 1, 0, m.tx, m.ty, 0, 1];
	}

	static function mul(a:Array<Float>, b:Array<Float>):Array<Float> {
		var r = [for (_ in 0...16) 0.0];
		for (c in 0...4)
			for (row in 0...4)
				r[c * 4 + row] = a[row] * b[c * 4] + a[4 + row] * b[c * 4 + 1] + a[8 + row] * b[c * 4 + 2] + a[12 + row] * b[c * 4 + 3];
		return r;
	}

	static function projection(cx:Float, cy:Float, f:Float):Array<Float>
		return [f, 0, 0, 0, 0, f, 0, 0, cx, cy, 0, 1, 0, 0, 0, f];

	/** The mapping from the local space of `d` to the stage: every matrix of the chain, a projection after each owner. */
	static function chain(d:DisplayObject):Array<Float> {
		var list = [];
		var n = d;
		while (n != null && n != Lib.current.stage) {
			list.push(n);
			n = n.parent;
		}
		var st = Lib.current.stage;
		var f0 = (st.stageWidth / 2) / Math.tan(55 / 2 * Math.PI / 180);
		var m = projection(st.stageWidth / 2, st.stageHeight / 2, f0);
		var i = list.length - 1;
		while (i >= 0) {
			var node = list[i];
			m = mul(m, local4(node));
			var pp = node.transform.perspectiveProjection;
			if (pp != null && node != d && node != Lib.current)
				m = mul(m, projection(pp.projectionCenter.x, pp.projectionCenter.y, pp.focalLength));
			// the root's own projection is the default one
			i--;
		}
		return m;
	}

	static function project(m:Array<Float>, x:Float, y:Float):Point {
		var X = m[0] * x + m[4] * y + m[12];
		var Y = m[1] * x + m[5] * y + m[13];
		var Wc = m[3] * x + m[7] * y + m[15];
		return new Point(X / Wc, Y / Wc);
	}

	static function r1(x:Float):String
		return Std.string(Math.round(x * 10) / 10);

	function check() {
		var st = Lib.current.stage;
		var bd = new BitmapData(960, 560, false, 0xFFFFFF);
		bd.draw(st);
		var n = 0;
		for (leaf in leaves) {
			n++;
			var m = chain(leaf);
			var leafColor:Int = Std.parseInt(leaf.name.substr(1));
			var inside = [new Point(W / 2, H_ / 2), new Point(20, 15), new Point(100, 15), new Point(20, 65), new Point(100, 65)];
			var outside = [new Point(-6, H_ / 2), new Point(W + 6, H_ / 2), new Point(W / 2, -6), new Point(W / 2, H_ + 6)];
			var colorOk = true;
			var hitInOk = true;
			var hitOutOk = true;
			var outPixelOk = true;
			for (p in inside) {
				var s = project(m, p.x, p.y);
				if ((cast bd.getPixel(Std.int(Math.round(s.x)), Std.int(Math.round(s.y))) : Int) != leafColor)
					colorOk = false;
				if (!leaf.hitTestPoint(s.x, s.y, true))
					hitInOk = false;
			}
			for (p in outside) {
				var s = project(m, p.x, p.y);
				if ((cast bd.getPixel(Std.int(Math.round(s.x)), Std.int(Math.round(s.y))) : Int) == leafColor)
					outPixelOk = false;
				if (leaf.hitTestPoint(s.x, s.y, true))
					hitOutOk = false;
			}
			// bounds: the box of the four projected corners, up to the player's rounding
			var xs = [], ys = [];
			for (p in [new Point(0, 0), new Point(W, 0), new Point(0, H_), new Point(W, H_)]) {
				var s = project(m, p.x, p.y);
				xs.push(s.x);
				ys.push(s.y);
			}
			var minX = Math.min(Math.min(xs[0], xs[1]), Math.min(xs[2], xs[3]));
			var maxX = Math.max(Math.max(xs[0], xs[1]), Math.max(xs[2], xs[3]));
			var minY = Math.min(Math.min(ys[0], ys[1]), Math.min(ys[2], ys[3]));
			var maxY = Math.max(Math.max(ys[0], ys[1]), Math.max(ys[2], ys[3]));
			var b:Rectangle = leaf.getBounds(st);
			var boundsOk = Math.abs(b.x - minX) <= 1.5 && Math.abs(b.y - minY) <= 1.5 && Math.abs(b.right - maxX) <= 1.5 && Math.abs(b.bottom - maxY) <= 1.5;
			// and the whole drawn box of this colour
			var dminX = 99999, dminY = 99999, dmaxX = -1, dmaxY = -1;
			var y0 = Std.int(Math.max(0, minY - 3)), y1 = Std.int(Math.min(559, maxY + 3));
			var x0 = Std.int(Math.max(0, minX - 3)), x1 = Std.int(Math.min(959, maxX + 3));
			for (yy in y0...y1 + 1)
				for (xx in x0...x1 + 1)
					if ((cast bd.getPixel(xx, yy) : Int) == leafColor) {
						if (xx < dminX) dminX = xx;
						if (yy < dminY) dminY = yy;
						if (xx > dmaxX) dmaxX = xx;
						if (yy > dmaxY) dmaxY = yy;
					}
			var drawnOk = dmaxX >= 0 && Math.abs(dminX - minX) <= 2 && Math.abs(dminY - minY) <= 2 && Math.abs(dmaxX + 1 - maxX) <= 2 && Math.abs(dmaxY + 1 - maxY) <= 2;
			// Flash Player does not follow one simple model for a 3D object that owns a projection and sits inside
			// another owner (its own bounds and drawing disagree), so that case is only reported.
			var mark = cases[index].name.indexOf("nested") >= 0 ? "~ " : "";
			H.log(mark + cases[index].name + " #" + n + ": inside points drawn " + (colorOk ? "ok" : "WRONG") + ", outside points not drawn " + (outPixelOk ? "ok" : "WRONG") + ", hit inside " + (hitInOk ? "ok" : "WRONG") + ", no hit outside " + (hitOutOk ? "ok" : "WRONG") + ", getBounds " + (boundsOk ? "ok" : "WRONG") + ", drawn box " + (drawnOk ? "ok" : "WRONG"));
			H.log("~   expected box (" + r1(minX) + "," + r1(minY) + ")-(" + r1(maxX) + "," + r1(maxY) + ") getBounds " + r1(b.x) + "," + r1(b.y) + " " + r1(b.width) + "x" + r1(b.height) + " drawn (" + dminX + "," + dminY + ")-(" + (dmaxX + 1) + "," + (dmaxY + 1) + ")");
		}
		bd.dispose();
	}
}
