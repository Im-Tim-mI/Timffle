// Timffle: Context3D leftovers — configureBackBuffer wantsBestResolution*,
// drawToBitmapData (back-buffer readback, srcRect/destPoint, Error #3802,
// disposed targets) and setRenderToTexture colorOutputIndex (multiple render
// targets: range #3770, profile #3779, mismatched targets #3761, fragment
// programs writing oc0..oc3, oc4 #3760). Needs a Context3D, i.e. a GPU; the
// expected output follows the Flash semantics of each call (the test harness
// runs with a viewport scale factor of 1, so the best-resolution back buffer
// has the requested size).
package {
    import flash.display.BitmapData;
    import flash.display.MovieClip;
    import flash.display.Stage3D;
    import flash.display3D.Context3D;
    import flash.display3D.Context3DProgramType;
    import flash.display3D.Context3DTextureFormat;
    import flash.display3D.Context3DVertexBufferFormat;
    import flash.display3D.IndexBuffer3D;
    import flash.display3D.Program3D;
    import flash.display3D.VertexBuffer3D;
    import flash.display3D.textures.Texture;
    import flash.events.ErrorEvent;
    import flash.events.Event;
    import flash.geom.Point;
    import flash.geom.Rectangle;

    public class Test extends MovieClip {
        public function Test() {
            var s3d:Stage3D = stage.stage3Ds[0];
            s3d.addEventListener(Event.CONTEXT3D_CREATE, onCreate);
            s3d.addEventListener(ErrorEvent.ERROR, function(e:ErrorEvent):void {
                trace("context3D error");
            });
            s3d.requestContext3D("auto", "standard");
        }

        private function errorId(f:Function):String {
            try {
                f();
                return "ok";
            } catch (err:Error) {
                return "" + err.errorID;
            }
        }

        private function onCreate(e:Event):void {
            var ctx:Context3D = Stage3D(e.target).context3D;
            trace("context created: " + ctx.profile);

            ctx.configureBackBuffer(64, 64, 0, true);
            trace("configureBackBuffer: " + ctx.backBufferWidth + "x" + ctx.backBufferHeight);
            ctx.configureBackBuffer(64, 64, 0, true, true, true);
            trace("configureBackBuffer best resolution: " + ctx.backBufferWidth + "x" + ctx.backBufferHeight);

            // drawToBitmapData reads the back buffer (what was drawn since the last present()).
            var bmp:BitmapData = new BitmapData(64, 64, false, 0);
            ctx.clear(1, 0, 0, 1);
            ctx.drawToBitmapData(bmp);
            trace("drawToBitmapData: " + bmp.getPixel(10, 10).toString(16));

            var bmp2:BitmapData = new BitmapData(32, 32, false, 0);
            ctx.clear(0, 0, 1, 1);
            ctx.drawToBitmapData(bmp2, new Rectangle(0, 0, 16, 16), new Point(8, 8));
            trace("drawToBitmapData srcRect/destPoint: " + bmp2.getPixel(4, 4).toString(16) + " " + bmp2.getPixel(12, 12).toString(16) + " " + bmp2.getPixel(28, 28).toString(16));

            trace("drawToBitmapData srcRect out of bounds: " + errorId(function():void {
                ctx.drawToBitmapData(bmp2, new Rectangle(0, 0, 100, 100));
            }));
            trace("drawToBitmapData destPoint out of bounds: " + errorId(function():void {
                ctx.drawToBitmapData(bmp2, null, new Point(32, 0));
            }));
            trace("drawToBitmapData NaN: " + errorId(function():void {
                ctx.drawToBitmapData(bmp2, new Rectangle(NaN, 0, 1, 1));
            }));
            // Larger buffer than bitmap: clipped, not scaled.
            trace("drawToBitmapData clipped: " + errorId(function():void {
                ctx.drawToBitmapData(bmp2);
            }) + " " + bmp2.getPixel(31, 31).toString(16));
            bmp.dispose();
            trace("drawToBitmapData disposed bitmap: " + errorId(function():void {
                ctx.drawToBitmapData(bmp);
            }));

            // Multiple render targets.
            var t0:Texture = ctx.createTexture(16, 16, Context3DTextureFormat.BGRA, true);
            var t1:Texture = ctx.createTexture(16, 16, Context3DTextureFormat.BGRA, true);
            var t2:Texture = ctx.createTexture(8, 8, Context3DTextureFormat.BGRA, true);
            var t3:Texture = ctx.createTexture(16, 16, Context3DTextureFormat.RGBA_HALF_FLOAT, true);
            trace("setRenderToTexture colorOutputIndex 4: " + errorId(function():void {
                ctx.setRenderToTexture(t0, false, 0, 0, 4);
            }));
            trace("setRenderToTexture colorOutputIndex 0/1: " + errorId(function():void {
                ctx.setRenderToTexture(t0, true, 0, 0, 0);
                ctx.setRenderToTexture(t1, false, 0, 0, 1);
            }));
            trace("setRenderToTexture colorOutputIndex 2 size mismatch: " + errorId(function():void {
                ctx.setRenderToTexture(t2, false, 0, 0, 2);
            }));
            trace("setRenderToTexture colorOutputIndex 2 bit depth mismatch: " + errorId(function():void {
                ctx.setRenderToTexture(t3, false, 0, 0, 2);
            }));

            var vertexAssembly:AGALMiniAssembler = new AGALMiniAssembler();
            var fragmentAssembly:AGALMiniAssembler = new AGALMiniAssembler();
            vertexAssembly.assemble(Context3DProgramType.VERTEX, "mov op, va0\nmov v0, va1", 2, false);
            fragmentAssembly.assemble(Context3DProgramType.FRAGMENT, "mov oc0, v0\nmov oc1, v0.yxzw", 2, false);
            var program:Program3D = ctx.createProgram();
            trace("program oc0/oc1: " + errorId(function():void {
                program.upload(vertexAssembly.agalcode, fragmentAssembly.agalcode);
            }));

            var indices:IndexBuffer3D = ctx.createIndexBuffer(3);
            indices.uploadFromVector(Vector.<uint>([0, 1, 2]), 0, 3);
            var vertices:VertexBuffer3D = ctx.createVertexBuffer(3, 8);
            vertices.uploadFromVector(Vector.<Number>([
                -1, -1, 0, 1, 1, 0, 0, 1,
                1, -1, 0, 1, 0, 1, 0, 1,
                0, 1, 0, 1, 0, 0, 1, 1
            ]), 0, 3);
            ctx.setVertexBufferAt(0, vertices, 0, Context3DVertexBufferFormat.FLOAT_4);
            ctx.setVertexBufferAt(1, vertices, 4, Context3DVertexBufferFormat.FLOAT_4);
            ctx.setProgram(program);
            trace("mrt draw: " + errorId(function():void {
                ctx.clear(0, 0, 0, 1);
                ctx.drawTriangles(indices, 0, 1);
                ctx.setRenderToBackBuffer();
            }));

            var badFragment:AGALMiniAssembler = new AGALMiniAssembler();
            badFragment.assemble(Context3DProgramType.FRAGMENT, "mov oc4, v0", 2, true);
            trace("program oc4: " + errorId(function():void {
                ctx.createProgram().upload(vertexAssembly.agalcode, badFragment.agalcode);
            }));

            ctx.present();
            ctx.dispose(false);
            trace("drawToBitmapData after dispose: " + errorId(function():void {
                ctx.drawToBitmapData(bmp2);
            }));
        }
    }
}
