import flash.geom.Matrix3D;
import flash.geom.Vector3D;

/** Bit-level arithmetic of Matrix3D: random inputs, exact outputs. */
class D37Arith {
	static var seed:UInt = 12345;

	static function rnd():Float {
		// xorshift32
		seed ^= seed << 13;
		seed ^= seed >>> 17;
		seed ^= seed << 5;
		return (seed & 0xFFFFFF) / 16777216.0;
	}

	static function val():Float {
		// a mix of magnitudes and decimal fractions
		var k = Std.int(rnd() * 4);
		var base = (rnd() - 0.5) * 20;
		if (k == 0)
			return Math.round(base * 10) / 10;
		if (k == 1)
			return base;
		if (k == 2)
			return base * 0.001;
		return Math.round(base) / 3;
	}

	static function randMatrix():Matrix3D {
		var v = new flash.Vector<Float>();
		for (i in 0...16)
			v.push(val());
		return new Matrix3D(v);
	}

	static function s(m:Matrix3D):String
		return [for (i in 0...16) Std.string(m.rawData[i])].join(",");

	static function main() {
		H.init("d37arith", 60000);
		for (i in 0...60) {
			var m = randMatrix();
			var n = randMatrix();
			var v = new Vector3D(val(), val(), val(), 1);
			var tv = m.transformVector(v);
			var dv = m.deltaTransformVector(v);
			H.log("TV m=" + s(m) + " v=" + v.x + "," + v.y + "," + v.z + " out=" + tv.x + "," + tv.y + "," + tv.z + "," + tv.w + " delta=" + dv.x + "," + dv.y + "," + dv.z + "," + dv.w);
			var a = randMatrix();
			a.append(n);
			H.log("APPEND m=" + s(m) + " n=" + s(n) + " out=" + s(a_append(m, n)));
			H.log("PREPEND m=" + s(m) + " n=" + s(n) + " out=" + s(a_prepend(m, n)));
			H.log("DET m=" + s(m) + " out=" + Std.string(m.determinant));
			var inv = m.clone();
			var ok = inv.invert();
			H.log("INV m=" + s(m) + " ok=" + ok + " out=" + s(inv));
		}
		H.done();
	}

	static function a_append(m:Matrix3D, n:Matrix3D):Matrix3D {
		var c = m.clone();
		c.append(n);
		return c;
	}

	static function a_prepend(m:Matrix3D, n:Matrix3D):Matrix3D {
		var c = m.clone();
		c.prepend(n);
		return c;
	}
}
