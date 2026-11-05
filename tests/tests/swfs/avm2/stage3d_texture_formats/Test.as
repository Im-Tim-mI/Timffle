// Timffle: Context3D.createTexture formats (bgra, bgrPacked565,
// bgraPacked4444, compressed, compressedAlpha), uploadFromBitmapData /
// uploadFromByteArray for each of them, and uploadCompressedTextureFromByteArray
// with hand-built RAW_COMPRESSED (DXT1) / RAW_COMPRESSED_ALPHA (DXT5) ATF
// containers (sync and async). Needs a live Context3D, so the expected
// output follows the Adobe AS3 Reference: "Miplevel Too Large" #3674,
// RangeError "Bad Input Size" #3669, "Texture Format Mismatch" #3675,
// "Texture Size Does Not Match" #3679, "Texture Decoding Failed" #3677.
package {
    import flash.display.BitmapData;
    import flash.display.MovieClip;
    import flash.display.Stage3D;
    import flash.display3D.Context3D;
    import flash.display3D.textures.CubeTexture;
    import flash.display3D.textures.Texture;
    import flash.events.Event;
    import flash.utils.ByteArray;

    public class Test extends MovieClip {
        private var ctx:Context3D;

        public function Test() {
            var s:Stage3D = stage.stage3Ds[0];
            s.addEventListener(Event.CONTEXT3D_CREATE, created);
            s.requestContext3D("auto", "standard");
        }

        // A version-3 ATF container holding one mip level of raw block data
        // (format 3 = RAW_COMPRESSED with DXT1 blocks, 5 = RAW_COMPRESSED_ALPHA
        // with DXT5 blocks; the PVRTC/ETC1/ETC2 records are empty).
        private function atf(format:uint, log2:uint, cube:Boolean, payload:ByteArray):ByteArray {
            var b:ByteArray = new ByteArray();
            b.writeUTFBytes("ATF");
            b.writeByte(0);
            b.writeByte(0);
            b.writeByte(0);
            b.writeByte(0xFF);
            b.writeByte(3);
            var body:ByteArray = new ByteArray();
            body.writeByte(format | (cube ? 0x80 : 0));
            body.writeByte(log2);
            body.writeByte(log2);
            body.writeByte(1);
            var faces:int = cube ? 6 : 1;
            for (var f:int = 0; f < faces; f++) {
                body.writeUnsignedInt(payload.length);
                body.writeBytes(payload);
                body.writeUnsignedInt(0);
                body.writeUnsignedInt(0);
                body.writeUnsignedInt(0);
            }
            b.writeUnsignedInt(body.length);
            b.writeBytes(body);
            b.position = 0;
            return b;
        }

        private function block(bytes:Array):ByteArray {
            var b:ByteArray = new ByteArray();
            for each (var v:uint in bytes) {
                b.writeByte(v);
            }
            b.position = 0;
            return b;
        }

        private function filled(len:uint):ByteArray {
            var b:ByteArray = new ByteArray();
            for (var i:uint = 0; i < len; i++) {
                b.writeByte(i & 0xFF);
            }
            b.position = 0;
            return b;
        }

        private function attempt(label:String, fn:Function):void {
            try {
                fn();
                trace(label + ": ok");
            } catch (e:Error) {
                trace(label + ": " + e.errorID);
            }
        }

        private function created(e:Event):void {
            ctx = Stage3D(e.target).context3D;
            var formats:Array = ["bgra", "bgrPacked565", "bgraPacked4444", "compressed", "compressedAlpha"];
            var bytesPerPixel:Object = {bgra: 4, bgrPacked565: 2, bgraPacked4444: 2, compressed: 4, compressedAlpha: 4};
            var bmp:BitmapData = new BitmapData(4, 4, true, 0x80FF8040);
            var self:Test = this;

            for each (var format:String in formats) {
                var before:int = ctx.totalGPUMemory;
                var tex:Texture = ctx.createTexture(4, 4, format, false);
                trace(format + " GPU bytes: " + (ctx.totalGPUMemory - before));
                attempt(format + " uploadFromBitmapData", function():void {
                    tex.uploadFromBitmapData(bmp);
                });
                attempt(format + " uploadFromBitmapData level 1", function():void {
                    tex.uploadFromBitmapData(new BitmapData(2, 2, true, 0xFF00FF00), 1);
                });
                attempt(format + " uploadFromBitmapData level 2", function():void {
                    tex.uploadFromBitmapData(new BitmapData(1, 1, true, 0xFF00FF00), 2);
                });
                attempt(format + " uploadFromBitmapData level 3", function():void {
                    tex.uploadFromBitmapData(new BitmapData(1, 1, true, 0xFF00FF00), 3);
                });
                var bpp:int = bytesPerPixel[format];
                attempt(format + " uploadFromByteArray", function():void {
                    tex.uploadFromByteArray(filled(16 * bpp), 0);
                });
                attempt(format + " uploadFromByteArray offset", function():void {
                    tex.uploadFromByteArray(filled(16 * bpp + 3), 3);
                });
                attempt(format + " uploadFromByteArray short", function():void {
                    tex.uploadFromByteArray(filled(16 * bpp - 1), 0);
                });
                attempt(format + " uploadFromByteArray level 1", function():void {
                    tex.uploadFromByteArray(filled(4 * bpp), 0, 1);
                });
                tex.dispose();
            }

            // DXT1: red/blue endpoints, 4-colour mode. DXT5: alpha 255/0 + the same colours.
            var dxt1:ByteArray = block([0x00, 0xF8, 0x1F, 0x00, 0xE4, 0xE4, 0xE4, 0xE4]);
            var dxt5:ByteArray = block([0xFF, 0x00, 0x49, 0x92, 0x24, 0x49, 0x92, 0x24, 0x00, 0xF8, 0x1F, 0x00, 0xE4, 0xE4, 0xE4, 0xE4]);

            var compressed:Texture = ctx.createTexture(4, 4, "compressed", false);
            var compressedAlpha:Texture = ctx.createTexture(4, 4, "compressedAlpha", false);
            attempt("DXT1 ATF into compressed", function():void {
                compressed.uploadCompressedTextureFromByteArray(atf(3, 2, false, dxt1), 0);
            });
            attempt("DXT5 ATF into compressedAlpha", function():void {
                compressedAlpha.uploadCompressedTextureFromByteArray(atf(5, 2, false, dxt5), 0);
            });
            attempt("DXT5 ATF into compressed", function():void {
                compressed.uploadCompressedTextureFromByteArray(atf(5, 2, false, dxt5), 0);
            });
            attempt("DXT1 ATF into compressedAlpha", function():void {
                compressedAlpha.uploadCompressedTextureFromByteArray(atf(3, 2, false, dxt1), 0);
            });
            attempt("8x8 ATF into 4x4", function():void {
                compressed.uploadCompressedTextureFromByteArray(atf(3, 3, false, filled(32)), 0);
            });
            attempt("cube ATF into Texture", function():void {
                compressed.uploadCompressedTextureFromByteArray(atf(3, 2, true, dxt1), 0);
            });
            attempt("garbage ATF", function():void {
                compressed.uploadCompressedTextureFromByteArray(filled(64), 0);
            });
            attempt("ATF offset past the end", function():void {
                compressed.uploadCompressedTextureFromByteArray(filled(8), 4);
            });
            attempt("ATF at an offset", function():void {
                var padded:ByteArray = new ByteArray();
                padded.writeByte(1);
                padded.writeByte(2);
                padded.writeBytes(atf(3, 2, false, dxt1));
                compressed.uploadCompressedTextureFromByteArray(padded, 2);
            });

            var cube:CubeTexture = ctx.createCubeTexture(4, "compressed", false);
            attempt("cube ATF into CubeTexture", function():void {
                cube.uploadCompressedTextureFromByteArray(atf(3, 2, true, dxt1), 0);
            });
            attempt("flat ATF into CubeTexture", function():void {
                cube.uploadCompressedTextureFromByteArray(atf(3, 2, false, dxt1), 0);
            });
            attempt("cube uploadFromBitmapData side 5", function():void {
                cube.uploadFromBitmapData(bmp, 5);
            });
            attempt("cube uploadFromByteArray side 2 level 1", function():void {
                cube.uploadFromByteArray(filled(16), 0, 2, 1);
            });

            compressedAlpha.addEventListener("textureReady", function(ev:Event):void {
                trace("textureReady: " + ev.type + " " + (ev.target === compressedAlpha));
            });
            attempt("async DXT5 ATF", function():void {
                compressedAlpha.uploadCompressedTextureFromByteArray(atf(5, 2, false, dxt5), 0, true);
            });
            trace("sync part done");
        }
    }
}
