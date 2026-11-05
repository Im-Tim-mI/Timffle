package flash.display3D {
    import flash.utils.ByteArray;

    [API("674")]
    [Ruffle(Abstract)]
    public final class IndexBuffer3D {
        public native function uploadFromByteArray(data:ByteArray, byteArrayOffset:int, startOffset:int, count:int):void;
        public native function uploadFromVector(data:Vector.<uint>, startOffset:int, count:int):void;

        // Timffle: releases the GPU resource; later use throws Error #3694.
        public native function dispose():void;
    }
}
