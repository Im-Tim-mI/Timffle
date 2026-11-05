package flash.net {
    import flash.net.NetConnection;
    import flash.net.NetStreamPlayOptions;
    import flash.net.NetStreamPlayTransitions;
    import flash.net.NetStreamInfo;
    import flash.events.EventDispatcher;
    import flash.events.NetStatusEvent;
    import flash.utils.ByteArray;
    import flash.media.Microphone;
    import flash.media.Camera;
    import flash.media.VideoStreamSettings;

    // Timffle: `NetStream` on this player. Playback is progressive download of
    // FLV files (and Data Generation Mode via `appendBytes`); there is no RTMP,
    // RTMFP or Flash Media Server client and no DRM module. The members that only
    // mean something on those transports behave as Flash Player does on a
    // `connect(null)` NetConnection: stored settings keep their documented
    // defaults, peer identifiers come from the (local) NetConnection, the
    // partial-reliability flags are always true ("ignored and becomes TRUE on a
    // protocol without partial reliability"), and nothing is ever published.
    [Ruffle(InstanceAllocator)]
    public class NetStream extends EventDispatcher {
        public static const CONNECT_TO_FMS:String = "connectToFMS";
        public static const DIRECT_CONNECTIONS:String = "directConnections";

        private var _connection:NetConnection;
        private var _bufferTimeMax:Number = 0;
        private var _maxPauseBufferTime:Number = 0;
        private var _checkPolicyFile:Boolean = false;
        private var _useHardwareDecoder:Boolean = true;
        private var _useJitterBuffer:Boolean = false;
        private var _audioSampleAccess:Boolean = false;
        private var _videoSampleAccess:Boolean = false;
        private var _videoStreamSettings:VideoStreamSettings = null;
        private var _receiveAudio:Boolean = true;
        private var _receiveVideo:Boolean = true;
        private var _receiveVideoFPS:Number = -1;
        // RTMFP multicast settings with Flash Player's defaults (the values the
        // RTMFP group implementations mirror: 8 s window, 4 push neighbours,
        // 2.5 s fetch period, 2 s relay margin, 0.1 s availability period).
        private var _multicastAvailabilitySendToAll:Boolean = false;
        private var _multicastAvailabilityUpdatePeriod:Number = 0.1;
        private var _multicastFetchPeriod:Number = 2.5;
        private var _multicastPushNeighborLimit:Number = 4;
        private var _multicastRelayMarginDuration:Number = 2;
        private var _multicastWindowDuration:Number = 8;

        public function NetStream(connection:NetConnection, peer:String = CONNECT_TO_FMS) {
            // Timffle: Flash Player requires a connected NetConnection (ArgumentError #2126;
            // null is TypeError #2007).
            if (connection == null) {
                throw new TypeError("Error #2007: Parameter connection must be non-null.", 2007);
            }
            if (!connection.connected) {
                throw new ArgumentError("Error #2126: NetConnection object must be connected.", 2126);
            }
            this._connection = connection;
            // Timffle: NetMonitor bookkeeping (`listStreams()`, `netStreamCreate`).
            this.registerWithMonitors();
        }

        private native function registerWithMonitors():void;

        // Timffle: Data Generation Mode (`play(null)` on a `connect(null)` NetConnection):
        // the bytes join the stream buffer like downloaded data. Outside that mode the
        // call does nothing here (Flash raises an exception whose class is not documented).
        public function appendBytes(bytes:ByteArray):void {
            if (bytes == null) {
                throw new TypeError("Error #2007: Parameter bytes must be non-null.", 2007);
            }
            this.appendBytesInternal(bytes);
        }

        private native function appendBytesInternal(bytes:ByteArray):Boolean;

        public function appendBytesAction(action:String):void {
            if (action == null) {
                throw new TypeError("Error #2007: Parameter action must be non-null.", 2007);
            }
            if (action != NetStreamAppendBytesAction.END_SEQUENCE
                && action != NetStreamAppendBytesAction.RESET_BEGIN
                && action != NetStreamAppendBytesAction.RESET_SEEK) {
                throw new ArgumentError("Error #2008: Parameter action must be one of the accepted values.", 2008);
            }
            this.appendBytesActionInternal(action);
        }

        private native function appendBytesActionInternal(action:String):Boolean;

        // Timffle: reconnection (Flash Media Server 3.5.3+): the stream continues on the
        // new connection. Here only the connection reference moves; the same validation
        // as the constructor applies.
        public function attach(connection:NetConnection):void {
            if (connection == null) {
                throw new TypeError("Error #2007: Parameter connection must be non-null.", 2007);
            }
            if (!connection.connected) {
                throw new ArgumentError("Error #2126: NetConnection object must be connected.", 2126);
            }
            this._connection = connection;
        }

        // Timffle: no Microphone/Camera device exists on this player
        // (`Microphone.getMicrophone()` / `Camera.getCamera()` are null), so the only
        // argument a SWF can pass is null, which stops a capture that never started.
        public function attachAudio(mic:Microphone):void {
        }

        public function attachCamera(cam:Camera, ms:int = -1):void {
        }

        public native function close():void;

        [API("674")]
        public native function dispose():void;

        public native function pause():void;

        public native function play(...args):void;

        // Timffle: dynamic streaming needs Flash Media Server. On progressive playback
        // the transitions reduce to what the file source can do: `stop` closes the
        // stream, every other transition (`reset`, `switch`, `swap`, `append`,
        // `appendAndWait`, `resume`) plays `streamName` from its `start` offset.
        // `NetStream.Play.Transition` / `TransitionComplete` are server messages
        // and never arrive.
        public function play2(param:NetStreamPlayOptions):void {
            if (param == null) {
                throw new TypeError("Error #2007: Parameter param must be non-null.", 2007);
            }
            if (param.transition == NetStreamPlayTransitions.STOP) {
                this.close();
                return;
            }
            if (param.streamName == null) {
                throw new TypeError("Error #2007: Parameter streamName must be non-null.", 2007);
            }
            this.play(param.streamName);
            if (param.start > 0) {
                this.seek(param.start);
            }
        }

        [API("663")]
        public function preloadEmbeddedData(param:NetStreamPlayOptions):void {
            if (param == null) {
                throw new TypeError("Error #2007: Parameter param must be non-null.", 2007);
            }
            // Timffle: there is no DRM module; there is no metadata to extract.
        }

        // Timffle: publishing needs Flash Media Server (or an RTMFP peer). A
        // `connect(null)` NetConnection has no server to publish to; what Flash Player
        // reports in that case is not documented, so nothing is sent here (partial).
        public function publish(name:String = null, type:String = null):void {
        }

        // Timffle: `receiveAudio`/`receiveVideo`/`receiveVideoFPS` tell Flash Media
        // Server what to send on a unicast stream; the reference says they do not apply
        // to progressive download or `appendBytes()`. The flags are remembered only.
        public function receiveAudio(flag:Boolean):void {
            this._receiveAudio = flag;
        }

        public function receiveVideo(flag:Boolean):void {
            this._receiveVideo = flag;
        }

        public function receiveVideoFPS(fps:Number):void {
            this._receiveVideoFPS = fps;
        }

        // Timffle: deletes the locally cached DRM vouchers. There is no DRM module and
        // no voucher cache here, so there is nothing to delete and nothing fails.
        [API("690")]
        public static function resetDRMVouchers():void {
        }

        public native function resume():void;

        public native function seek(offset:Number):void;

        // Timffle: `send()` delivers a message to the subscribers of a published stream
        // through Flash Media Server; this stream never publishes, so there is nobody
        // to deliver to. A null handler name is #2007 like every non-null parameter.
        public function send(handlerName:String, ...args):void {
            if (handlerName == null) {
                throw new TypeError("Error #2007: Parameter handlerName must be non-null.", 2007);
            }
        }

        [API("661")]
        public function setDRMAuthenticationCredentials(userName:String, password:String, type:String):void {
            if (userName == null) {
                throw new TypeError("Error #2007: Parameter userName must be non-null.", 2007);
            }
            if (password == null) {
                throw new TypeError("Error #2007: Parameter password must be non-null.", 2007);
            }
            if (type == null) {
                throw new TypeError("Error #2007: Parameter type must be non-null.", 2007);
            }
            // Timffle: no DRM module; the credentials are not kept.
        }

        // Timffle: frame stepping inside the buffer (needs `inBufferSeek`); on success
        // Flash sends `NetStream.Step.Notify`, on failure (target frame not buffered,
        // `inBufferSeek` false) nothing happens.
        public function step(frames:int):void {
            if (this.stepInternal(frames)) {
                this.dispatchEvent(new NetStatusEvent(NetStatusEvent.NET_STATUS, false, false,
                    {code: "NetStream.Step.Notify", level: "status"}));
            }
        }

        private native function stepInternal(frames:int):Boolean;

        public native function togglePause():void;

        // Timffle: `audioCodec`/`videoCodec` are the FLV codec ids of the stream being
        // played (0 before the first tag of that kind); `decodedFrames` counts the
        // video frames decoded so far.
        public native function get audioCodec():uint;

        public native function get videoCodec():uint;

        public native function get decodedFrames():uint;

        // Timffle: "setting FALSE on a protocol without partial reliability is ignored
        // and the value becomes TRUE" — no connection here has partial reliability.
        public function get audioReliable():Boolean {
            return true;
        }

        public function set audioReliable(isReliable:Boolean):void {
        }

        public function get audioSampleAccess():Boolean {
            return this._audioSampleAccess;
        }

        public function set audioSampleAccess(isAccessible:Boolean):void {
            this._audioSampleAccess = isAccessible;
        }

        public native function get backBufferLength():Number;

        public native function get backBufferTime():Number;

        public native function set backBufferTime(time:Number):void;

        public native function get bufferLength():Number;

        public native function get bufferTime():Number;

        public native function set bufferTime(time:Number):void;

        public function get bufferTimeMax():Number {
            return this._bufferTimeMax;
        }

        public function set bufferTimeMax(time:Number):void {
            this._bufferTimeMax = time;
        }

        public native function get bytesLoaded():uint;

        public native function get bytesTotal():uint;

        // Timffle: a policy file only matters when the loaded media is read back by
        // a SWF of another domain; stored, nothing here is restricted by it.
        public function get checkPolicyFile():Boolean {
            return this._checkPolicyFile;
        }

        public function set checkPolicyFile(doCheck:Boolean):void {
            this._checkPolicyFile = doCheck;
        }

        public native function get client():Object;

        public native function set client(client:Object):void;

        public native function get currentFPS():Number;

        public function get dataReliable():Boolean {
            return true;
        }

        public function set dataReliable(isReliable:Boolean):void {
        }

        // Timffle: the peer identifiers of a non-RTMFP stream are those of its
        // NetConnection (empty id, all-zero nonces on a local connection).
        public function get farID():String {
            return this._connection.farID;
        }

        public function get farNonce():String {
            return this._connection.farNonce;
        }

        public native function get inBufferSeek():Boolean;

        public native function set inBufferSeek(isInBuffer:Boolean):void;

        public function get info():NetStreamInfo {
            var result:NetStreamInfo = new NetStreamInfo();
            // Progressive download: `uri` is null and `isLive` false (reference).
            result.ruffleInit(this.infoValues(), null, false);
            return result;
        }

        private native function infoValues():Array;

        // Timffle: the delay of a live stream; a file is not live.
        public function get liveDelay():Number {
            return 0;
        }

        public function get maxPauseBufferTime():Number {
            return this._maxPauseBufferTime;
        }

        public function set maxPauseBufferTime(time:Number):void {
            this._maxPauseBufferTime = time;
        }

        public function get multicastAvailabilitySendToAll():Boolean {
            return this._multicastAvailabilitySendToAll;
        }

        public function set multicastAvailabilitySendToAll(toAll:Boolean):void {
            this._multicastAvailabilitySendToAll = toAll;
        }

        public function get multicastAvailabilityUpdatePeriod():Number {
            return this._multicastAvailabilityUpdatePeriod;
        }

        public function set multicastAvailabilityUpdatePeriod(period:Number):void {
            this._multicastAvailabilityUpdatePeriod = period;
        }

        public function get multicastFetchPeriod():Number {
            return this._multicastFetchPeriod;
        }

        public function set multicastFetchPeriod(period:Number):void {
            this._multicastFetchPeriod = period;
        }

        // Timffle: no multicast traffic: every counter is 0.
        public function get multicastInfo():NetStreamMulticastInfo {
            return new NetStreamMulticastInfo();
        }

        public function get multicastPushNeighborLimit():Number {
            return this._multicastPushNeighborLimit;
        }

        public function set multicastPushNeighborLimit(limit:Number):void {
            this._multicastPushNeighborLimit = limit;
        }

        public function get multicastRelayMarginDuration():Number {
            return this._multicastRelayMarginDuration;
        }

        public function set multicastRelayMarginDuration(dur:Number):void {
            this._multicastRelayMarginDuration = dur;
        }

        public function get multicastWindowDuration():Number {
            return this._multicastWindowDuration;
        }

        public function set multicastWindowDuration(dur:Number):void {
            this._multicastWindowDuration = dur;
        }

        public function get nearNonce():String {
            return this._connection.nearNonce;
        }

        // Timffle: the NetConnection's encoding (the reference: inherited from it).
        public function get objectEncoding():uint {
            return this._connection.objectEncoding;
        }

        // Timffle: the subscribers of a publishing stream; this stream never publishes.
        public function get peerStreams():Array {
            return [];
        }

        public native function get soundTransform():flash.media.SoundTransform;

        public native function set soundTransform(tf:flash.media.SoundTransform):void;

        public native function get time():Number;

        // Timffle: stored; the decoders here are software decoders whichever value is set.
        public function get useHardwareDecoder():Boolean {
            return this._useHardwareDecoder;
        }

        public function set useHardwareDecoder(dec:Boolean):void {
            this._useHardwareDecoder = dec;
        }

        // Timffle: the reference: the jitter buffer only exists in un-buffered mode,
        // so the getter is false whenever `bufferTime > 0`.
        [API("680")]
        public function get useJitterBuffer():Boolean {
            return this.bufferTime > 0 ? false : this._useJitterBuffer;
        }

        [API("680")]
        public function set useJitterBuffer(jbuf:Boolean):void {
            this._useJitterBuffer = jbuf;
        }

        public function get videoReliable():Boolean {
            return true;
        }

        public function set videoReliable(isReliable:Boolean):void {
        }

        public function get videoSampleAccess():Boolean {
            return this._videoSampleAccess;
        }

        public function set videoSampleAccess(isReadable:Boolean):void {
            this._videoSampleAccess = isReadable;
        }

        // Timffle: the settings of a published video track; kept for `publish()`.
        [API("674")]
        public function get videoStreamSettings():VideoStreamSettings {
            return this._videoStreamSettings;
        }

        [API("674")]
        public function set videoStreamSettings(settings:VideoStreamSettings):void {
            this._videoStreamSettings = settings;
        }

        // Timffle: the default client callback of a publishing stream ("if a publisher
        // does not implement it, all peers may play"): accept every subscriber.
        [API("667")]
        public function onPeerConnect(subscriber:NetStream):Boolean {
            return true;
        }
    }
}
