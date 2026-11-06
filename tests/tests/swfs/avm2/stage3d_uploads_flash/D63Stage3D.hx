import flash.Lib;
import flash.display.BitmapData;
import flash.display.Stage3D;
import flash.display3D.Context3D;
import flash.display3D.textures.Texture;
import flash.display3D.textures.CubeTexture;
import flash.events.Event;
import flash.utils.ByteArray;

/** Stage3D texture upload rules on real Flash: mip level bounds, source size mismatch,
 * ByteArray sizes, sampler mip filter names, render-to-texture antiAlias, driverInfo. */
class D63Stage3D {
	static var ctx:Context3D;
	static var steps:Array<{label:String, fn:Void->String}> = [];

	static function add(label:String, fn:Void->String)
		steps.push({label: label, fn: fn});

	static function errs(e:flash.errors.Error):String
		return "Error#" + e.errorID + " " + e.name;

	static function bytes(n:Int):ByteArray {
		var b = new ByteArray();
		for (i in 0...n)
			b.writeByte(i & 255);
		b.position = 0;
		return b;
	}

	static function main() {
		H.init("d63stage3d", 60000);
		var s3d:Stage3D = Lib.current.stage.stage3Ds[0];
		s3d.addEventListener(Event.CONTEXT3D_CREATE, function(_) {
			if (ctx != null) {
				H.log("context recreated");
				return;
			}
			ctx = s3d.context3D;
			H.log("driverInfo non-empty " + (ctx.driverInfo.length > 0));
			H.log("has totalGPUMemory " + Reflect.hasField(ctx, "totalGPUMemory"));
			var ok = true;
			try {
				H.log("totalGPUMemory " + untyped ctx.totalGPUMemory);
			} catch (e:flash.errors.Error) {
				H.log("totalGPUMemory THREW " + errs(e));
			}
			ctx.configureBackBuffer(64, 64, 0, true);
			var tex:Texture = null;
			add("createTexture 8x8 bgra streaming 2", function() {
				tex = ctx.createTexture(8, 8, cast "bgra", false, 2);
				return "ok";
			});
			add("upload mip0 8x8", function() { tex.uploadFromBitmapData(new BitmapData(8, 8, false, 0xFF0000), 0); return "ok"; });
			add("upload mip1 4x4", function() { tex.uploadFromBitmapData(new BitmapData(4, 4, false, 0x00FF00), 1); return "ok"; });
			add("upload mip2 2x2", function() { tex.uploadFromBitmapData(new BitmapData(2, 2, false, 0x0000FF), 2); return "ok"; });
			add("upload mip3 1x1", function() { tex.uploadFromBitmapData(new BitmapData(1, 1, false, 0xFFFFFF), 3); return "ok"; });
			add("upload mip4 1x1 (too large)", function() { tex.uploadFromBitmapData(new BitmapData(1, 1, false, 0xFFFFFF), 4); return "ok"; });
			add("upload mip1 with 8x8 (larger)", function() { tex.uploadFromBitmapData(new BitmapData(8, 8, false, 0x123456), 1); return "ok"; });
			add("upload mip0 with 4x4 (smaller)", function() { tex.uploadFromBitmapData(new BitmapData(4, 4, false, 0x123456), 0); return "ok"; });
			add("upload mip0 with 16x16 (larger)", function() { tex.uploadFromBitmapData(new BitmapData(16, 16, false, 0x123456), 0); return "ok"; });
			add("upload mip0 with 8x4 (narrow)", function() { tex.uploadFromBitmapData(new BitmapData(8, 4, false, 0x123456), 0); return "ok"; });
			add("bytes mip1 exact 64", function() { tex.uploadFromByteArray(bytes(64), 0, 1); return "ok"; });
			add("bytes mip1 short 63", function() { tex.uploadFromByteArray(bytes(63), 0, 1); return "ok"; });
			add("bytes mip0 offset 3 of 259", function() { tex.uploadFromByteArray(bytes(259), 3, 0); return "ok"; });
			add("bytes mip0 offset past end", function() { tex.uploadFromByteArray(bytes(8), 4, 0); return "ok"; });
			add("bytes mip4 (too large)", function() { tex.uploadFromByteArray(bytes(4), 0, 4); return "ok"; });
			add("bytes mip0 larger 1024", function() { tex.uploadFromByteArray(bytes(1024), 0, 0); return "ok"; });
			var cube:CubeTexture = null;
			add("createCubeTexture 4 streaming 1", function() { cube = ctx.createCubeTexture(4, cast "bgra", false, 1); return "ok"; });
			add("cube side 5 level 0", function() { cube.uploadFromBitmapData(new BitmapData(4, 4, false, 0x123456), 5, 0); return "ok"; });
			add("cube side 0 level 1", function() { cube.uploadFromBitmapData(new BitmapData(2, 2, false, 0x123456), 0, 1); return "ok"; });
			add("cube side 0 level 2", function() { cube.uploadFromBitmapData(new BitmapData(1, 1, false, 0x123456), 0, 2); return "ok"; });
			add("cube side 0 level 3 (too large)", function() { cube.uploadFromBitmapData(new BitmapData(1, 1, false, 0x123456), 0, 3); return "ok"; });
			add("cube side 6 level 0 (bad side)", function() { cube.uploadFromBitmapData(new BitmapData(4, 4, false, 0x123456), 6, 0); return "ok"; });
			add("cube bytes side 2 level 1 16 bytes", function() { cube.uploadFromByteArray(bytes(16), 0, 2, 1); return "ok"; });
			add("cube bytes side 2 level 1 short 15", function() { cube.uploadFromByteArray(bytes(15), 0, 2, 1); return "ok"; });
			add("sampler mipnone", function() { ctx.setSamplerStateAt(0, cast "clamp", cast "linear", cast "mipnone"); return "ok"; });
			add("sampler mipnearest", function() { ctx.setSamplerStateAt(0, cast "clamp", cast "linear", cast "mipnearest"); return "ok"; });
			add("sampler miplinear", function() { ctx.setSamplerStateAt(0, cast "repeat", cast "nearest", cast "miplinear"); return "ok"; });
			add("sampler bogus mip", function() { ctx.setSamplerStateAt(0, cast "clamp", cast "linear", cast "bogus"); return "ok"; });
			add("sampler bogus wrap", function() { ctx.setSamplerStateAt(0, cast "bogus", cast "linear", cast "mipnone"); return "ok"; });
			add("sampler bogus filter", function() { ctx.setSamplerStateAt(0, cast "clamp", cast "bogus", cast "mipnone"); return "ok"; });
			var packed:Texture = null;
			add("createTexture 4x4 bgrPacked565", function() { packed = ctx.createTexture(4, 4, cast "bgrPacked565", false); return "ok"; });
			add("565 bitmap 4x4", function() { packed.uploadFromBitmapData(new BitmapData(4, 4, true, 0x80FF8040)); return "ok"; });
			add("565 bytes 32", function() { packed.uploadFromByteArray(bytes(32), 0); return "ok"; });
			add("565 bytes 31", function() { packed.uploadFromByteArray(bytes(31), 0); return "ok"; });
			add("565 bytes 64", function() { packed.uploadFromByteArray(bytes(64), 0); return "ok"; });
			var p4:Texture = null;
			add("createTexture 4x4 bgraPacked4444", function() { p4 = ctx.createTexture(4, 4, cast "bgraPacked4444", false); return "ok"; });
			add("4444 bytes 32", function() { p4.uploadFromByteArray(bytes(32), 0); return "ok"; });
			add("4444 bytes 31", function() { p4.uploadFromByteArray(bytes(31), 0); return "ok"; });
			var comp:Texture = null;
			add("createTexture 4x4 compressed", function() { comp = ctx.createTexture(4, 4, cast "compressed", false); return "ok"; });
			add("compressed bitmap 4x4", function() { comp.uploadFromBitmapData(new BitmapData(4, 4, true, 0x80FF8040)); return "ok"; });
			add("compressed bytes 64", function() { comp.uploadFromByteArray(bytes(64), 0); return "ok"; });
			add("compressed bytes 63", function() { comp.uploadFromByteArray(bytes(63), 0); return "ok"; });
			add("compressed bytes 8", function() { comp.uploadFromByteArray(bytes(8), 0); return "ok"; });
			add("compressed garbage ATF 64", function() { comp.uploadCompressedTextureFromByteArray(bytes(64), 0); return "ok"; });
			add("compressed ATF offset past end", function() { comp.uploadCompressedTextureFromByteArray(bytes(8), 4); return "ok"; });
			var target:Texture = null;
			add("render to texture antiAlias 4", function() {
				target = ctx.createTexture(16, 16, cast "bgra", true);
				ctx.setRenderToTexture(target, true, 4);
				ctx.clear(0, 0, 1, 1);
				ctx.setRenderToBackBuffer();
				return "ok";
			});
			add("drawToBitmapData 64x64", function() {
				var b = new BitmapData(64, 64, false, 0);
				ctx.clear(1, 0, 0, 1);
				ctx.drawToBitmapData(b);
				return StringTools.hex(b.getPixel(1, 1), 6);
			});
			add("drawToBitmapData 32x32", function() {
				var b = new BitmapData(32, 32, false, 0);
				ctx.clear(0, 1, 0, 1);
				ctx.drawToBitmapData(b);
				return StringTools.hex(b.getPixel(1, 1), 6);
			});
			add("drawToBitmapData 128x128", function() {
				var b = new BitmapData(128, 128, false, 0x777777);
				ctx.clear(0, 0, 1, 1);
				ctx.drawToBitmapData(b);
				return StringTools.hex(b.getPixel(1, 1), 6) + " " + StringTools.hex(b.getPixel(100, 100), 6);
			});
			add("backBuffer size", function() {
				return untyped ctx.backBufferWidth + "x" + untyped ctx.backBufferHeight;
			});
			add("maxBackBufferWidth set 99999", function() {
				untyped ctx.maxBackBufferWidth = 99999;
				return "" + untyped ctx.maxBackBufferWidth;
			});
			add("maxBackBufferWidth set 1", function() {
				untyped ctx.maxBackBufferWidth = 1;
				return "" + untyped ctx.maxBackBufferWidth;
			});

			add("mip level from oversized bitmap", function() {
				ctx.configureBackBuffer(32, 32, 0, false);
				var t = ctx.createTexture(128, 128, cast "bgra", false);
				t.uploadFromBitmapData(new BitmapData(128, 128, false, 0xFF0000), 0);
				t.uploadFromBitmapData(new BitmapData(64, 64, false, 0x00FF00), 1);
				var b2 = new BitmapData(64, 64, false, 0xFFFF00);
				b2.fillRect(new flash.geom.Rectangle(0, 0, 32, 32), 0x0000FF);
				t.uploadFromBitmapData(b2, 2);
				var sz = 16;
				var lv = 3;
				while (sz >= 1) {
					t.uploadFromBitmapData(new BitmapData(sz, sz, false, 0xFFFFFF), lv);
					sz >>= 1;
					lv++;
				}
				var vb = ctx.createVertexBuffer(4, 4);
				vb.uploadFromVector(flash.Vector.ofArray([-1.0, 1, 0, 0, 1, 1, 1, 0, 1, -1, 1, 1, -1, -1, 0, 1]), 0, 4);
				var ib = ctx.createIndexBuffer(6);
				var iv = new flash.Vector<UInt>();
				for (x in [0, 1, 2, 0, 2, 3]) iv.push(x);
				ib.uploadFromVector(iv, 0, 6);
				var prog = ctx.createProgram();
				prog.upload(agal(0, [[0x00, 0, 3, 0, 0], [0x00, 0, 4, 1, 0]]), agal(1, [[0x28, 0, 2, 0, 4], [0x00, 0, 3, 0, 2]]));
				ctx.setProgram(prog);
				ctx.setVertexBufferAt(0, vb, 0, cast "float2");
				ctx.setVertexBufferAt(1, vb, 2, cast "float2");
				ctx.setTextureAt(0, t);
				var out = [];
				for (mf in ["mipnearest", "mipnone"]) {
					ctx.setSamplerStateAt(0, cast "clamp", cast "nearest", cast mf);
					ctx.clear(0, 0, 0, 1);
					ctx.drawTriangles(ib);
					var bd = new BitmapData(32, 32, false, 0);
					ctx.drawToBitmapData(bd);
					out.push(mf + " " + StringTools.hex(bd.getPixel(2, 2), 6) + " " + StringTools.hex(bd.getPixel(29, 29), 6) + " " + StringTools.hex(bd.getPixel(29, 2), 6));
				}
				ctx.setTextureAt(0, null);
				ctx.configureBackBuffer(64, 64, 0, true);
				return out.join(" | ");
			});
			add("dispose then driverInfo", function() {
				ctx.dispose();
				return ctx.driverInfo;
			});
			add("after dispose createTexture", function() { ctx.createTexture(4, 4, cast "bgra", false); return "ok"; });
			run(0);
		});
		s3d.addEventListener("error", function(e) {
			H.log("context3D error " + e);
			H.done();
		});
		s3d.requestContext3D();
	}


	// AGAL: tokens [opcode, destReg, destType, srcReg, srcType]; tex uses sampler fs0 <2d,clamp,nearest,mipnearest>
	static function agal(kind:Int, toks:Array<Array<Int>>):ByteArray {
		var b = new ByteArray();
		b.endian = flash.utils.Endian.LITTLE_ENDIAN;
		b.writeByte(0xa0);
		b.writeUnsignedInt(1);
		b.writeByte(0xa1);
		b.writeByte(kind);
		for (t in toks) {
			b.writeUnsignedInt(t[0]);
			b.writeShort(t[1]);
			b.writeByte(0xF);
			b.writeByte(t[2]);
			b.writeShort(t[3]);
			b.writeByte(0);
			b.writeByte(0xE4);
			b.writeByte(t[4]);
			b.writeByte(0);
			b.writeByte(0);
			b.writeByte(0);
			if (t[0] == 0x28) {
				b.writeShort(0);
				b.writeByte(0);
				b.writeByte(0);
				b.writeByte(5);
				b.writeByte(0);
				b.writeByte(0x10);
				b.writeByte(0);
			} else {
				b.writeUnsignedInt(0);
				b.writeUnsignedInt(0);
			}
		}
		b.position = 0;
		return b;
	}

	static function run(i:Int) {
		if (i >= steps.length) {
			H.done();
			return;
		}
		haxe.Timer.delay(function() {
			var st = steps[i];
			var r = "";
			try {
				r = st.fn();
			} catch (e:flash.errors.Error) {
				r = "THREW " + errs(e);
			}
			H.log(st.label + ": " + r);
			run(i + 1);
		}, 20);
	}
}
