import flash.Lib;
import flash.display.DisplayObject;
import flash.display.Sprite;
import flash.geom.Point;
import flash.geom.Rectangle;

/** Geometry of a projected (3D) child and of 2D objects around it: getBounds/getRect, width/height,
 * localToGlobal/globalToLocal, hitTestPoint and concatenatedMatrix, as the object, then its parent,
 * go 3D (z, rotationY) and back (matrix3D = null). A 2D child added under a 3D parent must follow the chain. */
class ProjectedBounds {
	static var root:Sprite;
	static var stage:flash.display.Stage;
	static var container:Sprite;
	static var child:Sprite;
	static var flat:Sprite;

	static function box(w:Float, h:Float, color:Int):Sprite {
		var s = new Sprite();
		s.graphics.beginFill(color);
		s.graphics.drawRect(0, 0, w, h);
		s.graphics.endFill();
		return s;
	}

	static function num(v:Float):String {
		// Keep the output stable across players: 2 decimals (twips are 1/20 px).
		return Std.string(Math.round(v * 100) / 100);
	}

	static function rect(r:Rectangle):String {
		return "(" + num(r.x) + "," + num(r.y) + "," + num(r.width) + "," + num(r.height) + ")";
	}

	static function pt(p:Point):String {
		return "(" + num(p.x) + "," + num(p.y) + ")";
	}

	static function report(label:String, extra:DisplayObject) {
		Out.line("== " + label);
		Out.line("child stage=" + rect(child.getBounds(stage)) + " container=" + rect(child.getBounds(container))
			+ " rect=" + rect(child.getRect(stage)) + " size=" + num(child.width) + "x" + num(child.height));
		Out.line("container stage=" + rect(container.getBounds(stage)) + " root=" + rect(container.getBounds(root))
			+ " size=" + num(container.width) + "x" + num(container.height));
		Out.line("flat stage=" + rect(flat.getBounds(stage)) + " container=" + rect(flat.getBounds(container)));
		if (extra != null) {
			Out.line("extra stage=" + rect(extra.getBounds(stage)) + " container=" + rect(extra.getBounds(container)));
		}
		Out.line("child l2g=" + pt(child.localToGlobal(new Point(0, 0))) + " " + pt(child.localToGlobal(new Point(100, 60)))
			+ " g2l=" + pt(child.globalToLocal(new Point(200, 150))) + " " + pt(child.globalToLocal(new Point(0, 0))));
		Out.line("flat l2g=" + pt(flat.localToGlobal(new Point(0, 0))) + " g2l=" + pt(flat.globalToLocal(new Point(200, 150))));
		var b = child.getBounds(stage);
		var cx = b.x + b.width / 2;
		var cy = b.y + b.height / 2;
		Out.line("child hit centre=" + child.hitTestPoint(cx, cy, false) + "/" + child.hitTestPoint(cx, cy, true)
			+ " corner2d=" + child.hitTestPoint(71 + 99, 51 + 59, false) + "/" + child.hitTestPoint(71 + 99, 51 + 59, true)
			+ " outside=" + child.hitTestPoint(390, 290, true));
		Out.line("flat hit=" + flat.hitTestPoint(201 + 10, 141 + 10, true) + "/" + flat.hitTestPoint(5, 5, true));
		Out.line("concat child=" + child.transform.concatenatedMatrix + " flat=" + flat.transform.concatenatedMatrix);
	}

	static function main() {
		Out.start("display_object_3d_projected_bounds");
		root = Lib.current;
		stage = root.stage;
		Out.line("stage " + stage.stageWidth + "x" + stage.stageHeight);

		container = new Sprite();
		container.x = 50;
		container.y = 40;
		root.addChild(container);
		child = box(100, 60, 0xFF0000);
		child.x = 21;
		child.y = 11;
		container.addChild(child);
		flat = box(40, 30, 0x0000FF);
		flat.x = 151;
		flat.y = 101;
		container.addChild(flat);

		report("2d", null);
		child.z = 200;
		report("child z=200", null);
		child.rotationY = 40;
		report("child z=200 rotationY=40", null);
		container.z = 100;
		report("container z=100", null);
		var late = box(40, 30, 0x00FF00);
		late.x = 251;
		late.y = 201;
		container.addChild(late);
		report("late 2d child under 3d parent", late);
		late.z = 0;
		report("late z=0", late);
		child.transform.matrix3D = null;
		child.x = 21;
		child.y = 11;
		report("child matrix3D=null", late);
		container.transform.matrix3D = null;
		container.x = 50;
		container.y = 40;
		report("container matrix3D=null", late);
		container.removeChild(late);
		report("late removed", null);
		Out.line("done");
		Out.finish();
	}
}
