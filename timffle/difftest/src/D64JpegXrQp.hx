/** Probe (no golden): JPEGXREncoderOptions.quantization -> codestream QP index, error classes,
 *  colour-space choices, 'auto' on larger pictures. Flash Player 32 standalone. */
import flash.Lib;
import flash.display.*;
import flash.geom.Rectangle;
import flash.utils.ByteArray;

class D64JpegXrQp {
	static function qn(e:Dynamic):String {
		return untyped __global__["flash.utils.getQualifiedClassName"](e);
	}

	static function hex(b:ByteArray, from:Int, n:Int):String {
		var s = new StringBuf();
		var p = b.position;
		b.position = from;
		var i = 0;
		while (b.bytesAvailable > 0 && i < n) {
			var v = b.readUnsignedByte();
			s.add(v < 16 ? "0" : "");
			s.add(StringTools.hex(v).toLowerCase());
			i++;
		}
		b.position = p;
		return s.toString();
	}

	static function gradient(w:Int, h:Int, transparent:Bool):BitmapData {
		var bd = new BitmapData(w, h, transparent, 0);
		for (y in 0...h)
			for (x in 0...w) {
				var r = Std.int(x * 255 / Math.max(1, w - 1));
				var g = Std.int(y * 255 / Math.max(1, h - 1));
				var b = (x * 37 + y * 91) & 255;
				var a = transparent ? ((x + y) & 1 == 0 ? 255 : Std.int(((x * 13 + y * 7) & 255))) : 255;
				bd.setPixel32(x, y, (a << 24) | (r << 16) | (g << 8) | b);
			}
		return bd;
	}

	static function tryEnc(label:String, bd:BitmapData, o:JPEGXREncoderOptions, full:Bool) {
		try {
			var out = bd.encode(bd.rect, o);
			H.log(label + " len=" + out.length + " head=" + hex(out, 90, full ? out.length : 40));
		} catch (e:flash.errors.Error) {
			H.log(label + " THREW " + qn(e) + " #" + e.errorID + " " + e.message);
		}
	}

	static function main() {
		H.init("d64jpegxrqp", 60000);
		var g8o = gradient(8, 8, false);
		var g8t = gradient(8, 8, true);
		for (q in [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 24, 28, 30, 32, 36, 40, 48, 50, 60, 64, 70, 80, 90, 100, 110, 120, 128, 140, 150, 160, 180, 200, 220, 240, 250, 252, 253, 254, 255, 256, 1000]) {
			tryEnc("g8o q" + q, g8o, new JPEGXREncoderOptions(q, COLORSPACE_AUTO, 0), false);
		}
		for (q in [0, 1, 20]) {
			tryEnc("g8o q" + q + " 420", g8o, new JPEGXREncoderOptions(q, COLORSPACE_4_2_0, 0), true);
			tryEnc("g8o q" + q + " 422", g8o, new JPEGXREncoderOptions(q, COLORSPACE_4_2_2, 0), true);
			tryEnc("g8t q" + q + " 420", g8t, new JPEGXREncoderOptions(q, COLORSPACE_4_2_0, 0), true);
		}
		for (t in [0, 1, 2, 7, 8, 14, 15, 16, 17, 100]) {
			tryEnc("g8o q20 trim" + t, g8o, new JPEGXREncoderOptions(20, COLORSPACE_AUTO, t), false);
			tryEnc("g8o q0 trim" + t, g8o, new JPEGXREncoderOptions(0, COLORSPACE_AUTO, t), false);
		}
		var big = gradient(300, 200, false);
		tryEnc("big300x200 q20 auto", big, new JPEGXREncoderOptions(20, COLORSPACE_AUTO, 0), false);
		tryEnc("big300x200 q20 444", big, new JPEGXREncoderOptions(20, COLORSPACE_4_4_4, 0), false);
		tryEnc("big300x200 q20 420", big, new JPEGXREncoderOptions(20, COLORSPACE_4_2_0, 0), false);
		tryEnc("big300x200 q0 auto", big, new JPEGXREncoderOptions(0, COLORSPACE_AUTO, 0), false);
		var bigt = gradient(300, 200, true);
		tryEnc("bigt300x200 q20 auto", bigt, new JPEGXREncoderOptions(20, COLORSPACE_AUTO, 0), false);
		var wide = gradient(1100, 40, false);
		tryEnc("wide1100x40 q20 auto", wide, new JPEGXREncoderOptions(20, COLORSPACE_AUTO, 0), false);
		var tall = gradient(40, 4200, false);
		tryEnc("tall40x4200 q20 auto", tall, new JPEGXREncoderOptions(20, COLORSPACE_AUTO, 0), false);
		try {
			var o = new JPEGXREncoderOptions(20, COLORSPACE_AUTO, 0);
			untyped o.colorSpace = null;
			var out = g8o.encode(g8o.rect, o);
			H.log("null cs len=" + out.length + " head=" + hex(out, 90, 40));
		} catch (e:flash.errors.Error) {
			H.log("null cs THREW " + qn(e) + " #" + e.errorID + " " + e.message);
		}
		try {
			var o = new JPEGXREncoderOptions(20, COLORSPACE_AUTO, 0);
			untyped o.colorSpace = "4:4:4 ";
			var out = g8o.encode(g8o.rect, o);
			H.log("cs with space len=" + out.length);
		} catch (e:flash.errors.Error) {
			H.log("cs with space THREW " + qn(e) + " #" + e.errorID + " " + e.message);
		}
		try {
			var ba = new ByteArray();
			ba.writeByte(9);
			ba.writeByte(9);
			ba.writeByte(9);
			ba.position = 1;
			var out = g8o.encode(g8o.rect, new JPEGXREncoderOptions(20, COLORSPACE_AUTO, 0), ba);
			H.log("given pos1 same=" + (out == ba) + " len=" + ba.length + " pos=" + ba.position + " head=" + hex(ba, 0, 8));
		} catch (e:flash.errors.Error) {
			H.log("given THREW " + qn(e) + " #" + e.errorID + " " + e.message);
		}
		H.done();
	}
}
