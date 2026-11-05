package flash.text {
    // Timffle: real implementation over the static texts of one container
    // (see core/src/avm2/globals/flash/text/text_snapshot.rs). A snapshot made
    // with `new TextSnapshot()` has no text; `DisplayObjectContainer.textSnapshot`
    // fills one in natively.
    [Ruffle(InstanceAllocator)]
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
