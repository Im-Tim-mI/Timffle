import flash.Lib;
import flash.display.DisplayObject;
import flash.display.Sprite;
import flash.geom.Matrix;
import flash.geom.Matrix3D;
import flash.geom.PerspectiveProjection;
import flash.geom.Point;
import flash.geom.Rectangle;
import flash.geom.Vector3D;

/**
 * How real Flash reports geometry of 3D display objects: 2D to 3D conversion, width/height, getBounds,
 * pixelBounds, localToGlobal, local3DToGlobal / globalToLocal3D, getRelativeMatrix3D, hit tests and container
 * bounds. Stage 960x560, no projection owner unless stated (the root's default: centre (480,280), fov 55).
 * Exploration (prints what the player does).
 */
class D17Geom3D {
	static function r(x:Float):String {
		var v = Math.round(x * 100) / 100;
		if (v == 0)
			v = 0;
		return Std.string(v);
	}

	static function rect(b:Rectangle):String
		return b == null ? "null" : "(" + r(b.x) + "," + r(b.y) + "," + r(b.width) + "x" + r(b.height) + ")";

	static function pt(p:Point):String
		return p == null ? "null" : "(" + r(p.x) + "," + r(p.y) + ")";

	static function v3(p:Vector3D):String
		return p == null ? "null" : "(" + r(p.x) + "," + r(p.y) + "," + r(p.z) + ")";

	static function m3(m:Matrix3D):String {
		if (m == null)
			return "null";
		var v = m.rawData;
		return [for (i in 0...16) r(v[i])].join(",");
	}

	static function box(parent:flash.display.DisplayObjectContainer, x:Float = 0, y:Float = 0):Sprite {
		var s = new Sprite();
		s.graphics.beginFill(0x336699);
		s.graphics.drawRect(0, 0, 100, 50);
		s.graphics.endFill();
		s.x = x;
		s.y = y;
		parent.addChild(s);
		return s;
	}

	static function geom(label:String, s:DisplayObject) {
		var st = Lib.current.stage;
		var line = label + ": w=" + r(s.width) + " h=" + r(s.height) + " bounds(stage)=" + rect(s.getBounds(st)) + " bounds(self)=" + rect(s.getBounds(s)) + " rect(stage)=" + rect(s.getRect(st)) + " pixelBounds=" + rect(s.transform.pixelBounds);
		H.log(line);
		H.log("   l2g(0,0)=" + pt(s.localToGlobal(new Point(0, 0))) + " l2g(100,50)=" + pt(s.localToGlobal(new Point(100, 50))) + " g2l(300,200)=" + pt(s.globalToLocal(new Point(300, 200))) + " l3d(0,0,0)=" + pt(s.local3DToGlobal(new Vector3D(0, 0, 0))) + " l3d(100,50,0)=" + pt(s.local3DToGlobal(new Vector3D(100, 50, 0))) + " l3d(10,20,30)=" + pt(s.local3DToGlobal(new Vector3D(10, 20, 30))) + " g2l3d(300,200)=" + v3(s.globalToLocal3D(new Point(300, 200))));
	}

	static function hits(label:String, s:DisplayObject) {
		// a coarse lattice over the stage: which points hit the shape?
		var sb = new StringBuf();
		var n = 0;
		var y = 0;
		while (y < 560) {
			var x = 0;
			while (x < 960) {
				if (s.hitTestPoint(x, y, true)) {
					n++;
				}
				x += 8;
			}
			y += 8;
		}
		H.log("   hit lattice (8px) count=" + n + " at centre-ish: " + s.hitTestPoint(480, 280, true) + " bounds-centre: " + s.hitTestPoint(s.getBounds(Lib.current.stage).x + s.getBounds(Lib.current.stage).width / 2, s.getBounds(Lib.current.stage).y + s.getBounds(Lib.current.stage).height / 2, true));
	}

	static function main() {
		H.init("d17geom3d", 40000);
		var root = Lib.current;

		// 2D -> 3D conversion keeps what the 2D matrix had
		var a = box(root);
		a.x = 5;
		a.y = 6;
		a.scaleX = 2;
		a.scaleY = 3;
		a.rotation = 30;
		H.log("2D: x=" + r(a.x) + " y=" + r(a.y) + " sx=" + r(a.scaleX) + " sy=" + r(a.scaleY) + " rot=" + r(a.rotation) + " matrix=" + a.transform.matrix);
		a.z = 10;
		H.log("2D then z=10: x=" + r(a.x) + " y=" + r(a.y) + " z=" + r(a.z) + " sx=" + r(a.scaleX) + " sy=" + r(a.scaleY) + " sz=" + r(a.scaleZ) + " rotX=" + r(a.rotationX) + " rotY=" + r(a.rotationY) + " rotZ=" + r(a.rotationZ) + " matrix3D=" + m3(a.transform.matrix3D));
		var a2 = box(root);
		var skew = new Matrix(1, 0.5, 0.2, 1, 7, 8);
		a2.transform.matrix = skew;
		a2.z = 0;
		H.log("skewed 2D then z=0: sx=" + r(a2.scaleX) + " sy=" + r(a2.scaleY) + " rotZ=" + r(a2.rotationZ) + " matrix3D=" + m3(a2.transform.matrix3D));
		var a3 = box(root);
		a3.x = 7;
		a3.y = 8;
		a3.scaleX = 2;
		a3.rotationX = 45;
		a3.transform.matrix3D = null;
		H.log("3D (x=7 y=8 sx=2 rotX=45) then matrix3D=null: x=" + r(a3.x) + " y=" + r(a3.y) + " sx=" + r(a3.scaleX) + " rotX=" + r(a3.rotationX) + " matrix=" + a3.transform.matrix + " matrix3D=" + m3(a3.transform.matrix3D));
		for (o in [a, a2, a3])
			root.removeChild(o);

		// geometry of a 100x50 box at (200,100) in a few 3D states (default projection: centre (480,280))
		var st:Array<Array<Dynamic>> = [
			["plain 2D", function(s:Sprite) {}],
			["z=0 only", function(s:Sprite) s.z = 0],
			["z=200", function(s:Sprite) s.z = 200],
			["rotationY=45", function(s:Sprite) s.rotationY = 45],
			["rotationX=45", function(s:Sprite) s.rotationX = 45],
			["rotationZ=45", function(s:Sprite) s.rotationZ = 45],
			["rotationY=60 z=100", function(s:Sprite) {
				s.rotationY = 60;
				s.z = 100;
			}],
			["rotationX=30 rotationY=40", function(s:Sprite) {
				s.rotationX = 30;
				s.rotationY = 40;
			}],
			["rotationY=89", function(s:Sprite) s.rotationY = 89],
			["rotationY=90", function(s:Sprite) s.rotationY = 90],
			["scaleZ=3 z=50", function(s:Sprite) {
				s.scaleZ = 3;
				s.z = 50;
			}],
			["z=-1000 (behind the viewer)", function(s:Sprite) s.z = -1000],
			["z=-922.1 (at the viewer)", function(s:Sprite) s.z = -922.1],
		];
		for (e in st) {
			var s = box(root, 200, 100);
			var setup:Sprite->Void = e[1];
			setup(s);
			geom(e[0], s);
			hits(e[0], s);
			root.removeChild(s);
		}

		// a 3D child in a 2D container, a 2D child in a 3D container, nested 3D
		var c = new Sprite();
		root.addChild(c);
		var k = box(c, 200, 100);
		k.rotationY = 45;
		H.log("container with a rotationY=45 child:");
		H.log("   container bounds(stage)=" + rect(c.getBounds(root.stage)) + " w=" + r(c.width) + " h=" + r(c.height) + " child bounds(stage)=" + rect(k.getBounds(root.stage)));
		root.removeChild(c);
		var c2 = new Sprite();
		root.addChild(c2);
		c2.rotationY = 45;
		c2.x = 100;
		var k2 = box(c2, 100, 50);
		H.log("3D container (rotationY=45, x=100) with a 2D child at (100,50):");
		H.log("   container bounds(stage)=" + rect(c2.getBounds(root.stage)) + " child bounds(stage)=" + rect(k2.getBounds(root.stage)) + " child w=" + r(k2.width) + " child l2g(0,0)=" + pt(k2.localToGlobal(new Point(0, 0))) + " child.transform.concatenatedMatrix=" + k2.transform.concatenatedMatrix + " child.matrix3D=" + m3(k2.transform.matrix3D));
		var k3 = box(c2, 0, 0);
		k3.rotationX = 30;
		k3.z = 20;
		H.log("   3D child (rotationX=30 z=20) bounds(stage)=" + rect(k3.getBounds(root.stage)) + " container bounds(stage)=" + rect(c2.getBounds(root.stage)));
		H.log("   getRelativeMatrix3D(stage)=" + m3(k3.transform.getRelativeMatrix3D(root.stage)) + " getRelativeMatrix3D(container)=" + m3(k3.transform.getRelativeMatrix3D(c2)));
		root.removeChild(c2);

		// an explicit projection owner
		var o = new Sprite();
		root.addChild(o);
		var pp = new PerspectiveProjection();
		pp.projectionCenter = new Point(300, 100);
		pp.fieldOfView = 70;
		o.transform.perspectiveProjection = pp;
		var k4 = box(o, 200, 100);
		k4.rotationY = 45;
		k4.z = 100;
		H.log("owner (centre (300,100), fov 70) with a rotationY=45 z=100 child:");
		geom("   child", k4);
		root.removeChild(o);
		H.done();
	}
}
