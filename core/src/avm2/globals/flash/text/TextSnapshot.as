package flash.text {
    // Timffle: real implementation over the static texts of one container
    // (see core/src/avm2/globals/flash/text/text_snapshot.rs). Snapshots come
    // only from `DisplayObjectContainer.textSnapshot`, which makes them
    // natively; `new TextSnapshot()` is #2012 before any constructor runs, as
    // in Flash Player.
    [Ruffle(Abstract)]
    public class TextSnapshot {
        public native function get charCount():int;

        public native function findText(beginIndex:int, textToFind:String, caseSensitive:Boolean):int;

        public native function getSelected(beginIndex:int, endIndex:int):Boolean;

        public native function getSelectedText(includeLineEndings:Boolean = false):String;

        public native function getText(beginIndex:int, endIndex:int, includeLineEndings:Boolean = false):String;

        public native function getTextRunInfo(beginIndex:int, endIndex:int):Array;

        public native function hitTestTextNearPos(x:Number, y:Number, maxDistance:Number = 0):Number;

        public native function setSelectColor(hexColor:uint = 0xFFFF00):void;

        public native function setSelected(beginIndex:int, endIndex:int, select:Boolean):void;
    }
}
