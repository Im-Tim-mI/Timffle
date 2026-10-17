import flash.geom.Matrix3D;
import flash.geom.Vector3D;

/**
 * Matrix3D.pointAt on matrices with shear/scale/rotation, to learn how Flash combines the old matrix with the new
 * orientation. Probe (no golden): run in real Flash, derive the rule, compare Ruffle.
 */
class D22PointAt {
	static function r(x:Float):String {
		var v = Math.round(x * 10000) / 10000;
		if (v == 0)
			v = 0;
		return Std.string(v);
	}

	static function raw(m:Matrix3D):String
		return [for (i in 0...16) r(m.rawData[i])].join(",");

	static function make(a:Array<Float>):Matrix3D {
		var v = new flash.Vector<Float>();
		for (x in a)
			v.push(x);
		return new Matrix3D(v);
	}

	// columns given as three 3-vectors, translation (tx,ty,tz)
	static function cols(c0:Array<Float>, c1:Array<Float>, c2:Array<Float>, tx:Float = 0, ty:Float = 0, tz:Float = 0):Matrix3D
		return make([c0[0], c0[1], c0[2], 0, c1[0], c1[1], c1[2], 0, c2[0], c2[1], c2[2], 0, tx, ty, tz, 1]);

	static function pa(label:String, m:Matrix3D, pos:Vector3D, at:Vector3D = null, up:Vector3D = null) {
		var before = raw(m);
		try {
			m.pointAt(pos, at, up);
			H.log(label + "\n   in : " + before + "\n   out: " + raw(m));
		} catch (e:Dynamic) {
			H.log(label + " THREW " + H.err(e));
		}
	}

	static function main() {
		H.init("d22pointat", 40000);
		var px = new Vector3D(100, 0, 0);
		var X = Vector3D.X_AXIS;
		var Y = Vector3D.Y_AXIS;
		// d = +X from the origin: world frame W = (e_x, -e_y, -e_z)
		pa("S1 diag(2,3,4)", cols([2, 0, 0], [0, 3, 0], [0, 0, 4]), px, X, Y);
		pa("S0 identity", cols([1, 0, 0], [0, 1, 0], [0, 0, 1]), px, X, Y);
		pa("uniform 2", cols([2, 0, 0], [0, 2, 0], [0, 0, 2]), px, X, Y);
		pa("shear c1.x=.5", cols([1, 0, 0], [.5, 1, 0], [0, 0, 1]), px, X, Y);
		pa("shear c2.x=.5", cols([1, 0, 0], [0, 1, 0], [.5, 0, 1]), px, X, Y);
		pa("shear c0.y=.5", cols([1, .5, 0], [0, 1, 0], [0, 0, 1]), px, X, Y);
		pa("shear c2.y=.5", cols([1, 0, 0], [0, 1, 0], [0, .5, 1]), px, X, Y);
		pa("shear c0.z=.5", cols([1, 0, 0.5], [0, 1, 0], [0, 0, 1]), px, X, Y);
		pa("shear c1.z=.5", cols([1, 0, 0], [0, 1, .5], [0, 0, 1]), px, X, Y);
		pa("scaled shear c1.x=.5", cols([2, 0, 0], [.5, 3, 0], [0, 0, 4]), px, X, Y);
		pa("scaled shear c0.y=.5", cols([2, .5, 0], [0, 3, 0], [0, 0, 4]), px, X, Y);
		pa("scaled shear c2.z..", cols([2, 0, 0], [0, 3, 0], [0, .5, 4]), px, X, Y);
		pa("rotZ30", cols([0.866, 0.5, 0], [-0.5, 0.866, 0], [0, 0, 1]), px, X, Y);
		pa("rotZ30 scaled (2,3,4) after", cols([1.732, 1.5, 0], [-1, 2.598, 0], [0, 0, 4]), px, X, Y);
		pa("rotZ30 scaled (2,3,4) before", cols([1.732, 1, 0], [-1.5, 2.598, 0], [0, 0, 4]), px, X, Y);
		// d along -Z with defaults (W = ...)
		pa("S1 pos=(0,0,-100) defaults", cols([2, 0, 0], [0, 3, 0], [0, 0, 4]), new Vector3D(0, 0, -100));
		pa("S1 pos=(0,0,100) defaults", cols([2, 0, 0], [0, 3, 0], [0, 0, 4]), new Vector3D(0, 0, 100));
		pa("S1 pos=(0,100,0) defaults", cols([2, 0, 0], [0, 3, 0], [0, 0, 4]), new Vector3D(0, 100, 0));
		pa("S1 pos=(0,100,0) at=X up=Y", cols([2, 0, 0], [0, 3, 0], [0, 0, 4]), new Vector3D(0, 100, 0), X, Y);
		pa("S1 pos=(0,0,100) at=X up=Y", cols([2, 0, 0], [0, 3, 0], [0, 0, 4]), new Vector3D(0, 0, 100), X, Y);
		pa("S1 pos=(0,-100,0) at=X up=Y", cols([2, 0, 0], [0, 3, 0], [0, 0, 4]), new Vector3D(0, -100, 0), X, Y);
		pa("S1 pos=(100,0,0) at=Y up=X", cols([2, 0, 0], [0, 3, 0], [0, 0, 4]), px, Y, X);
		pa("S1 pos=(100,0,0) at=Z up=X", cols([2, 0, 0], [0, 3, 0], [0, 0, 4]), px, Vector3D.Z_AXIS, X);
		pa("S1 pos=(100,0,0) at=Z up=Y", cols([2, 0, 0], [0, 3, 0], [0, 0, 4]), px, Vector3D.Z_AXIS, Y);
		pa("negative scale x", cols([-2, 0, 0], [0, 3, 0], [0, 0, 4]), px, X, Y);
		pa("negative scale z", cols([2, 0, 0], [0, 3, 0], [0, 0, -4]), px, X, Y);
		pa("reflection + shear", cols([-1, 0, 0], [0.5, 1, 0], [0, 0, 1]), px, X, Y);
		pa("tilted general", cols([1, 2, 0.5], [-0.3, 1, 2], [0.7, -0.2, 1.5], 3, 4, 5), new Vector3D(50, -20, 70), X, Y);
		pa("tilted general defaults", cols([1, 2, 0.5], [-0.3, 1, 2], [0.7, -0.2, 1.5], 3, 4, 5), new Vector3D(50, -20, 70));
		H.done();
	}
}
