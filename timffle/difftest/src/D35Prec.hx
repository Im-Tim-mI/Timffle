import flash.geom.Matrix3D;
import flash.geom.Vector3D;

class D35Prec {
	static function main() {
		H.init("d35prec", 10000);
		var v = new flash.Vector<Float>();
		for (x in [0.1, 0, 0, 0, 0, 0.01, 0, 0, 0, 0, 1, 0, 0.3, 0, 0, 1])
			v.push(x);
		var m = new Matrix3D(v);
		H.log("raw0=" + m.rawData[0]);
		H.log("raw5=" + m.rawData[5]);
		H.log("raw12=" + m.rawData[12]);
		var p = m.transformVector(new Vector3D(10, 100, 0, 1));
		H.log("tv=" + p.x + "," + p.y + "," + p.z + "," + p.w);
		var pv = flash.geom.Utils3D.projectVector(m, new Vector3D(10, 100, 0, 1));
		H.log("pv=" + pv.x + "," + pv.y + "," + pv.z + "," + pv.w);
		var v2 = new flash.Vector<Float>();
		for (x in [1.0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0.01])
			v2.push(x);
		var m2 = new Matrix3D(v2);
		var pv2 = flash.geom.Utils3D.projectVector(m2, new Vector3D(100, 50, 250, 1));
		H.log("pv2=" + pv2.x + "," + pv2.y + "," + pv2.z + "," + pv2.w);
		var tv2 = m2.transformVector(new Vector3D(100, 50, 250, 1));
		H.log("tv2=" + tv2.x + "," + tv2.y + "," + tv2.z + "," + tv2.w);
		H.log("det=" + m2.determinant);
		H.done();
	}
}
