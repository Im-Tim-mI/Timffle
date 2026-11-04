package {
import flash.display.Sprite;
import flash.xml.XMLDocument;

// XML / XMLList hasOwnProperty, propertyIsEnumerable and prototype.valueOf, the undocumented
// XML.setNotification, and flash.xml.XMLDocument.toString. Expected values are those of the
// standalone Flash Player 32.0.0.465 (timffle/difftest/src/D47XmlProps.hx, D48XmlNotify.hx).
public class Test extends Sprite {
    public function Test() {
        ownPropertyTests();
        notificationTests();
        xmlDocumentTests();
    }

    private function step(label:String, f:Function):void {
        try {
            f();
        } catch (e:Error) {
            trace(label + " THREW #" + e.errorID);
        }
    }

    private function desc(v:*):String {
        if (v is XML) {
            var x:XML = v;
            return "XML[" + x.nodeKind() + " " + (x.nodeKind() == "element" ? x.localName() : x.toString()) + "]";
        }
        if (v is XMLList) {
            return "XMLList[" + v.length() + "]";
        }
        if (v is Namespace) {
            return "Namespace[" + v.uri + "]";
        }
        return String(v) + ":" + typeof v;
    }

    private function esc(s:String):String {
        return s.split("\n").join("\\n");
    }

    private function ownPropertyTests():void {
        var x:XML = <a attr="1"><b>bbb</b><b>ccc</b><c/></a>;
        var names:Array = ["b", "c", "d", "@attr", "@zz", "0", "1", "toXMLString", "hasOwnProperty", "valueOf", "length", "attr", "*", "@*"];
        for each (var p:String in names) {
            trace("x.hasOwnProperty(" + p + ") = " + x.hasOwnProperty(p) + ", enumerable " + x.propertyIsEnumerable(p));
        }
        trace("x.hasOwnProperty(0) = " + x.hasOwnProperty(0) + ", enumerable " + x.propertyIsEnumerable(0));
        trace("x.propertyIsEnumerable() = " + x.propertyIsEnumerable());
        trace("x.AS3::hasOwnProperty('b') = " + x.AS3::hasOwnProperty("b") + ", x.AS3::propertyIsEnumerable('0') = " + x.AS3::propertyIsEnumerable("0"));
        trace("x.valueOf() === x: " + (x.valueOf() === x));
        var protoNames:Array = ["hasOwnProperty", "propertyIsEnumerable", "valueOf", "toString", "setNotification", "notification", "nope"];
        for each (p in protoNames) {
            trace("XML.prototype own " + p + ": " + Object.prototype.hasOwnProperty.call(XML.prototype, p) + ", enumerable " + Object.prototype.propertyIsEnumerable.call(XML.prototype, p) + ", " + typeof XML.prototype[p]);
        }
        trace("XML.prototype.valueOf === Object.prototype.valueOf: " + (XML.prototype.valueOf === Object.prototype.valueOf));
        trace("XML.prototype.hasOwnProperty === Object.prototype.hasOwnProperty: " + (XML.prototype.hasOwnProperty === Object.prototype.hasOwnProperty));
        trace("XML.prototype.valueOf.call(x) === x: " + (XML.prototype.valueOf.call(x) === x));
        // Note: Object.prototype.hasOwnProperty.call(x, ...) and XML.prototype.hasOwnProperty.call({}, ...)
        // are not checked here: Ruffle resolves `<prototype>.hasOwnProperty` to the AS3 method bound to
        // the prototype object itself (an upstream quirk unrelated to the XML class).

        var two:XMLList = x.b;
        var one:XMLList = x.c;
        var empty:XMLList = x.zzz;
        var listNames:Array = ["0", "1", "2", "b", "c", "@attr", "length", "toXMLString", "hasOwnProperty", "valueOf", "*"];
        for each (p in listNames) {
            trace("list2.hasOwnProperty(" + p + ") = " + two.hasOwnProperty(p) + "/" + two.propertyIsEnumerable(p)
                + ", list1 " + one.hasOwnProperty(p) + "/" + one.propertyIsEnumerable(p)
                + ", empty " + empty.hasOwnProperty(p) + "/" + empty.propertyIsEnumerable(p));
        }
        var nested:XMLList = <r><i><k>1</k></i><i attr="2"/></r>.i;
        trace("nested.hasOwnProperty(k) = " + nested.hasOwnProperty("k") + ", @attr " + nested.hasOwnProperty("@attr") + ", enumerable k " + nested.propertyIsEnumerable("k"));
        trace("list.valueOf() === list: " + (two.valueOf() === two));
        trace("list.AS3::hasOwnProperty('1') = " + two.AS3::hasOwnProperty("1") + ", list.AS3::propertyIsEnumerable(1) = " + two.AS3::propertyIsEnumerable(1));
        for each (p in ["hasOwnProperty", "propertyIsEnumerable", "valueOf", "toString", "nope"]) {
            trace("XMLList.prototype own " + p + ": " + Object.prototype.hasOwnProperty.call(XMLList.prototype, p) + ", enumerable " + Object.prototype.propertyIsEnumerable.call(XMLList.prototype, p) + ", " + typeof XMLList.prototype[p]);
        }
        trace("XMLList.prototype.valueOf === Object.prototype.valueOf: " + (XMLList.prototype.valueOf === Object.prototype.valueOf));
        trace("XMLList.prototype.valueOf.call(x) is XML: " + (XMLList.prototype.valueOf.call(x) is XML));
    }

    private function notificationTests():void {
        var n:XML = <n a="1"><p>t</p></n>;
        var self:Test = this;
        trace("notification() initially: " + n.notification());
        var cb:Function = function(target:*, command:String, prop:*, value:*, detail:*):void {
            trace("  cb target=" + (target === n ? "n" : self.desc(target)) + " cmd=" + command + " prop=" + (prop === n ? "n" : self.desc(prop)) + " value=" + self.desc(value) + " detail=" + self.desc(detail));
        };
        trace("setNotification returns " + n.setNotification(cb) + ", notification() === cb: " + (n.notification() === cb));
        var act:Function = function(label:String, f:Function):void {
            trace(label + ":");
            self.step(label, f);
        };
        act("appendChild", function():void { n.appendChild(<q/>); });
        act("prependChild", function():void { n.prependChild(<first/>); });
        act("setName", function():void { n.setName("m"); });
        act("setLocalName", function():void { n.setLocalName("m2"); });
        act("attribute change", function():void { n.@a = "2"; });
        act("attribute add", function():void { n.@b = "3"; });
        act("attribute delete", function():void { delete n.@b; });
        act("child text set", function():void { n.p = "u"; });
        act("new child text", function():void { n.z = "v"; });
        act("replace child with XML", function():void { n.z = <r/>; });
        act("delete child", function():void { delete n.q; });
        act("insertChildAfter", function():void { n.insertChildAfter(n.p[0], <ins/>); });
        act("insertChildBefore", function():void { n.insertChildBefore(n.p[0], <ins2/>); });
        act("replace(0)", function():void { n.replace(0, <rep/>); });
        act("setChildren", function():void { n.setChildren(<z/>); });
        act("grandchild attribute", function():void { n.z[0].@g = "1"; });
        act("grandchild setName", function():void { n.z[0].setName("zz"); });
        act("grandchild appendChild", function():void { n.zz[0].appendChild(<deep/>); });
        act("setNamespace", function():void { n.setNamespace(new Namespace("pre", "http://x/")); });
        act("addNamespace", function():void { n.addNamespace(new Namespace("other", "http://y/")); });
        act("removeNamespace", function():void { n.removeNamespace(new Namespace("other", "http://y/")); });
        act("setNotification(null)", function():void {
            trace("  returns " + n.setNotification(null) + ", notification() " + n.notification());
            n.appendChild(<after/>);
        });
        act("setNotification(1)", function():void {
            var notAFunction:Object = 1;
            n.setNotification(notAFunction);
        });
        act("throwing callback", function():void {
            n.setNotification(function(... rest):void { throw new Error("boom"); });
            n.setName("k2");
        });
        trace("after: " + n.name() + " with " + n.children().length() + " children");

        var r:XML = <r><i/><i/></r>;
        r.setNotification(function(target:*, command:String, prop:*, value:*, detail:*):void {
            trace("  rcb cmd=" + command + " prop=" + self.desc(prop) + " value=" + self.desc(value) + " detail=" + self.desc(detail));
        });
        act("list put r.i = 'all'", function():void { r.i = "all"; });
        trace("  -> " + esc(r.toXMLString()));
        act("delete r.i", function():void { delete r.i; });
        trace("  -> " + esc(r.toXMLString()));
    }

    private function xmlDocumentTests():void {
        var cases:Array = ["<a x='1'>t<b/></a>", "<?xml version=\"1.0\" encoding=\"utf-8\"?><a/>", "<!DOCTYPE a SYSTEM \"a.dtd\"><a/>",
            "<?xml version='1.0'?>\n<!DOCTYPE a>\n<a>\n <b/>\n</a>", "", "just text", "<a/><b/>", "<a>&amp;&lt;\"</a>", "<a>x</a> <!-- c --> tail", "<?pi target?><a/>"];
        for each (var c:String in cases) {
            var d:XMLDocument = new XMLDocument(c);
            trace("doc(" + esc(c) + ") = '" + esc(d.toString()) + "' xmlDecl=" + d.xmlDecl + " docTypeDecl=" + d.docTypeDecl + " children=" + d.childNodes.length);
        }
        var d2:XMLDocument = new XMLDocument();
        d2.ignoreWhite = true;
        d2.parseXML("<?xml version='1.0'?>\n<!DOCTYPE a>\n<a>\n <b/>\n</a>");
        trace("ignoreWhite doc = '" + esc(d2.toString()) + "' xmlDecl=" + d2.xmlDecl + " docTypeDecl=" + d2.docTypeDecl);
        var d3:XMLDocument = new XMLDocument();
        trace("empty doc = '" + d3.toString() + "' firstChild=" + d3.firstChild + " nodeName=" + d3.nodeName);
        d3.xmlDecl = "<?xml version='1.0'?>";
        d3.docTypeDecl = "<!DOCTYPE z>";
        trace("decl-only doc = '" + d3.toString() + "'");
        d3.appendChild(d3.createElement("z"));
        trace("decl+z doc = '" + d3.toString() + "' firstChild '" + d3.firstChild.toString() + "'");
        d3.xmlDecl = 5;
        d3.docTypeDecl = null;
        trace("numeric decl doc = '" + d3.toString() + "'");
    }
}
}
