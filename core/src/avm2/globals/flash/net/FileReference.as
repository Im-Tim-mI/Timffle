package flash.net {
    import flash.events.EventDispatcher;
    import flash.utils.ByteArray;
    import __ruffle__.stub_method;

    [Ruffle(InstanceAllocator)]
    public class FileReference extends EventDispatcher {
        public function FileReference() {}

        public native function get creationDate():Date;

        public function get creator():String {
            // This was macOS (pre OS X) only. (Deprecated)
            return null;
        }

        public native function get data():ByteArray;

        // AIR 1.0
        [API("661")]
        public function get extension():String {
            // The file extension, excluding the dot.
            return this.type ? this.type.slice(1) : null;
        }

        public native function get modificationDate():Date;

        public native function get name():String;

        public native function get size():Number;

        // File extension, including the dot. (Deprecated)
        public native function get type():String;

        public native function browse(typeFilter:Array = null):Boolean;

        // Timffle: stops a running download or upload from reporting (no `cancel` event, as
        // documented); harmless on an idle object.
        public native function cancel():void;

        // Timffle: the save dialog first (`select`, or `cancel`), then the request
        // (`open`, `progress`, `complete`, or `ioError`). Flash Player 32: a null request
        // or url is #2007, a dialog that is already open is #2041.
        public native function download(request:URLRequest, defaultFileName:String = null):void;

        public native function load():void;

        [API("681")]
        public function requestPermission():void {
            stub_method("flash.net.FileReference", "requestPermission");
        }

        public function save(data:*, defaultFileName:String = null):void {
            if (data == null) {
                // Yes, this is the error that Flash throws
                throw new ArgumentError("data");
            }

            // Convert the data to a ByteArray
            var byteArray:ByteArray = new ByteArray();
            if (data is ByteArray) {
                byteArray.writeBytes(data);
            } else if (data is XML) {
                byteArray.writeUTFBytes(data.toXMLString());
            } else {
                byteArray.writeUTFBytes(data);
            }

            if (defaultFileName == null) {
                defaultFileName = "";
            }

            this.saveInternal(byteArray, defaultFileName);
        }

        // NOTE: The bytearray passed to this function will be cleared
        private native function saveInternal(data:ByteArray, defaultFileName:String):void;

        // Timffle: a multipart/form-data POST of the selected file (`open`, `progress`,
        // `complete`, `uploadCompleteData` with the server's answer; `httpStatus` + `ioError`
        // on failure). Flash Player 32 error order: null request #2007, null field name #2007,
        // empty field name #2085, nothing selected #2037, null url #2007.
        public native function upload(
            request:URLRequest,
            uploadDataFieldName:String = "Filedata",
            testUpload:Boolean = false
        ):void;

        [API("681")]
        public function uploadUnencoded(request:URLRequest):void {
            stub_method("flash.net.FileReference", "uploadUnencoded");
        }
    }
}
