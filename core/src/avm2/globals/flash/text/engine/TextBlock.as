package flash.text.engine {
    [API("662")]
    [Ruffle(InstanceAllocator)]
    public final class TextBlock {
        public var userData;

        public function TextBlock(
            content:ContentElement = null,
            tabStops:Vector.<TabStop> = null,
            textJustifier:TextJustifier = null,
            lineRotation:String = "rotate0",
            baselineZero:String = "roman",
            bidiLevel:int = 0,
            applyNonLinearFontScaling:Boolean = true,
            baselineFontDescription:FontDescription = null,
            baselineFontSize:Number = 12
        ) {
            // The order of setting these properties matters- if lineRotation
            // is null/invalid, the rest won't be set because it will throw an error
            if (content) {
                this.content = content;
            }
            if (tabStops) {
                this.tabStops = tabStops;
            }
            if (textJustifier) {
                this.textJustifier = textJustifier;
            } else {
                // This should create a new TextJustifier with locale "en", but we don't actually support creating TextJustifiers yet.
                this.textJustifier = new SpaceJustifier();
            }

            this.lineRotation = lineRotation;

            if (baselineZero) {
                this.baselineZero = baselineZero;
            }
            if (baselineFontDescription) {
                this.baselineFontDescription = baselineFontDescription;
                this.baselineFontSize = baselineFontSize;
            }
            this.applyNonLinearFontScaling = applyNonLinearFontScaling;
        }

        public native function get applyNonLinearFontScaling():Boolean;
        public native function set applyNonLinearFontScaling(value:Boolean):void;

        public native function get baselineFontDescription():FontDescription;
        public native function set baselineFontDescription(value:FontDescription):void;

        public native function get baselineFontSize():Number;
        public native function set baselineFontSize(value:Number):void;

        public native function get baselineZero():String;
        public native function set baselineZero(value:String):void;

        public native function get bidiLevel():int;
        public native function set bidiLevel(value:int):void;

        public native function get lineRotation():String;
        public native function set lineRotation(value:String):void;

        public native function get tabStops():Vector.<TabStop>;
        public native function set tabStops(value:Vector.<TabStop>):void;

        public native function get textJustifier():TextJustifier;
        public function set textJustifier(value:TextJustifier):void {
            this.setTextJustifier(value);
        }

        private native function setTextJustifier(value:TextJustifier):void;

        public native function get content():ContentElement;
        public native function set content(value:ContentElement):void;

        public function createTextLine(
            previousLine:TextLine = null,
            width:Number = 1000000,
            lineOffset:Number = 0,
            fitSomething:Boolean = false
        ):TextLine {
            if (this.content === null) {
                return null;
            }

            if (previousLine !== null) {
                if (previousLine.validity !== TextLineValidity.VALID || previousLine.textBlock !== this) {
                    Error.throwError(ArgumentError, 2004);
                }
            }

            if (width < 0 || width > TextLine.MAX_LINE_WIDTH) {
                Error.throwError(ArgumentError, 2004);
            }

            // Timffle: DoCreateTextLine breaks the paragraph at `width`
            // (one visual line per TextLine) and honours `fitSomething`.
            return this.DoCreateTextLine(null, previousLine, width, lineOffset, fitSomething);
        }

        // Match the method name in FP, which can be seen in stack traces
        private native function DoCreateTextLine(lineToUse:TextLine, previousLine:TextLine, width:Number, lineOffset:Number, fitSomething:Boolean):TextLine;

        public function recreateTextLine(
            textLine:TextLine,
            previousLine:TextLine = null,
            width:Number = 1000000,
            lineOffset:Number = 0,
            fitSomething:Boolean = false
        ):TextLine {
            if (textLine == null) {
                Error.throwError(ArgumentError, 2004);
            }

            if (previousLine !== null) {
                if (previousLine.validity !== TextLineValidity.VALID || previousLine.textBlock !== this || previousLine === textLine) {
                    Error.throwError(ArgumentError, 2004);
                }
            }

            if (width < 0 || width > TextLine.MAX_LINE_WIDTH) {
                Error.throwError(ArgumentError, 2004);
            }

            // Clear AS-side properties of the text line
            textLine.userData = null;

            return this.DoCreateTextLine(textLine, previousLine, width, lineOffset, fitSomething);
        }

        public native function get textLineCreationResult():String;

        public native function get firstInvalidLine():TextLine;

        public native function get firstLine():TextLine;

        public native function get lastLine():TextLine;

        public native function releaseLines(start:TextLine, end:TextLine):void;

        // Timffle: new members.
        public native function getTextLineAtCharIndex(charIndex:int):TextLine;

        public native function findNextAtomBoundary(afterCharIndex:int):int;
        public native function findPreviousAtomBoundary(beforeCharIndex:int):int;
        public native function findNextWordBoundary(afterCharIndex:int):int;
        public native function findPreviousWordBoundary(beforeCharIndex:int):int;

        // Flash Player keeps shaping data of the content between
        // createTextLine calls and this method frees it. This player lays out
        // each line from the content directly and keeps no such cache, so
        // there is nothing to release.
        public function releaseLineCreationData():void { }

        // Flash Player's dump() format is undocumented; this prints the block's
        // settings, content tree and lines as XML.
        public function dump():String {
            var out:String = "<TextBlock baselineZero=\"" + this.baselineZero
                + "\" bidiLevel=\"" + this.bidiLevel
                + "\" lineRotation=\"" + this.lineRotation
                + "\" textLineCreationResult=\"" + this.textLineCreationResult + "\">\n";
            out += dumpElement(this.content, "  ");
            for (var line:TextLine = this.firstLine; line != null; line = line.nextLine) {
                out += "  <TextLine textBlockBeginIndex=\"" + line.textBlockBeginIndex
                    + "\" rawTextLength=\"" + line.rawTextLength
                    + "\" validity=\"" + line.validity + "\"/>\n";
            }
            return out + "</TextBlock>";
        }

        private static function dumpElement(element:ContentElement, indent:String):String {
            if (element == null) {
                return "";
            }
            if (element is GroupElement) {
                var group:GroupElement = GroupElement(element);
                var out:String = indent + "<GroupElement>\n";
                for (var i:int = 0; i < group.elementCount; i++) {
                    out += dumpElement(group.getElementAt(i), indent + "  ");
                }
                return out + indent + "</GroupElement>\n";
            }
            if (element is GraphicElement) {
                var g:GraphicElement = GraphicElement(element);
                return indent + "<GraphicElement elementWidth=\"" + g.elementWidth
                    + "\" elementHeight=\"" + g.elementHeight + "\"/>\n";
            }
            return indent + "<TextElement text=\"" + element.text + "\"/>\n";
        }
    }
}
