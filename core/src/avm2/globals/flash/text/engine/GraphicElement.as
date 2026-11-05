package flash.text.engine {
    import flash.display.DisplayObject;
    import flash.events.EventDispatcher;

    // Timffle: `graphic`, `elementWidth` and `elementHeight` are stored on the
    // element (natives) and the graphic occupies one U+FDEF character in the
    // block's raw text, as in Flash Player. The layout does not yet reserve an
    // inline box of elementWidth x elementHeight for it.
    [API("662")]
    public final class GraphicElement extends ContentElement {
        public function GraphicElement(
            graphic:DisplayObject = null,
            elementWidth:Number = 15.0,
            elementHeight:Number = 15.0,
            elementFormat:ElementFormat = null,
            eventMirror:EventDispatcher = null,
            textRotation:String = "rotate0"
        ) {
            super(elementFormat, eventMirror, textRotation);

            this.init();
            this.graphic = graphic;
            this.elementWidth = elementWidth;
            this.elementHeight = elementHeight;
        }

        private native function init():void;

        public native function get elementHeight():Number;
        public native function set elementHeight(value:Number):void;

        public native function get elementWidth():Number;
        public native function set elementWidth(value:Number):void;

        public native function get graphic():DisplayObject;
        public native function set graphic(value:DisplayObject):void;
    }
}
