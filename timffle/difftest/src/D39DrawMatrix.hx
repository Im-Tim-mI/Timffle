import flash.display.BitmapData;
import flash.display.Sprite;
import flash.geom.ColorTransform;
import flash.geom.Matrix;

class D39DrawMatrix {
	static function box(w:Float = 100, h:Float = 50):Sprite {
		var s = new Sprite();
		s.graphics.beginFill(0x336699);
		s.graphics.drawRect(0, 0, w, h);
		s.graphics.endFill();
		return s;
	}

	static function ext(label:String, bd:BitmapData) {
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
		H.log(label + ": (" + minX + "," + minY + ")-(" + (maxX + 1) + "," + (maxY + 1) + ") centre pixel " + StringTools.hex(bd.getPixel32(Std.int((minX + maxX) / 2), Std.int((minY + maxY) / 2)), 8));
	}

	static function main() {
		H.init("d39drawmatrix", 30000);
		var c3d = new Sprite();
		var k = box();
		k.x = 120;
		k.y = 80;
		k.rotationX = 50;
		k.z = 60;
		c3d.addChild(k);
		var c2d = new Sprite();
		var k2 = box();
		k2.x = 120;
		k2.y = 80;
		c2d.addChild(k2);
		var cases:Array<{n:String, m:Matrix, ct:ColorTransform}> = [
			{n: "identity", m: null, ct: null},
			{n: "translate(30,20)", m: new Matrix(1, 0, 0, 1, 30, 20), ct: null},
			{n: "scale 2", m: new Matrix(2, 0, 0, 2, 0, 0), ct: null},
			{n: "rotate 30deg", m: {var mm = new Matrix(); mm.rotate(Math.PI / 6); mm;}, ct: null},
			{n: "identity + colour transform (0.5 alpha)", m: null, ct: new ColorTransform(1, 1, 1, 0.5)},
			{n: "identity + colour transform (red)", m: null, ct: new ColorTransform(0, 0, 0, 1, 255, 0, 0, 0)},
		];
		for (cs in cases) {
			var bd = new BitmapData(400, 300, true, 0);
			bd.draw(c3d, cs.m, cs.ct);
			ext("3D child, " + cs.n, bd);
			var bd2 = new BitmapData(400, 300, true, 0);
			bd2.draw(c2d, cs.m, cs.ct);
			ext("2D child, " + cs.n, bd2);
		}
		// a 3D grandchild
		var outer = new Sprite();
		var inner = new Sprite();
		inner.x = 10;
		inner.y = 10;
		inner.addChild(k2);
		k2.rotationY = 40;
		k2.z = 30;
		outer.addChild(inner);
		var bd3 = new BitmapData(400, 300, true, 0);
		bd3.draw(outer, new Matrix(1, 0, 0, 1, 50, 50));
		ext("3D grandchild with translate(50,50)", bd3);
		var bd4 = new BitmapData(400, 300, true, 0);
		bd4.draw(outer);
		ext("3D grandchild identity", bd4);
		H.done();
	}
}
