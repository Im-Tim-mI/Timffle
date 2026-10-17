import flash.geom.Matrix3D;
import flash.geom.Orientation3D;
import flash.geom.Vector3D;

/** Each step runs in its own timer callback so that a silent script abort in one step does not hide the others. */
class D26Steps {
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

	static function main() {
		H.init("d26steps", 60000);
		var tt = new Vector3D(10, 20, 30);
		var ss = new Vector3D(1.5, 2, 0.5);
		var qs = Math.sin(Math.PI / 8);
		var qc = Math.cos(Math.PI / 8);
		add("throw ArgumentError", function() {
			throw new flash.errors.ArgumentError("x");
			return "";
		});
		add("try/catch ArgumentError", function() {
			try {
				throw new flash.errors.ArgumentError("x");
			} catch (e:Dynamic) {
				return "caught " + errs(e);
			}
			return "";
		});
		// quaternion normalisation threshold (norm = 1 +- eps), y-axis rotation of 45 degrees
		for (eps in [1e-7, 4e-7, 1e-6, 2e-6, 5e-6, 1e-5, 2e-5, 5e-5, 1e-4, 1e-3, 1e-2]) {
			for (sign in [1, -1]) {
				var k = 1 + sign * eps;
				var lab = "quat norm " + (sign > 0 ? "+" : "-") + eps;
				rc(lab, [tt, new Vector3D(0, qs * k, 0, qc * k), ss], Orientation3D.QUATERNION);
			}
		}
		rc("quat unnormalised (0,1,0,1)", [tt, new Vector3D(0, 1, 0, 1), ss], Orientation3D.QUATERNION);
		rc("quat zero", [tt, new Vector3D(0, 0, 0, 0), ss], Orientation3D.QUATERNION);
		rc("quat rounded y45", [tt, new Vector3D(0, 0.3827, 0, 0.9239), ss], Orientation3D.QUATERNION);
		rc("euler bad style", [tt, new Vector3D(0.3, 0.5, 0.7), ss], cast "bogus");
		rc("euler style null explicit", [tt, new Vector3D(0.3, 0.5, 0.7), ss], null);
		rc("axisAngle zero axis", [tt, new Vector3D(0, 0, 0, 0.8), ss], Orientation3D.AXIS_ANGLE);
		rc("axisAngle unnormalised axis", [tt, new Vector3D(0, 2, 0, 0.8), ss], Orientation3D.AXIS_ANGLE);
		rc("axisAngle 3 args", [tt, new Vector3D(0, 1, 0), ss], Orientation3D.AXIS_ANGLE);
		rc("scale zero x", [tt, new Vector3D(0.3, 0.5, 0.7), new Vector3D(0, 2, 0.5)]);
		rc("scale zero y", [tt, new Vector3D(0.3, 0.5, 0.7), new Vector3D(1, 0, 0.5)]);
		rc("scale zero z", [tt, new Vector3D(0.3, 0.5, 0.7), new Vector3D(1, 2, 0)]);
		rc("scale negative x", [tt, new Vector3D(0.3, 0.5, 0.7), new Vector3D(-1, 2, 0.5)]);
		rc("scale tiny 1e-10", [tt, new Vector3D(0.3, 0.5, 0.7), new Vector3D(1e-10, 2, 0.5)]);
		rc("two components", [tt, new Vector3D(0.3, 0.5, 0.7)]);
		rc("four components", [tt, new Vector3D(0.3, 0.5, 0.7), ss, ss]);
		rc("zero components", []);
		rc("one component", [tt]);
		add("recompose null", function() {
			var m = new Matrix3D();
			return Std.string(m.recompose(null));
		});
		rc("w ignored?", [new Vector3D(10, 20, 30, 5), new Vector3D(0.3, 0.5, 0.7, 6), new Vector3D(1.5, 2, 0.5, 7)]);
		rc("null element", [tt, null, ss]);
		add("pointAt null", function() {
			var m = new Matrix3D();
			m.pointAt(null);
			return raw(m);
		});
		add("transformVector null", function() {
			return v3(new Matrix3D().transformVector(null));
		});
		add("interpolate t=2", function() {
			var a = new Matrix3D();
			var b = new Matrix3D();
			b.appendTranslation(10, 0, 0);
			return raw(Matrix3D.interpolate(a, b, 2));
		});
		var i = 0;
		function run() {
			if (i >= steps.length) {
				H.log("end");
				H.done();
				return;
			}
			var s = steps[i++];
			H.log("start " + s.label);
			haxe.Timer.delay(run, 150);
			try {
				H.log("  " + s.label + ": " + s.fn());
			} catch (e:flash.errors.Error) {
				H.log("  " + s.label + " THREW Error#" + e.errorID + " " + e.name);
			}
		}
		run();
	}
}
