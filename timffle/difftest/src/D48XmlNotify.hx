/** Probe (no golden): the undocumented XML.AS3::setNotification / notification, reached through a
 *  QName in the AS3 namespace (Haxe cannot spell `AS3::`). Also XML.AS3::hasOwnProperty etc. */
class D48XmlNotify {
	static var XMLC:Dynamic;
	static var as3ns:Dynamic;

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

	static function as3(o:Dynamic, name:String):Dynamic {
		var qn:Dynamic = Type.createInstance(untyped __global__["QName"], [as3ns, name]);
		return untyped o[qn];
	}

	static function desc(v:Dynamic):String {
		var qn:Dynamic = untyped __global__["flash.utils.getQualifiedClassName"];
		if (v == null) return Std.string(v);
		var cls:String = qn(v);
		if (cls == "XML") return "XML(" + v.toXMLString().split("\n").join("\\n") + ")";
		if (cls == "XMLList") return "XMLList(" + v.toXMLString().split("\n").join("\\n") + ")";
		return cls + ":" + Std.string(v);
	}

	static function main() {
		H.init("d48xmlnotify");
		XMLC = untyped __global__["XML"];
		as3ns = Type.createInstance(untyped __global__["Namespace"], ["http://adobe.com/AS3/2006/builtin"]);
		var x:Dynamic = mk("<a attr='1'><b>bbb</b></a>");
		step("as3 hasOwnProperty", function() {
			var f:Dynamic = as3(x, "hasOwnProperty");
			H.log("AS3::hasOwnProperty is " + Type.typeof(f) + " b=" + f.call(x, "b") + " 0=" + f.call(x, "0") + " toString=" + f.call(x, "toString") + " num0=" + f.call(x, 0));
			var e:Dynamic = as3(x, "propertyIsEnumerable");
			H.log("AS3::propertyIsEnumerable 0=" + e.call(x, "0") + " num0=" + e.call(x, 0) + " b=" + e.call(x, "b") + " 1=" + e.call(x, "1"));
			H.log("AS3::hasOwnProperty(undefined)=" + f.call(x, null) + " proto(undefined)=" + XMLC.prototype.hasOwnProperty.call(x, null));
			H.log("AS3::valueOf===x " + (as3(x, "valueOf").call(x) == x) + " AS3::valueOf == proto.valueOf " + (as3(x, "valueOf") == XMLC.prototype.valueOf));
			H.log("proto.hasOwnProperty == AS3::hasOwnProperty " + (XMLC.prototype.hasOwnProperty == as3(x, "hasOwnProperty")));
		});
		step("as3 hasOwnProperty length", function() {
			H.log("AS3::hasOwnProperty.length=" + as3(x, "hasOwnProperty").length + " proto.length=" + XMLC.prototype.hasOwnProperty.length + " enum.length=" + as3(x, "propertyIsEnumerable").length + " Object.proto.hasOwnProperty.length=" + untyped __global__["Object"].prototype.hasOwnProperty.length);
		});
		step("as3 hasOwnProperty noarg", function() {
			H.log("AS3::hasOwnProperty()=" + as3(x, "hasOwnProperty").call(x));
		});
		step("as3 propertyIsEnumerable noarg", function() {
			H.log("AS3::propertyIsEnumerable()=" + as3(x, "propertyIsEnumerable").call(x));
		});
		var n:Dynamic = mk("<n a='1'><p>t</p></n>");
		var cb = function(a:Dynamic, b:Dynamic, c:Dynamic, d:Dynamic, e:Dynamic) {
			H.log("  cb this=" + desc(untyped __this__) + " target=" + (a == n ? "n" : desc(a)) + " cmd=" + Std.string(b) + " prop=" + (c == n ? "n" : desc(c)) + " value=" + desc(d) + " detail=" + desc(e));
		};
		step("notification", function() {
			H.log("notification() initial=" + as3(n, "notification").call(n) + " setNotification.length=" + as3(n, "setNotification").length);
			var r:Dynamic = as3(n, "setNotification").call(n, cb);
			H.log("setNotification ret=" + Std.string(r) + " type=" + Type.typeof(r) + " notification()==cb " + (as3(n, "notification").call(n) == cb));
		});
		function act(label:String, f:Void->Void) {
			H.log(label + ":");
			step(label, f);
		}
		act("appendChild", function() n.appendChild(mk("<q/>")));
		act("appendChild text", function() n.appendChild("tx"));
		act("prependChild", function() n.prependChild(mk("<first/>")));
		act("setName", function() n.setName("m"));
		act("setLocalName", function() n.setLocalName("m2"));
		act("setNamespace", function() n.setNamespace(Type.createInstance(untyped __global__["Namespace"], ["pre", "http://x/"])));
		act("addNamespace", function() n.addNamespace(Type.createInstance(untyped __global__["Namespace"], ["other", "http://y/"])));
		act("removeNamespace", function() n.removeNamespace(Type.createInstance(untyped __global__["Namespace"], ["other", "http://y/"])));
		act("attr change", function() Reflect.setField(n, "@a", "2"));
		act("attr add", function() Reflect.setField(n, "@b", "3"));
		act("attr delete", function() Reflect.deleteField(n, "@b"));
		act("child text set n.p='u'", function() Reflect.setField(n, "p", "u"));
		act("new child via n.z='v'", function() Reflect.setField(n, "z", "v"));
		act("replace child with xml n.z=<r/>", function() Reflect.setField(n, "z", mk("<r/>")));
		act("delete child q", function() Reflect.deleteField(n, "q"));
		act("insertChildAfter", function() n.insertChildAfter(untyped n.p[0], mk("<ins/>")));
		act("insertChildBefore", function() n.insertChildBefore(untyped n.p[0], mk("<ins2/>")));
		act("replace(0, <rep/>)", function() n.replace(0, mk("<rep/>")));
		act("setChildren", function() n.setChildren(mk("<z/>")));
		act("grandchild change (z.@g=1)", function() Reflect.setField(untyped n.z[0], "@g", "1"));
		act("grandchild setName", function() untyped n.z[0].setName("zz"));
		act("grandchild appendChild", function() untyped n.zz[0].appendChild(mk("<deep/>")));
		act("n[0] = <whole/> (self replace via list)", function() Reflect.setField(n.children(), "0", mk("<whole/>")));
		act("normalize", function() n.normalize());
		act("child's own notification", function() {
			var ch:Dynamic = untyped n.zz[0];
			as3(ch, "setNotification").call(ch, function(a:Dynamic, b:Dynamic, c:Dynamic, d:Dynamic, e:Dynamic) {
				H.log("  childcb target=" + desc(a) + " cmd=" + Std.string(b) + " prop=" + desc(c) + " value=" + desc(d) + " detail=" + desc(e));
			});
			ch.setName("zzz");
			Reflect.setField(ch, "@c", "9");
		});
		act("copy keeps notification?", function() {
			var c:Dynamic = n.copy();
			H.log("  copy.notification()=" + as3(c, "notification").call(c));
			c.setName("copied");
		});
		act("setNotification(null)", function() {
			H.log("  ret=" + Std.string(as3(n, "setNotification").call(n, null)) + " notification()=" + as3(n, "notification").call(n));
			n.appendChild(mk("<after/>"));
		});
		act("setNotification(1)", function() {
			H.log("  ret=" + Std.string(as3(n, "setNotification").call(n, 1)) + " notification()=" + as3(n, "notification").call(n));
		});
		act("setNotification('s')", function() {
			H.log("  ret=" + Std.string(as3(n, "setNotification").call(n, "s")) + " notification()=" + as3(n, "notification").call(n));
		});
		act("setNotification()", function() {
			H.log("  ret=" + Std.string(as3(n, "setNotification").call(n)) + " notification()=" + as3(n, "notification").call(n));
		});
		act("setNotification(fn with 0 params)", function() {
			as3(n, "setNotification").call(n, function() H.log("  zero-param cb called"));
			n.setName("k");
		});
		act("cb throwing", function() {
			as3(n, "setNotification").call(n, function(a:Dynamic, b:Dynamic, c:Dynamic, d:Dynamic, e:Dynamic) {
				throw Type.createInstance(untyped __global__["Error"], ["boom"]);
			});
			n.setName("k2");
			H.log("  after throwing cb name=" + n.name());
		});
		act("list of 2 with notification", function() {
			var l:Dynamic = mk("<r><i/><i/></r>");
			as3(l, "setNotification").call(l, function(a:Dynamic, b:Dynamic, c:Dynamic, d:Dynamic, e:Dynamic) {
				H.log("  rcb cmd=" + Std.string(b) + " prop=" + desc(c) + " value=" + desc(d) + " detail=" + desc(e));
			});
			Reflect.setField(l, "i", "all");
			H.log("  -> " + l.toXMLString().split("\n").join("\\n"));
			Reflect.deleteField(l, "i");
			H.log("  -> " + l.toXMLString().split("\n").join("\\n"));
		});
		H.log("final " + n.toXMLString().split("\n").join("\\n"));
		H.done();
	}
}
