package main

import (
	"net"
	"net/netip"
	"strings"
)

// A conservative, explicit public-unicast policy: every IPv4 special-purpose
// block that IANA lists as not globally reachable is denied, and so is all of
// 192.0.0.0/24 (IETF protocol assignments), including the two globally
// reachable anycast addresses inside it: game servers do not need IANA
// protocol-assignment destinations. The globally reachable special-purpose
// blocks that are not inside such a denied block (AS112 192.31.196.0/24 and
// 192.175.48.0/24, AMT 192.52.193.0/24) stay allowed, like any other public
// address. The snapshots below cover the IANA IPv4/IPv6 special-purpose
// registries as of 2026-10; future allocations require deliberate review,
// not an env override.
var blockedV4 = mustPrefixes(
	"0.0.0.0/8", "10.0.0.0/8", "100.64.0.0/10", "127.0.0.0/8",
	"169.254.0.0/16", "172.16.0.0/12", "192.0.0.0/24", "192.0.2.0/24",
	"192.88.99.0/24", "192.168.0.0/16", "198.18.0.0/15",
	"198.51.100.0/24", "203.0.113.0/24", "224.0.0.0/4", "240.0.0.0/4",
)

// Fail closed outside currently allocated global-unicast 2000::/3. This
// excludes unspecified, loopback, compatible-v4, NAT64, discard-only, local,
// link/site-local and multicast, and also the SRv6 SID block 5f00::/16
// (RFC 9602, not globally reachable), which lies outside 2000::/3 and so
// needs no entry below. Inside 2000::/3 deny all of the IETF assignments
// 2001::/23 (which include Teredo, benchmarking, ORCHID/ORCHIDv2, drone
// remote IDs and the globally reachable AMT, AS112 and PCP/TURN anycast
// assignments), documentation (both allocations), and 6to4 transition
// addresses. The AS112 delegation block 2620:4f:8000::/48 is globally
// reachable and outside any denied block, so it stays allowed.
var globalV6 = netip.MustParsePrefix("2000::/3")
var blockedV6 = mustPrefixes("2001::/23", "2001:db8::/32", "2002::/16", "3fff::/20")

func mustPrefixes(cidrs ...string) []netip.Prefix {
	result := make([]netip.Prefix, 0, len(cidrs))
	for _, cidr := range cidrs {
		result = append(result, netip.MustParsePrefix(cidr))
	}
	return result
}

func containsAny(prefixes []netip.Prefix, ip netip.Addr) bool {
	for _, prefix := range prefixes {
		if prefix.Contains(ip) {
			return true
		}
	}
	return false
}

func isPublicIP(ip net.IP) bool {
	addr, ok := netip.AddrFromSlice(ip)
	if !ok {
		return false
	}
	addr = addr.Unmap() // Mapped IPv6 MUST use the IPv4 policy.
	if addr.Is4() {
		return !containsAny(blockedV4, addr)
	}
	return globalV6.Contains(addr) && !containsAny(blockedV6, addr)
}

// The only ranges a website's own LAN address may come from: RFC 1918 and
// IPv6 ULA. Loopback (this computer), link-local and CGNAT never qualify.
var lanV4 = mustPrefixes("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16")
var lanV6 = netip.MustParsePrefix("fc00::/7")

// parseLANHost validates open's optional lanHost: the private IP literal that
// the extension derived from the website's own origin. Only a bare IP literal
// is accepted (netip.ParseAddr is strict: no brackets, port, leading zeros or
// names); a zone or an IPv4-mapped form fails rather than being normalized,
// so the exception can never name anything but that one address.
func parseLANHost(s string) (netip.Addr, bool) {
	if len(s) > 64 {
		return netip.Addr{}, false
	}
	addr, err := netip.ParseAddr(s)
	if err != nil || addr.Zone() != "" || addr.Is4In6() {
		return netip.Addr{}, false
	}
	if addr.Is4() && containsAny(lanV4, addr) || addr.Is6() && lanV6.Contains(addr) {
		return addr, true
	}
	return netip.Addr{}, false
}

// normalizeHost accepts an IP literal (IPv6 optionally bracketed) or an ASCII
// DNS name. It never accepts a zone, URL, port suffix, userinfo or whitespace.
func normalizeHost(host string) string {
	if strings.HasPrefix(host, "[") || strings.HasSuffix(host, "]") {
		if !strings.HasPrefix(host, "[") || !strings.HasSuffix(host, "]") {
			return ""
		}
		ip := net.ParseIP(host[1 : len(host)-1])
		if ip == nil || ip.To4() != nil {
			return ""
		}
		return ip.String()
	}
	if ip := net.ParseIP(host); ip != nil {
		return ip.String()
	}
	name := strings.TrimSuffix(strings.ToLower(host), ".")
	if name == "" || len(name) > 253 {
		return ""
	}
	for _, label := range strings.Split(name, ".") {
		if label == "" || len(label) > 63 || label[0] == '-' || label[len(label)-1] == '-' {
			return ""
		}
		for _, c := range label {
			if !(c >= 'a' && c <= 'z' || c >= '0' && c <= '9' || c == '-') {
				return ""
			}
		}
	}
	return name
}
