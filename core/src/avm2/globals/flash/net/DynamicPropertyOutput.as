package flash.net {
    // Timffle: the IDynamicPropertyOutput the AMF serializer hands to
    // `ObjectEncoding.dynamicPropertyWriter.writeDynamicProperties()` (Flash Player names this
    // class flash.net::DynamicPropertyOutput). Properties are serialized in the order they are
    // written, duplicates included; writes after the callback returned are ignored.
    public final class DynamicPropertyOutput implements IDynamicPropertyOutput {
        // [name, value, name, value, ...]
        [Ruffle(NativeAccessible)]
        private var _entries:Array = [];

        [Ruffle(NativeAccessible)]
        private var _open:Boolean = true;

        public function DynamicPropertyOutput() {}

        public function writeDynamicProperty(name:String, value:*):void {
            if (name == null) {
                throw new TypeError("Error #2007: Parameter name must be non-null.", 2007);
            }
            if (!this._open) {
                return;
            }
            this._entries.push(name, value);
        }
    }
}
