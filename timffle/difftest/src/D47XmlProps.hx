/** Probe (no golden): XML / XMLList hasOwnProperty, propertyIsEnumerable, prototype.valueOf,
 *  the undocumented XML.setNotification, and flash.xml.XMLDocument.toString. Everything is
 *  reached by name through the prototype (Haxe cannot spell the AS3 namespace). */
class D47XmlProps {
	static var XMLC:Dynamic;
	static var XMLLC:Dynamic;

	static function step(label:String, f:Void->Void) {
		try {
			f();
		} catch (e:flash.errors.Error) {
			H.log(label + " THREW " + e.name + " #" + e.errorID + " " + e.message);
		}
	}

	static function mk(s:String):Dynamic {
		return Type.createInstance(XMLC, [s]);
	}

	static function main() {
		H.init("d47xmlprops");
		XMLC = untyped __global__["XML"];
		XMLLC = untyped __global__["XMLList"];
		var objProto:Dynamic = untyped __global__["Object"].prototype;
		var x:Dynamic = mk("<a attr='1'><b>bbb</b><b>ccc</b><c/></a>");

		step("own", function() {
			for (p in ["b", "c", "d", "@attr", "@zz", "0", "1", "toXMLString", "hasOwnProperty", "valueOf", "length", "attr", "*", "@*"]) {
				H.log("x.hasOwnProperty(" + p + ")=" + x.hasOwnProperty(p) + " enum=" + x.propertyIsEnumerable(p));
			}
			H.log("x.hasOwnProperty(0)=" + x.hasOwnProperty(0) + " enum=" + x.propertyIsEnumerable(0));
			H.log("x.hasOwnProperty()=" + x.hasOwnProperty() + " enum()=" + x.propertyIsEnumerable());
			H.log("x.hasOwnProperty(null)=" + x.hasOwnProperty(null) + " enum=" + x.propertyIsEnumerable(null));
		});
		step("proto own", function() {
			var pr:Dynamic = XMLC.prototype;
			for (p in ["hasOwnProperty", "propertyIsEnumerable", "valueOf", "toString", "setNotification", "notification", "constructor", "nope"]) {
				H.log("XML.prototype own(" + p + ")=" + objProto.hasOwnProperty.call(pr, p) + " enum=" + objProto.propertyIsEnumerable.call(pr, p) + " type=" + Type.typeof(Reflect.field(pr, p)));
			}
			H.log("XML.prototype.valueOf == Object.prototype.valueOf: " + (pr.valueOf == objProto.valueOf));
			H.log("XML.prototype.hasOwnProperty == Object.prototype.hasOwnProperty: " + (pr.hasOwnProperty == objProto.hasOwnProperty));
			H.log("XML.prototype.propertyIsEnumerable == Object's: " + (pr.propertyIsEnumerable == objProto.propertyIsEnumerable));
			H.log("x.valueOf()===x: " + (x.valueOf() == x) + " proto.valueOf.call(x)===x: " + (pr.valueOf.call(x) == x));
			H.log("Object.proto.hasOwnProperty.call(x,'b')=" + objProto.hasOwnProperty.call(x, "b") + " Object.proto.enum.call(x,'0')=" + objProto.propertyIsEnumerable.call(x, "0"));
		});
		step("proto on other", function() {
			var pr:Dynamic = XMLC.prototype;
			H.log("XML.proto.hasOwnProperty.call({b:1},'b')=" + pr.hasOwnProperty.call({b: 1}, "b"));
		});
		step("proto on other enum", function() {
			var pr:Dynamic = XMLC.prototype;
			H.log("XML.proto.propertyIsEnumerable.call({b:1},'b')=" + pr.propertyIsEnumerable.call({b: 1}, "b"));
		});
		step("proto valueOf on other", function() {
			var pr:Dynamic = XMLC.prototype;
			H.log("XML.proto.valueOf.call({b:1})=" + pr.valueOf.call({b: 1}));
		});
		step("proto valueOf on list", function() {
			var pr:Dynamic = XMLC.prototype;
			var l:Dynamic = x.b;
			H.log("XML.proto.valueOf.call(list of 2)=" + untyped __global__["flash.utils.getQualifiedClassName"](pr.valueOf.call(l)));
		});
		step("list", function() {
			var l:Dynamic = x.b;
			var one:Dynamic = x.c;
			var empty:Dynamic = x.zzz;
			for (p in ["0", "1", "2", "b", "c", "@attr", "length", "toXMLString", "hasOwnProperty", "valueOf", "*"]) {
				H.log("list2.hasOwnProperty(" + p + ")=" + l.hasOwnProperty(p) + " enum=" + l.propertyIsEnumerable(p)
					+ " | list1: " + one.hasOwnProperty(p) + "/" + one.propertyIsEnumerable(p)
					+ " | empty: " + empty.hasOwnProperty(p) + "/" + empty.propertyIsEnumerable(p));
			}
			var nested:Dynamic = mk("<r><i><k>1</k></i><i attr='2'/></r>").i;
			H.log("nested.hasOwnProperty(k)=" + nested.hasOwnProperty("k") + " @attr=" + nested.hasOwnProperty("@attr") + " enum k=" + nested.propertyIsEnumerable("k"));
			var tl:Dynamic = mk("<r>t1<i/>t2</r>").children();
			H.log("textlist.hasOwnProperty(0)=" + tl.hasOwnProperty("0") + " (i)=" + tl.hasOwnProperty("i"));
			H.log("list.valueOf()===list: " + (l.valueOf() == l));
			var pr:Dynamic = XMLLC.prototype;
			for (p in ["hasOwnProperty", "propertyIsEnumerable", "valueOf", "toString", "nope"]) {
				H.log("XMLList.prototype own(" + p + ")=" + objProto.hasOwnProperty.call(pr, p) + " enum=" + objProto.propertyIsEnumerable.call(pr, p) + " type=" + Type.typeof(Reflect.field(pr, p)));
			}
			H.log("XMLList.prototype.valueOf == Object's: " + (pr.valueOf == objProto.valueOf) + " == XML's: " + (pr.valueOf == XMLC.prototype.valueOf));
		});
		step("list proto on other", function() {
			var pr:Dynamic = XMLLC.prototype;
			H.log("XMLList.proto.hasOwnProperty.call({b:1},'b')=" + pr.hasOwnProperty.call({b: 1}, "b"));
		});
		step("list proto valueOf on xml", function() {
			var pr:Dynamic = XMLLC.prototype;
			H.log("XMLList.proto.valueOf.call(x) class=" + untyped __global__["flash.utils.getQualifiedClassName"](pr.valueOf.call(x)));
		});
		step("notification", function() {
			var n:Dynamic = mk("<n a='1'><p>t</p></n>");
			H.log("notification() initial=" + n.notification());
			var cb = function(a:Dynamic, b:Dynamic, c:Dynamic, d:Dynamic, e:Dynamic) {
				H.log("  cb target=" + Std.string(a == n ? "n" : a) + " cmd=" + b + " prop=" + Std.string(c) + " value=" + Std.string(d) + " detail=" + Std.string(e)
					+ " types=" + Type.typeof(a) + "," + Type.typeof(b) + "," + Type.typeof(c) + "," + Type.typeof(d) + "," + Type.typeof(e));
			};
			var r:Dynamic = n.setNotification(cb);
			H.log("setNotification ret=" + r + " type=" + Type.typeof(r) + " notification()==cb " + (n.notification() == cb));
			H.log("appendChild:");
			n.appendChild(mk("<q/>"));
			H.log("setName:");
			n.setName("m");
			H.log("attr set:");
			Reflect.setField(n, "@a", "2");
			H.log("new attr:");
			Reflect.setField(n, "@b", "3");
			H.log("child text set:");
			Reflect.setField(n, "p", "u");
			H.log("delete child:");
			Reflect.deleteField(n, "q");
			H.log("setChildren:");
			n.setChildren(mk("<z/>"));
			H.log("child's own change (p.setName):");
			untyped n.p[0].setName("pp");
			H.log("setNotification(null) ret=" + n.setNotification(null) + " notification()=" + n.notification());
			n.appendChild(mk("<after/>"));
			H.log("done " + n.toXMLString());
		});
		step("setNotification bad", function() {
			var n:Dynamic = mk("<n/>");
			H.log("setNotification(1) ret=" + n.setNotification(1) + " notification()=" + n.notification());
		});
		step("xmldocument", function() {
			var XD:Dynamic = untyped __global__["flash.xml.XMLDocument"];
			var qn:Dynamic = untyped __global__["flash.utils.getQualifiedClassName"];
			var cases = ["<a x='1'>t<b/></a>", "<?xml version=\"1.0\" encoding=\"utf-8\"?><a/>", "<!DOCTYPE a SYSTEM \"a.dtd\"><a/>",
				"<?xml version='1.0'?>\n<!DOCTYPE a>\n<a>\n <b/>\n</a>", "", "just text", "<a/><b/>", "<a>&amp;&lt;\"</a>", "<a>x</a> <!-- c --> tail", "<?pi target?><a/>"];
			for (c in cases) {
				var d:Dynamic = Type.createInstance(XD, [c]);
				H.log("doc[" + c + "] toString='" + d.toString() + "' String()='" + Std.string(d) + "' xmlDecl=" + Std.string(d.xmlDecl) + " docTypeDecl=" + Std.string(d.docTypeDecl) + " nodeName=" + d.nodeName + " nodeType=" + d.nodeType + " children=" + d.childNodes.length);
			}
			var d2:Dynamic = Type.createInstance(XD, []);
			d2.ignoreWhite = true;
			d2.parseXML("<?xml version='1.0'?>\n<!DOCTYPE a>\n<a>\n <b/>\n</a>");
			H.log("ignoreWhite doc toString='" + d2.toString() + "' xmlDecl=" + Std.string(d2.xmlDecl) + " docTypeDecl=" + Std.string(d2.docTypeDecl));
			var d3:Dynamic = Type.createInstance(XD, []);
			H.log("empty doc toString='" + d3.toString() + "' firstChild=" + d3.firstChild + " nodeName=" + d3.nodeName);
			d3.xmlDecl = "<?xml version='1.0'?>";
			d3.docTypeDecl = "<!DOCTYPE z>";
			H.log("decl-only doc toString='" + d3.toString() + "'");
			d3.appendChild(d3.createElement("z"));
			H.log("decl+z doc toString='" + d3.toString() + "' firstChild.toString='" + d3.firstChild.toString() + "'");
			d3.xmlDecl = 5;
			d3.docTypeDecl = null;
			H.log("numeric decl doc toString='" + d3.toString() + "'");
			var XN:Dynamic = untyped __global__["flash.xml.XMLNode"];
			var el:Dynamic = Type.createInstance(XN, [1, "e"]);
			el.appendChild(Type.createInstance(XN, [3, "txt"]));
			H.log("plain XMLNode toString='" + el.toString() + "' class of doc=" + qn(Type.createInstance(XD, [])));
		});
		H.done();
	}
}
