package flash.net {
    // Timffle: the transport statistics of a NetGroup. No RTMFP group ever carries
    // traffic on this player. The constructor takes the eight rates in this order and
    // `toString()` lists them as `name=value` pairs separated by spaces (measured on
    // Flash Player 32, tests/tests/swfs/avm2/netstream_local_events).
    [API("667")]
    public final class NetGroupInfo {
        private var _postingSendDataBytesPerSecond:Number = 0;
        private var _postingSendControlBytesPerSecond:Number = 0;
        private var _postingReceiveDataBytesPerSecond:Number = 0;
        private var _postingReceiveControlBytesPerSecond:Number = 0;
        private var _routingSendBytesPerSecond:Number = 0;
        private var _routingReceiveBytesPerSecond:Number = 0;
        private var _objectReplicationSendBytesPerSecond:Number = 0;
        private var _objectReplicationReceiveBytesPerSecond:Number = 0;

        public function NetGroupInfo(postingSendDataBytesPerSecond:Number, postingSendControlBytesPerSecond:Number, postingReceiveDataBytesPerSecond:Number, postingReceiveControlBytesPerSecond:Number, routingSendBytesPerSecond:Number, routingReceiveBytesPerSecond:Number, objectReplicationSendBytesPerSecond:Number, objectReplicationReceiveBytesPerSecond:Number) {
            this._postingSendDataBytesPerSecond = postingSendDataBytesPerSecond;
            this._postingSendControlBytesPerSecond = postingSendControlBytesPerSecond;
            this._postingReceiveDataBytesPerSecond = postingReceiveDataBytesPerSecond;
            this._postingReceiveControlBytesPerSecond = postingReceiveControlBytesPerSecond;
            this._routingSendBytesPerSecond = routingSendBytesPerSecond;
            this._routingReceiveBytesPerSecond = routingReceiveBytesPerSecond;
            this._objectReplicationSendBytesPerSecond = objectReplicationSendBytesPerSecond;
            this._objectReplicationReceiveBytesPerSecond = objectReplicationReceiveBytesPerSecond;
        }

        public function toString():String {
            return "postingSendDataBytesPerSecond=" + this._postingSendDataBytesPerSecond
                + " postingSendControlBytesPerSecond=" + this._postingSendControlBytesPerSecond
                + " postingReceiveDataBytesPerSecond=" + this._postingReceiveDataBytesPerSecond
                + " postingReceiveControlBytesPerSecond=" + this._postingReceiveControlBytesPerSecond
                + " routingSendBytesPerSecond=" + this._routingSendBytesPerSecond
                + " routingReceiveBytesPerSecond=" + this._routingReceiveBytesPerSecond
                + " objectReplicationSendBytesPerSecond=" + this._objectReplicationSendBytesPerSecond
                + " objectReplicationReceiveBytesPerSecond=" + this._objectReplicationReceiveBytesPerSecond;
        }

        public function get objectReplicationReceiveBytesPerSecond():Number {
            return this._objectReplicationReceiveBytesPerSecond;
        }

        public function get objectReplicationSendBytesPerSecond():Number {
            return this._objectReplicationSendBytesPerSecond;
        }

        public function get postingReceiveControlBytesPerSecond():Number {
            return this._postingReceiveControlBytesPerSecond;
        }

        public function get postingReceiveDataBytesPerSecond():Number {
            return this._postingReceiveDataBytesPerSecond;
        }

        public function get postingSendControlBytesPerSecond():Number {
            return this._postingSendControlBytesPerSecond;
        }

        public function get postingSendDataBytesPerSecond():Number {
            return this._postingSendDataBytesPerSecond;
        }

        public function get routingReceiveBytesPerSecond():Number {
            return this._routingReceiveBytesPerSecond;
        }

        public function get routingSendBytesPerSecond():Number {
            return this._routingSendBytesPerSecond;
        }
    }
}
