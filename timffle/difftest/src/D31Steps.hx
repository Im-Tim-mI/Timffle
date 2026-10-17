import flash.geom.Matrix3D;
import flash.geom.Orientation3D;
import flash.geom.Vector3D;

/** More Matrix3D edge cases (interpolate percent, appendRotation axes, ...), each step in its own timer callback. */
class D31Steps {
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
		H.init("d31steps", 90000);
		var X = Vector3D.X_AXIS;
		var Y = Vector3D.Y_AXIS;
		var eps:Array<Float> = [1e-1, 1e-3, 1e-5, 1e-6, 1e-7, 1e-9, 1e-12];
		for (e in eps) {
			pa("d tiny " + e, tr, new Vector3D(10 + e, 20, 30), X, Y);
			pa("d tiny+bigy " + e, tr, new Vector3D(10 + e, 20 + 5, 30), X, Y);
		}
		for (e in eps) {
			pa("at tiny " + e, tr, new Vector3D(100, 50, 25), new Vector3D(e, 0, 0), Y);
			pa("up tiny " + e, tr, new Vector3D(100, 50, 25), X, new Vector3D(0, e, 0));
		}
		for (e in eps) {
			pa("at||up " + e, tr, new Vector3D(100, 50, 25), X, new Vector3D(1, e, 0));
		}
		for (e in eps) {
			pa("d||worldUp " + e, tr, new Vector3D(10 + e, 120, 30), X, Y);
			pa("d||-worldUp " + e, tr, new Vector3D(10 + e, -80, 30), X, Y);
		}
		pa("scale(0,1,1)", function() { var m = new Matrix3D(); m.appendScale(0, 1, 1); m.appendTranslation(10, 20, 30); return m; }, new Vector3D(100, 50, 25), X, Y);
		pa("scale(1,0,1)", function() { var m = new Matrix3D(); m.appendScale(1, 0, 1); m.appendTranslation(10, 20, 30); return m; }, new Vector3D(100, 50, 25), X, Y);
		pa("scale(1,1,0)", function() { var m = new Matrix3D(); m.appendScale(1, 1, 0); m.appendTranslation(10, 20, 30); return m; }, new Vector3D(100, 50, 25), X, Y);
		pa("scale(1e-10,1,1)", function() { var m = new Matrix3D(); m.appendScale(1e-10, 1, 1); m.appendTranslation(10, 20, 30); return m; }, new Vector3D(100, 50, 25), X, Y);
		pa("zero linear", function() return make([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 10, 20, 30, 1]), new Vector3D(100, 50, 25), X, Y);
		pa("c1==c0", function() return make([1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 10, 20, 30, 1]), new Vector3D(100, 50, 25), X, Y);
		pa("NaN pos", tr, new Vector3D(Math.NaN, 50, 25), X, Y);
		pa("NaN at", tr, new Vector3D(100, 50, 25), new Vector3D(Math.NaN, 0, 0), Y);
		pa("Infinity pos", tr, new Vector3D(Math.POSITIVE_INFINITY, 50, 25), X, Y);
		pa("huge pos 1e30", tr, new Vector3D(1e30, 5e29, 2e29), X, Y);
		pa("huge pos 1e20", tr, new Vector3D(1e20, 5e19, 2e19), X, Y);
		pa("tiny diff 1e-20 on huge position", function() { var m = new Matrix3D(); m.appendTranslation(1e20, 0, 0); return m; }, new Vector3D(1e20 + 1e6, 1e6, 0), X, Y);
		add("appendRotation zero axis pivot", function() {
			var m = new Matrix3D();
			m.appendRotation(30, new Vector3D(0, 0, 0), new Vector3D(10, 20, 30));
			return raw(m);
		});
		add("appendRotation tiny axis 1e-20", function() {
			var m = new Matrix3D();
			m.appendRotation(30, new Vector3D(1e-20, 0, 0));
			return raw(m);
		});
		add("appendRotation tiny axis 1e-30", function() {
			var m = new Matrix3D();
			m.appendRotation(30, new Vector3D(1e-30, 0, 0));
			return raw(m);
		});
		add("appendRotation NaN axis", function() {
			var m = new Matrix3D();
			m.appendRotation(30, new Vector3D(Math.NaN, 0, 0));
			return raw(m);
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
