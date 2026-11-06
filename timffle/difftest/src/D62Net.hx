/** Probe (no golden): flash.net members Ruffle still stubs or lacks — sendToURL, FileReference
 *  cancel/download/upload error paths, FileReferenceList.browse, NetConnection.connect with
 *  non-HTTP commands, ObjectEncoding.dynamicPropertyWriter, Socket.bytesPending, SecureSocket,
 *  and whether NetMonitor / URLRequest.useRedirectedURL exist in Flash Player 32 at all.
 *  Build with -swf-version 32; run in the standalone Flash Player 32 projector served over HTTP. */
import flash.Lib;
import flash.events.*;
import flash.net.*;
import flash.utils.ByteArray;

class Writer implements IDynamicPropertyWriter {
	public var calls:Array<String> = [];
	public var skip:String;
	public var outputs:Array<Dynamic> = [];

	public function new(skip:String) {
		this.skip = skip;
	}

	public function writeDynamicProperties(obj:Dynamic, output:IDynamicPropertyOutput):Void {
		var names = Reflect.fields(obj);
		names.sort(Reflect.compare);
		calls.push("obj=" + D62Net.qn(obj) + " fields=" + names.join(",") + " output=" + D62Net.qn(output));
		outputs.push(output);
		for (n in names) {
			if (n == skip)
				continue;
			output.writeDynamicProperty(n, Reflect.field(obj, n));
		}
		output.writeDynamicProperty("extra", 42);
	}
}

class Writer2 implements IDynamicPropertyWriter {
	var f:Dynamic->IDynamicPropertyOutput->Void;

	public function new(f) {
		this.f = f;
	}

	public function writeDynamicProperties(obj:Dynamic, output:IDynamicPropertyOutput):Void {
		f(obj, output);
	}
}

class Sealed {
	public var x:Int = 1;

	public function new() {}
}

class D62Net {
	public static var qn:Dynamic;
	static var sendToURL:Dynamic;
	static var pending = 0;
	public static var ns1:NetStream;
	static var frl:FileReferenceList;
	static var ncs:Array<NetConnection> = [];

	static function step(label:String, f:Void->Void) {
		try {
			f();
		} catch (e:flash.errors.Error) {
			H.log(label + " THREW " + qn(e) + " #" + e.errorID + " " + e.message);
		} catch (e:Dynamic) {
			H.log(label + " THREW other " + Std.string(e));
		}
	}

	static function def(name:String):Dynamic {
		try {
			return untyped __global__["flash.utils.getDefinitionByName"](name);
		} catch (e:Dynamic) {
			return null;
		}
	}

	static function bp(s:Dynamic):String {
		try {
			return Std.string(s.bytesPending);
		} catch (e:flash.errors.Error) {
			return "THREW #" + e.errorID;
		}
	}

	static function hex(ba:ByteArray):String {
		var s = "";
		ba.position = 0;
		while (ba.bytesAvailable > 0) {
			var b = ba.readUnsignedByte();
			s += StringTools.hex(b, 2);
		}
		return s;
	}

	static function roundTrip(label:String, v:Dynamic, enc:Int) {
		step(label, function() {
			var ba = new ByteArray();
			ba.objectEncoding = enc;
			ba.writeObject(v);
			ba.position = 0;
			var back:Dynamic = ba.readObject();
			var names = Reflect.fields(back);
			names.sort(Reflect.compare);
			var parts = [];
			for (n in names)
				parts.push(n + "=" + Std.string(Reflect.field(back, n)));
			H.log(label + " amf" + enc + " len=" + ba.length + " back=" + qn(back) + "{" + parts.join(",") + "} hex=" + hex(ba));
		});
	}

	static function nc(label:String, cmd:Dynamic, ?args:Array<Dynamic>) {
		var c = new NetConnection();
		ncs.push(c);
		var t0 = Lib.getTimer();
		c.addEventListener(NetStatusEvent.NET_STATUS, function(e:NetStatusEvent) {
			H.log(label + " netStatus " + e.info.code + " level=" + e.info.level + " connected=" + c.connected + " uri=" + c.uri + " t=" + (Lib.getTimer() - t0 > 500 ? ">500ms" : "<500ms"));
		});
		c.addEventListener(IOErrorEvent.IO_ERROR, function(e:IOErrorEvent) H.log(label + " ioError " + e.text));
		c.addEventListener(SecurityErrorEvent.SECURITY_ERROR, function(e:SecurityErrorEvent) H.log(label + " securityError " + e.text));
		c.addEventListener(AsyncErrorEvent.ASYNC_ERROR, function(e:AsyncErrorEvent) H.log(label + " asyncError " + e.text));
		step(label, function() {
			if (args == null)
				c.connect(cmd);
			else
				Reflect.callMethod(c, Reflect.field(c, "connect"), [cmd].concat(args));
			H.log(label + " returned connected=" + c.connected + " uri=" + c.uri);
			try {
				H.log(label + " protocol=" + c.protocol);
			} catch (e:flash.errors.Error) {
				H.log(label + " protocol THREW #" + e.errorID);
			}
		});
	}

	static function main() {
		qn = untyped __global__["flash.utils.getQualifiedClassName"];
		sendToURL = untyped __global__["flash.net.sendToURL"];
		H.init("d62net", 34000);
		for (sec in [secSocket, secSecure, secEnd2])
			step("section", sec);
	}

	static function secExist() {

		// --- existence of AIR-only members in FP 32
		H.log("NetMonitor def=" + (def("flash.net.NetMonitor") != null));
		H.log("SecureSocket def=" + (def("flash.net.SecureSocket") != null));
		H.log("X509Certificate def=" + (def("flash.security.X509Certificate") != null));
		H.log("CertificateStatus def=" + (def("flash.security.CertificateStatus") != null));
		var r = new URLRequest("http://a/b");
		H.log("URLRequest.useRedirectedURL in=" + (untyped __in__("useRedirectedURL", r)) + " followRedirects in=" + (untyped __in__("followRedirects", r)));
		var ndef = def("flash.net.NetMonitor");
		if (ndef != null) {
			step("NetMonitor", function() {
				var ncm = new NetConnection();
				ncm.connect(null);
				var ns0 = new NetStream(ncm);
				var m:Dynamic = Type.createInstance(ndef, []);
				var l0:Dynamic = m.listStreams();
				H.log("NetMonitor listStreams=" + qn(l0) + " len=" + l0.length + " has ns0=" + (l0.indexOf(ns0) >= 0) + " fixed=" + l0.fixed + " same list=" + (m.listStreams() == l0));
				m.addEventListener("netStreamCreate", function(e:Dynamic) {
					H.log("NetMonitor event " + e.type + " netStream=" + qn(e.netStream) + " isNs1=" + (e.netStream == D62Net.ns1) + " eventClass=" + qn(e) + " listLen=" + m.listStreams().length);
				});
				var m2:Dynamic = Type.createInstance(ndef, []);
				m2.addEventListener("netStreamCreate", function(e:Dynamic) H.log("NetMonitor2 event " + e.type));
				D62Net.ns1 = new NetStream(ncm);
				H.log("NetMonitor after ns1 synchronous len=" + m.listStreams().length);
				ns0.close();
				H.log("NetMonitor after ns0.close len=" + m.listStreams().length);
				ns0.dispose();
				H.log("NetMonitor after ns0.dispose len=" + m.listStreams().length);
				ncm.close();
				H.log("NetMonitor after nc.close len=" + m.listStreams().length);
			});
		}
	}

	static function secRedirect() {
		// --- URLRequest.useRedirectedURL
		step("useRedirectedURL null", function() {
			var r2 = new URLRequest("http://127.0.0.1:18765/x/y.txt");
			Reflect.callMethod(r2, Reflect.field(r2, "useRedirectedURL"), [null]);
			H.log("useRedirectedURL null url=" + r2.url);
		});
		step("useRedirectedURL unloaded src", function() {
			var r2 = new URLRequest("http://127.0.0.1:18765/x/y.txt");
			var src = new URLRequest("http://example.com/a/b.txt");
			try {
				Reflect.callMethod(r2, Reflect.field(r2, "useRedirectedURL"), [src]);
				H.log("useRedirectedURL unloaded url=" + r2.url);
			} catch (e:flash.errors.Error) {
				H.log("useRedirectedURL unloaded THREW " + qn(e) + " #" + e.errorID + " " + e.message + " url=" + r2.url);
			}
			var r3 = new URLRequest();
			Reflect.callMethod(r3, Reflect.field(r3, "useRedirectedURL"), [src, true]);
			H.log("useRedirectedURL unloaded nourl url=" + r3.url);
		});
		pending++;
		var srcReq = new URLRequest(H.BASE + "/data/redirect?to=" + StringTools.urlEncode("http://localhost:18765/data/text?v=redirected"));
		var ul = new URLLoader();
		ul.addEventListener(HTTPStatusEvent.HTTP_STATUS, function(e:Dynamic) {
			H.log("redirect httpStatus " + e.status + " redirected-in=" + (untyped __in__("redirected", e)) + " responseURL-in=" + (untyped __in__("responseURL", e)) + " redirected=" + Reflect.field(e, "redirected") + " responseURL=" + Reflect.field(e, "responseURL"));
		});
		ul.addEventListener(Event.COMPLETE, function(_) {
			H.log("redirect complete data=" + ul.data + " srcReq.url=" + srcReq.url);
			step("useRedirectedURL loaded", function() {
				var r2 = new URLRequest("http://127.0.0.1:18765/x/y.txt?q=1");
				Reflect.callMethod(r2, Reflect.field(r2, "useRedirectedURL"), [srcReq]);
				H.log("useRedirectedURL domain url=" + r2.url);
				var r3 = new URLRequest("http://127.0.0.1:18765/x/y.txt?q=1");
				Reflect.callMethod(r3, Reflect.field(r3, "useRedirectedURL"), [srcReq, true]);
				H.log("useRedirectedURL whole url=" + r3.url);
				var r4 = new URLRequest("http://127.0.0.1:18765/x/y.txt?q=1");
				Reflect.callMethod(r4, Reflect.field(r4, "useRedirectedURL"), [srcReq, false, "y.txt", "z.txt"]);
				H.log("useRedirectedURL pattern url=" + r4.url);
				var r5 = new URLRequest("http://127.0.0.1:18765/x/y.txt?q=1");
				Reflect.callMethod(r5, Reflect.field(r5, "useRedirectedURL"), [srcReq, true, ~/t/g, "T"]);
				H.log("useRedirectedURL regexp url=" + r5.url);
				var r6 = new URLRequest("http://127.0.0.1:18765/x/y.txt?q=1");
				Reflect.callMethod(r6, Reflect.field(r6, "useRedirectedURL"), [srcReq, false, "y.txt", null]);
				H.log("useRedirectedURL pattern nullreplace url=" + r6.url);
				var r7 = new URLRequest();
				Reflect.callMethod(r7, Reflect.field(r7, "useRedirectedURL"), [srcReq]);
				H.log("useRedirectedURL nourl url=" + r7.url);
				var r8 = new URLRequest("relative/path.txt");
				Reflect.callMethod(r8, Reflect.field(r8, "useRedirectedURL"), [srcReq]);
				H.log("useRedirectedURL relative url=" + r8.url);
				var r9 = new URLRequest("https://other.example:8443/x/y.txt");
				Reflect.callMethod(r9, Reflect.field(r9, "useRedirectedURL"), [srcReq]);
				H.log("useRedirectedURL otherscheme url=" + r9.url);
			});
			// a request that was loaded but not redirected
			var plain = new URLRequest(H.BASE + "/data/text?v=plain");
			var ul2 = new URLLoader();
			ul2.addEventListener(Event.COMPLETE, function(_) {
				step("useRedirectedURL unredirected", function() {
					var r2 = new URLRequest("http://127.0.0.1:18765/x/y.txt");
					Reflect.callMethod(r2, Reflect.field(r2, "useRedirectedURL"), [plain]);
					H.log("useRedirectedURL unredirected url=" + r2.url);
				});
				pending--;
			});
			ul2.load(plain);
		});
		ul.addEventListener(IOErrorEvent.IO_ERROR, function(e:IOErrorEvent) { H.log("redirect ioError " + e.text); pending--; });
		ul.load(srcReq);

	}

	static function secSendToURL() {
		// --- sendToURL
		step("sendToURL(null)", function() {
			sendToURL(null);
			H.log("sendToURL(null) returned");
		});
		step("sendToURL(new URLRequest())", function() {
			sendToURL(new URLRequest());
			H.log("sendToURL(nullurl) returned");
		});
		step("sendToURL get", function() {
			sendToURL(new URLRequest(H.BASE + "/data/text?v=sendToURL-get"));
			H.log("sendToURL get returned");
		});
		step("sendToURL post", function() {
			var rq = new URLRequest(H.BASE + "/data/text?v=sendToURL-post");
			rq.method = URLRequestMethod.POST;
			rq.data = "payload=1";
			sendToURL(rq);
			H.log("sendToURL post returned");
		});
		step("sendToURL 404", function() {
			sendToURL(new URLRequest(H.BASE + "/data/404"));
			H.log("sendToURL 404 returned");
		});
		step("sendToURL badhost", function() {
			sendToURL(new URLRequest("http://127.0.0.1:18767/x"));
			H.log("sendToURL badhost returned");
		});
		step("sendToURL file scheme", function() {
			sendToURL(new URLRequest("file:///C:/x.txt"));
			H.log("sendToURL file returned");
		});
		step("sendToURL badscheme", function() {
			sendToURL(new URLRequest("foo://bar"));
			H.log("sendToURL foo returned");
		});

	}

	static function secFileRef() {
		// --- FileReference error paths (each call on a fresh object; no dialog is opened)
		function fresh():FileReference {
			var fr = new FileReference();
			for (ev in ["open", "progress", "complete", "cancel", "select", "ioError", "securityError", "httpStatus", "uploadCompleteData", "httpResponseStatus"])
				fr.addEventListener(ev, function(e:Event) H.log("fr event " + e.type + " " + Std.string(e)));
			return fr;
		}
		step("fr.cancel() fresh", function() {
			fresh().cancel();
			H.log("fr.cancel fresh returned");
		});
		step("fr.download(null)", function() {
			fresh().download(null);
			H.log("fr.download(null) returned");
		});
		step("fr.download(new URLRequest())", function() {
			fresh().download(new URLRequest());
			H.log("fr.download(nullurl) returned");
		});
		step("fr.download(foo://)", function() {
			fresh().download(new URLRequest("foo://bar/x.bin"));
			H.log("fr.download(foo) returned");
		});
		step("fr.download(file://)", function() {
			fresh().download(new URLRequest("file:///C:/x.bin"));
			H.log("fr.download(file) returned");
		});
		step("fr.download(req) then cancel", function() {
			var fr = fresh();
			fr.download(new URLRequest(H.BASE + "/data/blob?size=10"), "a.bin");
			H.log("fr.download(req) returned (dialog open?)");
			fr.cancel();
			H.log("fr.cancel after download returned");
			step("fr.download(req) twice", function() {
				fr.download(new URLRequest(H.BASE + "/data/blob?size=10"), "b.bin");
				H.log("fr.download(req) twice returned");
			});
			step("fr.name after download", function() H.log("fr.name=" + fr.name));
		});
		step("fr.download(req, badname)", function() {
			fresh().download(new URLRequest(H.BASE + "/data/blob?size=10"), "a/b:c.bin");
			H.log("fr.download(req, badname) returned");
		});
		step("fr.upload(null)", function() {
			fresh().upload(null);
			H.log("fr.upload(null) returned");
		});
		step("fr.upload(req) unselected", function() {
			fresh().upload(new URLRequest(H.BASE + "/upload"));
			H.log("fr.upload unselected returned");
		});
		step("fr.upload(req, '') unselected", function() {
			fresh().upload(new URLRequest(H.BASE + "/upload"), "");
			H.log("fr.upload '' returned");
		});
		step("fr.upload(req, null) unselected", function() {
			fresh().upload(new URLRequest(H.BASE + "/upload"), null);
			H.log("fr.upload null field returned");
		});
		step("fr.upload(new URLRequest()) unselected", function() {
			fresh().upload(new URLRequest());
			H.log("fr.upload nullurl returned");
		});
		step("fr.upload(foo://) unselected", function() {
			fresh().upload(new URLRequest("foo://x/y"));
			H.log("fr.upload foo returned");
		});
		step("fr.load() unselected", function() {
			fresh().load();
			H.log("fr.load returned");
		});
		step("fr.name unselected", function() H.log("fr.name=" + fresh().name));
		frl = new FileReferenceList();
		H.log("frl.fileList fresh=" + frl.fileList);

	}

	static function secDpw() {
		// --- ObjectEncoding.dynamicPropertyWriter
		step("dpw default", function() H.log("dpw default=" + Std.string(ObjectEncoding.dynamicPropertyWriter)));
		var w = new Writer("b");
		step("dpw set", function() {
			ObjectEncoding.dynamicPropertyWriter = cast w;
			H.log("dpw set same=" + (ObjectEncoding.dynamicPropertyWriter == cast w));
		});
		step("dpw set bad", function() {
			var o:Dynamic = {};
			Reflect.setField(ObjectEncoding, "dynamicPropertyWriter", o);
			H.log("dpw set plain object ok=" + Std.string(ObjectEncoding.dynamicPropertyWriter));
		});
		ObjectEncoding.dynamicPropertyWriter = cast w;
		roundTrip("dpw plain", {a: 1, b: 2, c: "s"}, 3);
		roundTrip("dpw plain amf0", {a: 1, b: 2, c: "s"}, 0);
		var d = new URLVariables(); // a dynamic class with sealed methods
		Reflect.setField(d, "dynA", 5);
		Reflect.setField(d, "b", 6);
		roundTrip("dpw URLVariables", d, 3);
		roundTrip("dpw Sealed", new Sealed(), 3);
		roundTrip("dpw Array", [1, 2], 3);
		var arr:Array<Dynamic> = [1, 2];
		Reflect.setField(arr, "named", "n");
		roundTrip("dpw Array named", arr, 3);
		roundTrip("dpw nested", {outer: {inner: 1, b: 2}}, 3);
		roundTrip("dpw function value", {f: function() return 1, a: 1}, 3);
		H.log("dpw calls: " + w.calls.join(" | "));
		step("dpw output outside", function() {
			w.outputs[0].writeDynamicProperty("late", 1);
			H.log("dpw output outside returned");
		});
		step("dpw output null name", function() {
			ObjectEncoding.dynamicPropertyWriter = new Writer2(function(o:Dynamic, out:IDynamicPropertyOutput) {
				out.writeDynamicProperty(null, 1);
			});
			var ba = new ByteArray();
			ba.writeObject({a: 1});
			H.log("dpw null name len=" + ba.length + " hex=" + hex(ba));
		});
		step("dpw writer throws", function() {
			ObjectEncoding.dynamicPropertyWriter = new Writer2(function(o:Dynamic, out:IDynamicPropertyOutput) {
				throw new flash.errors.Error("boom", 77);
			});
			var ba = new ByteArray();
			ba.writeObject({a: 1});
			H.log("dpw throws len=" + ba.length);
		});
		step("dpw writer duplicate names", function() {
			ObjectEncoding.dynamicPropertyWriter = new Writer2(function(o:Dynamic, out:IDynamicPropertyOutput) {
				out.writeDynamicProperty("a", 1);
				out.writeDynamicProperty("a", 2);
			});
			var ba = new ByteArray();
			ba.writeObject({a: 0});
			ba.position = 0;
			var back:Dynamic = ba.readObject();
			H.log("dpw dup a=" + back.a + " hex=" + hex(ba));
		});
		ObjectEncoding.dynamicPropertyWriter = null;
		roundTrip("dpw cleared", {a: 1, b: 2}, 3);

	}

	static function secSocket() {
		// --- Socket.bytesPending
		var s = new Socket();
		H.log("socket fresh bytesPending=" + bp(s));
		step("socket fresh bytesAvailable", function() H.log("socket fresh bytesAvailable=" + s.bytesAvailable));
		step("socket fresh connected", function() H.log("socket fresh connected=" + s.connected));
		step("socket write unconnected", function() {
			s.writeUTFBytes("hello");
			H.log("socket write unconnected bytesPending=" + bp(s));
		});
		s.addEventListener(Event.CONNECT, function(_) {
			H.log("socket connect bytesPending=" + bp(s));
			var big = new ByteArray();
			big.length = 65536 * 4;
			s.writeInt(1000);
			s.writeUTFBytes("abc");
			H.log("socket after write bytesPending=" + bp(s));
			s.writeBytes(big);
			H.log("socket after big write bytesPending=" + bp(s));
			s.flush();
			H.log("socket after flush bytesPending=" + bp(s));
			haxe.Timer.delay(function() {
				H.log("socket 300ms later bytesPending=" + bp(s));
				s.close();
				H.log("socket closed bytesPending=" + bp(s));
				pending--;
				finish();
			}, 300);
		});
		s.addEventListener(IOErrorEvent.IO_ERROR, function(e:IOErrorEvent) {
			H.log("socket ioError " + e.text);
			pending--;
			finish();
		});
		s.addEventListener(SecurityErrorEvent.SECURITY_ERROR, function(e:SecurityErrorEvent) {
			H.log("socket securityError " + e.text);
			pending--;
			finish();
		});
		pending++;
		s.connect("127.0.0.1", 18766);

	}

	static function secSecure() {
		// --- SecureSocket
		var sdef = def("flash.net.SecureSocket");
		if (sdef != null) {
			step("SecureSocket.isSupported", function() H.log("SecureSocket.isSupported=" + Reflect.field(sdef, "isSupported")));
			step("new SecureSocket", function() {
				var ss:Dynamic = Type.createInstance(sdef, []);
				H.log("SecureSocket status=" + ss.serverCertificateStatus + " cert=" + ss.serverCertificate + " connected=" + ss.connected + " bytesPending=" + bp(ss));
				step("ss.addBinaryChainBuildingCertificate(null)", function() {
					ss.addBinaryChainBuildingCertificate(null, false);
					H.log("ss.addBinary null returned");
				});
				step("ss.addBinaryChainBuildingCertificate(garbage)", function() {
					var ba = new ByteArray();
					ba.writeUTFBytes("not a cert");
					ss.addBinaryChainBuildingCertificate(ba, true);
					H.log("ss.addBinary garbage returned");
				});
				for (ev in ["connect", "close", "ioError", "securityError", "socketData"])
					ss.addEventListener(ev, function(e:Event) {
						H.log("ss event " + e.type + " " + Std.string(e) + " status=" + ss.serverCertificateStatus + " cert=" + ss.serverCertificate);
						if (e.type != "socketData") {
							pending--;
							finish();
						}
					});
				pending++;
				step("ss.connect refused", function() {
					ss.connect("127.0.0.1", 18767);
					H.log("ss.connect refused returned status=" + ss.serverCertificateStatus);
				});
				var ss2:Dynamic = Type.createInstance(sdef, []);
				for (ev in ["connect", "close", "ioError", "securityError"])
					ss2.addEventListener(ev, function(e:Event) {
						H.log("ss2 event " + e.type + " " + Std.string(e) + " status=" + ss2.serverCertificateStatus);
						pending--;
						finish();
					});
				pending++;
				step("ss2.connect plain server", function() {
					ss2.connect("127.0.0.1", 18766);
					H.log("ss2.connect plain returned status=" + ss2.serverCertificateStatus);
				});
			});
		}

	}

	static function secNc() {
		// --- NetConnection.connect with non-HTTP commands
		nc("nc null", null);
		nc("nc empty", "");
		nc("nc foo", "foo://bar/app");
		nc("nc rtmp refused", "rtmp://127.0.0.1:18767/app");
		nc("nc rtmp args", "rtmp://127.0.0.1:18767/app", ["user", 1]);
		nc("nc rtmfp", "rtmfp:");
		nc("nc rtmfp host", "rtmfp://127.0.0.1:18767/app");
		nc("nc rtmps", "rtmps://127.0.0.1:18767/app");
		nc("nc rtmpt", "rtmpt://127.0.0.1:18767/app");
		nc("nc rtmp plain server", "rtmp://127.0.0.1:18766/app");
		nc("nc rtmp nohost", "rtmp:///app");
		nc("nc http ok", H.BASE + "/gateway");
		nc("nc badword", "hello");
		nc("nc rtmp then close", "rtmp://127.0.0.1:18767/app");
		step("nc close last", function() {
			ncs[ncs.length - 1].close();
			H.log("nc close last returned");
		});

	}

	static function secEnd2() {
		haxe.Timer.delay(function() {
			H.log("# after 30s pending=" + pending);
			H.done();
		}, 30000);
	}

	static function secEnd() {
		haxe.Timer.delay(function() {
			step("frl.browse([bad])", function() {
				H.log("frl.browse bad returned " + frl.browse(cast [1]));
			});
			step("frl.browse([filter bad ext])", function() {
				H.log("frl.browse badfilter returned " + frl.browse([new FileFilter("Images", "")]));
			});
		}, 13500);
		haxe.Timer.delay(function() {
			H.log("# after 14s pending=" + pending);
			for (i in 0...ncs.length)
				H.log("nc[" + i + "] connected=" + ncs[i].connected + " uri=" + ncs[i].uri);
			H.done();
		}, 14000);
	}

	static function finish() {
		// keep running until the 14 s timer; events are logged as they come
	}
}
