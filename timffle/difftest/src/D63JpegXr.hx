/** Probe (no golden): BitmapData.encode with JPEGXREncoderOptions in Flash Player 32.
 *  Dumps the complete encoded bytes as hex for a few small images and option sets, and
 *  decodes one result back with Loader.loadBytes to see Flash's own pixel values. */
import flash.Lib;
import flash.display.*;
import flash.events.Event;
import flash.events.IOErrorEvent;
import flash.geom.Rectangle;
import flash.utils.ByteArray;

class D63JpegXr {
	static var pending:Array<Void->Void> = [];

	static function step(label:String, f:Void->Void) {
		try {
			f();
		} catch (e:flash.errors.Error) {
			H.log(label + " THREW #" + e.errorID + " " + e.message);
		}
	}

	static function hex(b:ByteArray):String {
		var s = new StringBuf();
		var p = b.position;
		b.position = 0;
		while (b.bytesAvailable > 0) {
			var v = b.readUnsignedByte();
			s.add(v < 16 ? "0" : "");
			s.add(StringTools.hex(v).toLowerCase());
		}
		b.position = p;
		return s.toString();
	}

	// deterministic test pictures
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

	static function enc(name:String, bd:BitmapData, q:Int, cs:BitmapEncodingColorSpace, trim:Int) {
		step(name, function() {
			var o = new JPEGXREncoderOptions(q, cs, trim);
			var out:ByteArray = bd.encode(bd.rect, o);
			if (out == null) {
				H.log(name + " = null");
				return;
			}
			H.log(name + " len=" + out.length + " pos=" + out.position + " hex=" + hex(out));
		});
	}

	static function px(bd:BitmapData, x:Int, y:Int):String {
		return StringTools.hex(bd.getPixel32(x, y), 8).toLowerCase();
	}

	static function dumpPixels(label:String, bd:BitmapData) {
		var s = new StringBuf();
		for (y in 0...bd.height) {
			for (x in 0...bd.width) {
				s.add(px(bd, x, y));
				s.add(" ");
			}
			s.add("/ ");
		}
		H.log(label + " " + bd.width + "x" + bd.height + " transparent=" + bd.transparent + " px=" + s.toString());
	}

	static function roundTrip(name:String, bd:BitmapData, q:Int, cs:BitmapEncodingColorSpace, next:Void->Void) {
		var out:ByteArray = null;
		step(name + " encode", function() {
			out = bd.encode(bd.rect, new JPEGXREncoderOptions(q, cs, 0));
		});
		if (out == null) {
			H.log(name + " no bytes");
			next();
			return;
		}
		var ld = new Loader();
		var done = false;
		var timer = haxe.Timer.delay(function() {
			if (done) return;
			done = true;
			H.log(name + " loadBytes TIMEOUT");
			next();
		}, 4000);
		ld.contentLoaderInfo.addEventListener(Event.COMPLETE, function(_) {
			if (done) return;
			done = true;
			timer.stop();
			try {
				var bm:Bitmap = cast ld.content;
				H.log(name + " loaded " + ld.contentLoaderInfo.width + "x" + ld.contentLoaderInfo.height + " contentType=" + ld.contentLoaderInfo.contentType);
				dumpPixels(name + " decoded", bm.bitmapData);
			} catch (e:flash.errors.Error) {
				H.log(name + " content THREW #" + e.errorID + " " + e.message);
			}
			next();
		});
		ld.contentLoaderInfo.addEventListener(IOErrorEvent.IO_ERROR, function(e:IOErrorEvent) {
			if (done) return;
			done = true;
			timer.stop();
			H.log(name + " loadBytes IO_ERROR " + e.text);
			next();
		});
		step(name + " loadBytes", function() {
			out.position = 0;
			ld.loadBytes(out);
		});
	}

	static function main() {
		H.init("d63jpegxr", 60000);
		var g8o = gradient(8, 8, false);
		var g8t = gradient(8, 8, true);
		var n64t = noise(64, 48, true);
		var g64t = gradient(64, 48, true);
		var g24o = gradient(24, 20, false);
		var one = new BitmapData(1, 1, true, 0x80ff4020);
		dumpPixels("src g8o", g8o);
		dumpPixels("src g8t", g8t);
		dumpPixels("src g24o", g24o);
		dumpPixels("src one", one);
		step("defaults", function() {
			var o = new JPEGXREncoderOptions();
			H.log("defaults q=" + o.quantization + " cs=" + o.colorSpace + " trim=" + o.trimFlexBits);
		});
		enc("g8o q0 auto", g8o, 0, COLORSPACE_AUTO, 0);
		enc("g8o q20 auto", g8o, 20, COLORSPACE_AUTO, 0);
		enc("g8o q0 444", g8o, 0, COLORSPACE_4_4_4, 0);
		enc("g8o q20 444", g8o, 20, COLORSPACE_4_4_4, 0);
		enc("g8o q20 420", g8o, 20, COLORSPACE_4_2_0, 0);
		enc("g8o q20 422", g8o, 20, COLORSPACE_4_2_2, 0);
		enc("g8o q1 auto", g8o, 1, COLORSPACE_AUTO, 0);
		enc("g8o q255 auto", g8o, 255, COLORSPACE_AUTO, 0);
		enc("g8o q300 auto", g8o, 300, COLORSPACE_AUTO, 0);
		enc("g8o q20 auto trim4", g8o, 20, COLORSPACE_AUTO, 4);
		enc("g8o q20 auto trim15", g8o, 20, COLORSPACE_AUTO, 15);
		enc("g8o q20 auto trim16", g8o, 20, COLORSPACE_AUTO, 16);
		enc("g8t q0 auto", g8t, 0, COLORSPACE_AUTO, 0);
		enc("g8t q20 auto", g8t, 20, COLORSPACE_AUTO, 0);
		enc("g8t q0 444", g8t, 0, COLORSPACE_4_4_4, 0);
		enc("g8t q20 444", g8t, 20, COLORSPACE_4_4_4, 0);
		enc("g24o q0 auto", g24o, 0, COLORSPACE_AUTO, 0);
		enc("g24o q20 auto", g24o, 20, COLORSPACE_AUTO, 0);
		enc("one q0 auto", one, 0, COLORSPACE_AUTO, 0);
		enc("one q20 auto", one, 20, COLORSPACE_AUTO, 0);
		enc("g64t q0 auto", g64t, 0, COLORSPACE_AUTO, 0);
		enc("g64t q20 auto", g64t, 20, COLORSPACE_AUTO, 0);
		enc("g64t q20 444", g64t, 20, COLORSPACE_4_4_4, 0);
		enc("n64t q0 auto", n64t, 0, COLORSPACE_AUTO, 0);
		enc("n64t q20 auto", n64t, 20, COLORSPACE_AUTO, 0);
		step("rect sub", function() {
			var out = g64t.encode(new Rectangle(3, 5, 10, 7), new JPEGXREncoderOptions(0, COLORSPACE_AUTO, 0));
			H.log("g64t sub(3,5,10,7) q0 len=" + out.length + " hex=" + hex(out));
		});
		step("given bytearray", function() {
			var ba = new ByteArray();
			ba.writeByte(1);
			ba.writeByte(2);
			var out = g8o.encode(g8o.rect, new JPEGXREncoderOptions(0, COLORSPACE_AUTO, 0), ba);
			H.log("given same=" + (out == ba) + " len=" + ba.length + " pos=" + ba.position + " endian=" + ba.endian + " head=" + hex(ba).substr(0, 24));
		});
		step("bad colorspace", function() {
			var o = new JPEGXREncoderOptions(20, COLORSPACE_AUTO, 0);
			untyped o.colorSpace = "nonsense";
			var out = g8o.encode(g8o.rect, o);
			H.log("bad cs len=" + out.length + " hex=" + hex(out));
		});
		roundTrip("rt g8t q0", g8t, 0, COLORSPACE_AUTO, function() {
			roundTrip("rt g8t q20", g8t, 20, COLORSPACE_AUTO, function() {
				roundTrip("rt g8o q20", g8o, 20, COLORSPACE_AUTO, function() {
					roundTrip("rt one q0", one, 0, COLORSPACE_AUTO, function() {
						roundTrip("rt g24o q0", g24o, 0, COLORSPACE_AUTO, function() {
							H.done();
						});
					});
				});
			});
		});
	}
}
