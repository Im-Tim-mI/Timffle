package flash.net {
    // Timffle: filled by `NetStream.info` from the stream's buffer; `toString()` lists
    // the properties as `name=value` pairs separated by spaces in declaration order,
    // the layout Flash Player uses for this class.
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

        // Timffle: `values` comes from the native `NetStream.infoValues()`:
        // [currentBytesPerSecond, byteCount, maxBytesPerSecond, audioBytesPerSecond,
        //  audioByteCount, videoBytesPerSecond, videoByteCount, dataBytesPerSecond,
        //  dataByteCount, playbackBytesPerSecond, droppedFrames, audioBufferLength,
        //  videoBufferLength, dataBufferLength, audioBufferByteLength,
        //  videoBufferByteLength, dataBufferByteLength, metaData, xmpData, resourceName].
        internal function ruffleInit(values:Array, uri:String, isLive:Boolean):void {
            if (values == null) {
                return;
            }
            this._currentBytesPerSecond = values[0];
            this._byteCount = values[1];
            this._maxBytesPerSecond = values[2];
            this._audioBytesPerSecond = values[3];
            this._audioByteCount = values[4];
            this._videoBytesPerSecond = values[5];
            this._videoByteCount = values[6];
            this._dataBytesPerSecond = values[7];
            this._dataByteCount = values[8];
            this._playbackBytesPerSecond = values[9];
            this._droppedFrames = values[10];
            this._audioBufferLength = values[11];
            this._videoBufferLength = values[12];
            this._dataBufferLength = values[13];
            this._audioBufferByteLength = values[14];
            this._videoBufferByteLength = values[15];
            this._dataBufferByteLength = values[16];
            this._metaData = values[17];
            this._xmpData = values[18];
            this._resourceName = values[19];
            this._uri = uri;
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
                + " SRTT=" + this._SRTT
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
