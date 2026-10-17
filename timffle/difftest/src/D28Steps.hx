import flash.geom.Matrix3D;
import flash.geom.Orientation3D;
import flash.geom.Vector3D;

/** Each step runs in its own timer callback so that a silent script abort in one step does not hide the others. */
class D28Steps {
	static function r(x:Float):String {
		var v = Math.round(x * 10000) / 10000;
		if (v == 0)
			v = 0;
		return Std.string(v);
	}

	static function raw(m:Matrix3D):String
		return [for (i in 0...16) r(m.rawData[i])].join(",");

	static function v3(v:Vector3D):String
		return v == null ? "null" : "(" + r(v.x) + "," + r(v.y) + "," + r(v.z) + "," + r(v.w) + ")";

	static function vecs(a:Array<Vector3D>):flash.Vector<Vector3D> {
		var d = new flash.Vector<Vector3D>();
		for (x in a)
			d.push(x);
		return d;
	}

	static function errs(e:Dynamic):String {
		var id:Dynamic = untyped e.errorID;
		var name:Dynamic = untyped e.name;
		return "Error#" + id + " " + name;
	}

	static var steps:Array<{label:String, fn:Void->String}> = [];

	static function add(label:String, fn:Void->String)
		steps.push({label: label, fn: fn});

	static function rc(label:String, a:Array<Vector3D>, style:Null<Orientation3D> = null)
		add("recompose " + label, function() {
			var m = new Matrix3D();
			var ok = style == null ? m.recompose(vecs(a)) : m.recompose(vecs(a), style);
			return ok + " " + raw(m);
		});

	static function make(a:Array<Float>):Matrix3D {
		var v = new flash.Vector<Float>();
		for (x in a)
			v.push(x);
		return new Matrix3D(v);
	}

	static function ro(deg:Float, axis:Vector3D, tx:Float = 0, ty:Float = 0, tz:Float = 0):Matrix3D {
		var m = new Matrix3D();
		m.appendRotation(deg, axis);
		m.appendTranslation(tx, ty, tz);
		return m;
	}

	static function sample():Matrix3D {
		var m = new Matrix3D();
		m.appendRotation(20, Vector3D.X_AXIS);
		m.appendRotation(35, Vector3D.Y_AXIS);
		m.appendScale(1.5, 0.75, 2);
		m.appendTranslation(10, -20, 30);
		return m;
	}

	static function dc(label:String, m:Matrix3D) {
		for (style in [Orientation3D.EULER_ANGLES, Orientation3D.AXIS_ANGLE, Orientation3D.QUATERNION]) {
			add("decompose " + label + " [" + Std.string(style) + "]", function() {
				var d = m.decompose(style);
				return d == null ? "null" : [for (v in d) v3(v)].join(" ");
			});
		}
	}

	static function main() {
		H.init("d28steps", 90000);
		var tt = new Vector3D(10, 20, 30);
		var ss = new Vector3D(1.5, 2, 0.5);
		var qs = Math.sin(Math.PI / 8);
		var qc = Math.cos(Math.PI / 8);
		for (eps in [5.5e-6, 6e-6, 7e-6, 8e-6, 9e-6, 9.9e-6, 1.0e-5, 1.1e-5, 1.5e-5]) {
			for (sign in [1, -1]) {
				var k = 1 + sign * eps;
				rc("quat norm " + (sign > 0 ? "+" : "-") + eps, [tt, new Vector3D(0, qs * k, 0, qc * k), ss], Orientation3D.QUATERNION);
			}
		}
		// axis-angle with non-unit axes: fit the formula
		var aaSpecs:Array<Array<Float>> = [[0, 2, 0, 0.8], [0, 3, 0, 0.9], [0, 0.5, 0, 0.8], [1, 1, 0, 0.6], [2, 0, 0, 0.8], [1, 2, 3, 0.7], [0, 1, 0, 0.8], [0, 1, 0, -0.8], [0, 1, 0, 7.0], [0, 0, 0, 0.5], [0, 0, 0, 0], [0, 1, 0, 0], [1e-9, 0, 0, 0.8]];
		for (spec in aaSpecs) {
			rc("axisAngle (" + spec.join(",") + ")", [tt, new Vector3D(spec[0], spec[1], spec[2], spec[3]), new Vector3D(1, 1, 1)], Orientation3D.AXIS_ANGLE);
		}
		// euler: angles beyond pi, negative
		var euSpecs:Array<Array<Float>> = [[1, 2, 3], [-1, -2, -3], [4, 5, 6], [0, 1.5707963, 0], [0, -1.5707963, 0], [3.2, 0, 0]];
		for (spec in euSpecs) {
			rc("euler (" + spec.join(",") + ")", [tt, new Vector3D(spec[0], spec[1], spec[2]), new Vector3D(1, 1, 1)]);
		}
		dc("reflection x", make([-1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 5, 6, 7, 1]));
		dc("reflection xy+rot", make([-0.7071, -0.7071, 0, 0, 0.7071, -0.7071, 0, 0, 0, 0, 1, 0, 5, 6, 7, 1]));
		dc("reflection z", make([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, -1, 0, 5, 6, 7, 1]));
		dc("scale only (2,3,4)", make([2, 0, 0, 0, 0, 3, 0, 0, 0, 0, 4, 0, 5, 6, 7, 1]));
		dc("rotX 90", ro(90, Vector3D.X_AXIS));
		dc("rotY 90 gimbal", ro(90, Vector3D.Y_AXIS));
		dc("rotY -90 gimbal", ro(-90, Vector3D.Y_AXIS));
		dc("rotY 89.9", ro(89.9, Vector3D.Y_AXIS));
		dc("rotZ 180", ro(180, Vector3D.Z_AXIS));
		dc("rotX 180", ro(180, Vector3D.X_AXIS));
		dc("rotY 180", ro(180, Vector3D.Y_AXIS));
		dc("rot 120 about (1,1,1)", ro(120, new Vector3D(1, 1, 1)));
		dc("sample", sample());
		dc("projective", make([1, 0, 0, 0.01, 0, 1, 0, 0, 0, 0, 1, 0, 5, 6, 7, 1]));
		dc("w=2", make([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 5, 6, 7, 2]));
		dc("bottom row nonzero", make([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 5, 6, 7, 1]));
		var i = 0;
		function run() {
			if (i >= steps.length) {
				H.log("end");
				H.done();
				return;
			}
			var s = steps[i++];
			H.log("start " + s.label);
			haxe.Timer.delay(run, 100);
			try {
				H.log("  " + s.label + ": " + s.fn());
			} catch (e:flash.errors.Error) {
				H.log("  " + s.label + " THREW Error#" + e.errorID + " " + e.name);
			}
		}
		run();
	}
}
