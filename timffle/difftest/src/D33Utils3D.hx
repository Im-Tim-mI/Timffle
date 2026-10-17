import flash.geom.Matrix3D;
import flash.geom.Orientation3D;
import flash.geom.Vector3D;

/** More Matrix3D edge cases (interpolate percent, appendRotation axes, ...), each step in its own timer callback. */
class D33Utils3D {
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
		H.init("d33utils3d", 90000);
		add("projectVector identity", function() return v3(flash.geom.Utils3D.projectVector(new Matrix3D(), new Vector3D(1, 2, 3, 1))));
		add("projectVector persp", function() return v3(flash.geom.Utils3D.projectVector(persp(), new Vector3D(100, 50, 250, 1))));
		add("projectVector persp w=2 in", function() return v3(flash.geom.Utils3D.projectVector(persp(), new Vector3D(100, 50, 250, 2))));
		add("projectVector sample", function() return v3(flash.geom.Utils3D.projectVector(sample(), new Vector3D(1, 2, 3))));
		add("projectVector w becomes 0", function() return v3(flash.geom.Utils3D.projectVector(persp(), new Vector3D(100, 50, -500, 1))));
		add("projectVector null matrix", function() return v3(flash.geom.Utils3D.projectVector(null, new Vector3D(1, 2, 3))));
		add("projectVector null vector", function() return v3(flash.geom.Utils3D.projectVector(new Matrix3D(), null)));
		function pv(label:String, m:Matrix3D, verts:Array<Float>, proj:Array<Float>, uvt:Array<Float>) {
			add("projectVectors " + label, function() {
				var p = fv(proj);
				var u = fv(uvt);
				flash.geom.Utils3D.projectVectors(m, fv(verts), p, u);
				return "proj=" + [for (x in p) r(x)].join(",") + " uvt=" + [for (x in u) r(x)].join(",");
			});
		}
		pv("persp 2 verts", persp(), [100, 50, 250, 20, 10, 0], [], []);
		pv("persp 2 verts, prefilled", persp(), [100, 50, 250, 20, 10, 0], [9, 9, 9, 9, 9, 9, 9], [7, 7, 7, 7, 7, 7, 7]);
		pv("sample 1 vert", sample(), [1, 2, 3], [], []);
		pv("5 numbers", persp(), [100, 50, 250, 20, 10], [], []);
		pv("uvt with data", persp(), [100, 50, 250, 20, 10, 0], [], [0.1, 0.2, 0.3, 0.4, 0.5, 0.6]);
		pv("short uvt", persp(), [100, 50, 250, 20, 10, 0], [], [0.1]);
		pv("w zero", persp(), [100, 50, -500], [], []);
		add("projectVectors sets uvt.z from 1/w", function() {
			var u = fv([0.1, 0.2, 0.3]);
			var p = fv([]);
			flash.geom.Utils3D.projectVectors(persp(), fv([100, 50, 250]), p, u);
			return [for (x in u) r(x)].join(",");
		});
		function pt(label:String, pct:Float, m:Matrix3D, pos:Vector3D, at:Vector3D = null, up:Vector3D = null) {
			add("pointTowards " + label, function() return raw(flash.geom.Utils3D.pointTowards(pct, m, pos, at, up)));
		}
		var X = Vector3D.X_AXIS;
		var Y = Vector3D.Y_AXIS;
		for (p in [0.0, 0.25, 0.5, 1.0, 1.5, -0.5]) {
			pt("identity+t " + p, p, make([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 10, 20, 30, 1]), new Vector3D(100, 50, 25), X, Y);
			pt("sample " + p, p, sample(), new Vector3D(100, 50, 25), X, Y);
			pt("sample defaults " + p, p, sample(), new Vector3D(100, 50, 25));
		}
		pt("null at/up defaults 0.5 identity", 0.5, new Matrix3D(), new Vector3D(0, 0, -100));
		add("pointTowards doesn't modify input", function() {
			var m = sample();
			flash.geom.Utils3D.pointTowards(0.5, m, new Vector3D(100, 50, 25), X, Y);
			return raw(m);
		});
		add("pointTowards null mat", function() return raw(flash.geom.Utils3D.pointTowards(0.5, null, new Vector3D(1, 2, 3))));
		add("pointTowards null pos", function() return raw(flash.geom.Utils3D.pointTowards(0.5, new Matrix3D(), null)));
		add("pointTowards degenerate", function() return raw(flash.geom.Utils3D.pointTowards(0.5, make([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 10, 20, 30, 1]), new Vector3D(10, 20, 30), X, Y)));
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
