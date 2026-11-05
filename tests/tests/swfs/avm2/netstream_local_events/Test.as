package {
    import flash.display.Sprite;
    import flash.events.AsyncErrorEvent;
    import flash.events.Event;
    import flash.events.IOErrorEvent;
    import flash.events.NetStatusEvent;
    import flash.net.GroupSpecifier;
    import flash.net.NetConnection;
    import flash.net.NetGroup;
    import flash.net.NetGroupInfo;
    import flash.net.NetStream;
    import flash.net.NetStreamAppendBytesAction;
    import flash.net.NetStreamInfo;
    import flash.net.NetStreamMulticastInfo;
    import flash.net.NetStreamPlayOptions;
    import flash.net.NetStreamPlayTransitions;
    import flash.utils.ByteArray;
    import flash.utils.getQualifiedClassName;

    // Timffle: what a NetStream on a `connect(null)` NetConnection does without a
    // server: the events of `close()`, `publish()` and `appendBytes()` outside data
    // generation mode, `play2()` transitions on a progressive stream, the default of
    // `maxPauseBufferTime`, `multicastInfo`, the constructors and `toString()` layout
    // of the three info classes, the order of the status events of a played file, and
    // the errors of NetStream/NetGroup on a NetConnection whose RTMP connect failed or
    // that is not RTMFP. output.txt was recorded with the real Flash Player 32 (twice,
    // same output). `NetStream.Buffer.Full` is left out of the event lists: its place
    // relative to `onMetaData` changes from run to run in Flash Player.
    public class Test extends Sprite {
        private var nc:NetConnection;
        private var nc2:NetConnection;
        private var nsPlay:NetStream;
        private var nsP2:NetStream;
        private var phase:int = 0;
        private var wait:int = -1;
        private var events:Array = [];

        private function err(e:Error):String {
            return getQualifiedClassName(e) + " #" + e.errorID;
        }

        private function record(label:String):Function {
            var self:Test = this;
            return function(e:Event):void {
                if (e is NetStatusEvent) {
                    var o:Object = NetStatusEvent(e).info;
                    if (o.code == "NetStream.Buffer.Full") {
                        return;
                    }
                    self.events.push(label + " " + o.code + "(" + o.level + ")");
                    if (o.code == "NetStream.Play.Stop" && self.wait < 0) {
                        self.wait = 25;
                    }
                } else {
                    self.events.push(label + " " + e.type);
                }
            };
        }

        private function listen(target:Object, label:String):void {
            target.addEventListener(NetStatusEvent.NET_STATUS, record(label));
            target.addEventListener(IOErrorEvent.IO_ERROR, record(label));
            target.addEventListener(AsyncErrorEvent.ASYNC_ERROR, record(label));
        }

        private function client(label:String):Object {
            var self:Test = this;
            return {
                onMetaData: function(o:Object):void {
                    self.events.push(label + " onMetaData " + o.width + "x" + o.height);
                },
                onPlayStatus: function(o:Object):void {
                    self.events.push(label + " onPlayStatus " + o.code);
                }
            };
        }

        private function flush(title:String):void {
            trace(title + ": " + (events.length == 0 ? "(none)" : events.join(", ")));
            events = [];
        }

        public function Test() {
            trace("// info classes");
            var si:Class = NetStreamInfo;
            trace("NetStreamInfo(1..20,{a:1},null,'u','r',true): " + new si(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, {a: 1}, null, "u", "r", true));
            var info:NetStreamInfo = new si(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20);
            trace("NetStreamInfo(1..20) getters: " + [info.audioBufferByteLength, info.audioBufferLength, info.SRTT, info.isLive, info.uri, info.metaData].join(","));
            var mi:Class = NetStreamMulticastInfo;
            trace("NetStreamMulticastInfo(1..19): " + new mi(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19));
            var gi:Class = NetGroupInfo;
            trace("NetGroupInfo(1..8): " + new gi(1, 2, 3, 4, 5, 6, 7, 8));
            try {
                trace("NetStreamInfo(): " + new si());
            } catch (e:Error) {
                trace("NetStreamInfo() threw " + err(e));
            }
            try {
                trace("NetGroupInfo(): " + new gi());
            } catch (e:Error) {
                trace("NetGroupInfo() threw " + err(e));
            }

            nc = new NetConnection();
            listen(nc, "nc");
            nc.connect(null);
            trace("nc connected=" + nc.connected + " protocol=" + nc.protocol);

            trace("// a fresh stream");
            var ns:NetStream = new NetStream(nc);
            listen(ns, "ns0");
            trace("maxPauseBufferTime default: " + ns.maxPauseBufferTime);
            ns.maxPauseBufferTime = -1;
            trace("maxPauseBufferTime = -1: " + ns.maxPauseBufferTime);
            ns.maxPauseBufferTime = 1000;
            trace("maxPauseBufferTime = 1000: " + ns.maxPauseBufferTime);
            trace("info: " + ns.info);
            trace("info is a new object each time: " + (ns.info != ns.info));
            trace("multicastInfo: " + ns.multicastInfo);
            ns.close();
            trace("close() before play returned, time=" + ns.time);

            trace("// publish() on connect(null)");
            var nsPub:NetStream = new NetStream(nc);
            listen(nsPub, "nsPub");
            try {
                nsPub.publish("name", "live");
                trace("publish('name','live') returned");
            } catch (e:Error) {
                trace("publish('name','live') threw " + err(e));
            }
            try {
                nsPub.publish();
                trace("publish() returned");
            } catch (e:Error) {
                trace("publish() threw " + err(e));
            }
            try {
                nsPub.publish("name", "bogus");
                trace("publish('name','bogus') returned");
            } catch (e:Error) {
                trace("publish('name','bogus') threw " + err(e));
            }

            trace("// appendBytes() outside data generation mode");
            var nsApp:NetStream = new NetStream(nc);
            listen(nsApp, "nsApp");
            var bytes:ByteArray = new ByteArray();
            bytes.writeUTFBytes("FLV");
            try {
                nsApp.appendBytes(bytes);
                trace("appendBytes returned");
            } catch (e:Error) {
                trace("appendBytes threw " + err(e));
            }
            try {
                nsApp.appendBytesAction(NetStreamAppendBytesAction.RESET_BEGIN);
                trace("appendBytesAction returned");
            } catch (e:Error) {
                trace("appendBytesAction threw " + err(e));
            }
            try {
                nsApp.appendBytes(new ByteArray());
                trace("appendBytes(empty) returned");
            } catch (e:Error) {
                trace("appendBytes(empty) threw " + err(e));
            }
            var nsGen:NetStream = new NetStream(nc);
            nsGen.play(null);
            try {
                nsGen.appendBytesAction(NetStreamAppendBytesAction.RESET_BEGIN);
                nsGen.appendBytes(new ByteArray());
                trace("appendBytes after play(null) returned");
            } catch (e:Error) {
                trace("appendBytes after play(null) threw " + err(e));
            }
            nsGen.close();
            try {
                nsGen.appendBytes(new ByteArray());
                trace("appendBytes after play(null) and close() returned");
            } catch (e:Error) {
                trace("appendBytes after play(null) and close() threw " + err(e));
            }

            nsPlay = new NetStream(nc);
            listen(nsPlay, "nsPlay");
            nsPlay.client = client("nsPlay");
            nsP2 = new NetStream(nc);
            listen(nsP2, "nsP2");
            nsP2.client = client("nsP2");
            addEventListener(Event.ENTER_FRAME, onFrame);
        }

        private function play2(transition:String):void {
            var o:NetStreamPlayOptions = new NetStreamPlayOptions();
            o.transition = transition;
            o.streamName = "test.flv";
            o.oldStreamName = "test.flv";
            try {
                nsP2.play2(o);
                trace("play2(" + transition + ") returned");
            } catch (e:Error) {
                trace("play2(" + transition + ") threw " + err(e));
            }
        }

        private function onFrame(e:Event):void {
            if (wait > 0) {
                wait--;
                return;
            }
            switch (phase) {
                case 0:
                    flush("events of the synchronous part");
                    trace("// play, then close() right after onMetaData");
                    nsPlay.play("test.flv");
                    try {
                        nsPlay.appendBytes(new ByteArray());
                        trace("appendBytes while playing a file returned");
                    } catch (e:Error) {
                        trace("appendBytes while playing a file threw " + err(e));
                    }
                    phase = 1;
                    break;
                case 1:
                    if (events.join().indexOf("onMetaData") >= 0) {
                        flush("before close()");
                        nsPlay.close();
                        trace("close() returned, time=" + nsPlay.time + " bytesLoaded=" + nsPlay.bytesLoaded);
                        wait = 25;
                        phase = 2;
                    }
                    break;
                case 2:
                    flush("after close()");
                    trace("// play2() on an idle progressive stream");
                    play2(NetStreamPlayTransitions.SWITCH);
                    wait = -1;
                    phase = 3;
                    break;
                case 3:
                    if (wait == 0) {
                        flush("switch");
                        play2(NetStreamPlayTransitions.RESUME);
                        wait = -1;
                        phase = 4;
                    }
                    break;
                case 4:
                    if (wait == 0) {
                        flush("resume");
                        play2(NetStreamPlayTransitions.APPEND);
                        wait = -1;
                        phase = 5;
                    }
                    break;
                case 5:
                    if (wait == 0) {
                        flush("append");
                        play2(NetStreamPlayTransitions.STOP);
                        wait = -1;
                        phase = 6;
                    }
                    break;
                case 6:
                    if (wait == 0) {
                        flush("stop");
                        trace("// NetStream/NetGroup on a failed RTMP connection");
                        nc2 = new NetConnection();
                        listen(nc2, "nc2");
                        nc2.connect("rtmp://127.0.0.1:1/app");
                        trace("nc2 connect returned connected=" + nc2.connected);
                        wait = 60;
                        phase = 7;
                    }
                    break;
                case 7:
                    flush("nc2");
                    trace("nc2 connected=" + nc2.connected);
                    try {
                        trace("nc2 protocol=" + nc2.protocol);
                    } catch (e:Error) {
                        trace("nc2 protocol threw " + err(e));
                    }
                    try {
                        new NetStream(nc2);
                        trace("new NetStream(nc2) ok");
                    } catch (e:Error) {
                        trace("new NetStream(nc2) threw " + err(e));
                    }
                    try {
                        new NetGroup(nc2, new GroupSpecifier("g").groupspecWithAuthorizations());
                        trace("new NetGroup(nc2) ok");
                    } catch (e:Error) {
                        trace("new NetGroup(nc2) threw " + err(e));
                    }
                    try {
                        new NetGroup(nc, new GroupSpecifier("g").groupspecWithAuthorizations());
                        trace("new NetGroup(local) ok");
                    } catch (e:Error) {
                        trace("new NetGroup(local) threw " + err(e));
                    }
                    try {
                        new NetGroup(nc, "not a groupspec");
                        trace("new NetGroup(local, bad spec) ok");
                    } catch (e:Error) {
                        trace("new NetGroup(local, bad spec) threw " + err(e));
                    }
                    var peers:Array = [new GroupSpecifier("g").groupspecWithAuthorizations(), NetStream.DIRECT_CONNECTIONS,
                        "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef", NetStream.CONNECT_TO_FMS];
                    for (var i:int = 0; i < peers.length; i++) {
                        try {
                            new NetStream(nc, peers[i]);
                            trace("new NetStream(local, peer " + i + ") ok");
                        } catch (e:Error) {
                            trace("new NetStream(local, peer " + i + ") threw " + err(e));
                        }
                    }
                    trace("// done");
                    phase = 8;
                    removeEventListener(Event.ENTER_FRAME, onFrame);
                    break;
            }
        }
    }
}
