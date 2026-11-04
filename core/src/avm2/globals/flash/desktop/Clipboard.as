package flash.desktop {
    import flash.errors.IllegalOperationError;

    // Timffle: real implementation of Flash Player's clipboard (the rules are in
    // core/src/avm2/globals/flash/desktop/clipboard.rs). Flash Player, unlike AIR, has
    // only the operating-system clipboard: `generalClipboard` is the one object, `new`
    // throws #2178, `getData()` works only inside an Event.PASTE handler (#2179), and
    // the AIR-only formats (url, bitmap, file list, file promise list) are refused by
    // `setData()` with `false`.
    public class Clipboard {
        private static var _generalClipboard:Clipboard = null;
        // True only while `generalClipboard` makes its one object (the class object is
        // not reachable from the static initializer, so it is made on first use).
        private static var _makingGeneral:Boolean = false;

        public static function get generalClipboard():Clipboard {
            if (_generalClipboard == null) {
                _makingGeneral = true;
                _generalClipboard = new Clipboard();
                _makingGeneral = false;
            }
            return _generalClipboard;
        }

        public function Clipboard() {
            // Only the general clipboard exists in Flash Player; `new Clipboard()`
            // is an error there (it is allowed in AIR, for drag and drop).
            if (!_makingGeneral) {
                throw new IllegalOperationError("Error #2178: The Clipboard.generalClipboard object must be used instead of creating a new Clipboard.", 2178);
            }
        }

        public native function get formats():Array;

        public native function clear():void;

        public native function clearData(format:String):void;

        public native function getData(format:String, transferMode:String = "originalPreferred"):Object;

        public native function hasFormat(format:String):Boolean;

        public native function setData(format:String, data:Object, serializable:Boolean = true):Boolean;

        public native function setDataHandler(format:String, handler:Function, serializable:Boolean = true):Boolean;
    }
}
