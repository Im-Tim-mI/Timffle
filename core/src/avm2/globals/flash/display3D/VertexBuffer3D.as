package flash.display3D {
    import flash.utils.ByteArray;

    [API("674")]
    [Ruffle(Abstract)]
    public final class VertexBuffer3D {
        public native function uploadFromByteArray(data:ByteArray, byteArrayOffset:int, startVertex:int, numVertices:int):void
        public native function uploadFromVector(data:Vector.<Number>, startVertex:int, numVertices:int):void

        // Timffle: releases the GPU resource; later use throws Error #3694.
        public native function dispose():void;
    }
}
