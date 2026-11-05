/** Probe (no golden): BitmapData.encode with JPEGXREncoderOptions colorSpace 4:2:0 / 4:2:2 in
 *  Flash Player 32. Dumps the complete encoded bytes for several sizes, opaque and transparent,
 *  quantization 0/20/50, and decodes the lossless 4:2:0/4:2:2 results back with Loader.loadBytes
 *  (does lossless still subsample?). */
import flash.display.*;
import flash.events.Event;
import flash.events.IOErrorEvent;
import flash.utils.ByteArray;

class D66JpegXrSub {
	static function hex(b:ByteArray):String {
		var s = new StringBuf();
		b.position = 0;
		while (b.bytesAvailable > 0) {
			var v = b.readUnsignedByte();
			s.add(v < 16 ? "0" : "");
			s.add(StringTools.hex(v).toLowerCase());
		}
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

	static function noise(w:Int, h:Int, transparent:Bool):BitmapData {
		var bd = new BitmapData(w, h, transparent, 0);
		var s = 12345;
		for (y in 0...h)
			for (x in 0...w) {
				s = (s * 1103515245 + 12345) & 0x7fffffff;
				var c = s >>> 7;
				if (!transparent) c |= 0xff000000;
				bd.setPixel32(x, y, c);
			}
		return bd;
	}

	static function enc(name:String, bd:BitmapData, q:Int, cs:BitmapEncodingColorSpace):ByteArray {
		try {
			var out:ByteArray = bd.encode(bd.rect, new JPEGXREncoderOptions(q, cs, 0));
			H.log(name + " len=" + out.length + " hex=" + hex(out));
			return out;
		} catch (e:flash.errors.Error) {
			H.log(name + " THREW #" + e.errorID + " " + e.message);
		}
		return null;
	}

	static function dump(label:String, bd:BitmapData) {
		var s = new StringBuf();
		for (y in 0...bd.height)
			for (x in 0...bd.width) {
				s.add(StringTools.hex(bd.getPixel32(x, y), 8).toLowerCase());
				s.add(" ");
			}
		H.log(label + " " + bd.width + "x" + bd.height + " px=" + s.toString());
	}

	static var queue:Array<{name:String, bytes:ByteArray}> = [];

	static function next() {
		if (queue.length == 0) {
			H.done();
			return;
		}
		var item = queue.shift();
		var ld = new Loader();
		var done = false;
		var timer = haxe.Timer.delay(function() {
			if (done) return;
			done = true;
			H.log(item.name + " TIMEOUT");
			next();
		}, 4000);
		ld.contentLoaderInfo.addEventListener(Event.COMPLETE, function(_) {
			if (done) return;
			done = true;
			timer.stop();
			try {
				var bm:Bitmap = cast ld.content;
				dump(item.name + " decoded", bm.bitmapData);
			} catch (e:flash.errors.Error) {
				H.log(item.name + " content THREW #" + e.errorID);
			}
			next();
		});
		ld.contentLoaderInfo.addEventListener(IOErrorEvent.IO_ERROR, function(e:IOErrorEvent) {
			if (done) return;
			done = true;
			timer.stop();
			H.log(item.name + " IO_ERROR " + e.text);
			next();
		});
		try {
			item.bytes.position = 0;
			ld.loadBytes(item.bytes);
		} catch (e:flash.errors.Error) {
			H.log(item.name + " loadBytes THREW #" + e.errorID);
			done = true;
			timer.stop();
			next();
		}
	}

	static function main() {
		H.init("d66jpegxrsub", 120000);
		var imgs:Array<{n:String, bd:BitmapData}> = [];
		for (t in [false, true]) {
			var sfx = t ? "t" : "o";
			imgs.push({n: "g8" + sfx, bd: gradient(8, 8, t)});
			imgs.push({n: "g17x13" + sfx, bd: gradient(17, 13, t)});
			imgs.push({n: "n17x13" + sfx, bd: noise(17, 13, t)});
			imgs.push({n: "g1" + sfx, bd: gradient(1, 1, t)});
			imgs.push({n: "g5x3" + sfx, bd: gradient(5, 3, t)});
			imgs.push({n: "g40x36" + sfx, bd: gradient(40, 36, t)});
			imgs.push({n: "g300x200" + sfx, bd: gradient(300, 200, t)});
		}
		for (im in imgs)
			for (q in [0, 20, 50])
				for (c in [{n: "420", cs: BitmapEncodingColorSpace.COLORSPACE_4_2_0}, {n: "422", cs: BitmapEncodingColorSpace.COLORSPACE_4_2_2}]) {
					var name = im.n + " q" + q + " " + c.n;
					var out = enc(name, im.bd, q, c.cs);
					if (out != null && q == 0 && im.bd.width <= 17)
						queue.push({name: name, bytes: out});
				}
		next();
	}
}
