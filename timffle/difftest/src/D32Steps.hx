import flash.geom.Matrix3D;
import flash.geom.Orientation3D;
import flash.geom.Vector3D;

/** More Matrix3D edge cases (interpolate percent, appendRotation axes, ...), each step in its own timer callback. */
class D32Steps {
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

	static function tr():Matrix3D {
		var m = new Matrix3D();
		m.appendTranslation(10, 20, 30);
		return m;
	}

	static function pa(label:String, m:Void->Matrix3D, pos:Vector3D, at:Vector3D = null, up:Vector3D = null) {
		add("pointAt " + label, function() {
			var mm = m();
			mm.pointAt(pos, at, up);
			return raw(mm);
		});
	}

	static function main() {
		H.init("d32steps", 90000);
		var X = Vector3D.X_AXIS;
		var Y = Vector3D.Y_AXIS;
		var cases:Array<Array<Float>> = [
			[0, 0, 0, 0, 1, 0, 0, 0, 1],
			[1, 0, 0, 1, 0, 0, 0, 0, 1],
			[1, 0, 0, 2, 0, 0, 0, 0, 1],
			[1, 0, 0, 0, 1, 0, 1, 0, 0],
			[1, 0, 0, 0, 1, 0, 1, 1, 0],
			[1, 0, 0, 0, 1, 0, 0, 0, 0],
			[1, 1, 0, 1, 1, 0, 0, 0, 1],
			[0, 0, 0, 0, 0, 0, 0, 0, 0],
			[1, 0, 0, 1, 0, 0, 1, 0, 0],
			[0, 1, 0, 0, 1, 0, 0, 0, 1],
			[0, 0, 0, 0, 0, 0, 0, 0, 1],
			[1e-20, 0, 0, 0, 1, 0, 0, 0, 1],
			[1e-30, 0, 0, 0, 1, 0, 0, 0, 1],
			[1, 0, 0, 0, 1e-30, 0, 0, 0, 1],
		];
		for (c in cases) {
			var lab = c.join(",");
			add("pointAt X,Y cols " + lab, function() {
				var m = make([c[0], c[1], c[2], 0, c[3], c[4], c[5], 0, c[6], c[7], c[8], 0, 10, 20, 30, 1]);
				m.pointAt(new Vector3D(100, 50, 25), X, Y);
				return raw(m);
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
