// Timffle: Stage3D API surface that does not need a GPU context.
// (Context3D/IndexBuffer3D/VertexBuffer3D/Program3D/Texture instances can only
// come from a live Context3D, so their dispose()/#3694 paths are exercised
// through the context3DCreate listener below only when a renderer is present.)
package {
    import flash.display.MovieClip;
    import flash.display.Stage3D;
    import flash.display3D.Context3D;
    import flash.display3D.textures.TextureBase;
    import flash.display3D.textures.VideoTexture;
    import flash.events.Event;

    public class Test extends MovieClip {
        public function Test() {
            trace("Context3D.supportsVideoTexture: " + Context3D.supportsVideoTexture);

            try {
                new VideoTexture();
                trace("new VideoTexture() succeeded");
            } catch (e:Error) {
                trace("new VideoTexture(): " + e.errorID);
            }

            var tb:TextureBase = new TextureBase();
            tb.dispose();
            tb.dispose();
            trace("TextureBase.dispose twice: ok");

            trace("stage3Ds: " + stage.stage3Ds.length);
            trace("context3D before request: " + stage.stage3Ds[0].context3D);
        }
    }
}
