package flash.net {
    // Timffle: `GroupSpecifier` builds the opaque `groupspec` strings that `NetGroup`
    // and `NetStream` take for RTMFP peer-to-peer groups. The class is pure data and is
    // implemented completely: every setting is kept, the passwords are hashed
    // (SHA-256 of password + salt), `makeUnique()` adds 16 strong random bytes, and
    // the string is built in Flash Player's layout: "G:" followed by the hex of a
    // sequence of options, each `length, type, payload` (the length is a one-byte
    // VLU here; it covers the type byte). Flash Player's own output for
    // `new GroupSpecifier("test")` is "G:0101010c050e74657374": the fixed options
    // 01 and 0c, then option 0e carrying the name. The option types of the other
    // settings are not published by Adobe; the ones used here (02-0b for the flags
    // and addresses, 0f for the unique tag, 10-13 for the password hashes and the
    // authorizations) are this player's own and are documented as such.
    [API("667")]
    public class GroupSpecifier {
        private var _name:String;
        private var _ipMulticastMemberUpdatesEnabled:Boolean = false;
        private var _minGroupspecVersion:int = 1;
        private var _multicastEnabled:Boolean = false;
        private var _objectReplicationEnabled:Boolean = false;
        private var _peerToPeerDisabled:Boolean = false;
        private var _postingEnabled:Boolean = false;
        private var _routingEnabled:Boolean = false;
        private var _serverChannelEnabled:Boolean = false;
        private var _bootstrapPeers:Array = [];
        private var _ipMulticastAddresses:Array = [];
        private var _uniqueTag:String = null;
        private var _publishPassword:String = null;
        private var _publishPasswordHash:String = null;
        private var _postingPassword:String = null;
        private var _postingPasswordHash:String = null;

        public function GroupSpecifier(name:String) {
            if (name == null || name.length == 0) {
                throw new ArgumentError("Error #2004: One of the parameters is invalid.", 2004);
            }
            this._name = name;
        }

        // The highest groupspec version this runtime understands (Flash Player 11+:
        // version 2, which added IPv6 multicast addresses).
        [API("674")]
        public static function get maxSupportedGroupspecVersion():int {
            return 2;
        }

        [API("674")]
        public function get minGroupspecVersion():int {
            return this._minGroupspecVersion;
        }

        [API("674")]
        public function set minGroupspecVersion(version:int):void {
            if (version < 1) {
                throw new ArgumentError("Error #2004: One of the parameters is invalid.", 2004);
            }
            this._minGroupspecVersion = version;
        }

        public function get ipMulticastMemberUpdatesEnabled():Boolean {
            return this._ipMulticastMemberUpdatesEnabled;
        }

        public function set ipMulticastMemberUpdatesEnabled(enabled:Boolean):void {
            this._ipMulticastMemberUpdatesEnabled = enabled;
        }

        public function get multicastEnabled():Boolean {
            return this._multicastEnabled;
        }

        public function set multicastEnabled(enabled:Boolean):void {
            this._multicastEnabled = enabled;
        }

        public function get objectReplicationEnabled():Boolean {
            return this._objectReplicationEnabled;
        }

        public function set objectReplicationEnabled(enabled:Boolean):void {
            this._objectReplicationEnabled = enabled;
        }

        public function get peerToPeerDisabled():Boolean {
            return this._peerToPeerDisabled;
        }

        public function set peerToPeerDisabled(disabled:Boolean):void {
            this._peerToPeerDisabled = disabled;
        }

        public function get postingEnabled():Boolean {
            return this._postingEnabled;
        }

        public function set postingEnabled(enabled:Boolean):void {
            this._postingEnabled = enabled;
        }

        public function get routingEnabled():Boolean {
            return this._routingEnabled;
        }

        public function set routingEnabled(enabled:Boolean):void {
            this._routingEnabled = enabled;
        }

        public function get serverChannelEnabled():Boolean {
            return this._serverChannelEnabled;
        }

        public function set serverChannelEnabled(enabled:Boolean):void {
            this._serverChannelEnabled = enabled;
        }

        public function addBootstrapPeer(peerID:String):void {
            this._bootstrapPeers.push(GroupSpecifier.checkPeerID(peerID));
        }

        public function addIPMulticastAddress(address:String, port:* = null, source:String = null):void {
            this._ipMulticastAddresses.push(GroupSpecifier.formatMulticastAddress(address, port, source));
        }

        // The random tag makes this groupspec different from every other one built
        // from the same settings; other members must get this exact string.
        public function makeUnique():void {
            this._uniqueTag = GroupSpecifier.randomHex(16);
        }

        public function setPostingPassword(password:String = null, salt:String = null):void {
            this._postingPassword = password;
            this._postingPasswordHash = password == null ? null : GroupSpecifier.hashPassword(password, salt);
        }

        public function setPublishPassword(password:String = null, salt:String = null):void {
            this._publishPassword = password;
            this._publishPasswordHash = password == null ? null : GroupSpecifier.hashPassword(password, salt);
        }

        // The passwords (plain) that unlock the features whose hashes are in the
        // groupspec; appended to an unauthorized groupspec they authorize it.
        public function authorizations():String {
            var result:String = "";
            if (this._publishPassword != null) {
                result += GroupSpecifier.encodePublishAuthorization(this._publishPassword);
            }
            if (this._postingPassword != null) {
                result += GroupSpecifier.encodePostingAuthorization(this._postingPassword);
            }
            return result;
        }

        public function groupspecWithAuthorizations():String {
            return this.groupspecWithoutAuthorizations() + this.authorizations();
        }

        public function groupspecWithoutAuthorizations():String {
            var spec:String = "G:" + GroupSpecifier.option(0x01, "") + GroupSpecifier.option(0x0c, "");
            if (this._minGroupspecVersion > 1) {
                spec += GroupSpecifier.option(0x09, GroupSpecifier.hexByte(this._minGroupspecVersion));
            }
            spec += GroupSpecifier.option(0x0e, GroupSpecifier.utf8Hex(this._name));
            if (this._multicastEnabled) spec += GroupSpecifier.option(0x02, "");
            if (this._postingEnabled) spec += GroupSpecifier.option(0x03, "");
            if (this._objectReplicationEnabled) spec += GroupSpecifier.option(0x04, "");
            if (this._routingEnabled) spec += GroupSpecifier.option(0x05, "");
            if (this._serverChannelEnabled) spec += GroupSpecifier.option(0x06, "");
            if (this._peerToPeerDisabled) spec += GroupSpecifier.option(0x07, "");
            if (this._ipMulticastMemberUpdatesEnabled) spec += GroupSpecifier.option(0x08, "");
            for each (var peer:String in this._bootstrapPeers) {
                spec += GroupSpecifier.encodeBootstrapPeerIDSpec(peer);
            }
            for each (var addr:String in this._ipMulticastAddresses) {
                spec += GroupSpecifier.option(0x0b, GroupSpecifier.utf8Hex(addr));
            }
            if (this._uniqueTag != null) {
                spec += GroupSpecifier.option(0x0f, this._uniqueTag);
            }
            if (this._publishPasswordHash != null) {
                spec += GroupSpecifier.option(0x10, this._publishPasswordHash);
            }
            if (this._postingPasswordHash != null) {
                spec += GroupSpecifier.option(0x11, this._postingPasswordHash);
            }
            return spec;
        }

        public function toString():String {
            return this.groupspecWithAuthorizations();
        }

        public static function encodeBootstrapPeerIDSpec(peerID:String):String {
            return GroupSpecifier.option(0x0a, GroupSpecifier.checkPeerID(peerID));
        }

        public static function encodeIPMulticastAddressSpec(address:String, port:* = null, source:String = null):String {
            return GroupSpecifier.option(0x0b, GroupSpecifier.utf8Hex(GroupSpecifier.formatMulticastAddress(address, port, source)));
        }

        public static function encodePostingAuthorization(password:String):String {
            if (password == null) {
                throw new TypeError("Error #2007: Parameter password must be non-null.", 2007);
            }
            return GroupSpecifier.option(0x13, GroupSpecifier.utf8Hex(password));
        }

        public static function encodePublishAuthorization(password:String):String {
            if (password == null) {
                throw new TypeError("Error #2007: Parameter password must be non-null.", 2007);
            }
            return GroupSpecifier.option(0x12, GroupSpecifier.utf8Hex(password));
        }

        // --- helpers (Timffle) ---

        // A peer ID is the hex of 32 bytes (the SHA-256 of the peer's certificate).
        private static function checkPeerID(peerID:String):String {
            if (peerID == null) {
                throw new TypeError("Error #2007: Parameter peerID must be non-null.", 2007);
            }
            var lower:String = peerID.toLowerCase();
            if (lower.length != 64 || !/^[0-9a-f]{64}$/.test(lower)) {
                throw new ArgumentError("Error #2004: One of the parameters is invalid.", 2004);
            }
            return lower;
        }

        // "address:port" (IPv6 as "[address]:port"), with the optional SSM source as
        // "source@address:port". The port comes from `port` or from `address`, not both.
        private static function formatMulticastAddress(address:String, port:*, source:String):String {
            if (address == null) {
                throw new TypeError("Error #2007: Parameter address must be non-null.", 2007);
            }
            var host:String = address;
            var portInAddress:String = null;
            if (address.charAt(0) == "[") {
                var close:int = address.indexOf("]");
                if (close < 0) {
                    throw new ArgumentError("Error #2004: One of the parameters is invalid.", 2004);
                }
                host = address.substring(1, close);
                var rest:String = address.substring(close + 1);
                if (rest.length > 0) {
                    if (rest.charAt(0) != ":") {
                        throw new ArgumentError("Error #2004: One of the parameters is invalid.", 2004);
                    }
                    portInAddress = rest.substring(1);
                }
            } else if (address.indexOf(":") >= 0 && address.indexOf(":") == address.lastIndexOf(":")) {
                // IPv4 with a port; an IPv6 address has several colons and needs brackets.
                host = address.substring(0, address.indexOf(":"));
                portInAddress = address.substring(address.indexOf(":") + 1);
            }
            var portNumber:Number;
            if (port == null) {
                if (portInAddress == null) {
                    throw new ArgumentError("Error #2004: One of the parameters is invalid.", 2004);
                }
                portNumber = Number(portInAddress);
            } else {
                if (portInAddress != null) {
                    throw new ArgumentError("Error #2004: One of the parameters is invalid.", 2004);
                }
                portNumber = Number(port);
            }
            if (host.length == 0 || isNaN(portNumber) || portNumber < 0 || portNumber > 65535 || portNumber != int(portNumber)) {
                throw new ArgumentError("Error #2004: One of the parameters is invalid.", 2004);
            }
            var formatted:String = (host.indexOf(":") >= 0 ? "[" + host + "]" : host) + ":" + int(portNumber);
            return source == null ? formatted : source + "@" + formatted;
        }

        private static function hashPassword(password:String, salt:String):String {
            return GroupSpecifier.sha256Hex(salt == null ? password : password + salt);
        }

        private static function option(type:uint, payloadHex:String):String {
            var length:uint = 1 + payloadHex.length / 2;
            return GroupSpecifier.vlu(length) + GroupSpecifier.hexByte(type) + payloadHex;
        }

        // Variable-length unsigned integer, 7 bits per byte, high bit = more follows.
        private static function vlu(value:uint):String {
            var bytes:Array = [];
            do {
                bytes.unshift(value & 0x7f);
                value >>>= 7;
            } while (value > 0);
            var result:String = "";
            for (var i:int = 0; i < bytes.length; i++) {
                result += GroupSpecifier.hexByte(i < bytes.length - 1 ? bytes[i] | 0x80 : bytes[i]);
            }
            return result;
        }

        private static function hexByte(value:uint):String {
            var hex:String = (value & 0xff).toString(16);
            return hex.length < 2 ? "0" + hex : hex;
        }

        private static native function utf8Hex(text:String):String;

        private static native function sha256Hex(text:String):String;

        private static native function randomHex(bytes:uint):String;
    }
}
