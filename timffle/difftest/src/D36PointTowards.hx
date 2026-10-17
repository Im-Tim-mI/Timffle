import flash.geom.Matrix3D;
import flash.geom.Orientation3D;
import flash.geom.Vector3D;

/** More Matrix3D edge cases (interpolate percent, appendRotation axes, ...), each step in its own timer callback. */
class D36PointTowards {
	static function r(x:Float):String {
		if (x != x)
			return "NaN";
		if (x == Math.POSITIVE_INFINITY)
			return "Inf";
		if (x == Math.NEGATIVE_INFINITY)
			return "-Inf";
		if (x > 100000 || x < -100000)
			return Std.string(x);
		var v = Math.round(x * 10000) / 10000;
		if (v == 0)
			v = 0;
		return Std.string(v);
	}

	static function raw(m:Matrix3D):String
		return [for (i in 0...16) r(m.rawData[i])].join(",");

	static function v3(v:Vector3D):String
		return v == null ? "null" : "(" + r(v.x) + "," + r(v.y) + "," + r(v.z) + "," + r(v.w) + ")";

	static function errs(e:Dynamic):String {
		var id:Dynamic = untyped e.errorID;
		var name:Dynamic = untyped e.name;
		return "Error#" + id + " " + name;
	}

	static var steps:Array<{label:String, fn:Void->String}> = [];

	static function add(label:String, fn:Void->String)
		steps.push({label: label, fn: fn});

	static function make(a:Array<Float>):Matrix3D {
		var v = new flash.Vector<Float>();
		for (x in a)
			v.push(x);
		return new Matrix3D(v);
	}

	static function sample():Matrix3D {
		var m = new Matrix3D();
		m.appendRotation(20, Vector3D.X_AXIS);
		m.appendRotation(35, Vector3D.Y_AXIS);
		m.appendScale(1.5, 0.75, 2);
		m.appendTranslation(10, -20, 30);
		return m;
	}

	static function persp():Matrix3D {
		// a perspective-like matrix: w = 1 + z / 500
		return make([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0.002, 0, 0, 0, 1]);
	}

	static function fv(a:Array<Float>):flash.Vector<Float> {
		var v = new flash.Vector<Float>();
		for (x in a)
			v.push(x);
		return v;
	}

	static function main() {
		H.init("d36pointtowards", 90000);
		var X = Vector3D.X_AXIS;
		var Y = Vector3D.Y_AXIS;
		function pt(label:String, pct:Float, m:Matrix3D, pos:Vector3D, at:Vector3D = null, up:Vector3D = null) {
			add("pointTowards " + label, function() return raw(flash.geom.Utils3D.pointTowards(pct, m, pos, at, up)));
		}
		for (p in [0.0, 0.5, 1.0]) {
			pt("degenerate sample " + p, p, sample(), new Vector3D(10, -20, 30), X, Y);
			pt("degenerate at zero " + p, p, sample(), new Vector3D(100, 50, 25), new Vector3D(0, 0, 0), Y);
			pt("degenerate at||up " + p, p, sample(), new Vector3D(100, 50, 25), Y, Y);
			pt("zero linear " + p, p, make([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 10, 20, 30, 1]), new Vector3D(100, 50, 25), X, Y);
			pt("scale only " + p, p, make([2, 0, 0, 0, 0, 3, 0, 0, 0, 0, 4, 0, 10, 20, 30, 1]), new Vector3D(100, 50, 25), X, Y);
			pt("NaN pos " + p, p, sample(), new Vector3D(Math.NaN, 50, 25), X, Y);
			pt("projective mat " + p, p, make([1, 0, 0, 0.001, 0, 1, 0, 0, 0, 0, 1, 0, 10, 20, 30, 1]), new Vector3D(100, 50, 25), X, Y);
			pt("mirror " + p, p, make([-1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 10, 20, 30, 1]), new Vector3D(100, 50, 25), X, Y);
		}
		add("pointTowards NaN percent", function() return raw(flash.geom.Utils3D.pointTowards(Math.NaN, sample(), new Vector3D(100, 50, 25), X, Y)));
		var i = 0;
		function run() {
			if (i >= steps.length) {
				H.log("end");
				H.done();
				return;
			}
			var s = steps[i++];
			H.log("start " + s.label);
			haxe.Timer.delay(run, 60);
			try {
				H.log("  " + s.label + ": " + s.fn());
			} catch (e:flash.errors.Error) {
				H.log("  " + s.label + " THREW Error#" + e.errorID + " " + e.name);
			}
		}
		run();
	}
}
