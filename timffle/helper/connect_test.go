package main

import (
	"context"
	"errors"
	"io"
	"net"
	"reflect"
	"strconv"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

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
	for _, bad := range []net.IPAddr{
		{IP: net.ParseIP("192.168.0.1")}, {IP: net.ParseIP("::ffff:10.0.0.1")},
		{IP: net.ParseIP("2606:4700::1111"), Zone: "eth0"}, {IP: nil},
	} {
		opt := options{
			lookup: func(context.Context, string) ([]net.IPAddr, error) {
				var addrs []net.IPAddr
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
		if conn, code := openTCP(context.Background(), request{Host: "mixed.example", Port: 80}, opt); conn != nil || code != "blocked" {
			t.Fatalf("mixed DNS accepted: %v %q", conn, code)
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
			return nil, errors.New("refused")
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
		{"refused", "8.8.8.8", "refused", options{dial: func(context.Context, string, string) (net.Conn, error) { return nil, errors.New("connection refused") }}},
		{"unreachable", "8.8.8.8", "unreachable", options{dial: func(context.Context, string, string) (net.Conn, error) { return nil, errors.New("unreachable") }}},
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
	good := []string{"1.1.1.1", "8.8.8.8", "9.9.9.9", "192.0.1.1", "192.88.100.1", "100.128.0.1", "223.255.255.255", "2606:4700::1111", "2001:4860:4860::8888", "2001:200::1", "3ffe::1", "::ffff:8.8.8.8"}
	bad := []string{
		"0.1.2.3", "10.0.0.1", "100.64.0.1", "100.127.255.255", "127.1.2.3", "169.254.1.1", "172.16.1.1", "172.31.255.255",
		"192.0.0.9", "192.0.0.10", "192.0.2.1", "192.88.99.1", "192.168.1.1", "198.18.0.1", "198.19.255.255", "198.51.100.1", "203.0.113.1", "224.0.0.1", "240.0.0.1", "255.255.255.255",
		"::", "::1", "::8.8.8.8", "::ffff:10.0.0.1", "::ffff:127.0.0.1", "64:ff9b::808:808", "64:ff9b:1::1", "100::1", "100:0:0:1::1",
		"2001::1", "2001:2::1", "2001:3::1", "2001:4:112::1", "2001:10::1", "2001:20::1", "2001:30::1", "2001:1ff::1", "2001:db8::1", "2002::1", "3fff::1", "3fff:fff:ffff::1", "4000::1", "5f00::1", "fc00::1", "fe80::1", "fec0::1", "ff02::1",
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
