package flash.display3D.textures {
    import flash.events.EventDispatcher;

    [API("674")]
    public class TextureBase extends EventDispatcher {
        // Timffle: releases the GPU texture; later use throws Error #3694.
        public native function dispose():void;
    }
}
