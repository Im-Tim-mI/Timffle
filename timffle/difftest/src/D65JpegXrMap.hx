/** Probe (no golden): quantization 0..100 -> QP index byte, error precedence (Flash Player 32). */
import flash.display.*;
import flash.geom.Rectangle;
import flash.utils.ByteArray;

class D65JpegXrMap {
	static function qn(e:Dynamic):String {
		return untyped __global__["flash.utils.getQualifiedClassName"](e);
	}
	static function hex(b:ByteArray, from:Int, n:Int):String {
		var s = new StringBuf();
		b.position = from;
		var i = 0;
		while (b.bytesAvailable > 0 && i < n) {
			var v = b.readUnsignedByte();
			s.add(v < 16 ? "0" : "");
			s.add(StringTools.hex(v).toLowerCase());
			i++;
		}
		return s.toString();
	}
	static function t(label:String, f:Void->Void) {
		try {
			f();
		} catch (e:flash.errors.Error) {
			H.log(label + " THREW " + qn(e) + " #" + e.errorID);
		}
	}
	static function main() {
		H.init("d65jpegxrmap", 60000);
		var bd = new BitmapData(4, 4, false, 0xff336699);
		var s = new StringBuf();
		for (q in 0...101) {
			var out = bd.encode(bd.rect, new JPEGXREncoderOptions(q, COLORSPACE_4_4_4, 0));
			s.add(q + ":" + hex(out, 90 + 16, 4) + " ");
		}
		H.log("map " + s.toString());
		t("q200 trim20", function() bd.encode(bd.rect, new JPEGXREncoderOptions(200, COLORSPACE_AUTO, 20)));
		t("q200 badcs", function() {
			var o = new JPEGXREncoderOptions(200, COLORSPACE_AUTO, 0);
			untyped o.colorSpace = "x";
			bd.encode(bd.rect, o);
		});
		t("trim20 badcs", function() {
			var o = new JPEGXREncoderOptions(20, COLORSPACE_AUTO, 20);
			untyped o.colorSpace = "x";
			bd.encode(bd.rect, o);
		});
		t("q200 emptyrect", function() bd.encode(new Rectangle(0, 0, 0, 0), new JPEGXREncoderOptions(200, COLORSPACE_AUTO, 0)));
		t("badcs emptyrect", function() {
			var o = new JPEGXREncoderOptions(20, COLORSPACE_AUTO, 0);
			untyped o.colorSpace = "x";
			bd.encode(new Rectangle(0, 0, 0, 0), o);
		});
		t("ok emptyrect", function() bd.encode(new Rectangle(0, 0, 0, 0), new JPEGXREncoderOptions(20, COLORSPACE_AUTO, 0)));
		t("q200 disposed", function() {
			var d = new BitmapData(2, 2);
			d.dispose();
			d.encode(new Rectangle(0, 0, 2, 2), new JPEGXREncoderOptions(200, COLORSPACE_AUTO, 0));
		});
		var tr = new BitmapData(4, 4, true, 0);
		t("transparent zero", function() {
			var out = tr.encode(tr.rect, new JPEGXREncoderOptions(0, COLORSPACE_AUTO, 0));
			H.log("tz len=" + out.length + " guid=" + hex(out, 74, 16));
		});
		var op = new BitmapData(4, 4, true, 0xff102030);
		t("transparent but opaque", function() {
			var out = op.encode(op.rect, new JPEGXREncoderOptions(0, COLORSPACE_AUTO, 0));
			H.log("top len=" + out.length + " guid=" + hex(out, 74, 16));
		});
		H.done();
	}
}
