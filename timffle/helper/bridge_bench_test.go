package main

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"reflect"
	"strings"
	"sync/atomic"
	"testing"
)

// referenceSendData is the former validation: strict decode, then require
// that re-encoding reproduces the input exactly.
func referenceSendData(data string) ([]byte, bool) {
	if len(data) > base64.StdEncoding.EncodedLen(maxSend) {
		return nil, false
	}
	b, err := base64.StdEncoding.Strict().DecodeString(data)
	if err != nil || len(b) > maxSend || base64.StdEncoding.EncodeToString(b) != data {
		return nil, false
	}
	return b, true
}

func sendDataCorpus() []string {
	full := benchSendData()
	return []string{
		"", "AA==", "AAE=", "AAEC", "AB==", "AAA", "AAAA=", "AA===", "A", "=", "====", "AA==AA==", "AA==\n", "\nAA==", "A\rA==", "AA=\n=", " AA==", "AA==\x00",
		"AA\n==", "+/+/", "-_-_", "AAAA\r\n", full, full + "AAAA", full[:len(full)-4], full[:len(full)-3],
	}
}

func TestDecodeSendDataMatchesReference(t *testing.T) {
	for _, data := range sendDataCorpus() {
		got, ok := decodeSendData(data)
		want, wantOK := referenceSendData(data)
		if ok != wantOK || !bytes.Equal(got, want) {
			t.Errorf("decodeSendData(%q) = %v %v, reference %v %v", data, len(got), ok, len(want), wantOK)
		}
	}
}

func FuzzDecodeSendData(f *testing.F) {
	for _, data := range sendDataCorpus() {
		if len(data) < 1<<10 {
			f.Add(data)
		}
	}
	f.Fuzz(func(t *testing.T, data string) {
		got, ok := decodeSendData(data)
		want, wantOK := referenceSendData(data)
		if ok != wantOK || !bytes.Equal(got, want) {
			t.Fatalf("decodeSendData(%q) = %v %v, reference %v %v", data, got, ok, want, wantOK)
		}
	})
}

// Every reply parses to the same object as the former map encoding; a data
// frame's direct encoding is byte-for-byte what the standard encoder gives
// for a struct with the same field order (type first).
func TestEncodeFrameMatchesMapEncoding(t *testing.T) {
	payloads := [][]byte{nil, {}, {0}, {0, 1}, {0, 1, 2}, {255, 254, 253, 252}, bytes.Repeat([]byte{'"', '\\', '<', '>', '&', 0x7f, 0x80, '\n'}, 64), bytes.Repeat([]byte{7, 8, 9, 250}, readChunk/4)}
	for i := range 256 {
		payloads = append(payloads, bytes.Repeat([]byte{byte(i)}, i))
	}
	cases := []struct {
		value any
		old   any
	}{
		{helloReply{Type: "hello", Version: version, Protocol: protocolVersion}, map[string]any{"type": "hello", "version": version, "protocol": protocolVersion}},
		{typeMessage{Type: "opened"}, map[string]string{"type": "opened"}},
		{typeMessage{Type: "sent"}, map[string]string{"type": "sent"}},
		{typeMessage{Type: "closed"}, map[string]string{"type": "closed"}},
		{errorMessage("timeout"), map[string]string{"type": "error", "code": "timeout"}},
	}
	for _, p := range payloads {
		cases = append(cases, struct{ value, old any }{dataMessage(p), map[string]string{"type": "data", "data": base64.StdEncoding.EncodeToString(p)}})
	}
	for _, tc := range cases {
		frame, err := encodeFrame(tc.value)
		if err != nil {
			t.Fatal(err)
		}
		body := frame[4:]
		if binary.LittleEndian.Uint32(frame) != uint32(len(body)) {
			t.Fatalf("header %d for body %d", binary.LittleEndian.Uint32(frame), len(body))
		}
		want, err := json.Marshal(tc.old)
		if err != nil {
			t.Fatal(err)
		}
		var got, old map[string]any
		if err := json.Unmarshal(body, &got); err != nil {
			t.Fatalf("frame is not JSON: %v: %.80s", err, body)
		}
		if err := json.Unmarshal(want, &old); err != nil {
			t.Fatal(err)
		}
		if !reflect.DeepEqual(got, old) {
			t.Fatalf("frame %s differs from %s", body, want)
		}
		if d, ok := tc.value.(dataReply); ok {
			// Same bytes as the standard encoder gives for the same field order.
			std, err := json.Marshal(struct {
				Type string `json:"type"`
				Data string `json:"data"`
			}{"data", base64.StdEncoding.EncodeToString(d.Data)})
			if err != nil {
				t.Fatal(err)
			}
			if !bytes.Equal(body, std) {
				t.Fatalf("data frame for %d bytes differs from the standard encoding", len(d.Data))
			}
		}
		if bytes.ContainsAny(body, "\n") {
			t.Fatalf("frame body contains a newline: %q", body)
		}
	}
	if _, err := encodeFrame(make(chan int)); err == nil || !strings.Contains(err.Error(), "unsupported type") {
		t.Fatalf("encoding error not reported: %v", err)
	}
}

// The largest send the protocol allows: 64 KiB, 88 KiB once encoded.
func benchSendData() string {
	return base64.StdEncoding.EncodeToString(bytes.Repeat([]byte{0, 1, 255, 42}, maxSend/4))
}

func BenchmarkSendValidation(b *testing.B) {
	data := benchSendData()
	b.SetBytes(maxSend)
	b.ReportAllocs()
	for b.Loop() {
		if _, ok := decodeSendData(data); !ok {
			b.Fatal("rejected")
		}
	}
}

// One full send frame through the input path: framing, JSON, validation.
func BenchmarkInputLoopSend(b *testing.B) {
	frame := encode(request{Type: "send", Data: benchSendData()})
	b.SetBytes(int64(len(frame)))
	b.ReportAllocs()
	for b.Loop() {
		requests, ended := make(chan inputEvent, maxRequestBacklog), make(chan inputEnd, 1)
		abort, stop := make(chan struct{}), make(chan struct{})
		var busy atomic.Bool
		inputLoop(bytes.NewReader(frame), requests, ended, abort, stop, &busy)
		if e := <-ended; !e.silent {
			b.Fatalf("unexpected end %+v", e)
		}
	}
}

func BenchmarkReadFrame(b *testing.B) {
	frame := encode(request{Type: "send", Data: benchSendData()})
	b.SetBytes(int64(len(frame)))
	b.ReportAllocs()
	for b.Loop() {
		if _, err := readFrame(bytes.NewReader(frame)); err != nil {
			b.Fatal(err)
		}
	}
}

// One data frame to Chrome: a full 32 KiB read chunk, encoded and framed.
func BenchmarkDataFrame(b *testing.B) {
	chunk := bytes.Repeat([]byte{7, 8, 9, 250}, readChunk/4)
	b.SetBytes(readChunk)
	b.ReportAllocs()
	for b.Loop() {
		if _, err := encodeFrame(dataMessage(chunk)); err != nil {
			b.Fatal(err)
		}
	}
}

// Consecutive reads share one buffer inside serve; each data frame must still
// carry its own chunk, including a shorter second chunk after a longer first.
func TestConsecutiveDataFramesDoNotShareBuffers(t *testing.T) {
	opt, peer := pipeOptions(t)
	c := start(t, opt)
	c.open("127.0.0.1", 80)
	chunks := [][]byte{
		bytes.Repeat([]byte{0xAA}, 3000),
		bytes.Repeat([]byte{0x55, 0x01}, 700),
		{9, 8, 7},
		bytes.Repeat([]byte{0xC3}, readChunk),
	}
	var got [][]byte
	for i, chunk := range chunks {
		writing := make(chan error, 1)
		go func() { writing <- writeAll(peer, chunk) }()
		var acc []byte
		for len(acc) < len(chunk) {
			m := c.expect("data")
			b, err := base64.StdEncoding.DecodeString(m["data"].(string))
			if err != nil {
				t.Fatal(err)
			}
			acc = append(acc, b...)
			c.send(request{Type: "ack"})
		}
		if err := <-writing; err != nil {
			t.Fatal(err)
		}
		got = append(got, acc)
		// Frames already decoded must be unaffected by later reads.
		for j := 0; j <= i; j++ {
			if !bytes.Equal(got[j], chunks[j]) {
				t.Fatalf("chunk %d changed after chunk %d was read", j, i)
			}
		}
	}
	peer.Close()
	c.terminal("")
}

// Full serve loop over a fake connection that returns size bytes per read:
// one hello and open, then b.N data frames each acknowledged.
func benchSession(b *testing.B, size int) {
	chunk := bytes.Repeat([]byte{1, 2, 3, 250}, size/4+1)[:size]
	opt, peer := pipeOptionsB(b)
	inR, inW := io.Pipe()
	outR, outW := io.Pipe()
	done := make(chan error, 1)
	go func() { done <- serve(inR, outW, opt) }()
	readMsg := func() []byte {
		var h [4]byte
		if _, err := io.ReadFull(outR, h[:]); err != nil {
			b.Fatal(err)
		}
		m := make([]byte, binary.LittleEndian.Uint32(h[:]))
		if _, err := io.ReadFull(outR, m); err != nil {
			b.Fatal(err)
		}
		return m
	}
	inW.Write(encode(request{Type: "hello"}))
	readMsg()
	inW.Write(encode(request{Type: "open", Host: "127.0.0.1", Port: 80}))
	readMsg()
	ack := encode(request{Type: "ack"})
	b.SetBytes(int64(size))
	b.ReportAllocs()
	b.ResetTimer()
	for range b.N {
		go peer.Write(chunk)
		readMsg()
		inW.Write(ack)
	}
	b.StopTimer()
	inW.Close()
	outR.Close()
	peer.Close()
	<-done
}

func pipeOptionsB(b *testing.B) (options, net.Conn) {
	x, y := net.Pipe()
	b.Cleanup(func() { x.Close(); y.Close() })
	return options{allowPrivate: true, dial: func(context.Context, string, string) (net.Conn, error) { return x, nil }}, y
}

func BenchmarkSession(b *testing.B) {
	for _, size := range []int{100, 1400, readChunk} {
		b.Run(fmt.Sprint(size), func(b *testing.B) { benchSession(b, size) })
	}
}

// A process that only answers hello and sees EOF (the install window's probe).
func BenchmarkHelloOnly(b *testing.B) {
	in := encode(request{Type: "hello"})
	b.ReportAllocs()
	for b.Loop() {
		if err := serve(bytes.NewReader(in), io.Discard, options{}); err != nil {
			b.Fatal(err)
		}
	}
}
