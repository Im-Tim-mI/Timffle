package flash.text {
    import flash.display.InteractiveObject;
    import flash.display.DisplayObject;
    import flash.geom.Rectangle;

    [Ruffle(InstanceAllocator)]
    public class TextField extends InteractiveObject {
        public native function get alwaysShowSelection():Boolean;
        public native function set alwaysShowSelection(value:Boolean):void;

        public native function get autoSize():String;
        public native function set autoSize(value:String):void;

        public native function get background():Boolean;
        public native function set background(value:Boolean):void;

        public native function get backgroundColor():uint;
        public native function set backgroundColor(value:uint):void;

        public native function get border():Boolean;
        public native function set border(value:Boolean):void;

        public native function get borderColor():uint;
        public native function set borderColor(value:uint):void;

        public native function get bottomScrollV():int;

        public native function get condenseWhite():Boolean
        public native function set condenseWhite(value:Boolean):void

        public native function get defaultTextFormat():TextFormat;
        public native function set defaultTextFormat(value:TextFormat):void;

        public native function get displayAsPassword():Boolean;
        public native function set displayAsPassword(value:Boolean):void;

        public native function get embedFonts():Boolean;
        public native function set embedFonts(value:Boolean):void;

        public native function get htmlText():String;
        public native function set htmlText(value:String):void;

        public native function get length():int;

        public native function get maxScrollH():int;

        public native function get maxScrollV():int;

        public native function get maxChars():int;
        public native function set maxChars(value:int):void;

        public native function get mouseWheelEnabled():Boolean
        public native function set mouseWheelEnabled(value:Boolean):void

        public native function get multiline():Boolean;
        public native function set multiline(value:Boolean):void;

        public native function get restrict():String;
        public native function set restrict(value:String):void;

        public native function get scrollH():int;
        public native function set scrollH(value:int):void;

        public native function get scrollV():int;
        public native function set scrollV(value:int):void;

        public native function get selectable():Boolean;
        public native function set selectable(value:Boolean):void;

        public native function get styleSheet():StyleSheet;
        public native function set styleSheet(value:StyleSheet):void;

        public native function get text():String;
        public native function set text(value:String):void;

        public native function get textColor():uint;
        public native function set textColor(value:uint):void;

        public native function get textHeight():Number;

        public native function get textWidth():Number;

        public native function get type():String;
        public native function set type(value:String):void;

        // Timffle: when true, copy/cut also puts the selection's HTML on the
        // clipboard (`air:html`) and paste reads it back with its formatting
        // (see `EditText::text_control_input`).
        public native function get useRichTextClipboard():Boolean;
        public native function set useRichTextClipboard(value:Boolean):void;

        public native function get wordWrap():Boolean;
        public native function set wordWrap(value:Boolean):void;

        public native function get antiAliasType():String;
        public native function set antiAliasType(value:String):void;

        public native function get gridFitType():String;
        public native function set gridFitType(value:String):void;

        public native function get thickness():Number;
        public native function set thickness(value:Number):void;

        public native function get sharpness():Number;
        public native function set sharpness(value:Number):void;

        public native function get numLines():int;

        public native function get caretIndex():int;

        public native function get selectionBeginIndex():int;
        public native function get selectionEndIndex():int;

        public native function appendText(text:String):void;
        public native function getLineMetrics(lineIndex:int):TextLineMetrics;
        public native function getTextFormat(beginIndex:int = -1, endIndex:int = -1):TextFormat;
        public native function setTextFormat(format:TextFormat, beginIndex:int = -1, endIndex:int = -1):void;
        public native function replaceSelectedText(value:String):void;
        public native function replaceText(beginIndex:int, endIndex:int, newText:String):void;
        public native function setSelection(beginIndex:int, endIndex:int):void;
        public native function getTextRuns():Array;

        public native function get selectedText():String;

        // Timffle: the undocumented rich-text trio playerglobal declares.
        // `getRawText` is the plain text, `getXMLText` the Flash HTML
        // (`<TEXTFORMAT>`/`<P>`/`<FONT>`) of a character range, and
        // `insertXMLText` replaces a range with such HTML, keeping its formatting.
        public native function getRawText():String;
        public native function getXMLText(beginIndex:int = 0, endIndex:int = 2147483647):String;
        public native function insertXMLText(beginIndex:int, endIndex:int, richText:String, pasting:Boolean = false):void;

        public native function getCharIndexAtPoint(x:Number, y:Number):int;

        public native function getLineLength(lineIndex:int):int;

        public native function getLineText(lineIndex:int):String;

        public native function getLineOffset(lineIndex:int):int;

        public native function getCharBoundaries(charIndex:int):Rectangle;

        public native function getFirstCharInParagraph(charIndex:int):int;

        // Timffle: this player parses `<img>` tags (src, id, size, align...) but
        // does not load or lay out the picture, so no Loader exists for it; Flash
        // returns null when no `<img>` with that id exists, and that is what the
        // caller sees here.
        public function getImageReference(id:String):DisplayObject {
            return null;
        }

        public native function getLineIndexAtPoint(x:Number, y:Number):int;

        public native function getLineIndexOfChar(charIndex:int):int;

        public native function getParagraphLength(charIndex:int):int;

        // Timffle: true only for an embedded (`FontType.EMBEDDED`) font of that
        // name and style, registered with `Font.registerFont` or defined in
        // the calling SWF; an unknown `fontStyle` is `ArgumentError #2008`.
        public static native function isFontCompatible(fontName:String, fontStyle:String):Boolean;

        // Timffle: read-only in Flash Player. "selection" exists only on mobile
        // (chosen from the built-in context menu); on desktop the mode is always
        // "normal", which is what this player has.
        [API("670")]
        public function get textInteractionMode():String {
            return TextInteractionMode.NORMAL;
        }
    }
}
