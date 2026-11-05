package flash.display3D {
    import flash.utils.ByteArray;

    [API("674")]
    [Ruffle(Abstract)]
    public final class Program3D {
        public native function upload(vertexProgram:ByteArray, fragmentProgram:ByteArray):void;

        // Timffle: releases the GPU resource; later use throws Error #3694.
        public native function dispose():void;
    }
}
