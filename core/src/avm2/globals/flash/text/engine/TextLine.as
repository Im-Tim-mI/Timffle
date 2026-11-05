package flash.text.engine {
    import flash.display.DisplayObject;
    import flash.display.DisplayObjectContainer;
    import flash.errors.IllegalOperationError;
    import flash.events.EventDispatcher;
    import flash.geom.Rectangle;
    import flash.ui.ContextMenu;

    // FIXME: None of the DisplayObjectContainer methods actually work on
    // the TextLine class in Ruffle, despite the methods working fine in FP-
    // however, it's unlikely that SWFs will actually attempt to add children
    // to a TextLine.
    [Ruffle(Abstract)]
    [API("662")]
    public final class TextLine extends DisplayObjectContainer {
        public static const MAX_LINE_WIDTH:int = 1000000;

        public var userData;

        public native function get rawTextLength():int;

        public native function get textBlockBeginIndex():int;

        public native function get specifiedWidth():Number;

        public native function get textBlock():TextBlock;

        public native function get ascent():Number;

        // Timffle: the layout places graphics as inline text (no inline box
        // yet), so the total extents equal the text extents.
        [API("670")]
        public function get totalAscent():Number {
            return this.ascent;
        }

        public native function get descent():Number;

        [API("670")]
        public function get totalDescent():Number {
            return this.descent;
        }

        [API("670")]
        public function get totalHeight():Number {
            return this.totalAscent + this.totalDescent;
        }

        // Timffle: the line's text is laid out without justification, so the
        // unjustified width is the measured text width.
        public function get unjustifiedTextWidth():Number {
            return this.textWidth;
        }

        public native function get textWidth():Number;
        public native function get textHeight():Number;

        public native function get validity():String;
        public native function set validity(value:String):void;

        // Timffle: true when a GraphicElement's U+FDEF placeholder falls into
        // this line's character range.
        public function get hasGraphicElement():Boolean {
            for (var i:int = 0; i < this.atomCount; i++) {
                if (this.getAtomGraphic(i) != null) {
                    return true;
                }
            }
            return false;
        }

        public native function get atomCount():int;

        public native function get previousLine():TextLine;
        public native function get nextLine():TextLine;

        // Timffle: positions relative to the roman baseline (the line's
        // y = 0 when TextBlock.baselineZero is "roman", as it is here), derived
        // from the laid-out ascent/descent of the line.
        public function getBaselinePosition(baseline:String):Number {
            switch (baseline) {
                case TextBaseline.ROMAN:
                    return 0;
                case TextBaseline.ASCENT:
                case TextBaseline.IDEOGRAPHIC_TOP:
                    return -this.ascent;
                case TextBaseline.DESCENT:
                case TextBaseline.IDEOGRAPHIC_BOTTOM:
                    return this.descent;
                case TextBaseline.IDEOGRAPHIC_CENTER:
                    return (this.descent - this.ascent) / 2;
                default:
                    throw new ArgumentError("Error #2008: Parameter baseline must be one of the accepted values.", 2008);
            }
        }

        public native function get hasTabs():Boolean;

        public native function getAtomIndexAtPoint(stageX:Number, stageY:Number):int;

        public native function getAtomIndexAtCharIndex(charIndex:int):int;

        // Timffle: the resolved UAX #9 embedding level of the atom, from the
        // bidirectional resolution of the line with TextBlock.bidiLevel as
        // the paragraph level.
        public native function getAtomBidiLevel(index:int):int;

        public native function getAtomBounds(index:int):Rectangle;

        public native function getAtomCenter(index:int):Number;

        public function getAtomGraphic(index:int):DisplayObject {
            var element:ContentElement = this.elementAtAtom(index);
            if (element is GraphicElement) {
                return GraphicElement(element).graphic;
            }
            return null;
        }

        public native function getAtomTextBlockBeginIndex(index:int):int;

        public native function getAtomTextBlockEndIndex(index:int):int;

        public function getAtomTextRotation(index:int):String {
            var element:ContentElement = this.elementAtAtom(index);
            if (element == null) {
                return TextRotation.ROTATE_0;
            }
            var rotation:String = element.textRotation;
            if (rotation == TextRotation.AUTO) {
                return TextRotation.ROTATE_0;
            }
            return rotation;
        }

        public native function getAtomWordBoundaryOnLeft(index:int):Boolean;

        // This function does nothing in Flash Player 32
        public function flushAtomData():void { }

        // Timffle: mirror regions — one per content element of this line that
        // has an eventMirror, covering the atoms the element contributes.
        public function get mirrorRegions():Vector.<TextLineMirrorRegion> {
            var regions:Vector.<TextLineMirrorRegion> = new Vector.<TextLineMirrorRegion>();
            var count:int = this.atomCount;
            var current:TextLineMirrorRegion = null;
            var currentElement:ContentElement = null;
            for (var i:int = 0; i < count; i++) {
                var element:ContentElement = this.elementAtAtom(i);
                var mirror:ContentElement = element;
                while (mirror != null && mirror.eventMirror == null) {
                    mirror = mirror.groupElement;
                }
                if (mirror == null) {
                    currentElement = null;
                    continue;
                }
                var bounds:Rectangle = this.getAtomBounds(i);
                if (mirror === currentElement) {
                    current._bounds = current._bounds.union(bounds);
                    continue;
                }
                var region:TextLineMirrorRegion = TextLineMirrorRegion.create();
                region._bounds = bounds;
                region._element = mirror;
                region._mirror = mirror.eventMirror;
                region._textLine = this;
                region._previousRegion = current;
                if (current != null) {
                    current._nextRegion = region;
                }
                regions.push(region);
                current = region;
                currentElement = mirror;
            }
            return regions.length > 0 ? regions : null;
        }

        public function getMirrorRegion(mirror:EventDispatcher):TextLineMirrorRegion {
            var regions:Vector.<TextLineMirrorRegion> = this.mirrorRegions;
            if (regions == null) {
                return null;
            }
            for each (var region:TextLineMirrorRegion in regions) {
                if (region.mirror === mirror) {
                    return region;
                }
            }
            return null;
        }

        // Timffle: Flash Player's dump() format is undocumented; this prints
        // the line's measurements and atoms as XML.
        public function dump():String {
            var out:String = "<TextLine textBlockBeginIndex=\"" + this.textBlockBeginIndex
                + "\" rawTextLength=\"" + this.rawTextLength
                + "\" specifiedWidth=\"" + this.specifiedWidth
                + "\" textWidth=\"" + this.textWidth
                + "\" ascent=\"" + this.ascent
                + "\" descent=\"" + this.descent
                + "\" validity=\"" + this.validity + "\">\n";
            var count:int = this.atomCount;
            for (var i:int = 0; i < count; i++) {
                var b:Rectangle = this.getAtomBounds(i);
                out += "  <Atom index=\"" + i + "\" begin=\"" + this.getAtomTextBlockBeginIndex(i)
                    + "\" end=\"" + this.getAtomTextBlockEndIndex(i)
                    + "\" x=\"" + b.x + "\" width=\"" + b.width + "\"/>\n";
            }
            return out + "</TextLine>";
        }

        private function checkAtomIndex(index:int):void {
            if (index < 0 || index >= this.atomCount) {
                throw new RangeError("Error #2006: The supplied index is out of bounds.", 2006);
            }
        }

        private function elementAtAtom(index:int):ContentElement {
            this.checkAtomIndex(index);
            var block:TextBlock = this.textBlock;
            if (block == null || block.content == null) {
                return null;
            }
            return block.content.leafAtCharIndex(this.getAtomTextBlockBeginIndex(index));
        }

        // Overrides

        override public function set contextMenu(cm:ContextMenu):void {
            Error.throwError(IllegalOperationError, 2181);
        }

        override public function set focusRect(value:Object):void {
            Error.throwError(IllegalOperationError, 2181);
        }

        override public function set tabChildren(value:Boolean):void {
            Error.throwError(IllegalOperationError, 2181);
        }

        override public function set tabEnabled(value:Boolean):void {
            Error.throwError(IllegalOperationError, 2181);
        }

        override public function set tabIndex(index:int):void {
            Error.throwError(IllegalOperationError, 2181);
        }

        // End of overrides
    }
}
