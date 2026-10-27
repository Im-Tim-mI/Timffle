import flash.Lib;
import flash.display.DisplayObject;
import flash.display.Sprite;
import flash.geom.Point;
import flash.geom.Rectangle;

/** Once every 3D object has left (removed from the display list, moved to another container, or had its
 * matrix3D set to null), the 2D geometry of everything else must be exactly what it was before any 3D
 * existed: bounds, width/height, localToGlobal/globalToLocal, hitTestPoint, concatenatedMatrix, pixelBounds. */
class LeaveRestores2D {
	static var root:Sprite;
	static var stage:flash.display.Stage;
	static var a:Sprite;
	static var b:Sprite;
	static var items:Array<DisplayObject> = [];

	static function box(w:Float, h:Float, color:Int):Sprite {
		var s = new Sprite();
		s.graphics.beginFill(color);
		s.graphics.drawRect(0, 0, w, h);
		s.graphics.endFill();
		return s;
	}

	static function num(v:Float):String {
		return Std.string(Math.round(v * 100) / 100);
	}

	static function rect(r:Rectangle):String {
		return "(" + num(r.x) + "," + num(r.y) + "," + num(r.width) + "," + num(r.height) + ")";
	}

	static function pt(p:Point):String {
		return "(" + num(p.x) + "," + num(p.y) + ")";
	}

	static function snapshot():Array<String> {
		var lines = [];
		for (i in 0...items.length) {
			var d = items[i];
			var gb = d.getBounds(stage);
			lines.push("item" + i + " stage=" + rect(gb) + " parent=" + rect(d.getBounds(d.parent)) + " rect=" + rect(d.getRect(stage))
				+ " pixel=" + rect(d.transform.pixelBounds) + " size=" + num(d.width) + "x" + num(d.height)
				+ " l2g=" + pt(d.localToGlobal(new Point(3, 4))) + " g2l=" + pt(d.globalToLocal(new Point(123, 77)))
				+ " hit=" + d.hitTestPoint(gb.x + 1, gb.y + 1, true) + "/" + d.hitTestPoint(gb.x + gb.width / 2, gb.y + gb.height / 2, false)
				+ "/" + d.hitTestPoint(gb.x - 1, gb.y - 1, true)
				+ " concat=" + d.transform.concatenatedMatrix
				+ " mouse=" + num(d.mouseX) + "," + num(d.mouseY));
		}
		return lines;
	}

	static function print(label:String, lines:Array<String>) {
		Out.line("== " + label);
		for (l in lines) Out.line(l);
	}

	static function same(label:String, before:Array<String>, after:Array<String>) {
		var ok = before.length == after.length;
		for (i in 0...before.length) {
			if (ok && before[i] != after[i]) {
				ok = false;
				Out.line("first difference at " + i + ": " + after[i]);
			}
		}
		Out.line(label + ": " + ok);
	}

	static function main() {
		Out.start("display_object_3d_leave_restores_2d");
		root = Lib.current;
		stage = root.stage;

		a = new Sprite();
		a.x = 30;
		a.y = 20;
		a.scaleX = 1.5;
		root.addChild(a);
		b = new Sprite();
		b.x = 200;
		b.y = 150;
		b.rotation = 10;
		root.addChild(b);
		var inner = new Sprite();
		inner.x = 12;
		inner.y = 8;
		a.addChild(inner);
		var deep = box(50, 40, 0xFF0000);
		deep.x = 7;
		deep.y = 9;
		inner.addChild(deep);
		var a2 = box(30, 30, 0x00FF00);
		a2.x = 100;
		a2.y = 5;
		a.addChild(a2);
		var b1 = box(60, 20, 0x0000FF);
		b1.x = 10;
		b1.y = 10;
		b.addChild(b1);
		items = [a, inner, deep, a2, b, b1];

		var before = snapshot();
		print("before any 3d", before);

		// 1. A 3D object added under `inner`, then removed.
		var cube = box(40, 40, 0xFF00FF);
		cube.x = 60;
		cube.y = 30;
		cube.z = 300;
		inner.addChild(cube);
		print("with 3d child", snapshot());
		inner.removeChild(cube);
		same("same after removing the 3d child", before, snapshot());

		// 2. The same object moved to `b`, then taken back out.
		b.addChild(cube);
		var moved = snapshot();
		print("3d child moved to b", moved);
		b.removeChild(cube);
		same("same after moving it out again", before, snapshot());

		// 3. A 3D ancestor: `a` itself, then its matrix3D set to null (which also resets its matrix).
		a.z = 0;
		print("a z=0", snapshot());
		a.transform.matrix3D = null;
		a.x = 30;
		a.y = 20;
		a.scaleX = 1.5;
		same("same after a.matrix3D = null", before, snapshot());

		// 4. A 2D matrix assignment leaves 3D too.
		b1.rotationX = 30;
		print("b1 rotationX=30", snapshot());
		b1.transform.matrix = new flash.geom.Matrix(1, 0, 0, 1, 10, 10);
		same("same after b1.transform.matrix = 2d", before, snapshot());

		// 5. A 3D child that is still 3D when removed, then reattached as 2D elsewhere.
		cube.rotationY = 45;
		a2.addChild(cube);
		print("3d grandchild under a2", snapshot());
		a2.removeChild(cube);
		cube.transform.matrix3D = null;
		b.addChild(cube);
		print("former 3d child, now 2d, under b", snapshot());
		b.removeChild(cube);
		same("same after all 3d is gone", before, snapshot());

		// 6. New 2D content created after 3D has come and gone.
		var fresh = box(20, 20, 0x000000);
		fresh.x = 300;
		fresh.y = 200;
		root.addChild(fresh);
		Out.line("fresh stage=" + rect(fresh.getBounds(stage)) + " hit=" + fresh.hitTestPoint(305, 205, true)
			+ " l2g=" + pt(fresh.localToGlobal(new Point(1, 1))) + " concat=" + fresh.transform.concatenatedMatrix);
		Out.line("done");
		Out.finish();
	}
}
