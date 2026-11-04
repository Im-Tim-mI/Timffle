/** Probe (no golden): flash.net.SharedObject members Ruffle still stubs or lacks (client, connect,
 *  fps, send, setDirty, defaultObjectEncoding, deleteAll, getDiskUsage, getRemote, preventBackup,
 *  close, objectEncoding). Build with -swf-version 32, run in the standalone Flash Player 32 projector
 *  served over HTTP (so getLocal has a host). */
import flash.net.NetConnection;

class D45SharedObject {
	static var SO:Dynamic;
	static var url:String;

	static function step(label:String, f:Void->Void) {
		try {
			f();
		} catch (e:flash.errors.Error) {
			H.log(label + " THREW " + e.name + " #" + e.errorID + " " + e.message);
		}
	}

	static function main() {
		H.init("d45sharedobject");
		SO = untyped __global__["flash.net.SharedObject"];
		url = flash.Lib.current.loaderInfo.url;
		var qn:Dynamic = untyped __global__["flash.utils.getQualifiedClassName"];
		H.log("url=" + url);
		step("defaultObjectEncoding", function() H.log("defaultObjectEncoding=" + SO.defaultObjectEncoding));
		for (v in [0, 1, 3, 5, 2]) {
			step("defaultObjectEncoding=" + v, function() { SO.defaultObjectEncoding = v; H.log("defaultObjectEncoding=" + v + " -> " + SO.defaultObjectEncoding); });
		}
		step("defaultObjectEncoding=3", function() SO.defaultObjectEncoding = 3);
		step("preventBackup", function() H.log("preventBackup=" + SO.preventBackup));
		step("preventBackup=true", function() { SO.preventBackup = true; H.log("preventBackup=true -> " + SO.preventBackup); });
		step("preventBackup=false", function() SO.preventBackup = false);

		// clean slate
		step("deleteAll(url) first", function() H.log("deleteAll(url) first = " + SO.deleteAll(url)));
		step("getDiskUsage(url) empty", function() H.log("getDiskUsage(url) empty = " + SO.getDiskUsage(url)));

		var so:Dynamic = null;
		step("getLocal", function() { so = SO.getLocal("probe"); H.log("getLocal ok objectEncoding=" + so.objectEncoding + " size=" + so.size); });
		step("client default", function() H.log("client == so: " + (so.client == so) + " client=" + qn(so.client)));
		step("client=obj", function() { var o = {}; so.client = o; H.log("client=obj -> same " + (so.client == o)); });
		step("client=null", function() { so.client = null; H.log("client=null -> " + so.client + " == so " + (so.client == so)); });
		step("client=1", function() { so.client = 1; H.log("client=1 -> " + so.client); });
		step("fps read", function() H.log("fps read = " + Reflect.field(so, "fps")));
		step("fps=10", function() { so.fps = 10; H.log("fps=10 ok"); });
		step("fps=-1", function() { so.fps = -1; H.log("fps=-1 ok"); });
		step("setDirty", function() { so.setDirty("x"); H.log("setDirty(x) ok"); });
		step("setDirty(null)", function() { so.setDirty(null); H.log("setDirty(null) ok"); });
		step("send on local", function() { so.send("m", 1); H.log("send on local ok"); });
		step("connect(null) on local", function() { so.connect(null); H.log("connect(null) local ok"); });
		step("connect(unconnected nc) on local", function() { so.connect(new NetConnection()); H.log("connect(nc) local ok"); });
		step("connect(connected null nc) on local", function() {
			var nc = new NetConnection();
			nc.connect(null);
			H.log("nc.connected=" + nc.connected);
			so.connect(nc);
			H.log("connect(connected nc) local ok");
		});
		for (v in [0, 1, 3, 7]) {
			step("objectEncoding=" + v, function() { so.objectEncoding = v; H.log("objectEncoding=" + v + " -> " + so.objectEncoding); });
		}
		step("objectEncoding=3", function() so.objectEncoding = 3);
		step("data+flush", function() {
			so.data.a = 1;
			so.data.s = "hello";
			H.log("flush=" + so.flush() + " size=" + so.size);
		});
		step("objectEncoding=0 size", function() { so.objectEncoding = 0; H.log("amf0 size=" + so.size + " flush=" + so.flush()); so.objectEncoding = 3; H.log("amf3 size again=" + so.size); });
		step("getDiskUsage(url)", function() H.log("getDiskUsage(url) = " + SO.getDiskUsage(url)));
		step("getDiskUsage(dir)", function() H.log("getDiskUsage(dir) = " + SO.getDiskUsage(url.substr(0, url.lastIndexOf("/") + 1))));
		step("getDiskUsage(dir no slash)", function() H.log("getDiskUsage(dir no slash) = " + SO.getDiskUsage(url.substr(0, url.lastIndexOf("/")))));
		step("getDiskUsage(host)", function() H.log("getDiskUsage(host) = " + SO.getDiskUsage("http://127.0.0.1:18765/")));
		step("getDiskUsage(host no port)", function() H.log("getDiskUsage(host no port) = " + SO.getDiskUsage("http://127.0.0.1/")));
		step("getDiskUsage(other)", function() H.log("getDiskUsage(other) = " + SO.getDiskUsage("http://example.com/")));
		step("getDiskUsage(relative)", function() H.log("getDiskUsage(relative) = " + SO.getDiskUsage("flash/d45sharedobject.swf")));
		step("getDiskUsage(empty)", function() H.log("getDiskUsage(empty) = " + SO.getDiskUsage("")));
		step("getDiskUsage(null)", function() H.log("getDiskUsage(null) = " + SO.getDiskUsage(null)));
		step("getDiskUsage(query)", function() H.log("getDiskUsage(query) = " + SO.getDiskUsage(url + "?x=1")));
		step("close local", function() { so.close(); H.log("close ok; data.a=" + so.data.a + " size=" + so.size); });
		step("after close flush", function() H.log("flush after close=" + so.flush()));
		step("after close getLocal same", function() { var so2 = SO.getLocal("probe"); H.log("same after close: " + (so2 == so) + " so2.data.a=" + so2.data.a); });
		step("after close set+flush", function() { so.data.b = 2; H.log("set after close flush=" + so.flush() + " size=" + so.size); });
		step("getLocal second name", function() { var so3 = SO.getLocal("probe2/sub"); so3.data.q = 1; H.log("probe2 flush=" + so3.flush() + " size=" + so3.size); });
		step("getDiskUsage(url) two", function() H.log("getDiskUsage(url) two = " + SO.getDiskUsage(url)));
		step("deleteAll(other)", function() H.log("deleteAll(other) = " + SO.deleteAll("http://example.com/")));
		step("deleteAll(dir)", function() H.log("deleteAll(dir) = " + SO.deleteAll(url.substr(0, url.lastIndexOf("/") + 1))));
		step("deleteAll(url)", function() H.log("deleteAll(url) = " + SO.deleteAll(url) + " then so.data.a=" + so.data.a + " size=" + so.size + " usage=" + SO.getDiskUsage(url)));
		step("deleteAll(url) again", function() H.log("deleteAll(url) again = " + SO.deleteAll(url)));
		step("deleteAll(null)", function() H.log("deleteAll(null) = " + SO.deleteAll(null)));
		step("getLocal after deleteAll", function() { var so4 = SO.getLocal("probe"); H.log("after deleteAll same=" + (so4 == so) + " data.a=" + so4.data.a + " data.b=" + so4.data.b); });
		step("flush after deleteAll", function() H.log("flush after deleteAll=" + so.flush() + " usage=" + SO.getDiskUsage(url)));
		step("deleteAll cleanup", function() SO.deleteAll(url));

		step("getRemote(null path)", function() { var r = SO.getRemote("r1"); H.log("getRemote(r1) = " + qn(r) + " " + r); });
		step("getRemote(null path, null name)", function() { var r = SO.getRemote(null); H.log("getRemote(null) = " + qn(r) + " " + r); });
		var r:Dynamic = null;
		step("getRemote", function() {
			r = SO.getRemote("r2", "rtmp://127.0.0.1/app", false);
			H.log("getRemote = " + qn(r) + " size=" + r.size + " objectEncoding=" + r.objectEncoding + " data=" + qn(r.data));
		});
		step("getRemote same", function() { var r2 = SO.getRemote("r2", "rtmp://127.0.0.1/app", false); H.log("getRemote same = " + (r2 == r)); });
		step("getRemote persist", function() { var r3 = SO.getRemote("r2", "rtmp://127.0.0.1/app", true); H.log("getRemote persist same = " + (r3 == r)); });
		step("remote data set", function() { r.data.z = 1; H.log("remote data.z=" + r.data.z + " size=" + r.size); });
		step("remote flush", function() H.log("remote flush = " + r.flush()));
		step("remote send", function() { r.send("m", 1); H.log("remote send ok"); });
		step("remote setDirty", function() { r.setDirty("z"); H.log("remote setDirty ok"); });
		step("remote connect(null)", function() { r.connect(null); H.log("remote connect(null) ok"); });
		step("remote connect(unconnected)", function() { r.connect(new NetConnection()); H.log("remote connect(unconnected) ok"); });
		step("remote connect(null-connected)", function() {
			var nc = new NetConnection();
			nc.connect(null);
			r.addEventListener("netStatus", function(e:Dynamic) H.log("remote netStatus " + e.info.code + " level=" + e.info.level));
			r.addEventListener("sync", function(e:Dynamic) H.log("remote sync " + e.changeList.length));
			r.addEventListener("asyncError", function(e:Dynamic) H.log("remote asyncError " + e.text));
			r.connect(nc);
			H.log("remote connect(null-connected) ok");
		});
		step("remote close", function() { r.close(); H.log("remote close ok size=" + r.size); });
		step("remote clear", function() { r.clear(); H.log("remote clear ok"); });
		step("getRemote(local-looking path)", function() { var r4 = SO.getRemote("r5", "http://127.0.0.1/"); H.log("getRemote http = " + qn(r4)); });
		haxe.Timer.delay(function() H.done(), 1500);
	}
}
