package flash.net {
    import flash.events.EventDispatcher;

    public class FileReferenceList extends EventDispatcher {
        // Timffle: null until the first browse(), an empty Array while the dialog is open or
        // after cancel, one FileReference per selected file after select.
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
