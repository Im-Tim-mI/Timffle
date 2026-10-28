package main

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/netip"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

type client struct {
	t        *testing.T
	in       *io.PipeWriter
	out      *io.PipeReader
	messages chan map[string]any
	done     chan struct{}
	err      error // synchronized by done
}

func start(t *testing.T, opt options) *client {
	t.Helper()
	return startHost(t, func(in io.Reader, out io.Writer) error { return serve(in, out, opt) })
}

// startHost drives any entry point that serves one native messaging session.
func startHost(t *testing.T, host func(io.Reader, io.Writer) error) *client {
	t.Helper()
	inR, inW := io.Pipe()
	outR, outW := io.Pipe()
	c := &client{t: t, in: inW, out: outR, messages: make(chan map[string]any, 32), done: make(chan struct{})}
	go func() {
		defer close(c.messages)
		for {
			var header [4]byte
			if _, err := io.ReadFull(outR, header[:]); err != nil {
				return
			}
			n := binary.LittleEndian.Uint32(header[:])
			if n == 0 || n > maxInbound {
				return
			}
			b := make([]byte, n)
			if _, err := io.ReadFull(outR, b); err != nil {
				return
			}
			var m map[string]any
			if json.Unmarshal(b, &m) != nil {
				return
			}
			c.messages <- m
		}
	}()
	go func() { c.err = host(inR, outW); close(c.done) }()
	t.Cleanup(func() { _ = inW.Close(); _ = outR.Close(); c.wait() })
	return c
}

func encode(v any) []byte {
	b, err := json.Marshal(v)
	if err != nil {
		panic(err)
	}
	return rawFrame(b)
}
func rawFrame(b []byte) []byte {
	frame := make([]byte, 4+len(b))
	binary.LittleEndian.PutUint32(frame, uint32(len(b)))
	copy(frame[4:], b)
	return frame
}
func (c *client) raw(b []byte) {
	c.t.Helper()
	done := make(chan error, 1)
	go func() { _, err := c.in.Write(b); done <- err }()
	select {
	case err := <-done:
		if err != nil {
			c.t.Fatalf("input write: %v", err)
		}
	case <-time.After(2 * time.Second):
		c.t.Fatal("input write blocked")
	}
}
func (c *client) send(v any) { c.t.Helper(); c.raw(encode(v)) }
func (c *client) recv() map[string]any {
	c.t.Helper()
	select {
	case m, ok := <-c.messages:
		if !ok {
			c.t.Fatal("helper output closed")
		}
		return m
	case <-time.After(3 * time.Second):
		c.t.Fatal("helper output timed out")
		return nil
	}
}
func (c *client) expect(typ string) map[string]any {
	c.t.Helper()
	m := c.recv()
	if m["type"] != typ {
		c.t.Fatalf("got %v, want %q", m, typ)
	}
	return m
}
func (c *client) expectError(code string) {
	c.t.Helper()
	if m := c.expect("error"); m["code"] != code {
		c.t.Fatalf("got %v, want error %q", m, code)
	}
}
func (c *client) wait() error {
	c.t.Helper()
	select {
	case <-c.done:
		return c.err
	case <-time.After(2 * time.Second):
		c.t.Fatal("helper did not stop")
		return nil
	}
}
func (c *client) noMessage() {
	c.t.Helper()
	select {
	case m := <-c.messages:
		c.t.Fatalf("unexpected message: %v", m)
	case <-time.After(40 * time.Millisecond):
	}
}
func (c *client) hello() {
	c.t.Helper()
	c.send(request{Type: "hello"})
	m := c.expect("hello")
	if m["version"] != "1.4.1" || m["protocol"] != float64(2) {
		c.t.Fatalf("bad hello: %v", m)
	}
}
func (c *client) open(host string, port int) {
	c.t.Helper()
	c.hello()
	c.send(request{Type: "open", Host: host, Port: port})
	c.expect("opened")
}
func (c *client) terminal(code string) {
	c.t.Helper()
	if code != "" {
		c.expectError(code)
	}
	c.expect("closed")
	c.wait()
	for m := range c.messages {
		c.t.Errorf("duplicate/unexpected terminal output: %v", m)
	}
}
func signal(t *testing.T, ch <-chan struct{}) {
	t.Helper()
	select {
	case <-ch:
	case <-time.After(time.Second):
		t.Fatal("signal timed out")
	}
}

func local() options { return options{allowPrivate: true} }
func pipeOptions(t *testing.T) (options, net.Conn) {
	t.Helper()
	a, b := net.Pipe()
	t.Cleanup(func() { a.Close(); b.Close() })
	return options{allowPrivate: true, dial: func(context.Context, string, string) (net.Conn, error) { return a, nil }}, b
}

func TestHelloReportsVersion(t *testing.T) { start(t, options{}).hello() }
func TestOpenRequiresHello(t *testing.T) {
	var dialed atomic.Bool
	c := start(t, options{dial: func(context.Context, string, string) (net.Conn, error) { dialed.Store(true); return nil, io.EOF }})
	c.send(request{Type: "open", Host: "8.8.8.8", Port: 80})
	c.terminal("invalid")
	if dialed.Load() {
		t.Fatal("dialed before hello")
	}
}

func TestBinaryRoundTripAndRemoteClose(t *testing.T) {
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer l.Close()
	payload := bytes.Repeat([]byte{0, 1, 255, 42, 128, 10}, 7000)
	serverDone := make(chan error, 1)
	go func() {
		conn, e := l.Accept()
		if e != nil {
			serverDone <- e
			return
		}
		defer conn.Close()
		b := make([]byte, len(payload))
		if _, e = io.ReadFull(conn, b); e == nil && !bytes.Equal(b, payload) {
			e = errors.New("payload differs")
		}
		if e == nil {
			e = writeAll(conn, b)
		}
		serverDone <- e
	}()
	c := start(t, local())
	c.open("127.0.0.1", l.Addr().(*net.TCPAddr).Port)
	c.send(request{Type: "send", Data: base64.StdEncoding.EncodeToString(payload)})
	var got []byte
	sent := false
	for len(got) < len(payload) || !sent {
		m := c.recv()
		switch m["type"] {
		case "sent":
			if sent {
				t.Fatal("duplicate sent")
			}
			sent = true
		case "data":
			b, e := base64.StdEncoding.DecodeString(m["data"].(string))
			if e != nil || len(b) > readChunk {
				t.Fatal("bad data frame")
			}
			got = append(got, b...)
			c.send(request{Type: "ack"})
		default:
			t.Fatalf("unexpected message %v", m)
		}
	}
	if !bytes.Equal(got, payload) {
		t.Fatal("echo differs")
	}
	c.terminal("")
	if err := <-serverDone; err != nil {
		t.Fatal(err)
	}
}

func TestCancellationDuringLookupAndDial(t *testing.T) {
	for _, stage := range []string{"dns", "dial"} {
		for _, method := range []string{"eof", "close"} {
			t.Run(stage+"/"+method, func(t *testing.T) {
				entered, cancelled := make(chan struct{}), make(chan struct{})
				opt := options{}
				if stage == "dns" {
					opt.lookup = func(ctx context.Context, _ string) ([]net.IPAddr, error) {
						close(entered)
						<-ctx.Done()
						close(cancelled)
						return nil, ctx.Err()
					}
				} else {
					opt.lookup = func(context.Context, string) ([]net.IPAddr, error) {
						return []net.IPAddr{{IP: net.ParseIP("8.8.8.8")}}, nil
					}
					opt.dial = func(ctx context.Context, _, _ string) (net.Conn, error) {
						close(entered)
						<-ctx.Done()
						close(cancelled)
						return nil, ctx.Err()
					}
				}
				c := start(t, opt)
				c.hello()
				c.send(request{Type: "open", Host: "fake.example", Port: 80})
				signal(t, entered)
				if method == "eof" {
					c.in.Close()
					c.wait()
				} else {
					c.send(request{Type: "close"})
					c.terminal("")
				}
				signal(t, cancelled)
				for m := range c.messages {
					if m["type"] == "opened" {
						t.Fatal("opened after cancellation")
					}
				}
			})
		}
	}
}

func TestCancellationDuringBlockedWrite(t *testing.T) {
	for _, method := range []string{"eof", "close"} {
		t.Run(method, func(t *testing.T) {
			opt, peer := pipeOptions(t)
			began := make(chan struct{})
			original := opt.dial
			opt.dial = func(ctx context.Context, n, a string) (net.Conn, error) {
				conn, e := original(ctx, n, a)
				return &writeSignalConn{Conn: conn, began: began}, e
			}
			c := start(t, opt)
			c.open("127.0.0.1", 80)
			c.send(request{Type: "send", Data: "AA=="})
			signal(t, began)
			if method == "eof" {
				c.in.Close()
				c.wait()
			} else {
				c.send(request{Type: "close"})
				c.terminal("")
			}
			peer.SetReadDeadline(time.Now().Add(time.Second))
			if _, err := peer.Read(make([]byte, 1)); !errors.Is(err, io.EOF) {
				t.Fatalf("TCP not closed: %v", err)
			}
		})
	}
}

type writeSignalConn struct {
	net.Conn
	began chan struct{}
	once  sync.Once
}

func (c *writeSignalConn) Write(p []byte) (int, error) {
	c.once.Do(func() { close(c.began) })
	return c.Conn.Write(p)
}

func TestSentOnlyAfterFullWrite(t *testing.T) {
	opt, peer := pipeOptions(t)
	c := start(t, opt)
	c.open("127.0.0.1", 80)
	payload := bytes.Repeat([]byte{42}, maxSend)
	c.send(request{Type: "send", Data: base64.StdEncoding.EncodeToString(payload)})
	c.noMessage()
	first := make([]byte, 1)
	if _, err := io.ReadFull(peer, first); err != nil {
		t.Fatal(err)
	}
	c.noMessage()
	rest := make([]byte, len(payload)-1)
	if _, err := io.ReadFull(peer, rest); err != nil {
		t.Fatal(err)
	}
	c.expect("sent")
	if !bytes.Equal(append(first, rest...), payload) {
		t.Fatal("short write lost bytes")
	}
	c.send(request{Type: "send", Data: ""})
	c.expect("sent")
}

func TestOneSendInFlightAndNoQueuedBacklog(t *testing.T) {
	opt, _ := pipeOptions(t)
	c := start(t, opt)
	c.open("127.0.0.1", 80)
	c.send(request{Type: "send", Data: "AA=="})
	c.send(request{Type: "send", Data: "AQ=="})
	c.terminal("invalid")
}

func TestReadWaitsForAckAndCancellation(t *testing.T) {
	for _, method := range []string{"ack", "eof", "close", "timeout"} {
		t.Run(method, func(t *testing.T) {
			opt, peer := pipeOptions(t)
			if method == "timeout" {
				opt.ackTimeout = 100 * time.Millisecond
			}
			c := start(t, opt)
			c.open("127.0.0.1", 80)
			payload := bytes.Repeat([]byte{55}, readChunk*2)
			writing := make(chan error, 1)
			go func() { writing <- writeAll(peer, payload) }()
			m := c.expect("data")
			b, _ := base64.StdEncoding.DecodeString(m["data"].(string))
			if len(b) != readChunk {
				t.Fatalf("chunk size %d", len(b))
			}
			c.noMessage()
			select {
			case err := <-writing:
				t.Fatalf("read ahead without ack: %v", err)
			default:
			}
			switch method {
			case "ack":
				c.send(request{Type: "ack"})
				c.expect("data")
				c.send(request{Type: "ack"})
				if err := <-writing; err != nil {
					t.Fatal(err)
				}
				peer.Close()
				c.terminal("")
			case "eof":
				c.in.Close()
				c.wait()
				<-writing
			case "close":
				c.send(request{Type: "close"})
				c.terminal("")
				<-writing
			case "timeout":
				c.terminal("timeout")
				<-writing
			}
		})
	}
}

func TestWriteStallIsBounded(t *testing.T) {
	opt, _ := pipeOptions(t)
	opt.writeTimeout = 50 * time.Millisecond
	c := start(t, opt)
	c.open("127.0.0.1", 80)
	c.send(request{Type: "send", Data: "AA=="})
	c.terminal("timeout")
}

func TestInvalidSendsAndRequestsTerminateOnce(t *testing.T) {
	cases := []request{
		{Type: "send", Data: "not base64!"}, {Type: "send", Data: "AA==\n"},
		{Type: "send", Data: "AB=="}, {Type: "send", Data: base64.StdEncoding.EncodeToString(make([]byte, maxSend+1))},
		{Type: "send", Data: base64.StdEncoding.EncodeToString(make([]byte, maxInbound/2))},
		{Type: "unknown"}, {Type: "ack"}, {Type: "hello"},
		{Type: "open", Host: "127.0.0.1", Port: 80},
	}
	for i, req := range cases {
		t.Run(fmt.Sprint(i), func(t *testing.T) {
			opt, _ := pipeOptions(t)
			c := start(t, opt)
			c.open("127.0.0.1", 80)
			c.send(req)
			c.terminal("invalid")
		})
	}
}

func TestBadFraming(t *testing.T) {
	oversized := make([]byte, 4)
	binary.LittleEndian.PutUint32(oversized, maxInbound+1)
	cases := [][]byte{{0, 0, 0, 0}, oversized, {1, 2}, {10, 0, 0, 0, '{'}, rawFrame([]byte("{")), rawFrame([]byte("null")), rawFrame([]byte("[]")), rawFrame([]byte(`{"type":"hello"}{}`)), rawFrame([]byte(`{"type":3}`))}
	for i, b := range cases {
		t.Run(fmt.Sprint(i), func(t *testing.T) {
			c := start(t, options{})
			c.raw(b)
			if i == 2 || i == 3 {
				c.in.Close()
			}
			c.terminal("invalid")
		})
	}
}

func TestInputBacklogBounded(t *testing.T) {
	var b bytes.Buffer
	for i := 0; i < maxRequestBacklog+2; i++ {
		b.Write(encode(request{Type: "hello"}))
	}
	requests, ended := make(chan inputEvent, maxRequestBacklog), make(chan inputEnd, 1)
	abort, stop := make(chan struct{}), make(chan struct{})
	var busy atomic.Bool
	inputLoop(&b, requests, ended, abort, stop, &busy)
	e := <-ended
	if e.code != "invalid" || !errors.Is(e.err, errFlowControl) {
		t.Fatalf("unexpected end: %+v", e)
	}
	if len(requests) != maxRequestBacklog {
		t.Fatal("unbounded/incorrect backlog")
	}
	signal(t, abort)
}

func TestStdoutFailureClosesTCP(t *testing.T) {
	opt, peer := pipeOptions(t)
	c := start(t, opt)
	c.open("127.0.0.1", 80)
	c.out.Close()
	go peer.Write([]byte{1})
	if err := c.wait(); err == nil {
		t.Fatal("stdout failure not returned")
	}
	peer.SetReadDeadline(time.Now().Add(time.Second))
	if _, err := peer.Read(make([]byte, 1)); !errors.Is(err, io.EOF) {
		t.Fatalf("TCP remained open: %v", err)
	}
}

func TestBlockedStdoutTimeoutAndEOF(t *testing.T) {
	for _, method := range []string{"timeout", "eof"} {
		t.Run(method, func(t *testing.T) {
			inR, inW := io.Pipe()
			outR, outW := io.Pipe()
			defer inW.Close()
			defer outR.Close()
			done := make(chan error, 1)
			go func() { done <- serve(inR, outW, options{outputTimeout: 60 * time.Millisecond}) }()
			if _, err := inW.Write(encode(request{Type: "hello"})); err != nil {
				t.Fatal(err)
			}
			if method == "eof" {
				inW.Close()
			}
			select {
			case err := <-done:
				if method == "timeout" && !errors.Is(err, errOutputTimeout) {
					t.Fatalf("unexpected output failure: %v", err)
				}
			case <-time.After(time.Second):
				t.Fatal("blocked stdout held session")
			}
		})
	}
}

type shortWriter struct {
	bytes.Buffer
	max  int
	zero bool
}

func (w *shortWriter) Write(b []byte) (int, error) {
	if w.zero {
		return 0, nil
	}
	return w.Buffer.Write(b[:min(len(b), w.max)])
}
func TestWriteAllShortWrites(t *testing.T) {
	w := &shortWriter{max: 3}
	if err := writeAll(w, []byte("abcdefghij")); err != nil || w.String() != "abcdefghij" {
		t.Fatal("short writes not handled")
	}
	if err := writeAll(&shortWriter{zero: true}, []byte{1}); !errors.Is(err, io.ErrShortWrite) {
		t.Fatal("zero write not rejected")
	}
}

func forbiddenDial(t *testing.T) func(context.Context, string, string) (net.Conn, error) {
	return func(context.Context, string, string) (net.Conn, error) {
		t.Error("dialed")
		return nil, io.EOF
	}
}

// lanOpen is an open frame with a raw lanHost value of any JSON type.
func lanOpen(host string, lanHost any) map[string]any {
	return map[string]any{"type": "open", "host": host, "port": 1863, "lanHost": lanHost}
}

func TestLANHostOpensTheWebsitesOwnAddress(t *testing.T) {
	a, b := net.Pipe()
	t.Cleanup(func() { a.Close(); b.Close() })
	var dialed atomic.Value
	// The production policy: no test-only private permission.
	c := start(t, options{dial: func(_ context.Context, _, address string) (net.Conn, error) { dialed.Store(address); return a, nil }})
	c.hello()
	c.send(lanOpen("192.168.0.163", "192.168.0.163"))
	c.expect("opened")
	if dialed.Load() != "192.168.0.163:1863" {
		t.Fatalf("dialed %v", dialed.Load())
	}
	c.send(request{Type: "close"})
	c.terminal("")
}

func TestLANHostAbsentNullOrOtherAddressBlocks(t *testing.T) {
	for i, frame := range []map[string]any{
		{"type": "open", "host": "192.168.0.163", "port": 1863},
		lanOpen("192.168.0.163", nil),
		lanOpen("192.168.0.164", "192.168.0.163"),
		lanOpen("127.0.0.1", "192.168.0.163"),
		lanOpen("[fd12::2]", "fd12::1"),
	} {
		t.Run(fmt.Sprint(i), func(t *testing.T) {
			c := start(t, options{dial: forbiddenDial(t)})
			c.hello()
			c.send(frame)
			c.terminal("blocked")
		})
	}
}

// Invalid even for a public destination: the open fails closed instead of
// ignoring the field. A value that is not a string is an invalid frame.
func TestInvalidLANHostTerminates(t *testing.T) {
	values := []any{5, true, []string{"192.168.0.163"}, map[string]string{"ip": "192.168.0.163"}}
	for _, value := range invalidLANHosts {
		values = append(values, value)
	}
	for i, value := range values {
		t.Run(fmt.Sprint(i), func(t *testing.T) {
			c := start(t, options{dial: forbiddenDial(t)})
			c.hello()
			c.send(lanOpen("8.8.8.8", value))
			c.terminal("invalid")
		})
	}
}

// Each frame below is valid without its lanHost.
func TestLANHostOnlyOnOpen(t *testing.T) {
	for _, value := range []any{"192.168.0.163", ""} {
		c := start(t, options{})
		c.send(map[string]any{"type": "hello", "lanHost": value})
		c.terminal("invalid")
	}
	opt, _ := pipeOptions(t)
	c := start(t, opt)
	c.open("127.0.0.1", 80)
	c.send(map[string]any{"type": "send", "data": "AA==", "lanHost": "192.168.0.163"})
	c.terminal("invalid")

	opt, peer := pipeOptions(t)
	c = start(t, opt)
	c.open("127.0.0.1", 80)
	go peer.Write([]byte{1})
	c.expect("data")
	c.send(map[string]any{"type": "ack", "lanHost": "192.168.0.163"})
	c.terminal("invalid")
}

// privateInterfaceAddr returns a private IPv4 (else ULA) address of this
// machine, the kind a LAN website's own server has, or skips the test.
func privateInterfaceAddr(t *testing.T) netip.Addr {
	t.Helper()
	addrs, err := net.InterfaceAddrs()
	if err != nil {
		t.Skipf("no interface addresses: %v", err)
	}
	var v6 netip.Addr
	for _, a := range addrs {
		if n, ok := a.(*net.IPNet); ok {
			if ip, ok := netip.AddrFromSlice(n.IP); ok {
				if lan, ok := parseLANHost(ip.Unmap().String()); ok && lan.Is4() {
					return lan
				} else if ok && !v6.IsValid() {
					v6 = lan
				}
			}
		}
	}
	if !v6.IsValid() {
		t.Skip("this machine has no private (RFC 1918 or ULA) address")
	}
	return v6
}

// Real TCP with the production policy: the website's own address carries
// data, the same address without lanHost and this computer stay blocked.
func TestLANHostRealConnection(t *testing.T) {
	lan := privateInterfaceAddr(t)
	l, err := net.Listen("tcp", net.JoinHostPort(lan.String(), "0"))
	if err != nil {
		t.Skipf("cannot listen on %s: %v", lan, err)
	}
	defer l.Close()
	go func() {
		if conn, err := l.Accept(); err == nil {
			defer conn.Close()
			_, _ = io.Copy(conn, conn)
		}
	}()
	loopback, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer loopback.Close()
	host, port := lan.String(), l.Addr().(*net.TCPAddr).Port

	c := start(t, options{})
	c.hello()
	c.send(request{Type: "open", Host: host, Port: port})
	c.terminal("blocked")

	c = start(t, options{})
	c.hello()
	c.send(request{Type: "open", Host: "127.0.0.1", Port: loopback.Addr().(*net.TCPAddr).Port, LanHost: &host})
	c.terminal("blocked")
	loopback.(*net.TCPListener).SetDeadline(time.Now().Add(100 * time.Millisecond))
	if conn, err := loopback.Accept(); err == nil {
		conn.Close()
		t.Fatal("this computer was reached")
	}

	c = start(t, options{})
	c.hello()
	c.send(request{Type: "open", Host: host, Port: port, LanHost: &host})
	c.expect("opened")
	payload := []byte{1, 2, 3}
	c.send(request{Type: "send", Data: base64.StdEncoding.EncodeToString(payload)})
	var got []byte
	sent := false
	for !sent || len(got) < len(payload) {
		switch m := c.recv(); m["type"] {
		case "sent":
			sent = true
		case "data":
			b, _ := base64.StdEncoding.DecodeString(m["data"].(string))
			got = append(got, b...)
			c.send(request{Type: "ack"})
		default:
			t.Fatalf("unexpected message %v", m)
		}
	}
	if !bytes.Equal(got, payload) {
		t.Fatalf("echo %v", got)
	}
	c.send(request{Type: "close"})
	c.terminal("")
}
