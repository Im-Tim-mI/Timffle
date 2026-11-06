package flash.xml {
    import flash.xml.XMLNode;
    import flash.xml.XMLNodeType;

    public class XMLDocument extends XMLNode {
        public var docTypeDecl:Object = null;
        public var idMap:Object;
        public var ignoreWhite:Boolean = false;
        public var xmlDecl:Object = null;

        public function XMLDocument(input:String = null) {
            super(XMLNodeType.ELEMENT_NODE, "");

            this.idMap = {};
            this.nodeName = null;

            if (input != null) {
                parseXML(input);
            }
        }

        public function parseXML(input:String):void {
            // This is something of a hack, but that's somewhat the nature of XMLDocument
            // It accepts things like `<node>...</node> <!-- comment --> foo` which is FOUR children:
            // `<node>...</node>` gets parsed as an element
            // ` ` gets parsed as a text node
            // `<!-- comment -->` gets parsed as a comment
            // ` foo` is another text node
            // To achieve this, just wrap it all together in a parent.

            var oldSettings = XML.AS3::settings();
            var newSettings = XML.AS3::defaultSettings();
            newSettings.ignoreWhitespace = this.ignoreWhite;
            XML.AS3::setSettings(newSettings);

            try {
                clear();
                // Timffle: like Flash, an XML declaration and a DOCTYPE are lifted out of the
                // input into xmlDecl/docTypeDecl; the text on either side of them stays as
                // separate text nodes (Flash's parser handles the pieces one after another).
                for each (var segment:String in _takeDeclarations(input)) {
                    var root = new XML("<xml>" + segment + "</xml>");
                    for each (var child in root.children()) {
                        appendChild(_convertXmlNode(child));
                    }
                }
            } finally {
                XML.AS3::setSettings(oldSettings);
            }
        }

        private function _convertXmlNode(original:XML):XMLNode {
            var nodeType = _convertXmlNodeType(original.nodeKind());
            var nodeValue = nodeType == XMLNodeType.ELEMENT_NODE ?
                _convertXmlName(original) : original.toString();
            var result = new XMLNode(nodeType, nodeValue);
            for each (var originalChild in original.children()) {
                result.appendChild(_convertXmlNode(originalChild));
            }

            var attributes = {};
            for each (var attribute in original.attributes()) {
                attributes[_convertXmlName(attribute)] = attribute.toString();
            }
            for each (var ns in original.namespaceDeclarations()) {
                var name = "xmlns";
                if (ns.prefix) {
                    name += ":" + ns.prefix;
                }
                attributes[name] = ns.uri;
            }

            result.attributes = attributes;
            return result;
        }

        private function _convertXmlName(node:XML):String {
            var ns = node.namespace();
            if (ns.prefix) {
            return ns.prefix + ":" + node.localName();
            }
            return node.localName();
        }

        private function _convertXmlNodeType(kind:String):uint {
            if (kind == "text") {
                return XMLNodeType.TEXT_NODE;
            }
            if (kind == "comment") {
                return XMLNodeType.COMMENT_NODE;
            }
            if (kind == "element") {
                return XMLNodeType.ELEMENT_NODE;
            }
            throw new Error("Invalid XML Node kind '" + kind + "' found whilst constructing (legacy) XMLDocument");
        }

        public function createElement(name:String):XMLNode {
            return new XMLNode(XMLNodeType.ELEMENT_NODE, name);
        }

        public function createTextNode(text:String):XMLNode {
            return new XMLNode(XMLNodeType.TEXT_NODE, text);
        }

        // Timffle: Flash Player 32 (timffle/difftest/src/D47XmlProps.hx) prints xmlDecl, then
        // docTypeDecl (each converted with String() when not null), then the child nodes in
        // document order; a document without children prints "<>".
        override public function toString():String {
            var result:String = "";
            if (this.xmlDecl != null) {
                result += this.xmlDecl;
            }
            if (this.docTypeDecl != null) {
                result += this.docTypeDecl;
            }
            if (hasChildNodes()) {
                result += super.toString();
            } else {
                result += "<>";
            }
            return result;
        }

        // Timffle: cut every `<?xml ...?>` and `<!DOCTYPE ...>` (with an optional internal
        // subset in brackets) out of the input, remember the last of each, and return the
        // pieces of text that were between them.
        private function _takeDeclarations(input:String):Array {
            var segments:Array = [];
            var rest:String = input;
            while (true) {
                var declStart:int = rest.indexOf("<?xml");
                var docStart:int = rest.indexOf("<!DOCTYPE");
                var start:int;
                var end:int;
                if (declStart >= 0 && (docStart < 0 || declStart < docStart)) {
                    end = rest.indexOf("?>", declStart);
                    if (end < 0) {
                        break;
                    }
                    end += 2;
                    this.xmlDecl = rest.substring(declStart, end);
                    start = declStart;
                } else if (docStart >= 0) {
                    var depth:int = 0;
                    var i:int = docStart;
                    while (i < rest.length) {
                        var ch:String = rest.charAt(i);
                        if (ch == "[") {
                            depth++;
                        } else if (ch == "]") {
                            depth--;
                        } else if (ch == ">" && depth <= 0) {
                            break;
                        }
                        i++;
                    }
                    if (i >= rest.length) {
                        break;
                    }
                    end = i + 1;
                    this.docTypeDecl = rest.substring(docStart, end);
                    start = docStart;
                } else {
                    break;
                }
                if (start > 0) {
                    segments.push(rest.substring(0, start));
                }
                rest = rest.substring(end);
            }
            if (rest.length > 0 || segments.length == 0) {
                segments.push(rest);
            }
            return segments;
        }
    }
}
