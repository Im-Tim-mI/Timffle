import flash.geom.Matrix3D;
import flash.geom.Orientation3D;
import flash.geom.Vector3D;

/** More Matrix3D edge cases (interpolate percent, appendRotation axes, ...), each step in its own timer callback. */
class D34Utils3DW {
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
		H.init("d34utils3dw", 90000);
		var ws:Array<Float> = [1, 0.5, 0.1, 0.01, 0.006, 0.0059375, 0.005, 0.001, 1e-4, 1e-6, 1e-9, 0, -1e-9, -1e-6, -1e-3, -0.5, -1, -100];
		for (w in ws) {
			add("projectVector w=" + w, function() {
				var m = make([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, w]);
				return v3(flash.geom.Utils3D.projectVector(m, new Vector3D(100, 50, 250, 1)));
			});
			add("projectVectors w=" + w, function() {
				var m = make([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, w]);
				var p = new flash.Vector<Float>();
				var u = new flash.Vector<Float>();
				var v = new flash.Vector<Float>();
				for (x in [100.0, 50, 250])
					v.push(x);
				flash.geom.Utils3D.projectVectors(m, v, p, u);
				return "proj=" + [for (x in p) r(x)].join(",") + " uvt=" + [for (x in u) r(x)].join(",");
			});
		}
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
