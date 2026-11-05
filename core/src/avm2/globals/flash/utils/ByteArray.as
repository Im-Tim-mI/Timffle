package flash.utils {
    [Ruffle(InstanceAllocator)]
    public class ByteArray implements IDataInput2, IDataOutput2 {
        // Timffle: `shareable` is the flag that lets a worker's MessageChannel pass this
        // ByteArray's memory instead of a copy. This player has no Workers
        // (`WorkerDomain.isSupported` is false), so, like Flash Player on a platform without
        // them, the flag only records the setting: it starts false, the setter stores the
        // value (the AVM makes the buffer shareable on the first `true`; nothing is copied
        // on `false` afterwards -- the property simply reads the stored value), and no other
        // behaviour depends on it.
        private var _shareable:Boolean = false;

        [API("684")]
        public function set shareable(shareable:Boolean):void {
            this._shareable = shareable;
        }

        [API("684")]
        public function get shareable():Boolean {
            return this._shareable;
        }

        // Timffle: the AIR 3.4 / Flash Player 11.4 atomic operations for shared byte arrays.
        [API("684")]
        public native function atomicCompareAndSwapIntAt(byteIndex:int, expectedValue:int, newValue:int):int;
        [API("684")]
        public native function atomicCompareAndSwapLength(expectedLength:int, newLength:int):int;

        public static native function get defaultObjectEncoding():uint;
        public static native function set defaultObjectEncoding(encoding:uint):void;

        public native function get bytesAvailable():uint;

        public native function get endian():String;
        public native function set endian(value:String):void;

        public native function get length():uint;
        public native function set length(value:uint):void;

        public native function get objectEncoding():uint;
        public native function set objectEncoding(value:uint):void;

        public native function get position():uint;
        public native function set position(value:uint):void;

        public function ByteArray() {
            // The bytearray's objectEncoding is set in the allocator
        }

        public native function clear():void;

        public function deflate():void {
            this.compress("deflate");
        }

        public native function compress(algorithm:String = CompressionAlgorithm.ZLIB):void;

        public function inflate():void {
            this.uncompress("deflate");
        }

        public native function uncompress(algorithm:String = CompressionAlgorithm.ZLIB):void;

        public native function toString():String;

        public native function readBoolean():Boolean;
        public native function readByte():int;
        public native function readBytes(bytes:ByteArray, offset:uint = 0, length:uint = 0):void;
        public native function readDouble():Number;
        public native function readFloat():Number;
        public native function readInt():int;
        public native function readMultiByte(length:uint, charSet:String):String;
        public native function readObject():*;
        public native function readShort():int;
        public native function readUnsignedByte():uint;
        public native function readUnsignedInt():uint;
        public native function readUnsignedShort():uint;
        public native function readUTF():String;
        public native function readUTFBytes(length:uint):String;

        public native function writeBoolean(value:Boolean):void;
        public native function writeByte(value:int):void;
        public native function writeBytes(bytes:ByteArray, offset:uint = 0, length:uint = 0):void;
        public native function writeDouble(value:Number):void;
        public native function writeFloat(value:Number):void;
        public native function writeInt(value:int):void;
        public native function writeMultiByte(value:String, charSet:String):void;
        public native function writeShort(value:int):void;
        public native function writeUnsignedInt(value:uint):void;
        public native function writeUTF(value:String):void;
        public native function writeUTFBytes(value:String):void;
        public native function writeObject(object:*):void;

        prototype.toJSON = function(k:String):* {
            return "ByteArray";
        };
        prototype.setPropertyIsEnumerable("toJSON", false);
    }
}
