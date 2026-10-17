import flash.geom.Matrix3D;
import flash.geom.Orientation3D;
import flash.geom.Vector3D;

/**
 * The flash.geom.Matrix3D class on its own (no display objects): every method on a few inputs, results rounded to
 * 4 decimals. Run in real Flash and in Ruffle and compare. Exploration, then a golden once they agree.
 */
class D18Matrix3D {
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

	static function t(label:String, f:Void->String) {
		try {
			H.log(label + ": " + f());
		} catch (e:flash.errors.Error) {
			// A native catch: Haxe's wrapper for `Dynamic` fails in release players (no stack traces).
			H.log(label + " THREW Error#" + e.errorID + " " + e.name);
		}
	}

	static function main() {
		H.init("d18matrix3d", 30000);
		t("identity", function() return raw(new Matrix3D()));
		t("sample", function() return raw(sample()));
		t("determinant", function() return r(sample().determinant));
		t("position", function() return v3(sample().position));
		t("position set", function() {
			var m = sample();
			m.position = new Vector3D(1, 2, 3);
			return raw(m);
		});
		t("clone", function() return raw(sample().clone()));
		t("invert", function() {
			var m = sample();
			var ok = m.invert();
			return ok + " " + raw(m);
		});
		t("invert singular", function() {
			var m = make([1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]);
			var ok = m.invert();
			return ok + " " + raw(m);
		});
		t("transpose", function() {
			var m = sample();
			m.transpose();
			return raw(m);
		});
		t("append", function() {
			var m = sample();
			var n = new Matrix3D();
			n.appendTranslation(5, 6, 7);
			n.appendRotation(30, Vector3D.Z_AXIS);
			m.append(n);
			return raw(m);
		});
		t("prepend", function() {
			var m = sample();
			var n = new Matrix3D();
			n.appendTranslation(5, 6, 7);
			n.appendRotation(30, Vector3D.Z_AXIS);
			m.prepend(n);
			return raw(m);
		});
		t("appendRotation pivot", function() {
			var m = sample();
			m.appendRotation(40, new Vector3D(1, 2, 3), new Vector3D(10, 20, 30));
			return raw(m);
		});
		t("prependRotation", function() {
			var m = sample();
			m.prependRotation(40, new Vector3D(1, 2, 3));
			return raw(m);
		});
		t("prependRotation pivot", function() {
			var m = sample();
			m.prependRotation(40, new Vector3D(1, 2, 3), new Vector3D(10, 20, 30));
			return raw(m);
		});
		t("appendScale", function() {
			var m = sample();
			m.appendScale(2, 3, 4);
			return raw(m);
		});
		t("prependScale", function() {
			var m = sample();
			m.prependScale(2, 3, 4);
			return raw(m);
		});
		t("appendTranslation", function() {
			var m = sample();
			m.appendTranslation(2, 3, 4);
			return raw(m);
		});
		t("prependTranslation", function() {
			var m = sample();
			m.prependTranslation(2, 3, 4);
			return raw(m);
		});
		t("transformVector", function() return v3(sample().transformVector(new Vector3D(1, 2, 3, 1))));
		t("transformVector w=0 input", function() return v3(sample().transformVector(new Vector3D(1, 2, 3, 0))));
		t("deltaTransformVector", function() return v3(sample().deltaTransformVector(new Vector3D(1, 2, 3))));
		t("transformVectors", function() {
			var i = new flash.Vector<Float>();
			for (x in [1.0, 2, 3, 4, 5, 6])
				i.push(x);
			var o = new flash.Vector<Float>();
			sample().transformVectors(i, o);
			return [for (x in o) r(x)].join(",");
		});
		t("decompose euler", function() {
			var d = sample().decompose(Orientation3D.EULER_ANGLES);
			return [for (v in d) v3(v)].join(" ");
		});
		t("decompose axis-angle", function() {
			var d = sample().decompose(Orientation3D.AXIS_ANGLE);
			return [for (v in d) v3(v)].join(" ");
		});
		t("decompose quaternion", function() {
			var d = sample().decompose(Orientation3D.QUATERNION);
			return [for (v in d) v3(v)].join(" ");
		});
		t("~decompose singular", function() {
			var m = make([1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]);
			var d = m.decompose();
			return d == null ? "null" : [for (v in d) v3(v)].join(" ");
		});
		t("recompose euler", function() {
			var d = new flash.Vector<Vector3D>();
			d.push(new Vector3D(10, 20, 30));
			d.push(new Vector3D(0.3, 0.5, 0.7));
			d.push(new Vector3D(1.5, 2, 0.5));
			var m = new Matrix3D();
			var ok = m.recompose(d);
			return ok + " " + raw(m);
		});
		t("recompose axis-angle", function() {
			var d = new flash.Vector<Vector3D>();
			d.push(new Vector3D(10, 20, 30));
			d.push(new Vector3D(0, 1, 0, 0.8));
			d.push(new Vector3D(1.5, 2, 0.5));
			var m = new Matrix3D();
			var ok = m.recompose(d, Orientation3D.AXIS_ANGLE);
			return ok + " " + raw(m);
		});
		t("recompose quaternion", function() {
			var d = new flash.Vector<Vector3D>();
			d.push(new Vector3D(10, 20, 30));
			d.push(new Vector3D(0, 0.3827, 0, 0.9239));
			d.push(new Vector3D(1.5, 2, 0.5));
			var m = new Matrix3D();
			var ok = m.recompose(d, Orientation3D.QUATERNION);
			return ok + " " + raw(m);
		});
		t("interpolate", function() {
			var a = sample();
			var b = new Matrix3D();
			b.appendRotation(80, Vector3D.Y_AXIS);
			b.appendTranslation(40, 0, 0);
			return raw(Matrix3D.interpolate(a, b, 0.3));
		});
		t("interpolateTo", function() {
			var a = sample();
			var b = new Matrix3D();
			b.appendRotation(80, Vector3D.Y_AXIS);
			b.appendTranslation(40, 0, 0);
			a.interpolateTo(b, 0.3);
			return raw(a);
		});
		t("pointAt", function() {
			var m = sample();
			m.pointAt(new Vector3D(100, 50, 25), Vector3D.X_AXIS, Vector3D.Y_AXIS);
			return raw(m);
		});
		t("copyFrom", function() {
			var m = new Matrix3D();
			m.copyFrom(sample());
			return raw(m);
		});
		t("copyRawDataTo", function() {
			var v = new flash.Vector<Float>();
			sample().copyRawDataTo(v, 2, true);
			return [for (x in v) r(x)].join(",");
		});
		t("copyRawDataFrom", function() {
			var m = new Matrix3D();
			var v = new flash.Vector<Float>();
			for (i in 0...20)
				v.push(i + 1);
			m.copyRawDataFrom(v, 2, true);
			return raw(m);
		});
		t("copyColumnTo/From", function() {
			var m = sample();
			var c = new Vector3D();
			m.copyColumnTo(1, c);
			var n = new Matrix3D();
			n.copyColumnFrom(2, new Vector3D(7, 8, 9, 10));
			return v3(c) + " " + raw(n);
		});
		t("copyRowTo/From", function() {
			var m = sample();
			var c = new Vector3D();
			m.copyRowTo(1, c);
			var n = new Matrix3D();
			n.copyRowFrom(2, new Vector3D(7, 8, 9, 10));
			return v3(c) + " " + raw(n);
		});
		t("copyToMatrix3D", function() {
			var n = new Matrix3D();
			sample().copyToMatrix3D(n);
			return raw(n);
		});
		t("rawData set", function() {
			var m = new Matrix3D();
			var v = new flash.Vector<Float>();
			for (i in 0...16)
				v.push(i * 0.5);
			m.rawData = v;
			return raw(m);
		});
		t("identity()", function() {
			var m = sample();
			m.identity();
			return raw(m);
		});
		H.done();
	}
}
