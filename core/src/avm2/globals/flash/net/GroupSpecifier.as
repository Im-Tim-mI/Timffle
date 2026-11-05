package flash.net {
    // Timffle: `GroupSpecifier` builds the opaque `groupspec` strings that `NetGroup`
    // and `NetStream` take for RTMFP peer-to-peer groups. The class is pure data, and
    // the strings are byte for byte the ones Flash Player 32 builds (measured,
    // tests/tests/swfs/avm2/groupspecifier_options). Layout: "G:" and the hex of a
    // list of options, each `length, type, payload` with the length a VLU (7 bits per
    // byte, high bit = more follows) that covers the type byte:
    //   7f minGroupspecVersion (a VLU; left out for version 1), 00 routing,
    //   01 multicast, 02 object replication, 03 posting, 05 publish password,
    //   07 posting password, 0c server channel, 0d peer-to-peer disabled,
    //   0e the name (UTF-8), 0e again with the 32 random bytes of `makeUnique()`,
    //   1b IP multicast member updates, then a 00 byte; after it every IP multicast
    //   address (0a: 4 or 16 address bytes, the port, an optional source address of
    //   the same family) and then every bootstrap peer (0b), each in the order added;
    //   with authorizations, 15 the publish password and 17 the posting password
    //   (UTF-8) follow.
    // A password hash is SHA-256(salt + password) after the salt itself (no salt:
    // SHA-256(password)); an empty password clears it. Flash Player copies a
    // bootstrap peer ID into the hex unchecked, so this does too.
    [API("667")]
    public class GroupSpecifier {
        private var _name:String;
        private var _ipMulticastMemberUpdatesEnabled:Boolean = false;
        private var _minGroupspecVersion:int = 2;
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
                throw new ArgumentError("Name can not be empty");
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
            this._minGroupspecVersion = version < 1 ? 1 : version;
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
            this._bootstrapPeers.push(GroupSpecifier.encodeBootstrapPeerIDSpec(peerID));
        }

        public function addIPMulticastAddress(address:String, port:* = null, source:String = null):void {
            this._ipMulticastAddresses.push(GroupSpecifier.encodeIPMulticastAddressSpec(address, port, source));
        }

        // The random tag makes this groupspec different from every other one built
        // from the same settings; other members must get this exact string.
        public function makeUnique():void {
            this._uniqueTag = GroupSpecifier.randomHex(32);
        }

        public function setPostingPassword(password:String = null, salt:String = null):void {
            this._postingPassword = password == null || password.length == 0 ? null : password;
            this._postingPasswordHash = this._postingPassword == null ? null : GroupSpecifier.hashPassword(password, salt);
        }

        public function setPublishPassword(password:String = null, salt:String = null):void {
            this._publishPassword = password == null || password.length == 0 ? null : password;
            this._publishPasswordHash = this._publishPassword == null ? null : GroupSpecifier.hashPassword(password, salt);
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
            var spec:String = "G:";
            if (this._minGroupspecVersion > 1) {
                spec += GroupSpecifier.option(0x7f, GroupSpecifier.vlu(this._minGroupspecVersion));
            }
            if (this._routingEnabled) spec += GroupSpecifier.option(0x00, "");
            if (this._multicastEnabled) spec += GroupSpecifier.option(0x01, "");
            if (this._objectReplicationEnabled) spec += GroupSpecifier.option(0x02, "");
            if (this._postingEnabled) spec += GroupSpecifier.option(0x03, "");
            if (this._publishPasswordHash != null) spec += GroupSpecifier.option(0x05, this._publishPasswordHash);
            if (this._postingPasswordHash != null) spec += GroupSpecifier.option(0x07, this._postingPasswordHash);
            if (this._serverChannelEnabled) spec += GroupSpecifier.option(0x0c, "");
            if (this._peerToPeerDisabled) spec += GroupSpecifier.option(0x0d, "");
            spec += GroupSpecifier.option(0x0e, GroupSpecifier.utf8Hex(this._name));
            if (this._uniqueTag != null) spec += GroupSpecifier.option(0x0e, this._uniqueTag);
            if (this._ipMulticastMemberUpdatesEnabled) spec += GroupSpecifier.option(0x1b, "");
            spec += "00";
            for each (var addr:String in this._ipMulticastAddresses) {
                spec += addr;
            }
            for each (var peer:String in this._bootstrapPeers) {
                spec += peer;
            }
            return spec;
        }

        public function toString():String {
            return this.groupspecWithAuthorizations();
        }

        // The peer ID goes into the hex as it is (Flash Player 32 does not check it:
        // "abc" makes the option 020babc, null the text "null").
        public static function encodeBootstrapPeerIDSpec(peerID:String):String {
            return GroupSpecifier.option(0x0b, peerID == null ? "null" : peerID);
        }

        public static function encodeIPMulticastAddressSpec(address:String, port:* = null, source:String = null):String {
            if (address == null) {
                throw new ArgumentError("Invalid address");
            }
            var host:String = address;
            var portText:String = null;
            if (address.charAt(0) == "[") {
                var close:int = address.indexOf("]");
                if (close < 0) {
                    throw new ArgumentError("Invalid address");
                }
                host = address.substring(1, close);
                var rest:String = address.substring(close + 1);
                if (rest.length > 0) {
                    if (rest.charAt(0) != ":") {
                        throw new ArgumentError("Invalid address");
                    }
                    portText = rest.substring(1);
                }
            } else if (address.indexOf(":") >= 0 && address.indexOf(":") == address.lastIndexOf(":")) {
                // IPv4 with a port; a bare IPv6 address has several colons.
                host = address.substring(0, address.indexOf(":"));
                portText = address.substring(address.indexOf(":") + 1);
            }
            // A `port` argument wins over a port in `address`.
            var portNumber:Number;
            if (port != null) {
                portNumber = Number(port);
            } else if (portText != null) {
                portNumber = Number(portText);
            } else {
                throw new ArgumentError("Invalid address");
            }
            if (isNaN(portNumber)) {
                throw new ArgumentError("Invalid address");
            }
            if (portNumber < 0 || portNumber > 65535) {
                throw new RangeError();
            }
            var hostHex:String = GroupSpecifier.addressHex(host);
            var payload:String = hostHex + GroupSpecifier.hexByte(int(portNumber) >> 8) + GroupSpecifier.hexByte(int(portNumber));
            if (source != null) {
                var sourceHex:String = GroupSpecifier.addressHex(source);
                if (sourceHex.length != hostHex.length) {
                    throw new ArgumentError("Invalid address");
                }
                payload += sourceHex;
            }
            return GroupSpecifier.option(0x0a, payload);
        }

        public static function encodePostingAuthorization(password:String):String {
            if (password == null) {
                throw new TypeError("Error #2007: Parameter password must be non-null.", 2007);
            }
            return GroupSpecifier.option(0x17, GroupSpecifier.utf8Hex(password));
        }

        public static function encodePublishAuthorization(password:String):String {
            if (password == null) {
                throw new TypeError("Error #2007: Parameter password must be non-null.", 2007);
            }
            return GroupSpecifier.option(0x15, GroupSpecifier.utf8Hex(password));
        }

        // --- helpers (Timffle) ---

        // The bytes of a numeric IPv4 ("a.b.c.d", RangeError for a part above 255) or
        // IPv6 address as hex; anything else (host names too) is "Invalid address".
        private static function addressHex(host:String):String {
            var result:String = "";
            var i:int;
            if (host.indexOf(":") < 0) {
                var parts:Array = host.split(".");
                if (parts.length != 4) {
                    throw new ArgumentError("Invalid address");
                }
                for (i = 0; i < 4; i++) {
                    if (!/^[0-9]{1,3}$/.test(parts[i])) {
                        throw new ArgumentError("Invalid address");
                    }
                    var octet:int = int(parts[i]);
                    if (octet > 255) {
                        throw new RangeError();
                    }
                    result += GroupSpecifier.hexByte(octet);
                }
                return result;
            }
            var halves:Array = host.split("::");
            if (halves.length > 2) {
                throw new ArgumentError("Invalid address");
            }
            var head:Array = halves[0].length > 0 ? halves[0].split(":") : [];
            var tail:Array = halves.length == 2 && halves[1].length > 0 ? halves[1].split(":") : [];
            var missing:int = 8 - head.length - tail.length;
            if ((halves.length == 2 && missing < 1) || (halves.length == 1 && missing != 0)) {
                throw new ArgumentError("Invalid address");
            }
            var groups:Array = head.slice();
            for (i = 0; halves.length == 2 && i < missing; i++) {
                groups.push("0");
            }
            groups = groups.concat(tail);
            for (i = 0; i < 8; i++) {
                if (!/^[0-9a-fA-F]{1,4}$/.test(groups[i])) {
                    throw new ArgumentError("Invalid address");
                }
                var group:int = parseInt(groups[i], 16);
                result += GroupSpecifier.hexByte(group >> 8) + GroupSpecifier.hexByte(group);
            }
            return result;
        }

        private static function hashPassword(password:String, salt:String):String {
            if (salt == null || salt.length == 0) {
                return GroupSpecifier.sha256Hex(password);
            }
            return GroupSpecifier.utf8Hex(salt) + GroupSpecifier.sha256Hex(salt + password);
        }

        private static function option(type:uint, payloadHex:String):String {
            var length:uint = 1 + uint(payloadHex.length / 2);
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
