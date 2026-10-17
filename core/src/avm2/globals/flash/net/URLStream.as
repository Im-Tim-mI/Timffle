package flash.net {
    import flash.errors.IOError;
    import flash.events.EventDispatcher;
    import flash.utils.ByteArray;
    import flash.utils.Endian;
    import flash.utils.IDataInput;

    public class URLStream extends EventDispatcher implements IDataInput {
        // Data received so far; its position is the read position, so
        // `bytesAvailable` is whatever has arrived but not been read yet.
        // It is filled in chunk by chunk by `crate::loader::load_url_stream`,
        // which also dispatches the open/progress/httpStatus/complete/ioError events.
        // `null` while no stream is open: before the first `load()` and after `close()`.
        [Ruffle(NativeAccessible)]
        private var _buffer:ByteArray = null;

        private var _endian:String = Endian.BIG_ENDIAN;
        private var _objectEncoding:uint = 3;
        private var _connected:Boolean = false;

        // Bumped by `load()` and `close()`. A download only touches this object
        // while its generation is still current, so a closed or replaced
        // download delivers no further data or events.
        [Ruffle(NativeAccessible)]
        private var _generation:uint = 0;

        public function URLStream() {
            super();
        }

        public function load(request:URLRequest):void {
            this._generation++;
            this._buffer = new ByteArray();
            this._buffer.endian = this._endian;
            this._buffer.objectEncoding = this._objectEncoding;
            this._connected = true;
            this._load(request, this._generation);
        }

        private native function _load(request:URLRequest, generation:uint):void;

        // Flash Player's HTTP streams are not seekable. These FP 11.4 APIs
        // accept calls but neither seek nor stop the download (unlike close).
        [API("682")]
        public function stop():void {}

        [API("682")]
        public function get position():Number { return 0; }
        [API("682")]
        public function set position(value:Number):void {}
        [API("682")]
        public function get length():Number { return 0; }

        public function close():void {
            if (!this._connected) {
                throw new IOError("Error #2029: This URLStream object does not have a stream opened.", 2029);
            }
            this._generation++;
            this._buffer = null;
            this._connected = false;
        }

        // Every read requires an open stream, like in Flash.
        private function get buffer():ByteArray {
            if (this._buffer == null) {
                throw new IOError("Error #2029: This URLStream object does not have a stream opened.", 2029);
            }
            return this._buffer;
        }

        public function get bytesAvailable():uint {
            return this.buffer.bytesAvailable;
        }

        public function get connected():Boolean {
            return this._connected;
        }

        public function get endian():String {
            return this._endian;
        }

        public function set endian(value:String):void {
            if (value === Endian.BIG_ENDIAN || value === Endian.LITTLE_ENDIAN) {
                this._endian = value;
                if (this._buffer) {
                    this._buffer.endian = value;
                }
            } else {
                throw new ArgumentError("Error #2008: Parameter endian must be one of the accepted values.", 2008);
            }
        }

        public function get objectEncoding():uint {
            return this._objectEncoding;
        }

        public function set objectEncoding(value:uint):void {
            this._objectEncoding = value;
            if (this._buffer) {
                this._buffer.objectEncoding = value;
            }
        }

        public function readBoolean():Boolean {
            return this.buffer.readBoolean();
        }

        public function readByte():int {
            return this.buffer.readByte();
        }

        public function readBytes(bytes:ByteArray, offset:uint = 0, length:uint = 0):void {
            this.buffer.readBytes(bytes, offset, length);
        }

        public function readDouble():Number {
            return this.buffer.readDouble();
        }

        public function readFloat():Number {
            return this.buffer.readFloat();
        }

        public function readInt():int {
            return this.buffer.readInt();
        }

        public function readMultiByte(length:uint, charSet:String):String {
            return this.buffer.readMultiByte(length, charSet);
        }

        public function readObject():* {
            return this.buffer.readObject();
        }

        public function readShort():int {
            return this.buffer.readShort();
        }

        public function readUnsignedByte():uint {
            return this.buffer.readUnsignedByte();
        }

        public function readUnsignedInt():uint {
            return this.buffer.readUnsignedInt();
        }

        public function readUnsignedShort():uint {
            return this.buffer.readUnsignedShort();
        }

        public function readUTF():String {
            return this.buffer.readUTF();
        }

        public function readUTFBytes(length:uint):String {
            return this.buffer.readUTFBytes(length);
        }
    }
}
