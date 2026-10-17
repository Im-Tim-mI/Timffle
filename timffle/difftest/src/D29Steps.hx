import flash.geom.Matrix3D;
import flash.geom.Orientation3D;
import flash.geom.Vector3D;

/** More Matrix3D edge cases (interpolate percent, appendRotation axes, ...), each step in its own timer callback. */
class D29Steps {
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

	static function main() {
		H.init("d29steps", 90000);
		function a():Matrix3D {
			var m = new Matrix3D();
			m.appendRotation(20, Vector3D.X_AXIS);
			m.appendTranslation(10, 20, 30);
			return m;
		}
		function b():Matrix3D {
			var m = new Matrix3D();
			m.appendRotation(100, Vector3D.Y_AXIS);
			m.appendTranslation(50, -20, 0);
			return m;
		}
		var pcts:Array<Float> = [-1, -0.5, 0, 0.3, 1, 1.5, 2, 10, Math.NaN, Math.POSITIVE_INFINITY];
		for (p in pcts) {
			add("interpolate " + p, function() return raw(Matrix3D.interpolate(a(), b(), p)));
			add("interpolateTo " + p, function() {
				var m = a();
				m.interpolateTo(b(), p);
				return raw(m);
			});
		}
		// appendRotation / prependRotation with unusual axes
		var axes:Array<Array<Float>> = [[0, 2, 0], [0, 0, 0], [1, 1, 0], [0, 0.5, 0], [1, 2, 3], [0, 1, 0, 5]];
		for (ax in axes) {
			var v = ax.length > 3 ? new Vector3D(ax[0], ax[1], ax[2], ax[3]) : new Vector3D(ax[0], ax[1], ax[2]);
			add("appendRotation 30 axis " + ax.join(","), function() {
				var m = new Matrix3D();
				m.appendRotation(30, v);
				return raw(m);
			});
			add("prependRotation 30 axis " + ax.join(","), function() {
				var m = new Matrix3D();
				m.appendTranslation(1, 2, 3);
				m.prependRotation(30, v);
				return raw(m);
			});
		}
		add("appendRotation null axis", function() {
			var m = new Matrix3D();
			m.appendRotation(30, null);
			return raw(m);
		});
		add("appendRotation pivot w", function() {
			var m = new Matrix3D();
			m.appendRotation(30, Vector3D.Y_AXIS, new Vector3D(10, 0, 0, 5));
			return raw(m);
		});
		// construction / rawData edge cases
		add("new Matrix3D(8 numbers)", function() {
			var v = new flash.Vector<Float>();
			for (i in 0...8)
				v.push(i + 1);
			return raw(new Matrix3D(v));
		});
		add("new Matrix3D(20 numbers)", function() {
			var v = new flash.Vector<Float>();
			for (i in 0...20)
				v.push(i + 1);
			return raw(new Matrix3D(v));
		});
		add("rawData = 8 numbers", function() {
			var m = new Matrix3D();
			var v = new flash.Vector<Float>();
			for (i in 0...8)
				v.push(i + 1);
			m.rawData = v;
			return raw(m);
		});
		add("rawData = null", function() {
			var m = new Matrix3D();
			m.rawData = null;
			return raw(m);
		});
		add("copyColumnTo(4)", function() {
			var c = new Vector3D();
			new Matrix3D().copyColumnTo(4, c);
			return v3(c);
		});
		add("copyRowFrom(4)", function() {
			var m = new Matrix3D();
			m.copyRowFrom(4, new Vector3D(1, 2, 3, 4));
			return raw(m);
		});
		add("invert zero matrix", function() {
			var m = new Matrix3D();
			m.appendScale(0, 1, 1);
			var ok = m.invert();
			return ok + " " + raw(m);
		});
		add("determinant projective", function() {
			var v = new flash.Vector<Float>();
			for (x in [1.0, 0, 0, 0.1, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1])
				v.push(x);
			return r(new Matrix3D(v).determinant);
		});
		add("transformVectors short output", function() {
			var i = new flash.Vector<Float>();
			for (x in [1.0, 2, 3, 4, 5, 6])
				i.push(x);
			var o = new flash.Vector<Float>();
			o.push(99);
			new Matrix3D().transformVectors(i, o);
			return [for (x in o) r(x)].join(",");
		});
		add("transformVectors length 5 input", function() {
			var i = new flash.Vector<Float>();
			for (x in [1.0, 2, 3, 4, 5])
				i.push(x);
			var o = new flash.Vector<Float>();
			new Matrix3D().transformVectors(i, o);
			return [for (x in o) r(x)].join(",");
		});
		add("transformVector projective", function() {
			var v = new flash.Vector<Float>();
			for (x in [1.0, 0, 0, 0.1, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1])
				v.push(x);
			return v3(new Matrix3D(v).transformVector(new Vector3D(10, 20, 30, 1)));
		});
		add("position set w", function() {
			var m = new Matrix3D();
			m.position = new Vector3D(1, 2, 3, 9);
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
