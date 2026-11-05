package {
    import flash.display.Sprite;
    import flash.media.MicrophoneEnhancedOptions;
    import flash.net.NetConnection;
    import flash.net.NetStream;

    // Timffle: defaults of a NetStream on a `connect(null)` NetConnection, recorded
    // with the real Flash Player 32 (twice, same output): `bufferTime` reads 0 until it
    // is set or the stream plays, values below 0.1 become 0.1, NaN/Infinity
    // 4294967.295, `play()` turns 0 into 0.1; `audioSampleAccess`/`videoSampleAccess`
    // throw #2154; the multicast settings read 0 and ignore new values; the stream's
    // nonces are empty (the NetConnection's are 64 zeros);
    // `MicrophoneEnhancedOptions.autoGain` ignores new values.
    public class Test extends Sprite {
        public function Test() {
            var nc:NetConnection = new NetConnection();
            nc.connect(null);
            var vals:Array = [0, 0.01, 0.05, 0.0999, 0.1, 0.11, 0.5, 2, -1, -0.05, NaN, Infinity];
            for each (var v:Number in vals) {
                var ns:NetStream = new NetStream(nc);
                ns.bufferTime = v;
                trace("set " + v + " -> " + ns.bufferTime);
            }
            var a:NetStream = new NetStream(nc);
            trace("fresh " + a.bufferTime);
            a.play("test.flv");
            trace("after play " + a.bufferTime);
            a.close();
            trace("after close " + a.bufferTime);
            var b:NetStream = new NetStream(nc);
            b.play(null);
            trace("after play(null) " + b.bufferTime);
            var c:NetStream = new NetStream(nc);
            c.bufferTime = 0.5;
            c.bufferTime = 0;
            trace("0.5 then 0 -> " + c.bufferTime);
            var d:NetStream = new NetStream(nc);
            trace("multicast: " + [d.multicastAvailabilitySendToAll, d.multicastAvailabilityUpdatePeriod, d.multicastFetchPeriod, d.multicastPushNeighborLimit, d.multicastRelayMarginDuration, d.multicastWindowDuration].join(","));
            d.multicastAvailabilitySendToAll = true;
            d.multicastAvailabilityUpdatePeriod = 5;
            d.multicastFetchPeriod = 5;
            d.multicastPushNeighborLimit = 5;
            d.multicastRelayMarginDuration = 5;
            d.multicastWindowDuration = 5;
            trace("multicast after set: " + [d.multicastAvailabilitySendToAll, d.multicastAvailabilityUpdatePeriod, d.multicastFetchPeriod, d.multicastPushNeighborLimit, d.multicastRelayMarginDuration, d.multicastWindowDuration].join(","));
            trace("stream nonces: [" + d.farNonce + "] [" + d.nearNonce + "]");
            trace("connection nonces: [" + nc.farNonce + "] [" + nc.nearNonce + "]");
            try {
                trace("audioSampleAccess " + d.audioSampleAccess);
            } catch (e:Error) {
                trace("audioSampleAccess get threw " + e.errorID + " " + e.message + " " + (e is ArgumentError));
            }
            try {
                d.videoSampleAccess = true;
                trace("videoSampleAccess set ok");
            } catch (e:Error) {
                trace("videoSampleAccess set threw " + e.errorID);
            }
            d.play("test.flv");
            try {
                d.audioSampleAccess = true;
                trace("playing: audioSampleAccess set ok");
            } catch (e:Error) {
                trace("playing: audioSampleAccess set threw " + e.errorID);
            }
            d.close();
            var o:MicrophoneEnhancedOptions = new MicrophoneEnhancedOptions();
            trace("autoGain " + o.autoGain);
            o.autoGain = true;
            trace("autoGain after set true " + o.autoGain);
        }
    }
}
