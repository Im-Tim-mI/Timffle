/** Probe (no golden): what XML.setNotification reports for setName / setLocalName with string,
 *  QName and namespaced QName arguments (value and detail of the nameSet command). */
class D49XmlSetName {
	static var as3ns:Dynamic;

	static function as3(o:Dynamic, name:String):Dynamic {
		var qn:Dynamic = Type.createInstance(untyped __global__["QName"], [as3ns, name]);
		return untyped o[qn];
	}

	static function desc(v:Dynamic):String {
		var qn:Dynamic = untyped __global__["flash.utils.getQualifiedClassName"];
		if (v == null) return Std.string(v);
		return qn(v) + ":" + Std.string(v);
	}

	static function main() {
		H.init("d49xmlsetname");
		as3ns = Type.createInstance(untyped __global__["Namespace"], ["http://adobe.com/AS3/2006/builtin"]);
		var XMLC:Dynamic = untyped __global__["XML"];
		var QN:Dynamic = untyped __global__["QName"];
		var NS:Dynamic = untyped __global__["Namespace"];
		var n:Dynamic = Type.createInstance(XMLC, ["<n/>"]);
		as3(n, "setNotification").call(n, function(a:Dynamic, b:Dynamic, c:Dynamic, d:Dynamic, e:Dynamic) {
			H.log("  cb cmd=" + Std.string(b) + " value=" + desc(d) + " detail=" + desc(e) + " name now=" + desc(c.name()));
		});
		H.log("setName('m'):");
		n.setName("m");
		H.log("setLocalName('m2'):");
		n.setLocalName("m2");
		H.log("setName(QName('plain')):");
		n.setName(Type.createInstance(QN, ["plain"]));
		H.log("setName(QName('http://example.org','namespaced')):");
		n.setName(Type.createInstance(QN, ["http://example.org", "namespaced"]));
		H.log("setName(QName(null,'anyns')):");
		n.setName(Type.createInstance(QN, [null, "anyns"]));
		H.log("setName(QName(Namespace('p','http://p/'),'pre')):");
		n.setName(Type.createInstance(QN, [Type.createInstance(NS, ["p", "http://p/"]), "pre"]));
		H.log("setName('back'):");
		n.setName("back");
		H.log("setName(5):");
		n.setName(5);
		H.log("setLocalName(QName('http://x/','ln')):");
		n.setLocalName(Type.createInstance(QN, ["http://x/", "ln"]));
		H.log("final " + n.toXMLString());
		H.done();
	}
}
