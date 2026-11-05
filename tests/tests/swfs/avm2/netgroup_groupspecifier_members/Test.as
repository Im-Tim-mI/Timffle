package {
    import flash.display.Sprite;
    import flash.net.GroupSpecifier;
    import flash.net.NetConnection;
    import flash.net.NetGroup;
    import flash.net.NetGroupInfo;
    import flash.utils.getQualifiedClassName;

    public class Test extends Sprite {
        public function Test() {
            trace("// GroupSpecifier");
            try {
                new GroupSpecifier(null);
            } catch (e:Error) {
                trace("new GroupSpecifier(null): " + getQualifiedClassName(e) + " #" + e.errorID);
            }
            try {
                new GroupSpecifier("");
            } catch (e:Error) {
                trace("new GroupSpecifier(''): " + getQualifiedClassName(e) + " #" + e.errorID);
            }
            trace("maxSupportedGroupspecVersion: " + GroupSpecifier.maxSupportedGroupspecVersion);
            var gs:GroupSpecifier = new GroupSpecifier("test");
            trace("minGroupspecVersion: " + gs.minGroupspecVersion);
            trace("flags: " + gs.ipMulticastMemberUpdatesEnabled + " " + gs.multicastEnabled + " " + gs.objectReplicationEnabled + " " + gs.peerToPeerDisabled + " " + gs.postingEnabled + " " + gs.routingEnabled + " " + gs.serverChannelEnabled);
            trace("toString: " + gs);
            trace("groupspecWithoutAuthorizations: " + gs.groupspecWithoutAuthorizations());
            trace("groupspecWithAuthorizations: " + gs.groupspecWithAuthorizations());
            trace("authorizations: '" + gs.authorizations() + "'");

            gs.multicastEnabled = true;
            gs.postingEnabled = true;
            gs.objectReplicationEnabled = true;
            gs.routingEnabled = true;
            gs.serverChannelEnabled = true;
            gs.peerToPeerDisabled = true;
            gs.ipMulticastMemberUpdatesEnabled = true;
            trace("flags: " + gs.ipMulticastMemberUpdatesEnabled + " " + gs.multicastEnabled + " " + gs.objectReplicationEnabled + " " + gs.peerToPeerDisabled + " " + gs.postingEnabled + " " + gs.routingEnabled + " " + gs.serverChannelEnabled);
            trace("all flags: " + gs.groupspecWithoutAuthorizations());
            gs.minGroupspecVersion = 2;
            trace("version 2: " + gs.groupspecWithoutAuthorizations());
            try {
                gs.minGroupspecVersion = 0;
            } catch (e:Error) {
                trace("minGroupspecVersion = 0: " + getQualifiedClassName(e) + " #" + e.errorID);
            }

            var peer:String = "0123456789ABCDEF0123456789abcdef0123456789abcdef0123456789abcdef";
            trace("encodeBootstrapPeerIDSpec: " + GroupSpecifier.encodeBootstrapPeerIDSpec(peer));
            try {
                GroupSpecifier.encodeBootstrapPeerIDSpec("nothex");
            } catch (e:Error) {
                trace("encodeBootstrapPeerIDSpec(nothex): " + getQualifiedClassName(e) + " #" + e.errorID);
            }
            try {
                GroupSpecifier.encodeBootstrapPeerIDSpec(null);
            } catch (e:Error) {
                trace("encodeBootstrapPeerIDSpec(null): " + getQualifiedClassName(e) + " #" + e.errorID);
            }
            trace("encodeIPMulticastAddressSpec(a:p): " + GroupSpecifier.encodeIPMulticastAddressSpec("224.0.0.254:30000"));
            trace("encodeIPMulticastAddressSpec(a, p): " + GroupSpecifier.encodeIPMulticastAddressSpec("224.0.0.254", 30000));
            trace("encodeIPMulticastAddressSpec(a, p, s): " + GroupSpecifier.encodeIPMulticastAddressSpec("224.0.0.254", "30000", "10.0.0.1"));
            trace("encodeIPMulticastAddressSpec(v6): " + GroupSpecifier.encodeIPMulticastAddressSpec("[ff02::1]:30000"));
            try {
                GroupSpecifier.encodeIPMulticastAddressSpec("224.0.0.254");
            } catch (e:Error) {
                trace("encodeIPMulticastAddressSpec(no port): " + getQualifiedClassName(e) + " #" + e.errorID);
            }
            try {
                GroupSpecifier.encodeIPMulticastAddressSpec("224.0.0.254:1", 2);
            } catch (e:Error) {
                trace("encodeIPMulticastAddressSpec(two ports): " + getQualifiedClassName(e) + " #" + e.errorID);
            }
            try {
                GroupSpecifier.encodeIPMulticastAddressSpec(null, 1);
            } catch (e:Error) {
                trace("encodeIPMulticastAddressSpec(null): " + getQualifiedClassName(e) + " #" + e.errorID);
            }
            trace("encodePublishAuthorization: " + GroupSpecifier.encodePublishAuthorization("pw"));
            trace("encodePostingAuthorization: " + GroupSpecifier.encodePostingAuthorization("pw"));
            try {
                GroupSpecifier.encodePublishAuthorization(null);
            } catch (e:Error) {
                trace("encodePublishAuthorization(null): " + getQualifiedClassName(e) + " #" + e.errorID);
            }

            var gs2:GroupSpecifier = new GroupSpecifier("test");
            gs2.addBootstrapPeer(peer);
            gs2.addIPMulticastAddress("224.0.0.254", 30000);
            gs2.setPublishPassword("pw", "salt");
            gs2.setPostingPassword("post");
            trace("without: " + gs2.groupspecWithoutAuthorizations());
            trace("authorizations: " + gs2.authorizations());
            trace("with == without + authorizations: " + (gs2.groupspecWithAuthorizations() == gs2.groupspecWithoutAuthorizations() + gs2.authorizations()));
            gs2.setPublishPassword(null);
            gs2.setPostingPassword();
            trace("passwords cleared: " + gs2.groupspecWithAuthorizations());
            var plain:String = gs2.groupspecWithoutAuthorizations();
            gs2.makeUnique();
            var unique:String = gs2.groupspecWithoutAuthorizations();
            trace("makeUnique adds 36 hex digits: " + (unique.length == plain.length + 36) + ", starts the same: " + (unique.indexOf(plain) == 0));
            gs2.makeUnique();
            trace("makeUnique again differs: " + (gs2.groupspecWithoutAuthorizations() != unique));

            trace("// NetGroupInfo");
            trace(new NetGroupInfo());

            trace("// NetGroup");
            var nc:NetConnection = new NetConnection();
            try {
                new NetGroup(null, gs.toString());
            } catch (e:Error) {
                trace("new NetGroup(null): " + getQualifiedClassName(e) + " #" + e.errorID);
            }
            try {
                new NetGroup(nc, null);
            } catch (e:Error) {
                trace("new NetGroup(nc, null): " + getQualifiedClassName(e) + " #" + e.errorID);
            }
            try {
                new NetGroup(nc, gs.toString());
            } catch (e:Error) {
                trace("new NetGroup(unconnected): " + getQualifiedClassName(e) + " #" + e.errorID);
            }
            nc.connect(null);
            trace("protocol: " + nc.protocol);
            try {
                new NetGroup(nc, gs.toString());
            } catch (e:Error) {
                trace("new NetGroup(local): " + getQualifiedClassName(e) + " #" + e.errorID);
            }
        }
    }
}
