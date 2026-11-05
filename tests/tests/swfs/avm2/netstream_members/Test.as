package {
    import flash.display.Sprite;
    import flash.events.Event;
    import flash.events.NetStatusEvent;
    import flash.media.SoundTransform;
    import flash.media.VideoStreamSettings;
    import flash.net.NetConnection;
    import flash.net.NetStream;
    import flash.net.NetStreamAppendBytesAction;
    import flash.net.NetStreamInfo;
    import flash.net.NetStreamPlayOptions;
    import flash.net.NetStreamPlayTransitions;
    import flash.net.URLLoader;
    import flash.net.URLLoaderDataFormat;
    import flash.net.URLRequest;
    import flash.utils.ByteArray;
    import flash.utils.getQualifiedClassName;

    public class Test extends Sprite {
        private var nc:NetConnection;
        private var ns:NetStream;
        private var ns2:NetStream;
        private var phase:String = "play";
        private var flvBytes:ByteArray;

        public function Test() {
            var unconnected:NetConnection = new NetConnection();
            try {
                new NetStream(null);
            } catch (e:Error) {
                trace("new NetStream(null): " + getQualifiedClassName(e) + " #" + e.errorID);
            }
            try {
                new NetStream(unconnected);
            } catch (e:Error) {
                trace("new NetStream(unconnected): " + getQualifiedClassName(e) + " #" + e.errorID);
            }

            nc = new NetConnection();
            nc.connect(null);
            ns = new NetStream(nc);

            trace("// defaults");
            trace("bufferTime: " + ns.bufferTime);
            trace("bufferTimeMax: " + ns.bufferTimeMax);
            trace("bufferLength: " + ns.bufferLength);
            trace("backBufferTime: " + ns.backBufferTime);
            trace("backBufferLength: " + ns.backBufferLength);
            trace("inBufferSeek: " + ns.inBufferSeek);
            trace("useHardwareDecoder: " + ns.useHardwareDecoder);
            trace("useJitterBuffer: " + ns.useJitterBuffer);
            trace("checkPolicyFile: " + ns.checkPolicyFile);
            trace("liveDelay: " + ns.liveDelay);
            trace("maxPauseBufferTime: " + ns.maxPauseBufferTime);
            trace("objectEncoding: " + ns.objectEncoding);
            trace("farID: '" + ns.farID + "'");
            trace("farNonce: " + ns.farNonce);
            trace("nearNonce: " + ns.nearNonce);
            trace("peerStreams: " + ns.peerStreams.length);
            trace("audioReliable: " + ns.audioReliable);
            trace("videoReliable: " + ns.videoReliable);
            trace("dataReliable: " + ns.dataReliable);
            trace("audioSampleAccess: " + ns.audioSampleAccess);
            trace("videoSampleAccess: " + ns.videoSampleAccess);
            trace("videoStreamSettings: " + ns.videoStreamSettings);
            trace("multicastAvailabilitySendToAll: " + ns.multicastAvailabilitySendToAll);
            trace("multicastAvailabilityUpdatePeriod: " + ns.multicastAvailabilityUpdatePeriod);
            trace("multicastFetchPeriod: " + ns.multicastFetchPeriod);
            trace("multicastPushNeighborLimit: " + ns.multicastPushNeighborLimit);
            trace("multicastRelayMarginDuration: " + ns.multicastRelayMarginDuration);
            trace("multicastWindowDuration: " + ns.multicastWindowDuration);
            trace("multicastInfo: " + ns.multicastInfo);
            trace("audioCodec: " + ns.audioCodec);
            trace("videoCodec: " + ns.videoCodec);
            trace("decodedFrames: " + ns.decodedFrames);
            trace("currentFPS: " + ns.currentFPS);
            trace("soundTransform.volume: " + ns.soundTransform.volume);
            trace("info: " + ns.info);
            trace("time: " + ns.time);

            trace("// setters");
            ns.bufferTime = 2;
            trace("bufferTime: " + ns.bufferTime);
            ns.bufferTime = -1;
            trace("bufferTime (-1): " + ns.bufferTime);
            ns.useJitterBuffer = true;
            trace("useJitterBuffer (bufferTime 0): " + ns.useJitterBuffer);
            ns.bufferTime = 0.1;
            trace("useJitterBuffer (bufferTime 0.1): " + ns.useJitterBuffer);
            ns.bufferTimeMax = 5;
            trace("bufferTimeMax: " + ns.bufferTimeMax);
            ns.backBufferTime = 10;
            trace("backBufferTime: " + ns.backBufferTime);
            ns.inBufferSeek = true;
            trace("inBufferSeek: " + ns.inBufferSeek);
            ns.inBufferSeek = false;
            ns.useHardwareDecoder = false;
            trace("useHardwareDecoder: " + ns.useHardwareDecoder);
            ns.checkPolicyFile = true;
            trace("checkPolicyFile: " + ns.checkPolicyFile);
            ns.maxPauseBufferTime = 120;
            trace("maxPauseBufferTime: " + ns.maxPauseBufferTime);
            ns.audioReliable = false;
            trace("audioReliable (set false): " + ns.audioReliable);
            ns.videoReliable = false;
            trace("videoReliable (set false): " + ns.videoReliable);
            ns.dataReliable = false;
            trace("dataReliable (set false): " + ns.dataReliable);
            ns.audioSampleAccess = true;
            trace("audioSampleAccess: " + ns.audioSampleAccess);
            ns.videoSampleAccess = true;
            trace("videoSampleAccess: " + ns.videoSampleAccess);
            var vss:VideoStreamSettings = new VideoStreamSettings();
            ns.videoStreamSettings = vss;
            trace("videoStreamSettings same: " + (ns.videoStreamSettings == vss));
            ns.multicastAvailabilitySendToAll = true;
            ns.multicastAvailabilityUpdatePeriod = 0.5;
            ns.multicastFetchPeriod = 1;
            ns.multicastPushNeighborLimit = 2;
            ns.multicastRelayMarginDuration = 3;
            ns.multicastWindowDuration = 4;
            trace("multicast: " + ns.multicastAvailabilitySendToAll + " " + ns.multicastAvailabilityUpdatePeriod + " " + ns.multicastFetchPeriod + " " + ns.multicastPushNeighborLimit + " " + ns.multicastRelayMarginDuration + " " + ns.multicastWindowDuration);
            var st:SoundTransform = new SoundTransform(0.5, 0);
            ns.soundTransform = st;
            trace("soundTransform: " + ns.soundTransform.volume + " " + ns.soundTransform.pan);
            trace("soundTransform is a copy: " + (ns.soundTransform != st));
            try {
                ns.soundTransform = null;
            } catch (e:Error) {
                trace("soundTransform = null: " + getQualifiedClassName(e) + " #" + e.errorID);
            }

            trace("// methods without a server");
            trace("onPeerConnect: " + ns.onPeerConnect(null));
            try {
                ns.send(null);
            } catch (e:Error) {
                trace("send(null): " + getQualifiedClassName(e) + " #" + e.errorID);
            }
            ns.send("handler", 1, "two");
            trace("send ok");
            try {
                ns.attach(null);
            } catch (e:Error) {
                trace("attach(null): " + getQualifiedClassName(e) + " #" + e.errorID);
            }
            try {
                ns.attach(unconnected);
            } catch (e:Error) {
                trace("attach(unconnected): " + getQualifiedClassName(e) + " #" + e.errorID);
            }
            ns.attach(nc);
            trace("attach ok");
            ns.attachAudio(null);
            ns.attachCamera(null);
            trace("attachAudio/attachCamera(null) ok");
            try {
                ns.play2(null);
            } catch (e:Error) {
                trace("play2(null): " + getQualifiedClassName(e) + " #" + e.errorID);
            }
            try {
                ns.appendBytes(null);
            } catch (e:Error) {
                trace("appendBytes(null): " + getQualifiedClassName(e) + " #" + e.errorID);
            }
            try {
                ns.appendBytesAction("bogus");
            } catch (e:Error) {
                trace("appendBytesAction(bogus): " + getQualifiedClassName(e) + " #" + e.errorID);
            }
            ns.publish("name", "live");
            ns.receiveAudio(false);
            ns.receiveVideo(false);
            ns.receiveVideoFPS(5);
            NetStream.resetDRMVouchers();
            trace("publish/receive*/resetDRMVouchers ok");
            ns.addEventListener(NetStatusEvent.NET_STATUS, onStatus);
            ns.step(1);
            trace("step without inBufferSeek: nothing");
            ns.close();
            trace("close before play ok, time " + ns.time);

            trace("// playback");
            ns.client = {
                onMetaData: function(info:Object):void {
                    trace("onMetaData duration " + info.duration);
                }
            };
            ns.play("test.flv");
        }

        private function onStatus(event:NetStatusEvent):void {
            trace("status: " + event.info.code + (event.info.description ? " (" + event.info.description + ")" : ""));
            if (phase == "play" && event.info.code == "NetStream.Play.Stop") {
                phase = "stopped";
                trace("audioCodec: " + ns.audioCodec);
                trace("videoCodec: " + ns.videoCodec);
                // The test harness has no H.263 decoder: every frame handed to it
                // counts as dropped, so decoded + dropped is what reached the decoder.
                trace("frames reached the decoder: " + (ns.decodedFrames + ns.info.droppedFrames));
                trace("bytesLoaded == bytesTotal: " + (ns.bytesLoaded == ns.bytesTotal));
                trace("time > 0: " + (ns.time > 0));
                trace("bufferLength: " + ns.bufferLength);
                var info:NetStreamInfo = ns.info;
                trace("info.byteCount == bytesLoaded: " + (info.byteCount == ns.bytesLoaded));
                trace("info.videoByteCount > 0: " + (info.videoByteCount > 0));
                trace("info.audioByteCount: " + info.audioByteCount);
                trace("info.dataByteCount > 0: " + (info.dataByteCount > 0));
                trace("info.videoBufferByteLength: " + info.videoBufferByteLength);
                trace("info.metaData.duration: " + info.metaData.duration);
                trace("info.resourceName ends with test.flv: " + (info.resourceName.indexOf("test.flv") == info.resourceName.length - 8));
                trace("info.uri: " + info.uri);
                trace("info.isLive: " + info.isLive);
                trace("backBufferLength (inBufferSeek false): " + ns.backBufferLength);
                ns.inBufferSeek = true;
                trace("backBufferLength > 0: " + (ns.backBufferLength > 0));
                var before:uint = ns.decodedFrames + ns.info.droppedFrames;
                var timeBefore:Number = ns.time;
                ns.step(1);
                trace("step(1) at the end: nothing reached the decoder: " + (ns.decodedFrames + ns.info.droppedFrames == before));
                ns.step(-1);
                trace("step(-1): a frame reached the decoder: " + (ns.decodedFrames + ns.info.droppedFrames > before));
                trace("time after step(-1) went back: " + (ns.time < timeBefore && ns.time >= 0));
                ns.close();
                trace("closed: time " + ns.time + " bytesLoaded " + ns.bytesLoaded + " bufferLength " + ns.bufferLength);
                ns.dispose();
                trace("disposed");
                var loader:URLLoader = new URLLoader();
                loader.dataFormat = URLLoaderDataFormat.BINARY;
                loader.addEventListener(Event.COMPLETE, onBytes);
                loader.load(new URLRequest("test.flv"));
            } else if (phase == "generated" && event.info.code == "NetStream.Play.Stop") {
                phase = "done";
                trace("generated: frames reached the decoder: " + (ns2.decodedFrames + ns2.info.droppedFrames) + ", bytesLoaded == bytesTotal: " + (ns2.bytesLoaded == ns2.bytesTotal) + ", audioCodec " + ns2.audioCodec + ", videoCodec " + ns2.videoCodec);
                var options:NetStreamPlayOptions = new NetStreamPlayOptions();
                options.transition = NetStreamPlayTransitions.STOP;
                try {
                    ns2.play2(options);
                    trace("play2(stop) without streamName did not throw");
                } catch (e:Error) {
                    trace("play2(stop) without streamName: " + getQualifiedClassName(e) + " #" + e.errorID);
                }
            }
        }

        private function onBytes(event:Event):void {
            flvBytes = URLLoader(event.target).data as ByteArray;
            trace("// data generation mode, " + flvBytes.length + " bytes");
            ns2 = new NetStream(nc);
            ns2.client = {};
            ns2.addEventListener(NetStatusEvent.NET_STATUS, onStatus);
            phase = "generated";
            ns2.play(null);
            ns2.appendBytesAction(NetStreamAppendBytesAction.RESET_BEGIN);
            var first:ByteArray = new ByteArray();
            first.writeBytes(flvBytes, 0, 1000);
            ns2.appendBytes(first);
            var rest:ByteArray = new ByteArray();
            rest.writeBytes(flvBytes, 1000);
            ns2.appendBytes(rest);
            trace("appended, bytesLoaded " + ns2.bytesLoaded + " bytesTotal " + ns2.bytesTotal);
            ns2.appendBytesAction(NetStreamAppendBytesAction.END_SEQUENCE);
        }
    }
}
