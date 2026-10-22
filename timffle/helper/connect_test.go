package main

import (
	"context"
	"errors"
	"io"
	"net"
	"os"
	"reflect"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"testing"
	"time"
)

// refusedError is what the standard dialer returns for a refused connection:
// the errno wrapped in os.SyscallError and net.OpError.
func refusedError() error {
	return &net.OpError{Op: "dial", Net: "tcp", Err: &os.SyscallError{Syscall: "connect", Err: syscall.ECONNREFUSED}}
}

func TestFirstCandidateTimeoutFallsBackAndPins(t *testing.T) {
	var lookups atomic.Int32
	// An abandoned attempt's goroutine has no happens-before edge to the next one.
	var dialedMu sync.Mutex
	var dialed []string
	peer, server := net.Pipe()
	defer peer.Close()
	defer server.Close()
	opt := options{
		lookup: func(_ context.Context, host string) ([]net.IPAddr, error) {
			if host != "fake.example" {
				t.Errorf("lookup host %q", host)
			}
			lookups.Add(1)
			return []net.IPAddr{{IP: net.ParseIP("8.8.8.8")}, {IP: net.ParseIP("1.1.1.1")}}, nil
		},
		dial: func(ctx context.Context, network, address string) (net.Conn, error) {
			if network != "tcp" {
				t.Errorf("network %q", network)
			}
			dialedMu.Lock()
			dialed = append(dialed, address)
			dialedMu.Unlock()
			if address == "8.8.8.8:443" {
				<-ctx.Done()
				return nil, ctx.Err()
			}
			return peer, nil
		},
	}
	began := time.Now()
	conn, code := openTCP(context.Background(), request{Host: "FAKE.EXAMPLE.", Port: 443, TimeoutMs: 1000}, opt)
	if code != "" || conn != peer {
		t.Fatalf("fallback failed: %v %q", conn, code)
	}
	if elapsed := time.Since(began); elapsed < 400*time.Millisecond || elapsed > 950*time.Millisecond {
		t.Fatalf("fallback budget %v", elapsed)
	}
	dialedMu.Lock()
	defer dialedMu.Unlock()
	if lookups.Load() != 1 || !reflect.DeepEqual(dialed, []string{"8.8.8.8:443", "1.1.1.1:443"}) {
		t.Fatalf("DNS was not pinned: %v", dialed)
	}
}

func TestAllDNSAnswersValidatedBeforeCandidateCap(t *testing.T) {
	// The website's own LAN address excuses only itself, never another answer,
	// nor itself with a zone.
	lan := "192.168.0.163"
	for _, lanHost := range []*string{nil, &lan} {
		for _, bad := range []net.IPAddr{
			{IP: net.ParseIP("192.168.0.1")}, {IP: net.ParseIP("::ffff:10.0.0.1")},
			{IP: net.ParseIP("2606:4700::1111"), Zone: "eth0"}, {IP: nil},
			{IP: net.ParseIP("127.0.0.1")}, {IP: net.ParseIP(lan), Zone: "eth0"},
		} {
			opt := options{
				lookup: func(context.Context, string) ([]net.IPAddr, error) {
					var addrs []net.IPAddr
					if lanHost != nil {
						addrs = append(addrs, net.IPAddr{IP: net.ParseIP(lan)})
					}
					for i := 0; i < maxDialCandidates+5; i++ {
						addrs = append(addrs, net.IPAddr{IP: net.ParseIP("8.8.8." + strconv.Itoa(i+1))})
					}
					return append(addrs, bad), nil
				},
				dial: func(context.Context, string, string) (net.Conn, error) {
					t.Error("dialed mixed private DNS")
					return nil, io.EOF
				},
			}
			if conn, code := openTCP(context.Background(), request{Host: "mixed.example", Port: 80, LanHost: lanHost}, opt); conn != nil || code != "blocked" {
				t.Fatalf("mixed DNS accepted (lanHost %v): %v %q", lanHost != nil, conn, code)
			}
		}
	}
}

// answer turns a resolver answer into the form the system resolver returns:
// 4 bytes for IPv4, 16 for IPv6, so an IPv4-mapped answer stays mapped.
func answer(s string) net.IPAddr {
	ip := net.ParseIP(s)
	if !strings.Contains(s, ":") {
		ip = ip.To4()
	}
	return net.IPAddr{IP: ip}
}

// openLAN runs openTCP with the production policy, a fake resolver and a
// dialer that records every pinned target and refuses it. "refused" therefore
// means the policy let every answer through; "blocked" means it stopped them.
func openLAN(t *testing.T, host string, lanHost *string, answers ...string) ([]string, string) {
	t.Helper()
	var mu sync.Mutex
	var dialed []string
	opt := options{
		lookup: func(context.Context, string) ([]net.IPAddr, error) {
			var addrs []net.IPAddr
			for _, a := range answers {
				addrs = append(addrs, answer(a))
			}
			return addrs, nil
		},
		dial: func(_ context.Context, _, address string) (net.Conn, error) {
			mu.Lock()
			defer mu.Unlock()
			dialed = append(dialed, address)
			return nil, refusedError()
		},
	}
	conn, code := openTCP(context.Background(), request{Host: host, Port: 1863, TimeoutMs: 1000, LanHost: lanHost}, opt)
	if conn != nil {
		t.Fatalf("refusing dialer connected: %v", conn)
	}
	mu.Lock()
	defer mu.Unlock()
	return dialed, code
}

func TestLANHostAllowsExactlyTheWebsitesOwnAddress(t *testing.T) {
	const v4, v6 = "192.168.0.163", "fd12:3456:789a::163"
	for _, tt := range []struct {
		name, host, lan string
		answers         []string
		dialed          []string // nil: blocked before any dial
	}{
		{"own IPv4", v4, v4, nil, []string{"192.168.0.163:1863"}},
		{"own 10/8", "10.1.2.3", "10.1.2.3", nil, []string{"10.1.2.3:1863"}},
		{"own 172.16/12", "172.31.0.9", "172.31.0.9", nil, []string{"172.31.0.9:1863"}},
		{"own IPv6 ULA", "[" + v6 + "]", v6, nil, []string{"[" + v6 + "]:1863"}},
		{"own IPv6 ULA, other spelling", "FD12:3456:789A:0::163", v6, nil, []string{"[" + v6 + "]:1863"}},
		{"own IPv4 as v4-mapped literal", "::ffff:" + v4, v4, nil, []string{"192.168.0.163:1863"}},
		{"public still allowed", "8.8.8.8", v4, nil, []string{"8.8.8.8:1863"}},
		{"public IPv6 still allowed", "2606:4700::1111", v6, nil, []string{"[2606:4700::1111]:1863"}},
		{"name: own address", "game.example", v4, []string{v4}, []string{"192.168.0.163:1863"}},
		{"name: own and public", "game.example", v4, []string{v4, "8.8.8.8"}, []string{"192.168.0.163:1863", "8.8.8.8:1863"}},
		{"name: v4-mapped own address", "game.example", v4, []string{"::ffff:" + v4}, []string{"192.168.0.163:1863"}},
		{"name: own ULA and public IPv6", "game.example", v6, []string{"2606:4700::1111", v6}, []string{"[2606:4700::1111]:1863", "[" + v6 + "]:1863"}},
		{"another LAN address", "192.168.0.164", v4, nil, nil},
		{"another private range", "10.0.0.1", v4, nil, nil},
		{"another ULA", "fd12:3456:789a::164", v6, nil, nil},
		{"own IPv4, IPv6 ULA asked", v6, v4, nil, nil},
		{"own ULA, IPv4 asked", v4, v6, nil, nil},
		{"loopback", "127.0.0.1", v4, nil, nil},
		{"IPv6 loopback", "::1", v6, nil, nil},
		{"localhost", "localhost", v4, []string{"127.0.0.1", "::1"}, nil},
		{"link-local", "169.254.1.1", v4, nil, nil},
		{"IPv6 link-local", "fe80::1", v6, nil, nil},
		{"CGNAT", "100.64.0.1", v4, nil, nil},
		{"unspecified", "0.0.0.0", v4, nil, nil},
		{"broadcast", "255.255.255.255", v4, nil, nil},
		{"name: own and another LAN address", "game.example", v4, []string{v4, "192.168.0.1"}, nil},
		{"name: public, own, then loopback", "game.example", v4, []string{"8.8.8.8", v4, "127.0.0.1"}, nil},
		{"name: rebound to another LAN address", "rebind.example", v4, []string{"192.168.0.1"}, nil},
		{"name: own ULA and another ULA", "game.example", v6, []string{v6, "fd12:3456:789a::1"}, nil},
	} {
		t.Run(tt.name, func(t *testing.T) {
			lan := tt.lan
			dialed, code := openLAN(t, tt.host, &lan, tt.answers...)
			if tt.dialed == nil {
				if code != "blocked" || len(dialed) != 0 {
					t.Fatalf("not blocked: %q dialed %v", code, dialed)
				}
				return
			}
			if code != "refused" || !reflect.DeepEqual(dialed, tt.dialed) {
				t.Fatalf("got %q dialed %v, want %v", code, dialed, tt.dialed)
			}
		})
	}
}

// Without lanHost nothing changed: a private destination is still blocked,
// even the one address a LAN website would have been allowed.
func TestNoLANHostNoException(t *testing.T) {
	for _, host := range []string{"192.168.0.163", "fd12:3456:789a::163", "game.example"} {
		dialed, code := openLAN(t, host, nil, "192.168.0.163")
		if code != "blocked" || len(dialed) != 0 {
			t.Errorf("%s without lanHost: %q dialed %v", host, code, dialed)
		}
	}
}

// Every form 2.1 of the design rejects. The open fails as invalid even for a
// public destination, and nothing is resolved or dialed, in either build.
var invalidLANHosts = []string{
	"", " ", "\t", " 192.168.0.1", "192.168.0.1 ", "192.168.0.1\n", "192.168.0.1\x00",
	"127.0.0.1", "127.1.2.3", "::1", // loopback: this computer
	"169.254.1.1", "fe80::1", "fe80::1%eth0", // link-local
	"100.64.0.1", "100.127.255.254", // CGNAT
	"224.0.0.1", "239.255.255.250", "ff02::1", "ff05::1:3", // multicast
	"8.8.8.8", "1.1.1.1", "2606:4700::1111", "192.0.2.1", // public, documentation
	"0.0.0.0", "::", "255.255.255.255", "198.18.0.1", "fec0::1", "64:ff9b::c0a8:1", "::192.168.0.1",
	"11.0.0.1", "172.15.255.255", "172.32.0.1", "192.167.255.255", "192.169.0.1", "fbff::1", "fe00::1", // just outside
	"::ffff:192.168.0.1", "::ffff:c0a8:1", "::ffff:10.0.0.1", "0:0:0:0:0:ffff:192.168.0.1", // IPv4-mapped
	"fd00::1%eth0", "fd00::1%1", "192.168.0.1%eth0", // zone
	"[fd00::1]", "[192.168.0.1]", "[fd00::1", "fd00::1]", // brackets
	"192.168.0.1:80", "[fd00::1]:80", "fd00::1:80:", // port
	"192.168.000.001", "192.168.0.01", "010.0.0.1", // leading zeros
	"0xc0a80001", "3232235521", "0300.0250.0.1", "0xc0.0xa8.0.1", "192.168.1", "192.168.0.1.", "192.168..1", // other numeric forms
	"localhost", "lan.example", "192.168.0.1.nip.io", "fd00--1.ipv6.example", // names
	"http://192.168.0.1/", "http://[fd00::1]/", "//192.168.0.1", "user@192.168.0.1", "192.168.0.1/24", // URLs, userinfo, CIDR
	"１９２.１６８.０.１", "192.168.0.1‎", // fullwidth digits, invisible mark
	"fd00::1%" + strings.Repeat("a", 64), strings.Repeat("0", 65), // longer than 64
}

func TestInvalidLANHostFailsClosed(t *testing.T) {
	for _, allowPrivate := range []bool{false, true} {
		opt := options{
			allowPrivate: allowPrivate,
			lookup: func(context.Context, string) ([]net.IPAddr, error) {
				t.Error("resolved with an invalid lanHost")
				return nil, io.EOF
			},
			dial: func(context.Context, string, string) (net.Conn, error) {
				t.Error("dialed with an invalid lanHost")
				return nil, io.EOF
			},
		}
		for _, value := range invalidLANHosts {
			if _, ok := parseLANHost(value); ok {
				t.Errorf("parseLANHost accepted %q", value)
			}
			for _, host := range []string{"8.8.8.8", "game.example"} {
				value := value
				if conn, code := openTCP(context.Background(), request{Host: host, Port: 80, LanHost: &value}, opt); conn != nil || code != "invalid" {
					t.Errorf("lanHost %q (host %s, allowPrivate %v): %v %q", value, host, allowPrivate, conn, code)
				}
			}
		}
	}
}

func TestParseLANHost(t *testing.T) {
	for value, want := range map[string]string{
		"10.0.0.0": "10.0.0.0", "10.255.255.255": "10.255.255.255", "172.16.0.1": "172.16.0.1", "172.31.255.255": "172.31.255.255",
		"192.168.0.0": "192.168.0.0", "192.168.0.163": "192.168.0.163", "192.168.255.255": "192.168.255.255",
		"fc00::": "fc00::", "fd12:3456:789a::163": "fd12:3456:789a::163", "FD12:3456:789A::163": "fd12:3456:789a::163",
		"fdff:ffff:ffff:ffff:ffff:ffff:ffff:ffff": "fdff:ffff:ffff:ffff:ffff:ffff:ffff:ffff", "fd00::192.168.0.1": "fd00::c0a8:1",
	} {
		got, ok := parseLANHost(value)
		if !ok || got.String() != want || got.Zone() != "" || got.Is4In6() {
			t.Errorf("parseLANHost(%q) = %v %v, want %s", value, got, ok, want)
		}
	}
}

func TestCandidateLimitAndDeduplication(t *testing.T) {
	var count atomic.Int32
	opt := options{
		lookup: func(context.Context, string) ([]net.IPAddr, error) {
			var addrs []net.IPAddr
			for i := 0; i < 40; i++ {
				addrs = append(addrs, net.IPAddr{IP: net.ParseIP("8.8.8." + strconv.Itoa(i+1))})
			}
			addrs = append([]net.IPAddr{addrs[0]}, addrs...)
			return addrs, nil
		},
		dial: func(context.Context, string, string) (net.Conn, error) {
			count.Add(1)
			return nil, refusedError()
		},
	}
	_, code := openTCP(context.Background(), request{Host: "many.example", Port: 80}, opt)
	if code != "refused" || count.Load() != maxDialCandidates {
		t.Fatalf("candidate cap count=%d code=%q", count.Load(), code)
	}
}

func TestFailedConnectionsNeverOpen(t *testing.T) {
	tests := []struct {
		name, host, code string
		opt              options
	}{
		{"dns", "fake.example", "dns", options{lookup: func(context.Context, string) ([]net.IPAddr, error) { return nil, errors.New("fake lookup failure") }}},
		{"empty", "fake.example", "dns", options{lookup: func(context.Context, string) ([]net.IPAddr, error) { return nil, nil }}},
		{"blocked", "127.0.0.1", "blocked", options{}},
		{"refused", "8.8.8.8", "refused", options{dial: func(context.Context, string, string) (net.Conn, error) { return nil, refusedError() }}},
		{"unreachable", "8.8.8.8", "unreachable", options{dial: func(context.Context, string, string) (net.Conn, error) { return nil, errors.New("unreachable") }}},
		// The text no longer decides: only the errno does.
		{"refused-text", "8.8.8.8", "unreachable", options{dial: func(context.Context, string, string) (net.Conn, error) { return nil, errors.New("connection refused") }}},
		{"reset", "8.8.8.8", "unreachable", options{dial: func(context.Context, string, string) (net.Conn, error) {
			return nil, &net.OpError{Op: "dial", Err: &os.SyscallError{Syscall: "connect", Err: syscall.ECONNRESET}}
		}}},
		{"nil-success", "8.8.8.8", "unreachable", options{dial: func(context.Context, string, string) (net.Conn, error) { return nil, nil }}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			c := start(t, tt.opt)
			c.hello()
			c.send(request{Type: "open", Host: tt.host, Port: 80})
			c.terminal(tt.code)
		})
	}
}

// A port nobody listens on: the kernel refuses at once, and the production
// dialer's error must map to "refused" on this platform.
func TestRealRefusedConnection(t *testing.T) {
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	port := l.Addr().(*net.TCPAddr).Port
	l.Close()
	c := start(t, local())
	c.hello()
	c.send(request{Type: "open", Host: "127.0.0.1", Port: port, TimeoutMs: 5000})
	c.terminal("refused")
}

func TestTotalTimeoutIncludesDNS(t *testing.T) {
	opt := options{
		lookup: func(ctx context.Context, _ string) ([]net.IPAddr, error) { <-ctx.Done(); return nil, ctx.Err() },
		dial: func(context.Context, string, string) (net.Conn, error) {
			t.Error("dialed after DNS timeout")
			return nil, io.EOF
		},
	}
	c := start(t, opt)
	c.hello()
	began := time.Now()
	c.send(request{Type: "open", Host: "slow.example", Port: 80, TimeoutMs: 1000})
	c.terminal("timeout")
	if elapsed := time.Since(began); elapsed < 900*time.Millisecond || elapsed > 1800*time.Millisecond {
		t.Fatalf("timeout not bounded: %v", elapsed)
	}
}

func TestLateDialSuccessClosedAfterCancellation(t *testing.T) {
	entered, release, finished := make(chan struct{}), make(chan struct{}), make(chan struct{})
	a, b := net.Pipe()
	defer b.Close()
	conn := &closeSignalConn{Conn: a, closed: make(chan struct{})}
	ctx, cancel := context.WithCancel(context.Background())
	go func() {
		c, code := openTCP(ctx, request{Host: "8.8.8.8", Port: 80}, options{dial: func(context.Context, string, string) (net.Conn, error) { close(entered); <-release; return conn, nil }})
		if c != nil || code != "timeout" {
			t.Errorf("late success leaked: %v %q", c, code)
		}
		close(finished)
	}()
	signal(t, entered)
	cancel()
	signal(t, finished)
	close(release)
	signal(t, conn.closed)
}

type closeSignalConn struct {
	net.Conn
	closed chan struct{}
	count  atomic.Int32
}

func (c *closeSignalConn) Close() error {
	if c.count.Add(1) == 1 {
		close(c.closed)
	}
	return c.Conn.Close()
}

func TestMappedIPv6PinnedAsIPv4(t *testing.T) {
	var dialed string
	opt := options{dial: func(_ context.Context, _, addr string) (net.Conn, error) { dialed = addr; return nil, io.EOF }}
	_, code := openTCP(context.Background(), request{Host: "::ffff:8.8.8.8", Port: 80}, opt)
	if dialed != "8.8.8.8:80" || code != "unreachable" {
		t.Fatalf("mapped address %q %q", dialed, code)
	}
}

func TestTimeoutBoundsAndOverflow(t *testing.T) {
	for ms, want := range map[int64]time.Duration{0: 20 * time.Second, 1: time.Second, 1000: time.Second, 5000: 5 * time.Second, 120000: 120 * time.Second, 9223372036854775807: 120 * time.Second} {
		if got := connectionTimeout(ms); got != want {
			t.Errorf("timeout(%d)=%v want %v", ms, got, want)
		}
	}
	if _, code := openTCP(context.Background(), request{Host: "8.8.8.8", Port: 80, TimeoutMs: -1}, options{}); code != "invalid" {
		t.Fatal("negative timeout accepted")
	}
}

func TestIsPublicIP(t *testing.T) {
	good := []string{
		"1.1.1.1", "8.8.8.8", "9.9.9.9", "192.0.1.1", "192.88.100.1", "100.128.0.1", "223.255.255.255", "2606:4700::1111", "2001:4860:4860::8888", "2001:200::1", "3ffe::1", "::ffff:8.8.8.8",
		// Globally reachable special-purpose blocks outside any denied block
		// (AS112 and AMT) are ordinary public addresses to this policy.
		"192.31.196.1", "192.52.193.1", "192.175.48.1", "2620:4f:8000::1",
		// Neighbours of denied blocks.
		"192.0.1.255", "192.0.3.0", "2001:200::", "3ffe:ffff::1", "3fff:1000::1", "2003::1",
	}
	bad := []string{
		"0.1.2.3", "10.0.0.1", "100.64.0.1", "100.127.255.255", "127.1.2.3", "169.254.1.1", "172.16.1.1", "172.31.255.255",
		"192.0.0.9", "192.0.0.10", "192.0.2.1", "192.88.99.1", "192.168.1.1", "198.18.0.1", "198.19.255.255", "198.51.100.1", "203.0.113.1", "224.0.0.1", "240.0.0.1", "255.255.255.255",
		"::", "::1", "::8.8.8.8", "::ffff:10.0.0.1", "::ffff:127.0.0.1", "64:ff9b::808:808", "64:ff9b:1::1", "100::1", "100:0:0:1::1",
		"2001::1", "2001:2::1", "2001:3::1", "2001:4:112::1", "2001:10::1", "2001:20::1", "2001:30::1", "2001:1ff::1", "2001:db8::1", "2002::1", "3fff::1", "3fff:fff:ffff::1", "4000::1", "fc00::1", "fe80::1", "fec0::1", "ff02::1",
		// Globally reachable anycast assignments inside denied blocks: PCP and
		// TURN (IPv4 and IPv6), AMT and AS112 in 2001::/23.
		"192.0.0.0", "192.0.0.255", "2001:1::1", "2001:1::2", "2001:3:ffff::1", "2001:4:112:ffff::1", "2001:1ff:ffff::1",
		// SRv6 SIDs (RFC 9602): the whole of 5f00::/16, which is outside 2000::/3.
		"5f00::", "5f00::1", "5f00:ffff:ffff:ffff:ffff:ffff:ffff:ffff", "5eff::1", "5f01::1", "5fff::1",
	}
	for _, ip := range good {
		if !isPublicIP(net.ParseIP(ip)) {
			t.Errorf("public IP blocked: %s", ip)
		}
	}
	for _, ip := range bad {
		if isPublicIP(net.ParseIP(ip)) {
			t.Errorf("special IP allowed: %s", ip)
		}
	}
	if isPublicIP(nil) || isPublicIP(net.IP{1, 2, 3}) {
		t.Fatal("invalid IP accepted")
	}
}

func TestNormalizeHostAndInvalidOpen(t *testing.T) {
	for value, want := range map[string]string{"LOCALHOST.": "localhost", "Example.COM.": "example.com", "[2606:4700::1111]": "2606:4700::1111", "[::1]": "::1", "::ffff:8.8.8.8": "8.8.8.8"} {
		if got := normalizeHost(value); got != want {
			t.Errorf("normalize(%q)=%q want %q", value, got, want)
		}
	}
	for _, host := range []string{"", "a b", "https://example.com", "user@example.com", "example.com:80", "bad_label.example", "fe80::1%eth0", "[::1", "[example.com]", "[8.8.8.8]", "a..b", "-a.example", "a-.example", "é.example"} {
		if normalizeHost(host) != "" {
			t.Errorf("invalid host accepted: %q", host)
		}
	}
}
