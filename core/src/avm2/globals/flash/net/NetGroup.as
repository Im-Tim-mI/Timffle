package flash.net {
    import flash.events.EventDispatcher;

    // Timffle: RTMFP peer-to-peer groups. This player has no RTMFP client, so a
    // NetConnection is never connected with protocol "rtmfp" and the constructor
    // always ends in the ArgumentError the reference gives for a NetConnection that
    // is not (RTMFP-)connected (#2126, the code Flash Player uses for every
    // "NetConnection object must be connected" check). The remaining members are
    // declared with the values of a group that is not connected: no neighbours, no
    // coverage, nothing routed; they are unreachable without an instance.
    [API("667")]
    public class NetGroup extends EventDispatcher {
        private var _receiveMode:String = NetGroupReceiveMode.EXACT;
        private var _replicationStrategy:String = NetGroupReplicationStrategy.RAREST_FIRST;

        public function NetGroup(connection:NetConnection, groupspec:String) {
            if (connection == null) {
                throw new TypeError("Error #2007: Parameter connection must be non-null.", 2007);
            }
            if (groupspec == null) {
                throw new TypeError("Error #2007: Parameter groupspec must be non-null.", 2007);
            }
            if (!connection.connected || connection.protocol != "rtmfp") {
                throw new ArgumentError("Error #2126: NetConnection object must be connected.", 2126);
            }
            if (groupspec.indexOf("G:") != 0) {
                throw new ArgumentError("Error #2004: One of the parameters is invalid.", 2004);
            }
        }

        public function get estimatedMemberCount():Number {
            return 0;
        }

        public function get info():NetGroupInfo {
            return new NetGroupInfo();
        }

        public function get localCoverageFrom():String {
            return "";
        }

        public function get localCoverageTo():String {
            return "";
        }

        public function get neighborCount():Number {
            return 0;
        }

        public function get receiveMode():String {
            return this._receiveMode;
        }

        public function set receiveMode(mode:String):void {
            if (mode != NetGroupReceiveMode.EXACT && mode != NetGroupReceiveMode.NEAREST) {
                throw new ArgumentError("Error #2008: Parameter receiveMode must be one of the accepted values.", 2008);
            }
            this._receiveMode = mode;
        }

        public function get replicationStrategy():String {
            return this._replicationStrategy;
        }

        public function set replicationStrategy(strategy:String):void {
            if (strategy != NetGroupReplicationStrategy.LOWEST_FIRST && strategy != NetGroupReplicationStrategy.RAREST_FIRST) {
                throw new ArgumentError("Error #2008: Parameter replicationStrategy must be one of the accepted values.", 2008);
            }
            this._replicationStrategy = strategy;
        }

        public function addHaveObjects(startIndex:Number, endIndex:Number):void {
            NetGroup.checkRange(startIndex, endIndex);
        }

        public function addMemberHint(peerID:String):Boolean {
            return false;
        }

        public function addNeighbor(peerID:String):Boolean {
            return false;
        }

        public function addWantObjects(startIndex:Number, endIndex:Number):void {
            NetGroup.checkRange(startIndex, endIndex);
        }

        public function close():void {
        }

        public native function convertPeerIDToGroupAddress(peerID:String):String;

        public function denyRequestedObject(requestID:int):void {
        }

        // No posting is possible without the group: null is the documented error value.
        public function post(message:Object):String {
            return null;
        }

        public function removeHaveObjects(startIndex:Number, endIndex:Number):void {
            NetGroup.checkRange(startIndex, endIndex);
        }

        public function removeWantObjects(startIndex:Number, endIndex:Number):void {
            NetGroup.checkRange(startIndex, endIndex);
        }

        public function sendToAllNeighbors(message:Object):String {
            return NetGroupSendResult.NO_ROUTE;
        }

        public function sendToNearest(message:Object, groupAddress:String):String {
            return NetGroupSendResult.NO_ROUTE;
        }

        public function sendToNeighbor(message:Object, sendMode:String):String {
            return NetGroupSendResult.NO_ROUTE;
        }

        public function writeRequestedObject(requestID:int, object:Object):void {
        }

        // Object indices must lie in 0 .. 9007199254740992 (RangeError, reference).
        private static function checkRange(startIndex:Number, endIndex:Number):void {
            if (isNaN(startIndex) || isNaN(endIndex) || startIndex < 0 || endIndex < 0
                || startIndex > 9007199254740992 || endIndex > 9007199254740992) {
                throw new RangeError("Error #2006: The supplied index is out of bounds.", 2006);
            }
        }
    }
}
