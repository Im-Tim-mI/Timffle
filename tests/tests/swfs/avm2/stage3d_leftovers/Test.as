// Timffle: Stage3D leftovers — mip-chain textures (createTexture with
// streamingLevels, uploadFromBitmapData / uploadFromByteArray at miplevel > 0,
// CubeTexture uploads per side and level), setSamplerStateAt mip filters and
// setRenderToTexture antiAlias. Needs a Context3D, i.e. a GPU; the expected
// output follows the Flash semantics of each call.
package {
    import flash.display.BitmapData;
    import flash.display.MovieClip;
    import flash.display.Stage3D;
    import flash.display3D.Context3D;
    import flash.display3D.Context3DMipFilter;
    import flash.display3D.Context3DTextureFormat;
    import flash.display3D.textures.CubeTexture;
    import flash.display3D.textures.Texture;
    import flash.events.ErrorEvent;
    import flash.events.Event;
    import flash.utils.ByteArray;

    public class Test extends MovieClip {
        public function Test() {
            trace("mip filters: " + Context3DMipFilter.MIPNONE + " " + Context3DMipFilter.MIPNEAREST + " " + Context3DMipFilter.MIPLINEAR);
            var s3d:Stage3D = stage.stage3Ds[0];
            s3d.addEventListener(Event.CONTEXT3D_CREATE, onCreate);
            s3d.addEventListener(ErrorEvent.ERROR, function(e:ErrorEvent):void {
                trace("context3D error");
            });
            s3d.requestContext3D();
        }

        private function onCreate(e:Event):void {
            var ctx:Context3D = Stage3D(e.target).context3D;
            trace("context created");
            ctx.configureBackBuffer(64, 64, 0, true);

            var tex:Texture = ctx.createTexture(8, 8, Context3DTextureFormat.BGRA, false, 2);
            trace("texture with streamingLevels: " + (tex != null));
            tex.uploadFromBitmapData(new BitmapData(8, 8, false, 0xFF0000), 0);
            tex.uploadFromBitmapData(new BitmapData(4, 4, false, 0x00FF00), 1);
            tex.uploadFromBitmapData(new BitmapData(2, 2, false, 0x0000FF), 2);
            tex.uploadFromBitmapData(new BitmapData(1, 1, false, 0xFFFFFF), 3);
            trace("mip uploads: ok");
            try {
                tex.uploadFromBitmapData(new BitmapData(1, 1), 4);
                trace("mip 4: accepted");
            } catch (err:Error) {
                trace("mip 4: " + err.errorID);
            }

            var bytes:ByteArray = new ByteArray();
            for (var i:int = 0; i < 4 * 4 * 4; i++) {
                bytes.writeByte(0x80);
            }
            tex.uploadFromByteArray(bytes, 0, 1);
            trace("byte upload mip 1: ok");

            var cube:CubeTexture = ctx.createCubeTexture(4, Context3DTextureFormat.BGRA, false, 1);
            for (var side:int = 0; side < 6; side++) {
                cube.uploadFromBitmapData(new BitmapData(4, 4, false, 0x123456), side, 0);
                cube.uploadFromBitmapData(new BitmapData(2, 2, false, 0x654321), side, 1);
            }
            cube.uploadFromByteArray(bytes, 0, 2, 0);
            trace("cube uploads: ok");

            ctx.setSamplerStateAt(0, "clamp", "linear", Context3DMipFilter.MIPNONE);
            ctx.setSamplerStateAt(0, "clamp", "linear", Context3DMipFilter.MIPNEAREST);
            ctx.setSamplerStateAt(0, "repeat", "nearest", Context3DMipFilter.MIPLINEAR);
            trace("sampler mip filters: ok");
            try {
                ctx.setSamplerStateAt(0, "clamp", "linear", "bogus");
                trace("bad mipfilter: accepted");
            } catch (err:Error) {
                trace("bad mipfilter: " + err.errorID);
            }

            var target:Texture = ctx.createTexture(16, 16, Context3DTextureFormat.BGRA, true);
            ctx.setRenderToTexture(target, true, 4);
            ctx.clear(0, 0, 1, 1);
            ctx.setRenderToBackBuffer();
            trace("render to texture with antiAlias 4: ok");
        }
    }
}
