import flash.Lib;
import flash.display.Sprite;
import flash.geom.Matrix3D;
import flash.geom.Vector3D;

/** Matrix3D methods whose argument is the matrix itself, on a live `transform.matrix3D` (bound to a 3D display
 * object). Such a live matrix refreshes itself from the object before every read; aliasing must not break that.
 * Every live result is compared with the same operation on a plain (unbound) copy. */
class LiveSelfAppend {
	static var s:Sprite;

	static function raw(m:Matrix3D):String {
		return Std.string(m.rawData);
	}

	static function equal(a:Matrix3D, b:Matrix3D):Bool {
		var ra = a.rawData;
		var rb = b.rawData;
		for (i in 0...16) if (ra[i] != rb[i]) return false;
		return true;
	}

	// Small integers so the products are exact.
	static function reset():Matrix3D {
		s.transform.matrix3D = new Matrix3D(flash.Vector.ofArray([2.0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 1, 0, 5, 7, 11, 1]));
		return s.transform.matrix3D;
	}

	static function check(label:String, plain:Matrix3D, live:Matrix3D) {
		Out.line(label + " plain=" + raw(plain));
		Out.line(label + " live=" + raw(live) + " object=" + raw(s.transform.matrix3D) + " equal=" + (equal(plain, live) && equal(live, s.transform.matrix3D)));
		Out.line(label + " x=" + s.x + " y=" + s.y + " z=" + s.z + " scaleX=" + s.scaleX + " scaleY=" + s.scaleY);
	}

	static function main() {
		Out.start("matrix3d_live_self_append");
		s = new Sprite();
		Lib.current.addChild(s);

		var live = reset();
		var plain = live.clone();
		plain.append(plain);
		live.append(live);
		check("append(self)", plain, live);

		live = reset();
		plain = live.clone();
		plain.prepend(plain);
		live.prepend(live);
		check("prepend(self)", plain, live);

		live = reset();
		plain = live.clone();
		plain.copyFrom(plain);
		live.copyFrom(live);
		check("copyFrom(self)", plain, live);

		live = reset();
		plain = live.clone();
		plain.copyToMatrix3D(plain);
		live.copyToMatrix3D(live);
		check("copyToMatrix3D(self)", plain, live);

		live = reset();
		plain = live.clone();
		plain.interpolateTo(plain, 0.25);
		live.interpolateTo(live, 0.25);
		check("interpolateTo(self)", plain, live);

		live = reset();
		plain = live.clone();
		var ip = Matrix3D.interpolate(plain, plain, 0.5);
		var il = Matrix3D.interpolate(live, live, 0.5);
		Out.line("interpolate(self, self) plain=" + raw(ip) + " live=" + raw(il) + " equal=" + equal(ip, il));

		// Two live views of the same object alias each other through the object.
		live = reset();
		var other = s.transform.matrix3D;
		plain = live.clone();
		plain.append(plain);
		live.append(other);
		check("append(other live view)", plain, live);

		// A live matrix of an object that left 3D is a plain matrix again.
		live = reset();
		s.transform.matrix3D = null;
		plain = live.clone();
		plain.append(plain);
		live.append(live);
		Out.line("after leaving 3d: live=" + raw(live) + " plain=" + raw(plain) + " equal=" + equal(plain, live) + " matrix3D=" + s.transform.matrix3D);
		Out.line("done");
		Out.finish();
	}
}
