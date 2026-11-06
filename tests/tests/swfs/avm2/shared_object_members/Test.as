package {
import flash.display.Sprite;
import flash.net.NetConnection;
import flash.net.SharedObject;
import flash.events.NetStatusEvent;

// The flash.net.SharedObject members that were missing or stubs. Expected values are those
// of the standalone Flash Player 32.0.0.465 (timffle/difftest/src/D45SharedObject.hx):
// objectEncoding 0/3 only, client defaults to the object itself, connect() without a server
// raises #2139 (UriMismatch first on a connected NetConnection), getRemote() needs an RTMP
// path, deleteAll()/getDiskUsage() are AIR-only (#2014), preventBackup reads null at first.
public class Test extends Sprite {
    public function Test() {
        step("defaultObjectEncoding", function():void { trace("defaultObjectEncoding = " + SharedObject.defaultObjectEncoding); });
        step("defaultObjectEncoding = 5", function():void { SharedObject.defaultObjectEncoding = 5; trace("-> " + SharedObject.defaultObjectEncoding); });
        step("defaultObjectEncoding = 0", function():void { SharedObject.defaultObjectEncoding = 0; trace("-> " + SharedObject.defaultObjectEncoding); });
        var amf0:SharedObject;
        step("getLocal with default 0", function():void { amf0 = SharedObject.getLocal("amf0"); trace("objectEncoding = " + amf0.objectEncoding); });
        SharedObject.defaultObjectEncoding = 3;
        step("preventBackup", function():void { trace("preventBackup = " + SharedObject.preventBackup); });
        step("preventBackup = true", function():void { SharedObject.preventBackup = true; trace("-> " + SharedObject.preventBackup); });
        step("deleteAll(url)", function():void { trace(SharedObject.deleteAll("http://localhost/test.swf")); });
        step("deleteAll(null)", function():void { trace(SharedObject.deleteAll(null)); });
        step("getDiskUsage(url)", function():void { trace(SharedObject.getDiskUsage("http://localhost/test.swf")); });
        step("getDiskUsage(null)", function():void { trace(SharedObject.getDiskUsage(null)); });

        var so:SharedObject = SharedObject.getLocal("probe");
        step("objectEncoding", function():void { trace("objectEncoding = " + so.objectEncoding + " size = " + so.size); });
        step("client == so", function():void { trace(so.client == so); });
        var o:Object = {};
        step("client = obj", function():void { so.client = o; trace(so.client == o); });
        step("client = so", function():void { so.client = so; trace(so.client == so); });
        step("client = null", function():void { so.client = null; });
        step("client = 1", function():void { so.client = 1; });
        step("fps = 10", function():void { so.fps = 10; trace("ok"); });
        step("setDirty(x)", function():void { so.setDirty("x"); trace("ok"); });
        step("setDirty(null)", function():void { so.setDirty(null); });
        step("setProperty", function():void { so.setProperty("p", 7); trace("data.p = " + so.data.p); });
        step("send on local", function():void { so.send("m", 1); trace("ok"); });
        step("connect(null) on local", function():void { so.connect(null); });
        step("connect(unconnected nc) on local", function():void { so.connect(new NetConnection()); });
        step("objectEncoding = 1", function():void { so.objectEncoding = 1; });
        step("objectEncoding = 7", function():void { so.objectEncoding = 7; });
        step("objectEncoding = 0", function():void { so.objectEncoding = 0; trace("-> " + so.objectEncoding); });
        step("objectEncoding = 3", function():void { so.objectEncoding = 3; trace("-> " + so.objectEncoding); });

        delete so.data.p;
        so.data.a = 1;
        so.data.s = "hello";
        step("flush AMF3", function():void { trace(so.flush() + " size = " + so.size); });
        step("size AMF0", function():void { so.objectEncoding = 0; trace(so.flush() + " size = " + so.size); so.objectEncoding = 3; trace("AMF3 again size = " + so.size); });
        step("close local", function():void { so.close(); trace("data.a = " + so.data.a + " size = " + so.size + " flush = " + so.flush()); });
        step("getLocal after close", function():void { trace(SharedObject.getLocal("probe") == so); });

        step("getRemote(name)", function():void { SharedObject.getRemote("r1"); });
        step("getRemote(null)", function():void { SharedObject.getRemote(null); });
        step("getRemote(http path)", function():void { SharedObject.getRemote("r5", "http://localhost/"); });
        var r:SharedObject;
        step("getRemote(rtmp)", function():void {
            r = SharedObject.getRemote("r2", "rtmp://localhost/app", false);
            trace("size = " + r.size + " objectEncoding = " + r.objectEncoding + " data = " + r.data);
        });
        step("getRemote same", function():void { trace(SharedObject.getRemote("r2", "rtmp://localhost/app", false) == r); });
        step("getRemote persistent differs", function():void { trace(SharedObject.getRemote("r2", "rtmp://localhost/app", true) == r); });
        step("getRemote RTMFP", function():void { trace(SharedObject.getRemote("r3", "RTMFP://localhost/app") != null); });
        step("remote data", function():void { r.data.z = 1; trace("data.z = " + r.data.z + " size = " + r.size); });
        step("remote flush", function():void { trace(r.flush()); });
        step("remote send", function():void { r.send("m", 1); trace("ok"); });
        step("remote setDirty", function():void { r.setDirty("z"); trace("ok"); });
        step("remote connect(null)", function():void { r.connect(null); });
        step("remote connect(unconnected)", function():void { r.connect(new NetConnection()); });
        step("remote connect(connected)", function():void {
            var nc:NetConnection = new NetConnection();
            nc.connect(null);
            trace("nc.connected = " + nc.connected);
            r.addEventListener(NetStatusEvent.NET_STATUS, function(e:NetStatusEvent):void {
                trace("netStatus " + e.info.code + " level=" + e.info.level);
            });
            r.connect(nc);
        });
        step("remote close", function():void { r.close(); trace("size = " + r.size); });
        step("remote clear", function():void { r.clear(); trace("size = " + r.size); });
    }

    static function step(label:String, f:Function):void {
        trace("// " + label);
        try {
            f();
        } catch (e:Error) {
            trace(e.name + " #" + e.errorID + ": " + e.message);
        }
    }
}
}
