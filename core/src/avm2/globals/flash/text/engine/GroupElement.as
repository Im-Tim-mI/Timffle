package flash.text.engine {
    import flash.events.EventDispatcher;

    [API("662")]
    public final class GroupElement extends ContentElement {
        public function GroupElement(
            elements:Vector.<ContentElement> = null,
            elementFormat:ElementFormat = null,
            eventMirror:EventDispatcher = null,
            textRotation:String = "rotate0"
        ) {
            super(elementFormat, eventMirror, textRotation);

            this.init();
            this.setElements(elements);
        }

        private native function init():void;

        public native function get elementCount():int;

        public native function getElementAt(index:int):ContentElement;

        public function getElementIndex(testElement:ContentElement):int {
            for (var i:int = 0; i < this.elementCount; i ++) {
                var element:ContentElement = this.getElementAt(i);
                if (testElement == element) {
                    return i;
                }
            }

            return -1;
        }

        public native function setElements(elements:Vector.<ContentElement>):void;

        public native function replaceElements(
            beginIndex:int,
            endIndex:int,
            newElements:Vector.<ContentElement>
        ):Vector.<ContentElement>;

        // Timffle: the four tree operations below are real operations over the
        // element vector, with the errors Flash Player throws.

        public function getElementAtCharIndex(charIndex:int):ContentElement {
            if (charIndex < 0 || charIndex >= this.rawText.length) {
                throw new RangeError("Error #2006: The supplied index is out of bounds.", 2006);
            }
            var pos:int = 0;
            for (var i:int = 0; i < this.elementCount; i++) {
                var element:ContentElement = this.getElementAt(i);
                var text:String = element.rawText;
                var len:int = text == null ? 0 : text.length;
                if (charIndex < pos + len) {
                    return element;
                }
                pos += len;
            }
            return null;
        }

        public function groupElements(beginIndex:int, endIndex:int):GroupElement {
            if (beginIndex < 0 || endIndex > this.elementCount || beginIndex > endIndex) {
                throw new RangeError("Error #2006: The supplied index is out of bounds.", 2006);
            }
            var removed:Vector.<ContentElement> = this.replaceElements(beginIndex, endIndex, null);
            var group:GroupElement = new GroupElement(removed);
            this.replaceElements(beginIndex, beginIndex, Vector.<ContentElement>([group]));
            return group;
        }

        public function ungroupElements(groupIndex:int):void {
            if (groupIndex < 0 || groupIndex >= this.elementCount) {
                throw new RangeError("Error #2006: The supplied index is out of bounds.", 2006);
            }
            var element:ContentElement = this.getElementAt(groupIndex);
            if (!(element is GroupElement)) {
                throw new ArgumentError("Error #2004: One of the parameters is invalid.", 2004);
            }
            var group:GroupElement = GroupElement(element);
            var children:Vector.<ContentElement> = group.replaceElements(0, group.elementCount, null);
            this.replaceElements(groupIndex, groupIndex + 1, children);
        }

        public function mergeTextElements(beginIndex:int, endIndex:int):TextElement {
            if (beginIndex < 0 || endIndex > this.elementCount || beginIndex >= endIndex) {
                throw new RangeError("Error #2006: The supplied index is out of bounds.", 2006);
            }
            var i:int;
            for (i = beginIndex; i < endIndex; i++) {
                if (!(this.getElementAt(i) is TextElement)) {
                    throw new ArgumentError("Error #2004: One of the parameters is invalid.", 2004);
                }
            }
            var first:TextElement = TextElement(this.getElementAt(beginIndex));
            var text:String = first.text;
            for (i = beginIndex + 1; i < endIndex; i++) {
                var next:String = TextElement(this.getElementAt(i)).text;
                if (next != null) {
                    text = text == null ? next : text + next;
                }
            }
            this.replaceElements(beginIndex + 1, endIndex, null);
            first.text = text;
            return first;
        }

        // TODO: This method should probably be implemented in native code
        public function splitTextElement(elementIndex:int, splitIndex:int):TextElement {
            var element:ContentElement = this.getElementAt(elementIndex);
            if (!(element instanceof TextElement)) {
                throw new ArgumentError("Error #2004: One of the parameters is invalid.", 2004);
            }

            var text:String = element.text;
            if (splitIndex < 0 || splitIndex >= text.length) {
                throw new RangeError("Error #2006: The supplied index is out of bounds.", 2006);
            }
            element.text = text.slice(0, splitIndex);

            var newTextElement:ContentElement = new TextElement(text.slice(splitIndex));
            this.replaceElements(
                elementIndex + 1,
                elementIndex + 1,
                Vector.<ContentElement>([newTextElement])
            );
            return newTextElement;
        }
    }
}
