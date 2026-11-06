package flash.net {
    // Timffle: the statistics of a NetStream. Flash Player 32 has a public
    // constructor taking the values in this order (20 numbers are required);
    // `toString()` lists the properties as `name=value` pairs separated by
    // spaces, with `srtt` in lower case (measured on Flash Player 32,
    // tests/tests/swfs/avm2/netstream_local_events).
    public final class NetStreamInfo {
        private var _audioBufferByteLength:Number = 0;
        private var _audioBufferLength:Number = 0;
        private var _audioByteCount:Number = 0;
        private var _audioBytesPerSecond:Number = 0;
        private var _audioLossRate:Number = 0;
        private var _byteCount:Number = 0;
        private var _currentBytesPerSecond:Number = 0;
        private var _dataBufferByteLength:Number = 0;
        private var _dataBufferLength:Number = 0;
        private var _dataByteCount:Number = 0;
        private var _dataBytesPerSecond:Number = 0;
        private var _droppedFrames:Number = 0;
        private var _isLive:Boolean = false;
        private var _maxBytesPerSecond:Number = 0;
        private var _metaData:Object = null;
        private var _playbackBytesPerSecond:Number = 0;
        private var _resourceName:String = null;
        private var _SRTT:Number = 0;
        private var _uri:String = null;
        private var _videoBufferByteLength:Number = 0;
        private var _videoBufferLength:Number = 0;
        private var _videoByteCount:Number = 0;
        private var _videoBytesPerSecond:Number = 0;
        private var _videoLossRate:Number = 0;
        private var _xmpData:Object = null;

        public function NetStreamInfo(curBPS:Number, byteCount:Number, maxBPS:Number, audioBPS:Number,
                audioByteCount:Number, videoBPS:Number, videoByteCount:Number, dataBPS:Number,
                dataByteCount:Number, playbackBPS:Number, droppedFrames:Number,
                audioBufferByteLength:Number, videoBufferByteLength:Number, dataBufferByteLength:Number,
                audioBufferLength:Number, videoBufferLength:Number, dataBufferLength:Number,
                srtt:Number, audioLossRate:Number, videoLossRate:Number, metaData:Object = null,
                xmpData:Object = null, uri:String = null, resourceName:String = null, isLive:Boolean = true) {
            this._currentBytesPerSecond = curBPS;
            this._byteCount = byteCount;
            this._maxBytesPerSecond = maxBPS;
            this._audioBytesPerSecond = audioBPS;
            this._audioByteCount = audioByteCount;
            this._videoBytesPerSecond = videoBPS;
            this._videoByteCount = videoByteCount;
            this._dataBytesPerSecond = dataBPS;
            this._dataByteCount = dataByteCount;
            this._playbackBytesPerSecond = playbackBPS;
            this._droppedFrames = droppedFrames;
            this._audioBufferByteLength = audioBufferByteLength;
            this._videoBufferByteLength = videoBufferByteLength;
            this._dataBufferByteLength = dataBufferByteLength;
            this._audioBufferLength = audioBufferLength;
            this._videoBufferLength = videoBufferLength;
            this._dataBufferLength = dataBufferLength;
            this._SRTT = srtt;
            this._audioLossRate = audioLossRate;
            this._videoLossRate = videoLossRate;
            this._metaData = metaData;
            this._xmpData = xmpData;
            this._uri = uri;
            this._resourceName = resourceName;
            this._isLive = isLive;
        }

        public function toString():String {
            return "currentBytesPerSecond=" + this._currentBytesPerSecond
                + " byteCount=" + this._byteCount
                + " maxBytesPerSecond=" + this._maxBytesPerSecond
                + " audioBytesPerSecond=" + this._audioBytesPerSecond
                + " audioByteCount=" + this._audioByteCount
                + " videoBytesPerSecond=" + this._videoBytesPerSecond
                + " videoByteCount=" + this._videoByteCount
                + " dataBytesPerSecond=" + this._dataBytesPerSecond
                + " dataByteCount=" + this._dataByteCount
                + " playbackBytesPerSecond=" + this._playbackBytesPerSecond
                + " droppedFrames=" + this._droppedFrames
                + " audioBufferLength=" + this._audioBufferLength
                + " videoBufferLength=" + this._videoBufferLength
                + " dataBufferLength=" + this._dataBufferLength
                + " audioBufferByteLength=" + this._audioBufferByteLength
                + " videoBufferByteLength=" + this._videoBufferByteLength
                + " dataBufferByteLength=" + this._dataBufferByteLength
                + " srtt=" + this._SRTT
                + " audioLossRate=" + this._audioLossRate
                + " videoLossRate=" + this._videoLossRate
                + " metaData=" + this._metaData
                + " xmpData=" + this._xmpData
                + " uri=" + this._uri
                + " resourceName=" + this._resourceName
                + " isLive=" + this._isLive;
        }

        public function get audioBufferByteLength():Number {
            return this._audioBufferByteLength;
        }

        public function get audioBufferLength():Number {
            return this._audioBufferLength;
        }

        public function get audioByteCount():Number {
            return this._audioByteCount;
        }

        public function get audioBytesPerSecond():Number {
            return this._audioBytesPerSecond;
        }

        public function get audioLossRate():Number {
            return this._audioLossRate;
        }

        public function get byteCount():Number {
            return this._byteCount;
        }

        public function get currentBytesPerSecond():Number {
            return this._currentBytesPerSecond;
        }

        public function get dataBufferByteLength():Number {
            return this._dataBufferByteLength;
        }

        public function get dataBufferLength():Number {
            return this._dataBufferLength;
        }

        public function get dataByteCount():Number {
            return this._dataByteCount;
        }

        public function get dataBytesPerSecond():Number {
            return this._dataBytesPerSecond;
        }

        public function get droppedFrames():Number {
            return this._droppedFrames;
        }

        public function get isLive():Boolean {
            return this._isLive;
        }

        public function get maxBytesPerSecond():Number {
            return this._maxBytesPerSecond;
        }

        public function get metaData():Object {
            return this._metaData;
        }

        public function get playbackBytesPerSecond():Number {
            return this._playbackBytesPerSecond;
        }

        public function get resourceName():String {
            return this._resourceName;
        }

        public function get SRTT():Number {
            return this._SRTT;
        }

        public function get uri():String {
            return this._uri;
        }

        public function get videoBufferByteLength():Number {
            return this._videoBufferByteLength;
        }

        public function get videoBufferLength():Number {
            return this._videoBufferLength;
        }

        public function get videoByteCount():Number {
            return this._videoByteCount;
        }

        public function get videoBytesPerSecond():Number {
            return this._videoBytesPerSecond;
        }

        public function get videoLossRate():Number {
            return this._videoLossRate;
        }

        public function get xmpData():Object {
            return this._xmpData;
        }
    }
}
