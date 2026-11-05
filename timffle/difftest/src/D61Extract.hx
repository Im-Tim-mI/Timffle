/** Probe (no golden): Sound.extract sample values on Flash Player 32 — endianness, the sequential
 *  cursor, the first non-silent samples of an embedded MP3, and extract() on sounds filled with
 *  loadPCMFromByteArray (D60 only saw zeros because the MP3 starts silent). Build with -swf-version 32. */
import flash.media.Sound;
import flash.utils.ByteArray;
import flash.utils.Endian;

@:sound("../../../tests/tests/swfs/avm2/sound_rootless/noise.mp3")
class Noise2 extends flash.media.Sound {}

class D61Extract {
	static var qn:Dynamic;

	static function step(label:String, f:Void->Void) {
		try {
			f();
		} catch (e:flash.errors.Error) {
			H.log(label + " THREW " + qn(e) + " #" + e.errorID + " " + e.message);
		}
	}

	static function f4(n:Float):String {
		return Std.string(Math.round(n * 10000) / 10000);
	}

	static function floats(ba:ByteArray, from:Int, count:Int):String {
		ba.position = from;
		var v = [];
		for (i in 0...count)
			if (ba.bytesAvailable >= 4)
				v.push(f4(ba.readFloat()));
		return v.join(",");
	}

	static function main() {
		H.init("d61extract", 20000);
		qn = untyped __global__["flash.utils.getQualifiedClassName"];
		var n = new Noise2();
		step("first nonzero", function() {
			var ba = new ByteArray();
			var r = n.extract(ba, 3000, 0);
			ba.position = 0;
			var idx = -1;
			var i = 0;
			while (ba.bytesAvailable >= 4) {
				var v = ba.readFloat();
				if (v != 0 && idx < 0)
					idx = i;
				i++;
			}
			H.log("first nonzero float index=" + idx + " (sample " + Std.int(idx / 2) + ") of " + r);
		});
		step("values at 2000", function() {
			var ba = new ByteArray();
			var r = n.extract(ba, 4, 2000);
			H.log("extract(4,2000) -> " + r + " " + floats(ba, 0, 8) + " position=" + ba.position + " length=" + ba.length);
		});
		step("values at 2000 LE", function() {
			var ba = new ByteArray();
			ba.endian = Endian.LITTLE_ENDIAN;
			var r = n.extract(ba, 4, 2000);
			H.log("extract(4,2000) LE -> " + r + " " + floats(ba, 0, 8));
			ba.endian = Endian.BIG_ENDIAN;
			H.log("same bytes read BE -> " + floats(ba, 0, 8));
		});
		step("sequential cursor", function() {
			var ba = new ByteArray();
			n.extract(ba, 2, 2000);
			var seq1 = floats(ba, 0, 4);
			var ba2 = new ByteArray();
			n.extract(ba2, 2);
			var seq2 = floats(ba2, 0, 4);
			var ba3 = new ByteArray();
			n.extract(ba3, 2);
			var seq3 = floats(ba3, 0, 4);
			var ba4 = new ByteArray();
			n.extract(ba4, 2, 2002);
			var seq4 = floats(ba4, 0, 4);
			var ba5 = new ByteArray();
			n.extract(ba5, 2, 2004);
			var seq5 = floats(ba5, 0, 4);
			H.log("at 2000=" + seq1 + " | next=" + seq2 + " | next=" + seq3 + " | explicit 2002=" + seq4 + " | explicit 2004=" + seq5);
			var ba6 = new ByteArray();
			n.extract(ba6, 2, -1);
			H.log("after explicit 2004, extract(2,-1)=" + floats(ba6, 0, 4) + " ; explicit 2006=" + (function() {
				var b = new ByteArray();
				n.extract(b, 2, 2006);
				return floats(b, 0, 4);
			})());
			var ba7 = new ByteArray();
			n.extract(ba7, 2, 2.9);
			var ba8 = new ByteArray();
			n.extract(ba8, 2, 2);
			H.log("start 2.9=" + floats(ba7, 0, 4) + " start 2=" + floats(ba8, 0, 4));
		});
		step("cursor after end", function() {
			var total = Math.round(n.length * 44.1);
			var ba = new ByteArray();
			n.extract(ba, 10, total - 2);
			var ba2 = new ByteArray();
			var r = n.extract(ba2, 10);
			H.log("after reading the tail, sequential extract -> " + r);
		});
		step("write position", function() {
			var ba = new ByteArray();
			ba.writeUTFBytes("abcdefgh");
			ba.position = 4;
			var r = n.extract(ba, 3, 2000);
			H.log("into pos 4 -> " + r + " length=" + ba.length + " position=" + ba.position);
			ba.position = 0;
			H.log("prefix kept=" + ba.readUTFBytes(4) + " floats=" + floats(ba, 4, 6));
		});
		step("pcm extract bigger", function() {
			var s = new Sound();
			var ba = new ByteArray();
			for (i in 0...5000) {
				ba.writeFloat(0.5);
				ba.writeFloat(-0.25);
			}
			ba.position = 0;
			s.loadPCMFromByteArray(ba, 5000, "float", true, 44100);
			var out = new ByteArray();
			var r = s.extract(out, 4, 0);
			H.log("pcm 5000 extract(4,0) -> " + r + " " + floats(out, 0, 8));
			var out2 = new ByteArray();
			r = s.extract(out2, 4, 2000);
			H.log("pcm 5000 extract(4,2000) -> " + r + " " + floats(out2, 0, 8));
			var out3 = new ByteArray();
			r = s.extract(out3, 1e9, 0);
			out3.position = 0;
			var idx = -1, i = 0, nz = 0;
			while (out3.bytesAvailable >= 4) {
				var v = out3.readFloat();
				if (v != 0) {
					nz++;
					if (idx < 0)
						idx = i;
				}
				i++;
			}
			H.log("pcm 5000 whole -> " + r + " floats=" + i + " nonzero=" + nz + " first nonzero index=" + idx + " length=" + s.length + " bytesTotal=" + s.bytesTotal);
		});
		step("pcm short extract", function() {
			var s = new Sound();
			var ba = new ByteArray();
			for (i in 0...3000)
				ba.writeShort(i == 0 ? 16384 : -8192);
			ba.position = 0;
			s.loadPCMFromByteArray(ba, 3000, "short", false, 44100);
			var out = new ByteArray();
			var r = s.extract(out, 3, 0);
			H.log("pcm short mono 3000 extract(3,0) -> " + r + " " + floats(out, 0, 6));
			var out2 = new ByteArray();
			r = s.extract(out2, 2, 1500);
			H.log("pcm short mono 3000 extract(2,1500) -> " + r + " " + floats(out2, 0, 4));
		});
		step("pcm 22050 extract", function() {
			var s = new Sound();
			var ba = new ByteArray();
			for (i in 0...3000) {
				ba.writeFloat(i % 2 == 0 ? 0.5 : -0.5);
				ba.writeFloat(0.125);
			}
			ba.position = 0;
			s.loadPCMFromByteArray(ba, 3000, "float", true, 22050);
			var out = new ByteArray();
			var r = s.extract(out, 6, 1000);
			H.log("pcm 22050 extract(6,1000) -> " + r + " " + floats(out, 0, 12) + " length=" + s.length);
		});
		step("pcm clipping", function() {
			var s = new Sound();
			var ba = new ByteArray();
			for (i in 0...3000) {
				ba.writeFloat(2.5);
				ba.writeFloat(-3);
			}
			ba.position = 0;
			s.loadPCMFromByteArray(ba, 3000, "float", true, 44100);
			var out = new ByteArray();
			var r = s.extract(out, 2, 1000);
			H.log("pcm clipping extract(2,1000) -> " + r + " " + floats(out, 0, 4));
		});
		step("pcm precision", function() {
			var s = new Sound();
			var ba = new ByteArray();
			for (i in 0...3000) {
				ba.writeFloat(0.123456789);
				ba.writeFloat(1 / 3);
			}
			ba.position = 0;
			s.loadPCMFromByteArray(ba, 3000, "float", true, 44100);
			var out = new ByteArray();
			var r = s.extract(out, 1, 1000);
			out.position = 0;
			var a = out.readFloat(), b = out.readFloat();
			H.log("pcm precision -> " + a + " " + b + " (x32768: " + (a * 32768) + " " + (b * 32768) + ")");
		});
		H.done();
	}
}
