package {
import flash.display.Sprite;
import flash.events.DataEvent;
import flash.events.Event;
import flash.events.HTTPStatusEvent;
import flash.events.IOErrorEvent;
import flash.events.NetStatusEvent;
import flash.events.ProgressEvent;
import flash.net.FileFilter;
import flash.net.FileReference;
import flash.net.FileReferenceList;
import flash.net.IDynamicPropertyOutput;
import flash.net.IDynamicPropertyWriter;
import flash.net.NetConnection;
import flash.net.NetMonitor;
import flash.net.NetStream;
import flash.net.ObjectEncoding;
import flash.net.SecureSocket;
import flash.net.Socket;
import flash.net.URLLoader;
import flash.net.URLRequest;
import flash.net.URLRequestMethod;
import flash.net.URLVariables;
import flash.net.sendToURL;
import flash.utils.ByteArray;
import flash.utils.getQualifiedClassName;

// flash.net members Ruffle used to stub or lack: sendToURL, FileReference cancel/download/upload,
// FileReferenceList.browse, NetConnection.connect with non-HTTP commands, NetMonitor,
// ObjectEncoding.dynamicPropertyWriter, SecureSocket, Socket.bytesPending and
// URLRequest.useRedirectedURL. Error codes, AMF bytes and event orders are what the standalone
// Flash Player 32.0.0.465 printed (timffle/difftest/src/D62Net.hx); the dialog and HTTP parts use
// the test harness' magic names (debug-select-success, debug-success.txt, ?debug-success,
// ?debug-error-dns, ?debug-error-statuscode).
public class Test extends Sprite {
    private var frame:int = 0;
    private var ncs:Array = [];
    private var sealedWriter:Writer;

    public function Test() {
        sendToUrlPart();
        socketPart();
        redirectedUrlPart();
        netConnectionPart();
        dynamicPropertyWriterPart();
        netMonitorPart();
        secureSocketPart();
        fileReferencePart();
        fileReferenceListPart();
        addEventListener(Event.ENTER_FRAME, onFrame);
    }

    private function step(label:String, f:Function):void {
        try {
            f();
        } catch (e:Error) {
            trace(label + " THREW " + getQualifiedClassName(e) + " #" + e.errorID);
        }
    }

    private function onFrame(e:Event):void {
        frame++;
        if (frame == 4) {
            trace("// frame 4");
            for (var i:int = 0; i < ncs.length; i++) {
                trace("nc[" + i + "] connected=" + ncs[i].connected + " uri=" + ncs[i].uri);
            }
        }
    }

    // --- flash.net.sendToURL

    private function sendToUrlPart():void {
        trace("// sendToURL");
        step("sendToURL(null)", function():void { sendToURL(null); });
        step("sendToURL(new URLRequest())", function():void { sendToURL(new URLRequest()); });
        step("sendToURL get", function():void {
            sendToURL(new URLRequest("ping.txt?debug-success"));
            trace("sendToURL get returned");
        });
        step("sendToURL post", function():void {
            var req:URLRequest = new URLRequest("ping.txt?debug-success");
            req.method = URLRequestMethod.POST;
            req.data = "payload=1";
            sendToURL(req);
            trace("sendToURL post returned");
        });
        step("sendToURL unknown scheme", function():void {
            sendToURL(new URLRequest("foo://bar"));
            trace("sendToURL foo returned");
        });
    }

    // --- Socket.bytesPending

    private function socketPart():void {
        trace("// Socket.bytesPending");
        var s:Socket = new Socket();
        step("bytesPending unconnected", function():void { trace(s.bytesPending); });
        s.addEventListener(Event.CONNECT, function(e:Event):void {
            trace("socket connect bytesPending=" + s.bytesPending);
            s.writeInt(1000);
            s.writeUTFBytes("abc");
            trace("socket after write bytesPending=" + s.bytesPending);
            s.flush();
            trace("socket after flush bytesPending=" + s.bytesPending);
            s.close();
            step("bytesPending closed", function():void { trace(s.bytesPending); });
        });
        s.connect("localhost", 8001);
    }

    // --- URLRequest.useRedirectedURL

    private function redirectedUrlPart():void {
        trace("// URLRequest.useRedirectedURL");
        step("useRedirectedURL(null)", function():void {
            var r:URLRequest = new URLRequest("http://127.0.0.1:18765/x/y.txt");
            r.useRedirectedURL(null);
            trace("useRedirectedURL(null) url=" + r.url);
        });
        step("useRedirectedURL unloaded", function():void {
            var r:URLRequest = new URLRequest("http://127.0.0.1:18765/x/y.txt");
            r.useRedirectedURL(new URLRequest("http://example.com/a/b.txt"));
        });
        step("useRedirectedURL no url", function():void {
            new URLRequest().useRedirectedURL(new URLRequest("http://example.com/a/b.txt"), true);
        });
        var src:URLRequest = new URLRequest("data.txt?debug-success");
        var loader:URLLoader = new URLLoader();
        loader.addEventListener(Event.COMPLETE, function(e:Event):void {
            trace("// source request loaded: " + loader.data);
            step("useRedirectedURL loaded", function():void {
                var r:URLRequest = new URLRequest("http://127.0.0.1:18765/x/y.txt?q=1");
                r.useRedirectedURL(src);
                trace("useRedirectedURL domain url=" + r.url);
                r.useRedirectedURL(src, true, "y.txt", "z.txt");
                trace("useRedirectedURL whole+pattern url=" + r.url);
            });
        });
        loader.load(src);
    }

    // --- NetConnection.connect with non-HTTP commands

    private function nc(label:String, command:String):NetConnection {
        var c:NetConnection = new NetConnection();
        ncs.push(c);
        c.addEventListener(NetStatusEvent.NET_STATUS, function(e:NetStatusEvent):void {
            trace(label + " netStatus " + e.info.code + " level=" + e.info.level + " connected=" + c.connected + " uri=" + c.uri);
        });
        step(label, function():void {
            c.connect(command);
            trace(label + " returned connected=" + c.connected + " uri=" + c.uri);
            step(label + " protocol", function():void { trace(c.protocol); });
            step(label + " call", function():void { c.call("method", null); });
        });
        return c;
    }

    private function netConnectionPart():void {
        trace("// NetConnection.connect");
        nc("nc empty", "");
        nc("nc rtmp", "rtmp://localhost:1935/app");
        nc("nc rtmps", "rtmps://localhost/app");
        nc("nc rtmfp", "rtmfp:");
        nc("nc foo", "foo://bar/app");
        nc("nc word", "hello");
        var closed:NetConnection = nc("nc rtmp then close", "rtmp://localhost/app");
        closed.close();
        trace("nc rtmp then close closed, uri=" + closed.uri);
    }

    // --- ObjectEncoding.dynamicPropertyWriter

    private function hex(ba:ByteArray):String {
        var s:String = "";
        ba.position = 0;
        while (ba.bytesAvailable > 0) {
            var b:uint = ba.readUnsignedByte();
            s += (b < 16 ? "0" : "") + b.toString(16).toUpperCase();
        }
        return s;
    }

    private function roundTrip(label:String, v:*, encoding:uint):void {
        step(label, function():void {
            var ba:ByteArray = new ByteArray();
            ba.objectEncoding = encoding;
            ba.writeObject(v);
            ba.position = 0;
            var back:* = ba.readObject();
            var names:Array = [];
            for (var n:String in back) {
                names.push(n);
            }
            names.sort();
            var parts:Array = [];
            for each (var name:String in names) {
                parts.push(name + "=" + back[name]);
            }
            trace(label + " amf" + encoding + " len=" + ba.length + " back=" + getQualifiedClassName(back) + "{" + parts.join(",") + "} hex=" + hex(ba));
        });
    }

    private function dynamicPropertyWriterPart():void {
        trace("// ObjectEncoding.dynamicPropertyWriter");
        trace("default=" + ObjectEncoding.dynamicPropertyWriter);
        var w:Writer = new Writer("b");
        ObjectEncoding.dynamicPropertyWriter = w;
        trace("set same=" + (ObjectEncoding.dynamicPropertyWriter == w));
        step("set plain object", function():void {
            var o:* = {};
            ObjectEncoding.dynamicPropertyWriter = o;
        });
        trace("still same=" + (ObjectEncoding.dynamicPropertyWriter == w));

        roundTrip("plain", {a: 1, b: 2, c: "s"}, 3);
        roundTrip("plain", {a: 1, b: 2, c: "s"}, 0);
        var uv:URLVariables = new URLVariables();
        uv.dynA = 5;
        uv.b = 6;
        roundTrip("URLVariables", uv, 3);
        roundTrip("Sealed", new Sealed(), 3);
        roundTrip("Array", [1, 2], 3);
        var arr:Array = [1, 2];
        arr.named = "n";
        roundTrip("Array named", arr, 3);
        roundTrip("nested", {outer: {inner: 1, b: 2}}, 3);
        roundTrip("function value", {f: function():int { return 1; }, a: 1}, 3);
        trace("calls: " + w.calls.join(" | "));
        step("output after the callback", function():void {
            w.outputs[0].writeDynamicProperty("late", 1);
            trace("late write ignored");
        });
        roundTrip("plain again", {a: 1}, 3);

        step("null name", function():void {
            ObjectEncoding.dynamicPropertyWriter = new Writer2(function(o:Object, out:IDynamicPropertyOutput):void {
                out.writeDynamicProperty(null, 1);
            });
            new ByteArray().writeObject({a: 1});
        });
        step("writer throws", function():void {
            ObjectEncoding.dynamicPropertyWriter = new Writer2(function(o:Object, out:IDynamicPropertyOutput):void {
                throw new Error("boom", 77);
            });
            var ba:ByteArray = new ByteArray();
            ba.writeObject({a: 1});
        });
        step("duplicate names", function():void {
            ObjectEncoding.dynamicPropertyWriter = new Writer2(function(o:Object, out:IDynamicPropertyOutput):void {
                out.writeDynamicProperty("a", 1);
                out.writeDynamicProperty("a", 2);
            });
            var ba:ByteArray = new ByteArray();
            ba.writeObject({a: 0});
            ba.position = 0;
            trace("duplicate a=" + ba.readObject().a + " hex=" + hex(ba));
        });
        ObjectEncoding.dynamicPropertyWriter = null;
        trace("cleared=" + ObjectEncoding.dynamicPropertyWriter);
        roundTrip("cleared", {a: 1, b: 2}, 3);
    }

    // --- NetMonitor

    private function netMonitorPart():void {
        trace("// NetMonitor");
        var conn:NetConnection = new NetConnection();
        conn.connect(null);
        var ns0:NetStream = new NetStream(conn);
        var m:NetMonitor = new NetMonitor();
        var list:Vector.<NetStream> = m.listStreams();
        trace("listStreams " + getQualifiedClassName(list) + " len=" + list.length + " has ns0=" + (list.indexOf(ns0) >= 0) + " fixed=" + list.fixed + " same list=" + (m.listStreams() == list));
        var ns1:NetStream;
        m.addEventListener("netStreamCreate", function(e:*):void {
            trace("monitor event " + e.type + " " + getQualifiedClassName(e) + " netStream=" + getQualifiedClassName(e.netStream) + " isNs1=" + (e.netStream == ns1) + " listLen=" + m.listStreams().length);
        });
        var m2:NetMonitor = new NetMonitor();
        m2.addEventListener("netStreamCreate", function(e:*):void {
            trace("monitor2 event " + e.type);
        });
        ns1 = new NetStream(conn);
        trace("after ns1 len=" + m.listStreams().length + " [1] is ns1=" + (m.listStreams()[1] == ns1));
        ns0.close();
        ns0.dispose();
        trace("after close+dispose len=" + m.listStreams().length);
    }

    // --- SecureSocket

    private function secureSocketPart():void {
        trace("// SecureSocket");
        trace("isSupported=" + SecureSocket.isSupported);
        step("new SecureSocket()", function():void { new SecureSocket(); });
    }

    // --- FileReference

    private function listen(fr:FileReference, label:String):void {
        var events:Array = ["open", "progress", "complete", "cancel", "select", "ioError", "securityError", "httpStatus", "uploadCompleteData"];
        for each (var type:String in events) {
            fr.addEventListener(type, function(e:Event):void {
                var extra:String = "";
                if (e is ProgressEvent) {
                    extra = " " + ProgressEvent(e).bytesLoaded + "/" + ProgressEvent(e).bytesTotal;
                } else if (e is IOErrorEvent) {
                    extra = " #" + IOErrorEvent(e).errorID;
                } else if (e is HTTPStatusEvent) {
                    extra = " status=" + HTTPStatusEvent(e).status;
                } else if (e is DataEvent) {
                    extra = " data=" + DataEvent(e).data;
                }
                var name:String = "";
                try {
                    name = " name=" + fr.name + " size=" + fr.size;
                } catch (err:Error) {
                    name = " name THREW #" + err.errorID;
                }
                trace(label + " event " + e.type + extra + name);
            });
        }
    }

    private function fileReferencePart():void {
        trace("// FileReference");
        var fr:FileReference = new FileReference();
        listen(fr, "fr");
        step("cancel fresh", function():void { fr.cancel(); trace("cancel returned"); });
        step("download(null)", function():void { fr.download(null); });
        step("download(new URLRequest())", function():void { fr.download(new URLRequest()); });
        step("upload(null)", function():void { fr.upload(null); });
        step("upload(req, null)", function():void { fr.upload(new URLRequest("upload.php"), null); });
        step("upload(req, '')", function():void { fr.upload(new URLRequest("upload.php"), ""); });
        step("upload(req) unselected", function():void { fr.upload(new URLRequest("upload.php")); });
        step("upload(new URLRequest()) unselected", function():void { fr.upload(new URLRequest()); });
        step("load() unselected", function():void { fr.load(); });

        // download, then cancel at once: nothing is reported
        var cancelled:FileReference = new FileReference();
        listen(cancelled, "cancelled");
        step("download then cancel", function():void {
            cancelled.download(new URLRequest("down.txt?debug-success"), "debug-success.txt");
            cancelled.cancel();
            trace("download then cancel returned");
        });

        var ok:FileReference = new FileReference();
        listen(ok, "download");
        step("download", function():void {
            ok.download(new URLRequest("down.txt?debug-success"), "debug-success.txt");
            trace("download returned");
        });

        var dns:FileReference = new FileReference();
        listen(dns, "download-dns");
        step("download dns error", function():void {
            dns.download(new URLRequest("down.txt?debug-error-dns"), "debug-success.txt");
        });

        var status:FileReference = new FileReference();
        listen(status, "download-status");
        step("download status error", function():void {
            status.download(new URLRequest("down.txt?debug-error-statuscode"), "debug-success.txt");
        });

        var dialogCancel:FileReference = new FileReference();
        listen(dialogCancel, "download-dialog-cancel");
        step("download dialog cancelled", function():void {
            dialogCancel.download(new URLRequest("down.txt?debug-success"));
        });

        // upload: browse first (the harness selects a 13-byte "Hello, World!" test.txt)
        var up:FileReference = new FileReference();
        listen(up, "upload");
        up.addEventListener(Event.SELECT, function(e:Event):void {
            step("upload", function():void {
                var req:URLRequest = new URLRequest("upload.php?debug-success");
                req.method = URLRequestMethod.POST;
                var vars:URLVariables = new URLVariables();
                vars.api_key = "k1";
                vars.title = "t 2";
                req.data = vars;
                up.upload(req, "Filedata");
                trace("upload returned");
            });
        });
        up.browse([new FileFilter("debug-select-success", "*.txt")]);

        var upErr:FileReference = new FileReference();
        listen(upErr, "upload-status");
        upErr.addEventListener(Event.SELECT, function(e:Event):void {
            step("upload status error", function():void {
                upErr.upload(new URLRequest("upload.php?debug-error-statuscode"), "file");
            });
        });
        upErr.browse([new FileFilter("debug-select-success", "*.txt")]);

        var upCancel:FileReference = new FileReference();
        listen(upCancel, "upload-cancelled");
        upCancel.addEventListener(Event.SELECT, function(e:Event):void {
            step("upload then cancel", function():void {
                upCancel.upload(new URLRequest("upload.php?debug-success"));
                upCancel.cancel();
                trace("upload then cancel returned");
            });
        });
        upCancel.browse([new FileFilter("debug-select-success", "*.txt")]);
    }

    // --- FileReferenceList

    private function fileReferenceListPart():void {
        trace("// FileReferenceList");
        var list:FileReferenceList = new FileReferenceList();
        trace("fileList fresh=" + list.fileList);
        list.addEventListener(Event.SELECT, function(e:Event):void {
            var names:Array = [];
            for each (var f:FileReference in list.fileList) {
                names.push(f.name + ":" + f.size);
            }
            trace("list select len=" + list.fileList.length + " " + names.join(","));
        });
        list.addEventListener(Event.CANCEL, function(e:Event):void {
            trace("list cancel fileList=" + list.fileList);
        });
        step("list.browse([1])", function():void { list.browse([1]); });
        step("list.browse(select)", function():void {
            trace("list.browse returned " + list.browse([new FileFilter("debug-select-success", "*.txt")]));
        });
        var list2:FileReferenceList = new FileReferenceList();
        list2.addEventListener(Event.CANCEL, function(e:Event):void {
            trace("list2 cancel fileList=" + list2.fileList);
        });
        step("list2.browse()", function():void {
            trace("list2.browse returned " + list2.browse());
        });
    }
}
}

import flash.net.IDynamicPropertyOutput;
import flash.net.IDynamicPropertyWriter;
import flash.utils.getQualifiedClassName;

class Writer implements IDynamicPropertyWriter {
    public var calls:Array = [];
    public var outputs:Array = [];
    public var skip:String;

    public function Writer(skip:String) {
        this.skip = skip;
    }

    public function writeDynamicProperties(obj:Object, output:IDynamicPropertyOutput):void {
        var names:Array = [];
        for (var n:String in obj) {
            names.push(n);
        }
        names.sort();
        calls.push("obj=" + getQualifiedClassName(obj) + " fields=" + names.join(",") + " output=" + getQualifiedClassName(output));
        outputs.push(output);
        for each (var name:String in names) {
            if (name == skip) {
                continue;
            }
            output.writeDynamicProperty(name, obj[name]);
        }
        output.writeDynamicProperty("extra", 42);
    }
}

class Writer2 implements IDynamicPropertyWriter {
    private var f:Function;

    public function Writer2(f:Function) {
        this.f = f;
    }

    public function writeDynamicProperties(obj:Object, output:IDynamicPropertyOutput):void {
        f(obj, output);
    }
}

class Sealed {
    public var x:int = 1;
}
