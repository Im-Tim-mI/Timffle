import flash.display.BitmapData;
import flash.display.Sprite;
import flash.geom.Matrix;
import flash.geom.PerspectiveProjection;
import flash.geom.Point;

/**
 * BitmapData.draw of 3D content, self-checking: where the non-transparent pixels end up is compared with the
 * projection computed here (stage 400x300, default projection centred on the stage, fov 55), within 1.5 px (Flash
 * Player filters the picture of a 3D object, so its edges are soft). An object that is 3D itself is drawn flat,
 * at the origin, and the matrix argument is ignored; the projection it owns is used for its children.
 */
class D38DrawBitmap {
	static var STAGE_W = 400.0;
	static var STAGE_H = 300.0;

	static function box(w:Float = 100, h:Float = 50):Sprite {
		var s = new Sprite();
		s.graphics.beginFill(0x336699);
		s.graphics.drawRect(0, 0, w, h);
		s.graphics.endFill();
		return s;
	}

	/** Projects a point (x, y, z) in the space of the drawn object. */
	static function project(x:Float, y:Float, z:Float, fov:Float, cx:Float, cy:Float):Array<Float> {
		var f = (STAGE_W / 2) / Math.tan(fov * Math.PI / 360);
		var s = f / (f + z);
		return [cx + (x - cx) * s, cy + (y - cy) * s];
	}

	/** The extents of the projection of a w x h box at (px, py, pz) turned by rotationX/rotationY (degrees). */
	static function quad(w:Float, h:Float, px:Float, py:Float, pz:Float, rx:Float, ry:Float, fov:Float, cx:Float, cy:Float):Array<Float> {
		var minX = 1e9;
		var minY = 1e9;
		var maxX = -1e9;
		var maxY = -1e9;
		var cosX = Math.cos(rx * Math.PI / 180);
		var sinX = Math.sin(rx * Math.PI / 180);
		var cosY = Math.cos(ry * Math.PI / 180);
		var sinY = Math.sin(ry * Math.PI / 180);
		var corners:Array<Array<Float>> = [[0.0, 0.0], [w, 0.0], [w, h], [0.0, h]];
		for (c in corners) {
			// R = Ry * Rx (rotationZ is 0)
			var x = c[0];
			var y = c[1] * cosX;
			var z = c[1] * sinX;
			var x2 = x * cosY + z * sinY;
			var z2 = -x * sinY + z * cosY;
			var p = project(px + x2, py + y, pz + z2, fov, cx, cy);
			minX = Math.min(minX, p[0]);
			maxX = Math.max(maxX, p[0]);
			minY = Math.min(minY, p[1]);
			maxY = Math.max(maxY, p[1]);
		}
		return [minX, minY, maxX, maxY];
	}

	static function check(label:String, bd:BitmapData, e:Array<Float>) {
		var minX = 1000000;
		var minY = 1000000;
		var maxX = -1;
		var maxY = -1;
		for (y in 0...bd.height)
			for (x in 0...bd.width)
				if ((bd.getPixel32(x, y) >>> 24) != 0) {
					if (x < minX)
						minX = x;
					if (x > maxX)
						maxX = x;
					if (y < minY)
						minY = y;
					if (y > maxY)
						maxY = y;
				}
		// Flash Player's soft edges add up to a pixel on every side.
		var ok = maxX >= 0 && minX - e[0] >= -2.5 && minX - e[0] <= 1.5 && minY - e[1] >= -2.5 && minY - e[1] <= 1.5 && maxX + 1 - e[2] >= -1.5 && maxX + 1 - e[2] <= 2.5
			&& maxY + 1 - e[3] >= -1.5 && maxY + 1 - e[3] <= 2.5;
		H.log(label + ": " + (ok ? "ok" : "WRONG"));
		H.log("~   expected (" + Math.round(e[0] * 10) / 10 + "," + Math.round(e[1] * 10) / 10 + ")-(" + Math.round(e[2] * 10) / 10 + "," + Math.round(e[3] * 10) / 10 + ") drawn (" + minX + "," + minY + ")-(" + (maxX + 1) + "," + (maxY + 1) + ")");
	}

	static function main() {
		H.init("d38drawbitmap", 30000);
		var root = flash.Lib.current;
		var cxs = STAGE_W / 2;
		var cys = STAGE_H / 2;

		var bd = new BitmapData(400, 300, true, 0);
		var s1 = box();
		s1.x = 150;
		s1.y = 100;
		s1.rotationY = 45;
		bd.draw(s1);
		check("3D source (rotationY=45) is drawn flat at the origin", bd, [0, 0, 100, 50]);

		bd = new BitmapData(400, 300, true, 0);
		bd.draw(s1, new Matrix(1, 0, 0, 1, 20, 10));
		check("the matrix is ignored for a 3D source", bd, [0, 0, 100, 50]);

		bd = new BitmapData(400, 300, true, 0);
		var s5 = box(200, 100);
		s5.rotationY = 80;
		bd.draw(s5, new Matrix(2, 0, 0, 2, 0, 0));
		check("3D source drawn with a scale 2 matrix", bd, [0, 0, 200, 100]);

		bd = new BitmapData(400, 300, true, 0);
		var s4 = box();
		s4.z = 200;
		s4.x = 100;
		bd.draw(s4);
		check("z=200 source is drawn flat", bd, [0, 0, 100, 50]);

		bd = new BitmapData(400, 300, true, 0);
		var c2 = new Sprite();
		c2.z = 40;
		c2.rotationZ = 20;
		var k2 = box();
		k2.x = 100;
		k2.y = 100;
		c2.addChild(k2);
		bd.draw(c2);
		check("3D container, 2D child: the container's transform is ignored", bd, [100, 100, 200, 150]);

		bd = new BitmapData(400, 300, true, 0);
		var c = new Sprite();
		var k = box();
		k.x = 120;
		k.y = 80;
		k.rotationX = 50;
		k.z = 60;
		c.addChild(k);
		bd.draw(c);
		check("2D container with a rotationX=50 z=60 child", bd, quad(100, 50, 120, 80, 60, 50, 0, 55, cxs, cys));

		bd = new BitmapData(400, 300, true, 0);
		bd.draw(c, new Matrix(1, 0, 0, 1, 30, 20));
		var e = quad(100, 50, 120, 80, 60, 50, 0, 55, cxs, cys);
		// the matrix is ignored when the content is 3D
		check("same drawn with translate(30,20): the matrix is ignored", bd, e);

		bd = new BitmapData(400, 300, true, 0);
		bd.draw(c, new Matrix(2, 0, 0, 2, 0, 0));
		check("same drawn with a scale 2 matrix: ignored too", bd, e);

		function variant(label:String, fov:Float, cx:Float, cy:Float, usePP:Bool, onStage:Bool, rotY:Float, z:Float) {
			var bdv = new BitmapData(400, 300, true, 0);
			var cv = new Sprite();
			if (onStage) {
				root.addChild(cv);
				cv.x = 50;
				cv.y = 50;
			}
			if (usePP) {
				var ppv = new PerspectiveProjection();
				ppv.fieldOfView = fov;
				ppv.projectionCenter = new Point(cx, cy);
				cv.transform.perspectiveProjection = ppv;
			}
			var kv = box();
			kv.x = 80;
			kv.y = 60;
			kv.rotationY = rotY;
			kv.z = z;
			cv.addChild(kv);
			bdv.draw(cv);
			var ef = usePP ? fov : 55;
			var ecx = usePP ? cx : cxs;
			var ecy = usePP ? cy : cys;
			check(label, bdv, quad(100, 50, 80, 60, z, 0, rotY, ef, ecx, ecy));
			if (onStage)
				root.removeChild(cv);
		}
		variant("no projection, child rotationY=50 z=100", 55, 0, 0, false, false, 50, 100);
		variant("no projection, container on the stage", 55, 0, 0, false, true, 50, 100);
		variant("projection fov 55 centre (200,100)", 55, 200, 100, true, false, 50, 100);
		variant("projection fov 70 centre (200,100), child flat at z=100", 70, 200, 100, true, false, 0, 100);
		variant("projection fov 70 centre (200,100), child rotationY=50 z=100", 70, 200, 100, true, false, 50, 100);
		variant("same, container on the stage at (50,50)", 70, 200, 100, true, true, 50, 100);
		variant("projection fov 90 centre (100,200), child rotationY=-30 z=-50", 90, 100, 200, true, false, -30, -50);
		H.done();
	}
}
