import flash.Lib;
import flash.display.Sprite;
import flash.geom.PerspectiveProjection;
import flash.geom.Point;

/** What a PerspectiveProjection reports before and after it is given to a display object, for the orders of setting
 *  its properties. Exploration. */
class D20PPSemantics {
	static function r(x:Float):String
		return Std.string(Math.round(x * 100) / 100);

	static function show(label:String, pp:PerspectiveProjection)
		H.log(label + ": " + (pp == null ? "null" : "fov=" + r(pp.fieldOfView) + " focalLength=" + r(pp.focalLength) + " centre=(" + r(pp.projectionCenter.x) + "," + r(pp.projectionCenter.y) + ")"));

	static function main() {
		H.init("d20ppsemantics", 20000);
		var pp = new PerspectiveProjection();
		show("new", pp);
		pp.projectionCenter = new Point(300, 100);
		show("new, centre (300,100)", pp);
		pp.fieldOfView = 70;
		show("then fov 70", pp);
		var o = new Sprite();
		Lib.current.addChild(o);
		o.transform.perspectiveProjection = pp;
		show("after assigning to a sprite (the sprite's)", o.transform.perspectiveProjection);
		show("the detached object after assigning", pp);
		var pq = new PerspectiveProjection();
		pq.fieldOfView = 70;
		pq.projectionCenter = new Point(300, 100);
		show("new: fov 70, then centre (300,100)", pq);
		var o2 = new Sprite();
		Lib.current.addChild(o2);
		o2.transform.perspectiveProjection = pq;
		show("after assigning (fov first, then centre)", o2.transform.perspectiveProjection);
		var pr = new PerspectiveProjection();
		pr.focalLength = 500;
		show("new: focalLength 500", pr);
		pr.projectionCenter = new Point(100, 200);
		var o3 = new Sprite();
		Lib.current.addChild(o3);
		o3.transform.perspectiveProjection = pr;
		show("after assigning (focalLength 500, centre (100,200))", o3.transform.perspectiveProjection);
		var live = new Sprite();
		Lib.current.addChild(live);
		live.transform.perspectiveProjection = new PerspectiveProjection();
		live.transform.perspectiveProjection.projectionCenter = new Point(300, 100);
		live.transform.perspectiveProjection.fieldOfView = 70;
		show("live: assigned, then centre (300,100), then fov 70", live.transform.perspectiveProjection);
		H.done();
	}
}
