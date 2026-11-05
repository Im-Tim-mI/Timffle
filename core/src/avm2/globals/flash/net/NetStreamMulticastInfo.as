package flash.net {
    // Timffle: the multicast statistics of a stream. This player has no RTMFP
    // multicast; `NetStream.multicastInfo` is null for its streams, as in Flash
    // Player 32 for a stream that is not multicast. The constructor takes the
    // 19 values in this order and `toString()` lists them as `name=value`
    // pairs separated by spaces (measured on Flash Player 32,
    // tests/tests/swfs/avm2/netstream_local_events).
    public final class NetStreamMulticastInfo {
        private var _bytesPushedFromPeers:Number = 0;
        private var _bytesPushedToPeers:Number = 0;
        private var _bytesReceivedFromIPMulticast:Number = 0;
        private var _bytesReceivedFromServer:Number = 0;
        private var _bytesRequestedByPeers:Number = 0;
        private var _bytesRequestedFromPeers:Number = 0;
        private var _fragmentsPushedFromPeers:Number = 0;
        private var _fragmentsPushedToPeers:Number = 0;
        private var _fragmentsReceivedFromIPMulticast:Number = 0;
        private var _fragmentsReceivedFromServer:Number = 0;
        private var _fragmentsRequestedByPeers:Number = 0;
        private var _fragmentsRequestedFromPeers:Number = 0;
        private var _receiveControlBytesPerSecond:Number = 0;
        private var _receiveDataBytesPerSecond:Number = 0;
        private var _receiveDataBytesPerSecondFromIPMulticast:Number = 0;
        private var _receiveDataBytesPerSecondFromServer:Number = 0;
        private var _sendControlBytesPerSecond:Number = 0;
        private var _sendControlBytesPerSecondToServer:Number = 0;
        private var _sendDataBytesPerSecond:Number = 0;

        public function NetStreamMulticastInfo(sendDataBytesPerSecond:Number, sendControlBytesPerSecond:Number, receiveDataBytesPerSecond:Number, receiveControlBytesPerSecond:Number, bytesPushedToPeers:Number, fragmentsPushedToPeers:Number, bytesRequestedByPeers:Number, fragmentsRequestedByPeers:Number, bytesPushedFromPeers:Number, fragmentsPushedFromPeers:Number, bytesRequestedFromPeers:Number, fragmentsRequestedFromPeers:Number, sendControlBytesPerSecondToServer:Number, receiveDataBytesPerSecondFromServer:Number, bytesReceivedFromServer:Number, fragmentsReceivedFromServer:Number, receiveDataBytesPerSecondFromIPMulticast:Number, bytesReceivedFromIPMulticast:Number, fragmentsReceivedFromIPMulticast:Number) {
            this._sendDataBytesPerSecond = sendDataBytesPerSecond;
            this._sendControlBytesPerSecond = sendControlBytesPerSecond;
            this._receiveDataBytesPerSecond = receiveDataBytesPerSecond;
            this._receiveControlBytesPerSecond = receiveControlBytesPerSecond;
            this._bytesPushedToPeers = bytesPushedToPeers;
            this._fragmentsPushedToPeers = fragmentsPushedToPeers;
            this._bytesRequestedByPeers = bytesRequestedByPeers;
            this._fragmentsRequestedByPeers = fragmentsRequestedByPeers;
            this._bytesPushedFromPeers = bytesPushedFromPeers;
            this._fragmentsPushedFromPeers = fragmentsPushedFromPeers;
            this._bytesRequestedFromPeers = bytesRequestedFromPeers;
            this._fragmentsRequestedFromPeers = fragmentsRequestedFromPeers;
            this._sendControlBytesPerSecondToServer = sendControlBytesPerSecondToServer;
            this._receiveDataBytesPerSecondFromServer = receiveDataBytesPerSecondFromServer;
            this._bytesReceivedFromServer = bytesReceivedFromServer;
            this._fragmentsReceivedFromServer = fragmentsReceivedFromServer;
            this._receiveDataBytesPerSecondFromIPMulticast = receiveDataBytesPerSecondFromIPMulticast;
            this._bytesReceivedFromIPMulticast = bytesReceivedFromIPMulticast;
            this._fragmentsReceivedFromIPMulticast = fragmentsReceivedFromIPMulticast;
        }

        public function toString():String {
            return "sendDataBytesPerSecond=" + this._sendDataBytesPerSecond
                + " sendControlBytesPerSecond=" + this._sendControlBytesPerSecond
                + " receiveDataBytesPerSecond=" + this._receiveDataBytesPerSecond
                + " receiveControlBytesPerSecond=" + this._receiveControlBytesPerSecond
                + " bytesPushedToPeers=" + this._bytesPushedToPeers
                + " fragmentsPushedToPeers=" + this._fragmentsPushedToPeers
                + " bytesRequestedByPeers=" + this._bytesRequestedByPeers
                + " fragmentsRequestedByPeers=" + this._fragmentsRequestedByPeers
                + " bytesPushedFromPeers=" + this._bytesPushedFromPeers
                + " fragmentsPushedFromPeers=" + this._fragmentsPushedFromPeers
                + " bytesRequestedFromPeers=" + this._bytesRequestedFromPeers
                + " fragmentsRequestedFromPeers=" + this._fragmentsRequestedFromPeers
                + " sendControlBytesPerSecondToServer=" + this._sendControlBytesPerSecondToServer
                + " receiveDataBytesPerSecondFromServer=" + this._receiveDataBytesPerSecondFromServer
                + " bytesReceivedFromServer=" + this._bytesReceivedFromServer
                + " fragmentsReceivedFromServer=" + this._fragmentsReceivedFromServer
                + " receiveDataBytesPerSecondFromIPMulticast=" + this._receiveDataBytesPerSecondFromIPMulticast
                + " bytesReceivedFromIPMulticast=" + this._bytesReceivedFromIPMulticast
                + " fragmentsReceivedFromIPMulticast=" + this._fragmentsReceivedFromIPMulticast;
        }

        public function get bytesPushedFromPeers():Number {
            return this._bytesPushedFromPeers;
        }

        public function get bytesPushedToPeers():Number {
            return this._bytesPushedToPeers;
        }

        public function get bytesReceivedFromIPMulticast():Number {
            return this._bytesReceivedFromIPMulticast;
        }

        public function get bytesReceivedFromServer():Number {
            return this._bytesReceivedFromServer;
        }

        public function get bytesRequestedByPeers():Number {
            return this._bytesRequestedByPeers;
        }

        public function get bytesRequestedFromPeers():Number {
            return this._bytesRequestedFromPeers;
        }

        public function get fragmentsPushedFromPeers():Number {
            return this._fragmentsPushedFromPeers;
        }

        public function get fragmentsPushedToPeers():Number {
            return this._fragmentsPushedToPeers;
        }

        public function get fragmentsReceivedFromIPMulticast():Number {
            return this._fragmentsReceivedFromIPMulticast;
        }

        public function get fragmentsReceivedFromServer():Number {
            return this._fragmentsReceivedFromServer;
        }

        public function get fragmentsRequestedByPeers():Number {
            return this._fragmentsRequestedByPeers;
        }

        public function get fragmentsRequestedFromPeers():Number {
            return this._fragmentsRequestedFromPeers;
        }

        public function get receiveControlBytesPerSecond():Number {
            return this._receiveControlBytesPerSecond;
        }

        public function get receiveDataBytesPerSecond():Number {
            return this._receiveDataBytesPerSecond;
        }

        public function get receiveDataBytesPerSecondFromIPMulticast():Number {
            return this._receiveDataBytesPerSecondFromIPMulticast;
        }

        public function get receiveDataBytesPerSecondFromServer():Number {
            return this._receiveDataBytesPerSecondFromServer;
        }

        public function get sendControlBytesPerSecond():Number {
            return this._sendControlBytesPerSecond;
        }

        public function get sendControlBytesPerSecondToServer():Number {
            return this._sendControlBytesPerSecondToServer;
        }

        public function get sendDataBytesPerSecond():Number {
            return this._sendDataBytesPerSecond;
        }
    }
}
