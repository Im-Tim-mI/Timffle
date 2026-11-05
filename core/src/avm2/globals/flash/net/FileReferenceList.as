package flash.net {
    import flash.events.EventDispatcher;

    public class FileReferenceList extends EventDispatcher {
        // Timffle: filled by the multi-file dialog (one FileReference per selected file).
        [Ruffle(NativeAccessible)]
        private var _fileList:Array;

        public function FileReferenceList() {}

        public function get fileList():Array {
            return this._fileList;
        }

        // Timffle: a real multi-selection dialog; `select` with `fileList` set, or `cancel`.
        public native function browse(typeFilter:Array = null):Boolean;
    }
}
