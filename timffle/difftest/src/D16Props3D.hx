import flash.Lib;
import flash.display.DisplayObject;
import flash.display.Sprite;
import flash.geom.Matrix;
import flash.geom.Matrix3D;
import flash.geom.Vector3D;

/**
 * What a DisplayObject's 3D properties do to `transform.matrix` / `transform.matrix3D` and to each other, as the
 * player reports it. Exploration (prints what the player does); the lines are compared between players by hand.
 */
class D16Props3D {
	static function r(x:Float):String {
		var v = Math.round(x * 10000) / 10000;
		if (v == 0)
			v = 0; // no -0
		return Std.string(v);
	}

	static function raw(m:Matrix3D):String {
		if (m == null)
			return "null";
		var v = m.rawData;
		var parts = [for (i in 0...16) r(v[i])];
		return parts.join(",");
	}

	static function props(d:DisplayObject):String {
		return "x=" + r(d.x) + " y=" + r(d.y) + " z=" + r(d.z) + " rotX=" + r(d.rotationX) + " rotY=" + r(d.rotationY) + " rotZ=" + r(d.rotationZ) + " rot=" + r(d.rotation) + " sx=" + r(d.scaleX) + " sy=" + r(d.scaleY) + " sz=" + r(d.scaleZ);
	}

	static function state(d:DisplayObject):String {
		var m = d.transform.matrix;
		return "matrix=" + (m == null ? "null" : r(m.a) + "," + r(m.b) + "," + r(m.c) + "," + r(m.d) + "," + r(m.tx) + "," + r(m.ty)) + " | matrix3D=" + raw(d.transform.matrix3D);
	}

	static function probe(label:String, f:Sprite->Void) {
		var s = new Sprite();
		s.graphics.beginFill(0x336699);
		s.graphics.drawRect(0, 0, 100, 50);
		s.graphics.endFill();
		Lib.current.addChild(s);
		try {
			f(s);
			H.log(label + ": " + props(s));
			H.log("   " + state(s));
		} catch (e:Dynamic) {
			H.log(label + " THREW " + H.err(e));
		}
		Lib.current.removeChild(s);
	}

	static function main() {
		H.init("d16props3d", 30000);
		probe("fresh", function(s) {});
		probe("x=10 y=20", function(s) {
			s.x = 10;
			s.y = 20;
		});
		probe("z=0", function(s) s.z = 0);
		probe("z=30", function(s) s.z = 30);
		probe("x=10 y=20 z=30", function(s) {
			s.x = 10;
			s.y = 20;
			s.z = 30;
		});
		probe("rotationX=0", function(s) s.rotationX = 0);
		probe("rotationX=30", function(s) s.rotationX = 30);
		probe("rotationY=30", function(s) s.rotationY = 30);
		probe("rotationZ=30", function(s) s.rotationZ = 30);
		probe("rotation=30 (2D)", function(s) s.rotation = 30);
		probe("scaleZ=1", function(s) s.scaleZ = 1);
		probe("scaleZ=2", function(s) s.scaleZ = 2);
		probe("scaleX=2 scaleY=3 scaleZ=4", function(s) {
			s.scaleX = 2;
			s.scaleY = 3;
			s.scaleZ = 4;
		});
		probe("rotX=20 rotY=30 rotZ=40", function(s) {
			s.rotationX = 20;
			s.rotationY = 30;
			s.rotationZ = 40;
		});
		probe("rotZ=40 rotY=30 rotX=20 (other order of setting)", function(s) {
			s.rotationZ = 40;
			s.rotationY = 30;
			s.rotationX = 20;
		});
		probe("full: x=10 y=20 z=30 rot 20/30/40 scale 1.5/0.5/2", function(s) {
			s.x = 10;
			s.y = 20;
			s.z = 30;
			s.rotationX = 20;
			s.rotationY = 30;
			s.rotationZ = 40;
			s.scaleX = 1.5;
			s.scaleY = 0.5;
			s.scaleZ = 2;
		});
		probe("rotationX=90", function(s) s.rotationX = 90);
		probe("rotationY=90", function(s) s.rotationY = 90);
		probe("rotationX=180", function(s) s.rotationX = 180);
		probe("rotationX=-45", function(s) s.rotationX = -45);
		probe("rotationY=200", function(s) s.rotationY = 200);
		probe("rotX=45 then rotation=20", function(s) {
			s.rotationX = 45;
			s.rotation = 20;
		});
		probe("rotX=45 then scaleX=2", function(s) {
			s.rotationX = 45;
			s.scaleX = 2;
		});
		probe("rotX=45 then x=7", function(s) {
			s.rotationX = 45;
			s.x = 7;
		});
		probe("rotX=45 then matrix=identity", function(s) {
			s.rotationX = 45;
			s.transform.matrix = new Matrix();
		});
		probe("rotX=45 then matrix3D=null", function(s) {
			s.rotationX = 45;
			s.transform.matrix3D = null;
		});
		probe("matrix3D = identity", function(s) s.transform.matrix3D = new Matrix3D());
		probe("matrix3D = translation(5,6,7)", function(s) {
			var m = new Matrix3D();
			m.appendTranslation(5, 6, 7);
			s.transform.matrix3D = m;
		});
		probe("matrix3D = rotX 30", function(s) {
			var m = new Matrix3D();
			m.appendRotation(30, Vector3D.X_AXIS);
			s.transform.matrix3D = m;
		});
		probe("matrix3D = rotY 30", function(s) {
			var m = new Matrix3D();
			m.appendRotation(30, Vector3D.Y_AXIS);
			s.transform.matrix3D = m;
		});
		probe("matrix3D = rotZ 30", function(s) {
			var m = new Matrix3D();
			m.appendRotation(30, Vector3D.Z_AXIS);
			s.transform.matrix3D = m;
		});
		probe("matrix3D = rotX 20, rotY 30, rotZ 40 (append order)", function(s) {
			var m = new Matrix3D();
			m.appendRotation(20, Vector3D.X_AXIS);
			m.appendRotation(30, Vector3D.Y_AXIS);
			m.appendRotation(40, Vector3D.Z_AXIS);
			s.transform.matrix3D = m;
		});
		probe("matrix3D = scale 2,3,4 then translate 1,2,3", function(s) {
			var m = new Matrix3D();
			m.appendScale(2, 3, 4);
			m.appendTranslation(1, 2, 3);
			s.transform.matrix3D = m;
		});
		probe("matrix3D = shear-ish raw", function(s) {
			var v = new flash.Vector<Float>();
			for (x in [1.0, 0.2, 0, 0, 0.3, 1, 0, 0, 0, 0, 1, 0, 10, 20, 30, 1])
				v.push(x);
			s.transform.matrix3D = new Matrix3D(v);
		});
		probe("matrix3D = perspective-ish raw (w != 1)", function(s) {
			var v = new flash.Vector<Float>();
			for (x in [1.0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0.001, 0, 0, 0, 1])
				v.push(x);
			s.transform.matrix3D = new Matrix3D(v);
		});
		probe("matrix3D = rotX 30 then rotationX read/modify -> 50", function(s) {
			var m = new Matrix3D();
			m.appendRotation(30, Vector3D.X_AXIS);
			s.transform.matrix3D = m;
			s.rotationX = 50;
		});
		// the same matrix object kept by the caller after assignment
		probe("matrix3D object shared: assign, then change the caller's matrix", function(s) {
			var m = new Matrix3D();
			s.transform.matrix3D = m;
			m.appendTranslation(50, 0, 0);
		});
		probe("matrix3D getter returns a copy?", function(s) {
			s.z = 10;
			var m1 = s.transform.matrix3D;
			m1.appendTranslation(100, 0, 0);
		});
		H.done();
	}
}
