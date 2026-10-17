import flash.geom.Matrix3D;
import flash.geom.Orientation3D;
import flash.geom.Vector3D;

/**
 * Matrix3D edge cases that D18 left open: pointAt (many inputs), recompose with quaternions and bad vectors, and
 * decompose of degenerate matrices. Probe: run in real Flash, derive the rules, compare Ruffle.
 */
class D21Matrix3DEdge {
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
		} catch (e:Dynamic) {
			H.log(label + " THREW " + H.err(e));
		}
	}

	static function pa(label:String, m:Matrix3D, pos:Vector3D, at:Vector3D = null, up:Vector3D = null) {
		t("pointAt " + label, function() {
			m.pointAt(pos, at, up);
			return raw(m);
		});
	}

	static function vecs(a:Array<Vector3D>):flash.Vector<Vector3D> {
		var d = new flash.Vector<Vector3D>();
		for (x in a)
			d.push(x);
		return d;
	}

	static function rc(label:String, a:Array<Vector3D>, style:Null<Orientation3D> = null) {
		t("recompose " + label, function() {
			var m = new Matrix3D();
			var ok = style == null ? m.recompose(vecs(a)) : m.recompose(vecs(a), style);
			return ok + " " + raw(m);
		});
	}

	static function dc(label:String, m:Matrix3D) {
		for (style in [Orientation3D.EULER_ANGLES, Orientation3D.AXIS_ANGLE, Orientation3D.QUATERNION]) {
			t("decompose " + label + " [" + Std.string(style) + "]", function() {
				var d = m.decompose(style);
				return d == null ? "null" : [for (v in d) v3(v)].join(" ");
			});
		}
	}

	static function tr(x:Float, y:Float, z:Float):Matrix3D {
		var m = new Matrix3D();
		m.appendTranslation(x, y, z);
		return m;
	}

	static function sc(x:Float, y:Float, z:Float, tx:Float = 0, ty:Float = 0, tz:Float = 0):Matrix3D {
		var m = new Matrix3D();
		m.appendScale(x, y, z);
		m.appendTranslation(tx, ty, tz);
		return m;
	}

	static function ro(deg:Float, axis:Vector3D, tx:Float = 0, ty:Float = 0, tz:Float = 0):Matrix3D {
		var m = new Matrix3D();
		m.appendRotation(deg, axis);
		m.appendTranslation(tx, ty, tz);
		return m;
	}

	static function main() {
		H.init("d21matrix3dedge", 40000);

		// pointAt: identity-like starting points first
		pa("identity pos=(100,0,0) defaults", new Matrix3D(), new Vector3D(100, 0, 0));
		pa("identity pos=(0,0,-100) defaults", new Matrix3D(), new Vector3D(0, 0, -100));
		pa("identity pos=(0,100,0) defaults", new Matrix3D(), new Vector3D(0, 100, 0));
		pa("identity pos=(0,0,100) defaults", new Matrix3D(), new Vector3D(0, 0, 100));
		pa("identity pos=(100,100,100) defaults", new Matrix3D(), new Vector3D(100, 100, 100));
		pa("t(10,20,30) pos=(100,0,0) defaults", tr(10, 20, 30), new Vector3D(100, 0, 0));
		pa("t(10,20,30) pos=(100,50,25) at=X up=Y", tr(10, 20, 30), new Vector3D(100, 50, 25), Vector3D.X_AXIS, Vector3D.Y_AXIS);
		pa("t(10,20,30) pos=(100,50,25) at=Z up=-Y", tr(10, 20, 30), new Vector3D(100, 50, 25), new Vector3D(0, 0, 1), new Vector3D(0, -1, 0));
		pa("t(10,20,30) pos=(100,50,25) at=-Z up=Y", tr(10, 20, 30), new Vector3D(100, 50, 25), new Vector3D(0, 0, -1), new Vector3D(0, 1, 0));
		pa("t(10,20,30) pos=(100,50,25) at=null up=Y", tr(10, 20, 30), new Vector3D(100, 50, 25), null, new Vector3D(0, 1, 0));
		pa("t(10,20,30) pos=(100,50,25) at=X up=null", tr(10, 20, 30), new Vector3D(100, 50, 25), Vector3D.X_AXIS, null);
		pa("scale(2,3,4) pos=(100,0,0) defaults", sc(2, 3, 4), new Vector3D(100, 0, 0));
		pa("scale(2,3,4)+t pos=(100,50,25) at=X up=Y", sc(2, 3, 4, 10, 20, 30), new Vector3D(100, 50, 25), Vector3D.X_AXIS, Vector3D.Y_AXIS);
		pa("rotY30 pos=(100,0,0) defaults", ro(30, Vector3D.Y_AXIS), new Vector3D(100, 0, 0));
		pa("rotY30+t pos=(100,50,25) at=X up=Y", ro(30, Vector3D.Y_AXIS, 10, 20, 30), new Vector3D(100, 50, 25), Vector3D.X_AXIS, Vector3D.Y_AXIS);
		pa("rotZ45+t pos=(100,50,25) at=X up=Y", ro(45, Vector3D.Z_AXIS, 10, 20, 30), new Vector3D(100, 50, 25), Vector3D.X_AXIS, Vector3D.Y_AXIS);
		pa("sample pos=(100,50,25) at=X up=Y", sample(), new Vector3D(100, 50, 25), Vector3D.X_AXIS, Vector3D.Y_AXIS);
		pa("sample pos=(100,50,25) defaults", sample(), new Vector3D(100, 50, 25));
		pa("pos == position", tr(10, 20, 30), new Vector3D(10, 20, 30));
		pa("at parallel to up", tr(10, 20, 30), new Vector3D(100, 50, 25), Vector3D.Y_AXIS, Vector3D.Y_AXIS);
		pa("at zero", tr(10, 20, 30), new Vector3D(100, 50, 25), new Vector3D(0, 0, 0), Vector3D.Y_AXIS);
		pa("up zero", tr(10, 20, 30), new Vector3D(100, 50, 25), Vector3D.X_AXIS, new Vector3D(0, 0, 0));
		pa("at not unit (3,0,0)", tr(10, 20, 30), new Vector3D(100, 50, 25), new Vector3D(3, 0, 0), new Vector3D(0, 2, 0));
		pa("non-orthogonal at/up", tr(10, 20, 30), new Vector3D(100, 50, 25), new Vector3D(1, 1, 0), new Vector3D(0, 1, 0));
		pa("w=1 in pos", tr(10, 20, 30), new Vector3D(100, 50, 25, 1));
		pa("w=2 in pos", tr(10, 20, 30), new Vector3D(100, 50, 25, 2));
		pa("projective column", make([1, 0, 0, 0.001, 0, 1, 0, 0, 0, 0, 1, 0, 10, 20, 30, 1]), new Vector3D(100, 50, 25), Vector3D.X_AXIS, Vector3D.Y_AXIS);
		// pointAt(null) aborts the whole script in Flash Player (no catch runs): not probed here.

		// recompose: quaternion and malformed inputs
		var tt = new Vector3D(10, 20, 30);
		var ss = new Vector3D(1.5, 2, 0.5);
		var qs = Math.sin(Math.PI / 8);
		var qc = Math.cos(Math.PI / 8);
		rc("quat exact y45", [tt, new Vector3D(0, qs, 0, qc), ss], Orientation3D.QUATERNION);
		rc("quat rounded y45", [tt, new Vector3D(0, 0.3827, 0, 0.9239), ss], Orientation3D.QUATERNION);
		rc("quat identity", [tt, new Vector3D(0, 0, 0, 1), ss], Orientation3D.QUATERNION);
		rc("quat unnormalised (0,1,0,1)", [tt, new Vector3D(0, 1, 0, 1), ss], Orientation3D.QUATERNION);
		rc("quat zero", [tt, new Vector3D(0, 0, 0, 0), ss], Orientation3D.QUATERNION);
		rc("quat x90", [tt, new Vector3D(Math.sin(Math.PI / 4), 0, 0, Math.cos(Math.PI / 4)), ss], Orientation3D.QUATERNION);
		rc("quat literal string", [tt, new Vector3D(0, qs, 0, qc), ss], cast "quaternion");
		rc("quat w=0", [tt, new Vector3D(0, 1, 0, 0), ss], Orientation3D.QUATERNION);
		rc("euler default string", [tt, new Vector3D(0.3, 0.5, 0.7), ss], cast "eulerAngles");
		rc("euler bad style", [tt, new Vector3D(0.3, 0.5, 0.7), ss], cast "bogus");
		rc("axisAngle zero axis", [tt, new Vector3D(0, 0, 0, 0.8), ss], Orientation3D.AXIS_ANGLE);
		rc("axisAngle unnormalised axis", [tt, new Vector3D(0, 2, 0, 0.8), ss], Orientation3D.AXIS_ANGLE);
		rc("scale zero x", [tt, new Vector3D(0.3, 0.5, 0.7), new Vector3D(0, 2, 0.5)]);
		rc("scale zero z", [tt, new Vector3D(0.3, 0.5, 0.7), new Vector3D(1, 2, 0)]);
		rc("scale negative", [tt, new Vector3D(0.3, 0.5, 0.7), new Vector3D(-1, 2, 0.5)]);
		rc("two components", [tt, new Vector3D(0.3, 0.5, 0.7)]);
		rc("four components", [tt, new Vector3D(0.3, 0.5, 0.7), ss, ss]);
		rc("zero components", []);
		t("recompose null", function() {
			var m = new Matrix3D();
			return Std.string(m.recompose(null));
		});
		rc("w components ignored?", [new Vector3D(10, 20, 30, 5), new Vector3D(0.3, 0.5, 0.7, 6), new Vector3D(1.5, 2, 0.5, 7)]);

		// decompose: degenerate matrices
		dc("c1 zero", make([1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]));
		dc("c0 zero", make([0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 5, 6, 7, 1]));
		dc("c2 zero", make([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 5, 6, 7, 1]));
		dc("c1 == c0", make([1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 5, 6, 7, 1]));
		dc("c2 == c0", make([1, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 5, 6, 7, 1]));
		dc("c2 == c1+c0", make([1, 0, 0, 0, 0, 1, 0, 0, 1, 1, 0, 0, 5, 6, 7, 1]));
		dc("all zero linear", make([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5, 6, 7, 1]));
		dc("projective", make([1, 0, 0, 0.01, 0, 1, 0, 0, 0, 0, 1, 0, 5, 6, 7, 1]));
		dc("w=2", make([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 5, 6, 7, 2]));
		dc("reflection x", make([-1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 5, 6, 7, 1]));
		dc("reflection xy+rot", make([-0.7071, -0.7071, 0, 0, 0.7071, -0.7071, 0, 0, 0, 0, 1, 0, 5, 6, 7, 1]));
		dc("scale only (2,3,4)", sc(2, 3, 4, 5, 6, 7));
		dc("rotX 90 gimbal", ro(90, Vector3D.X_AXIS));
		dc("rotY 90 gimbal", ro(90, Vector3D.Y_AXIS));
		dc("rotY -90 gimbal", ro(-90, Vector3D.Y_AXIS));
		dc("rotZ 180", ro(180, Vector3D.Z_AXIS));
		dc("rotX 180", ro(180, Vector3D.X_AXIS));
		dc("sample", sample());
		H.done();
	}
}
