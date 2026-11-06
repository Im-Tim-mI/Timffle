package {
    import flash.display.Sprite;
    import flash.net.GroupSpecifier;
    import flash.utils.getQualifiedClassName;

    // Timffle: the groupspec string of every GroupSpecifier option on its own and in
    // combination, the encode* helpers and their errors. output.txt was recorded with
    // the real Flash Player 32 (twice, same output; makeUnique() is random, so only
    // its framing is shown). The errors with errorID 0 carry Flash Player's own text.
    public class Test extends Sprite {
        private function fresh():GroupSpecifier {
            return new GroupSpecifier("test");
        }

        private function show(label:String, gs:GroupSpecifier):void {
            trace(label + ": without=" + gs.groupspecWithoutAuthorizations() + " auth='" + gs.authorizations() + "' with=" + gs.groupspecWithAuthorizations() + " toString=" + gs.toString());
        }

        private function attempt(label:String, f:Function):void {
            try {
                trace(label + " -> " + f());
            } catch (e:Error) {
                trace(label + " threw " + getQualifiedClassName(e) + " #" + e.errorID + (e.errorID == 0 ? " '" + e.message + "'" : ""));
            }
        }

        public function Test() {
            var gs:GroupSpecifier;
            show("plain", fresh());
            gs = fresh(); gs.ipMulticastMemberUpdatesEnabled = true; show("ipMulticastMemberUpdatesEnabled", gs);
            gs = fresh(); gs.multicastEnabled = true; show("multicastEnabled", gs);
            gs = fresh(); gs.objectReplicationEnabled = true; show("objectReplicationEnabled", gs);
            gs = fresh(); gs.peerToPeerDisabled = true; show("peerToPeerDisabled", gs);
            gs = fresh(); gs.postingEnabled = true; show("postingEnabled", gs);
            gs = fresh(); gs.routingEnabled = true; show("routingEnabled", gs);
            gs = fresh(); gs.serverChannelEnabled = true; show("serverChannelEnabled", gs);
            gs = fresh(); gs.multicastEnabled = true; gs.postingEnabled = true; show("multicast+posting", gs);
            gs = fresh(); gs.multicastEnabled = true; gs.multicastEnabled = false; show("multicast on then off", gs);
            gs = fresh();
            gs.routingEnabled = gs.multicastEnabled = gs.objectReplicationEnabled = gs.postingEnabled = true;
            gs.serverChannelEnabled = gs.peerToPeerDisabled = gs.ipMulticastMemberUpdatesEnabled = true;
            show("all flags", gs);
            trace("flags: " + [gs.ipMulticastMemberUpdatesEnabled, gs.multicastEnabled, gs.objectReplicationEnabled, gs.peerToPeerDisabled, gs.postingEnabled, gs.routingEnabled, gs.serverChannelEnabled].join(" "));
            trace("minGroupspecVersion default: " + fresh().minGroupspecVersion + ", maxSupportedGroupspecVersion: " + GroupSpecifier.maxSupportedGroupspecVersion);
            var versions:Array = [2, 3, 1, 0, -3, 300];
            for each (var ver:int in versions) {
                gs = fresh();
                gs.minGroupspecVersion = ver;
                show("minGroupspecVersion=" + ver + " (reads " + gs.minGroupspecVersion + ")", gs);
            }
            var peer:String = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
            gs = fresh(); gs.addBootstrapPeer(peer); show("addBootstrapPeer", gs);
            gs = fresh(); gs.addBootstrapPeer(peer); gs.addBootstrapPeer(peer.toUpperCase()); show("addBootstrapPeer x2", gs);
            gs = fresh(); gs.addBootstrapPeer("nothex"); show("addBootstrapPeer(nothex)", gs);
            gs = fresh(); gs.addBootstrapPeer("abc"); show("addBootstrapPeer(abc)", gs);
            gs = fresh(); gs.addBootstrapPeer(""); show("addBootstrapPeer('')", gs);
            gs = fresh(); gs.addBootstrapPeer(null); show("addBootstrapPeer(null)", gs);
            gs = fresh(); gs.addIPMulticastAddress("224.0.0.254", 30000); show("addIPMulticastAddress(a,p)", gs);
            gs = fresh(); gs.addIPMulticastAddress("224.0.0.254:30000"); show("addIPMulticastAddress(a:p)", gs);
            gs = fresh(); gs.addIPMulticastAddress("224.0.0.254", 30000, "10.0.0.1"); show("addIPMulticastAddress(a,p,s)", gs);
            gs = fresh(); gs.addIPMulticastAddress("[ff02::1]:30000"); show("addIPMulticastAddress(v6)", gs);
            gs = fresh(); gs.addIPMulticastAddress("[ff02::1]:30000", null, "fe80::1"); show("addIPMulticastAddress(v6,s)", gs);
            gs = fresh(); gs.addIPMulticastAddress("224.0.0.1:1"); gs.addIPMulticastAddress("224.0.0.1:1"); gs.addIPMulticastAddress("224.0.0.2:2"); show("addIPMulticastAddress x3", gs);
            gs = fresh(); gs.addBootstrapPeer("ab"); gs.addIPMulticastAddress("224.0.0.1:1"); gs.addBootstrapPeer("cd"); show("peer, address, peer", gs);
            gs = fresh(); gs.setPublishPassword("pw"); show("setPublishPassword(pw)", gs);
            gs = fresh(); gs.setPublishPassword("pw", "salt"); show("setPublishPassword(pw,salt)", gs);
            gs = fresh(); gs.setPublishPassword("a", "bb"); show("setPublishPassword(a,bb)", gs);
            gs = fresh(); gs.setPublishPassword("pw", ""); show("setPublishPassword(pw,'')", gs);
            gs = fresh(); gs.setPublishPassword("pw"); gs.setPublishPassword("pw"); show("setPublishPassword twice", gs);
            gs = fresh(); gs.setPostingPassword("pw"); show("setPostingPassword(pw)", gs);
            gs = fresh(); gs.setPostingPassword("pw", "salt"); show("setPostingPassword(pw,salt)", gs);
            gs = fresh(); gs.setPublishPassword("pw"); gs.setPostingPassword("pw"); show("both passwords", gs);
            gs = fresh(); gs.setPublishPassword("pw"); gs.setPublishPassword(null); show("publish password cleared", gs);
            gs = fresh(); gs.setPublishPassword(""); show("setPublishPassword('')", gs);
            gs = fresh(); gs.setPublishPassword(null, "salt"); show("setPublishPassword(null,salt)", gs);
            gs = fresh(); gs.makeUnique();
            var u:String = gs.groupspecWithoutAuthorizations();
            trace("makeUnique: length=" + u.length + " starts=" + u.substr(0, 24) + " ends=" + u.substr(u.length - 2));
            gs.makeUnique();
            trace("makeUnique twice: length=" + gs.groupspecWithoutAuthorizations().length + " differs=" + (gs.groupspecWithoutAuthorizations() != u));
            gs = fresh(); gs.makeUnique(); gs.multicastEnabled = true; gs.ipMulticastMemberUpdatesEnabled = true; gs.addBootstrapPeer("ab");
            u = gs.toString();
            trace("makeUnique+flags+peer: length=" + u.length + " starts=" + u.substr(0, 28) + " ends=" + u.substr(u.length - 12));
            gs = fresh();
            gs.multicastEnabled = true;
            gs.setPublishPassword("pw", "salt");
            gs.addBootstrapPeer(peer);
            gs.addIPMulticastAddress("224.0.0.254", 30000);
            gs.minGroupspecVersion = 2;
            show("combined", gs);
            show("name with utf8", new GroupSpecifier("grüp"));
            show("long name", new GroupSpecifier("0123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789"));
            attempt("new GroupSpecifier(null)", function():* { return new GroupSpecifier(null); });
            attempt("new GroupSpecifier('')", function():* { return new GroupSpecifier(""); });
            attempt("encodePublishAuthorization(pw)", function():* { return GroupSpecifier.encodePublishAuthorization("pw"); });
            attempt("encodePostingAuthorization(pw)", function():* { return GroupSpecifier.encodePostingAuthorization("pw"); });
            attempt("encodePublishAuthorization('')", function():* { return GroupSpecifier.encodePublishAuthorization(""); });
            attempt("encodePublishAuthorization(utf8)", function():* { return GroupSpecifier.encodePublishAuthorization("ü"); });
            attempt("encodePublishAuthorization(null)", function():* { return GroupSpecifier.encodePublishAuthorization(null); });
            attempt("encodePostingAuthorization(130 chars)", function():* { var p:String = ""; for (var k:int = 0; k < 130; k++) p += "x"; return GroupSpecifier.encodePostingAuthorization(p).substr(0, 12); });
            attempt("encodeBootstrapPeerIDSpec(peer)", function():* { return GroupSpecifier.encodeBootstrapPeerIDSpec(peer); });
            attempt("encodeBootstrapPeerIDSpec(abc)", function():* { return GroupSpecifier.encodeBootstrapPeerIDSpec("abc"); });
            attempt("encodeBootstrapPeerIDSpec(null)", function():* { return GroupSpecifier.encodeBootstrapPeerIDSpec(null); });
            var addresses:Array = [
                ["224.0.0.254", 30000, null], ["224.0.0.254:30000", null, null], ["224.0.0.254", 30000, "10.0.0.1"],
                ["224.0.0.254:1", 2, null], ["224.0.0.254", "7", null], ["224.0.0.254:0", null, null],
                ["[ff02::1]:30000", null, null], ["ff02::1", 5, null], ["[::]:5", null, null], ["[1:2:3:4:5:6:7:8]:5", null, null],
                ["[ff02::1]:5", null, "fe80::1"], ["224.0.0.254", 70000, null], ["1.2.3.400:5", null, null],
                ["224.0.0.254", null, null], ["localhost:5", null, null], ["1.2.3:5", null, null], [null, 1, null],
                ["224.0.0.254", 5, "bad"], ["224.0.0.254", 5, "fe80::1"], ["not an address", 1, null]];
            for each (var a:Array in addresses) {
                attempt("encodeIPMulticastAddressSpec(" + a.join(", ") + ")", (function(x:Array):Function {
                    return function():* { return GroupSpecifier.encodeIPMulticastAddressSpec(x[0], x[1], x[2]); };
                })(a));
            }
            attempt("addIPMulticastAddress(no port)", function():* { var g:GroupSpecifier = fresh(); g.addIPMulticastAddress("224.0.0.254"); return g.toString(); });
        }
    }
}
