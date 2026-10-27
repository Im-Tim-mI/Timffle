package main

import (
	"context"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"errors"
	"io"
	"net"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

const (
	protocolVersion     = 2
	maxInbound          = 1 << 20
	maxSend             = 64 << 10
	readChunk           = 32 << 10
	defaultTimeout      = 20 * time.Second
	minTimeout          = time.Second
	maxTimeout          = 120 * time.Second
	defaultStallTimeout = 30 * time.Second
	maxRequestBacklog   = 8
)

var (
	errInvalidFrame  = errors.New("invalid native message")
	errFlowControl   = errors.New("native flow control violation")
	errOutputTimeout = errors.New("native output stalled")
)

type request struct {
	Type      string `json:"type"`
	Host      string `json:"host"`
	Port      int    `json:"port"`
	TimeoutMs int64  `json:"timeoutMs"`
	Data      string `json:"data"`
	// open only. A pointer, so that a present but empty value fails instead of
	// reading as absent.
	LanHost *string `json:"lanHost,omitempty"`
}

type options struct {
	// Internal tests only. The production entry point cannot enable this.
	allowPrivate bool
	lookup       func(context.Context, string) ([]net.IPAddr, error)
	dial         func(context.Context, string, string) (net.Conn, error)
	// Shorter limits allow deterministic tests without real network traffic.
	writeTimeout  time.Duration
	ackTimeout    time.Duration
	outputTimeout time.Duration
}

func (o options) defaults() options {
	if o.lookup == nil {
		o.lookup = net.DefaultResolver.LookupIPAddr
	}
	if o.dial == nil {
		o.dial = (&net.Dialer{}).DialContext
	}
	if o.writeTimeout <= 0 {
		o.writeTimeout = defaultStallTimeout
	}
	if o.ackTimeout <= 0 {
		o.ackTimeout = defaultStallTimeout
	}
	if o.outputTimeout <= 0 {
		o.outputTimeout = defaultStallTimeout
	}
	return o
}

func readFrame(r io.Reader) (request, error) {
	var header [4]byte
	if _, err := io.ReadFull(r, header[:]); err != nil {
		if errors.Is(err, io.EOF) {
			return request{}, io.EOF
		}
		return request{}, errInvalidFrame
	}
	n := binary.LittleEndian.Uint32(header[:])
	if n == 0 || n > maxInbound {
		return request{}, errInvalidFrame
	}
	body := make([]byte, n)
	if _, err := io.ReadFull(r, body); err != nil {
		return request{}, errInvalidFrame
	}
	var req request
	if err := json.Unmarshal(body, &req); err != nil || req.Type == "" {
		return request{}, errInvalidFrame
	}
	return req, nil
}

// The helper's replies. Field names and values are the protocol's; only the
// key order inside a frame differs from the former map encoding.
type typeMessage struct {
	Type string `json:"type"`
}
type errorReply struct {
	Type string `json:"type"`
	Code string `json:"code"`
}
type helloReply struct {
	Type     string `json:"type"`
	Version  string `json:"version"`
	Protocol int    `json:"protocol"`
}

// dataReply carries the raw bytes; encodeFrame base64-encodes them straight
// into the frame.
type dataReply struct {
	Data []byte
}

func errorMessage(code string) errorReply { return errorReply{Type: "error", Code: code} }
func dataMessage(data []byte) dataReply   { return dataReply{Data: data} }

const (
	dataFramePrefix = `{"type":"data","data":"`
	dataFrameSuffix = `"}`
)

// encodeFrame serializes one native message with its 4-byte length header.
// A data frame is written in one allocation: the base64 alphabet contains
// nothing that JSON escapes, so the payload needs no further quoting.
func encodeFrame(value any) ([]byte, error) {
	if d, ok := value.(dataReply); ok {
		n := base64.StdEncoding.EncodedLen(len(d.Data))
		body := len(dataFramePrefix) + n + len(dataFrameSuffix)
		frame := make([]byte, 4+body)
		binary.LittleEndian.PutUint32(frame, uint32(body))
		p := frame[4:4]
		p = append(p, dataFramePrefix...)
		base64.StdEncoding.Encode(p[len(p):len(p)+n], d.Data)
		p = p[:len(p)+n]
		p = append(p, dataFrameSuffix...)
		return frame[:4+len(p)], nil
	}
	b, err := json.Marshal(value)
	if err != nil {
		return nil, err
	}
	frame := make([]byte, len(b)+4)
	binary.LittleEndian.PutUint32(frame, uint32(len(b)))
	copy(frame[4:], b)
	return frame, nil
}

// writeAll handles legal short writes, detects broken writers and never spins
// on a (0,nil) write. The caller supplies cancellation/deadline enforcement.
func writeAll(w io.Writer, b []byte) error {
	for len(b) > 0 {
		n, err := w.Write(b)
		if n < 0 || n > len(b) {
			return io.ErrShortWrite
		}
		b = b[n:]
		if err != nil {
			return err
		}
		if n == 0 {
			return io.ErrShortWrite
		}
	}
	return nil
}

type outputFrame struct {
	body []byte
	done chan error
}

// One writer, one bounded in-flight frame, no data queue. Even a blocked stdout
// cannot block cancellation or retain an unbounded number of goroutines.
// Real native stdio is owned by this session and closed during shutdown.
// A non-closable injected reader/writer must itself be nonblocking; Go cannot
// interrupt arbitrary third-party io.Reader/Writer implementations.
func outputLoop(out io.Writer, frames <-chan outputFrame, stop <-chan struct{}) {
	for {
		select {
		case <-stop:
			return
		case f := <-frames:
			err := writeAll(out, f.body)
			f.done <- err
			if err != nil {
				return
			}
		}
	}
}

func sendFrame(out chan<- outputFrame, value any, timeout time.Duration, abort <-chan struct{}) error {
	frame, err := encodeFrame(value)
	if err != nil {
		return err
	}
	done := make(chan error, 1)
	timer := time.NewTimer(timeout)
	defer timer.Stop()
	select {
	case out <- outputFrame{frame, done}:
	case <-abort:
		return context.Canceled
	case <-timer.C:
		return errOutputTimeout
	}
	select {
	case err := <-done:
		return err
	case <-abort:
		return context.Canceled
	case <-timer.C:
		return errOutputTimeout
	}
}

type inputEvent struct {
	req  request
	data []byte
}
type inputEnd struct {
	err    error
	code   string
	silent bool
}

// The scanner never waits on the socket, DNS, or stdout. This is important:
// queued sends must not hide EOF/close behind a blocked TCP Write. There is one
// permitted send in flight and a small fixed-size control-message backlog.
// Violating that bound terminates the session rather than blocking the scanner.
func inputLoop(in io.Reader, requests chan<- inputEvent, ended chan<- inputEnd, abort chan<- struct{}, stop <-chan struct{}, sendBusy *atomic.Bool) {
	finish := func(e inputEnd) { ended <- e; close(abort) }
	for {
		req, err := readFrame(in)
		if err != nil {
			if errors.Is(err, io.EOF) {
				finish(inputEnd{silent: true})
			} else {
				finish(inputEnd{err: err, code: "invalid"})
			}
			return
		}
		if req.Type == "close" {
			finish(inputEnd{})
			return
		}
		switch req.Type {
		case "hello", "open", "send", "ack":
		default:
			finish(inputEnd{err: errInvalidFrame, code: "invalid"})
			return
		}
		if len(req.Host) > 255 || (req.Type != "open" && (req.Host != "" || req.Port != 0 || req.TimeoutMs != 0 || req.LanHost != nil)) || (req.Type != "send" && req.Data != "") {
			finish(inputEnd{err: errInvalidFrame, code: "invalid"})
			return
		}
		event := inputEvent{req: req}
		if req.Type == "send" {
			b, ok := decodeSendData(req.Data)
			if !ok {
				finish(inputEnd{err: errInvalidFrame, code: "invalid"})
				return
			}
			if !sendBusy.CompareAndSwap(false, true) {
				finish(inputEnd{err: errFlowControl, code: "invalid"})
				return
			}
			event.data = b
			event.req.Data = "" // Do not retain the 1MiB input frame / encoded payload.
		}
		select {
		case <-stop:
			return
		default:
		}
		select {
		case requests <- event:
		case <-stop:
			return
		default:
			finish(inputEnd{err: errFlowControl, code: "invalid"})
			return
		}
	}
}

// decodeSendData decodes a send's payload. Newlines and noncanonical
// encodings are rejected (browser btoa output is always canonical): the
// strict decoder refuses nonzero padding bits, and the only characters it
// would skip are CR and LF, so refusing those up front, plus the length
// check, leaves exactly the inputs whose re-encoding reproduces them.
func decodeSendData(data string) ([]byte, bool) {
	// Check the encoded size before allocating a decode buffer.
	if len(data) > base64.StdEncoding.EncodedLen(maxSend) || strings.ContainsAny(data, "\r\n") {
		return nil, false
	}
	b, err := base64.StdEncoding.Strict().DecodeString(data)
	if err != nil || len(b) > maxSend || len(data) != base64.StdEncoding.EncodedLen(len(b)) {
		return nil, false
	}
	return b, true
}

type connectResult struct {
	conn net.Conn
	code string
}
type readResult struct {
	data []byte
	err  error
}

// serve owns both stdio handles and the single TCP socket for this process.
// All protocol-state mutations and output ordering are in this event loop.
func serve(in io.Reader, out io.Writer, opt options) error {
	opt = opt.defaults()
	ctx, cancel := context.WithCancel(context.Background())
	stopOutput := make(chan struct{})
	abort := make(chan struct{})
	ended := make(chan inputEnd, 1)
	requests := make(chan inputEvent, maxRequestBacklog)
	output := make(chan outputFrame)
	var sendBusy atomic.Bool
	var conn net.Conn
	var connectionWG sync.WaitGroup
	defer func() {
		cancel()
		if conn != nil {
			_ = conn.Close()
		}
		if c, ok := in.(io.Closer); ok {
			_ = c.Close()
		}
		close(stopOutput)
		if c, ok := out.(io.Closer); ok {
			_ = c.Close()
		}
		connectionWG.Wait()
	}()
	go inputLoop(in, requests, ended, abort, ctx.Done(), &sendBusy)
	go outputLoop(out, output, stopOutput)
	// Network cancellation must not depend on the event loop's stdout writer.
	go func() {
		select {
		case <-abort:
			cancel()
		case <-ctx.Done():
		}
	}()

	var ending *inputEnd
	var outputDead bool
	var errorSent, closedSent bool
	emit := func(value any) error {
		interrupted := (<-chan struct{})(abort)
		if ending != nil {
			interrupted = nil
		}
		err := sendFrame(output, value, opt.outputTimeout, interrupted)
		if err != nil && !errors.Is(err, context.Canceled) {
			outputDead = true
		}
		return err
	}
	finish := func(code string, cause error) error {
		cancel()
		if conn != nil {
			_ = conn.Close()
		}
		// EOF means Chrome is gone: don't spend 30s trying to notify a dead peer.
		if outputDead || (ending != nil && ending.silent) {
			return cause
		}
		// Canceled means Chrome closed its end meanwhile (possibly right after
		// reading these frames): a normal end, not a reason to exit non-zero.
		if code != "" && !errorSent {
			errorSent = true
			if err := emit(errorMessage(code)); err != nil && !errors.Is(err, context.Canceled) {
				return err
			}
		}
		if !closedSent {
			closedSent = true
			if err := emit(typeMessage{Type: "closed"}); err != nil && !errors.Is(err, context.Canceled) {
				return err
			}
		}
		return cause
	}
	absorbEnd := func() bool {
		if ending != nil {
			return true
		}
		select {
		case e := <-ended:
			ending = &e
			return true
		default:
			return false
		}
	}

	connected := make(chan connectResult)
	reads := make(chan readResult, 1)
	writes := make(chan error, 1)
	var greeted, opening, writing bool
	var ackTimer *time.Timer
	var ackDeadline <-chan time.Time
	var writeTimer *time.Timer
	var writeDeadline <-chan time.Time
	var waitingAck bool
	var afterAck error
	defer func() {
		if ackTimer != nil {
			ackTimer.Stop()
		}
		if writeTimer != nil {
			writeTimer.Stop()
		}
	}()
	// One read is in flight at a time, and the next is only started (after
	// opened, or after an ack) once the previous chunk has been encoded into
	// its frame, so a single buffer serves the whole session.
	// It is allocated on the first read, so a process that only answers hello
	// never pays for it.
	var readBuf []byte
	readNext := func() {
		c := conn
		if readBuf == nil {
			readBuf = make([]byte, readChunk)
		}
		buf := readBuf
		connectionWG.Add(1)
		go func() {
			defer connectionWG.Done()
			n, err := c.Read(buf)
			if n < 0 || n > len(buf) {
				n, err = 0, io.ErrUnexpectedEOF
			}
			if n == 0 && err == nil {
				err = io.ErrNoProgress
			}
			select {
			case reads <- readResult{buf[:n], err}:
			case <-ctx.Done():
			}
		}()
	}

	for {
		if absorbEnd() {
			return finish(ending.code, ending.err)
		}
		select {
		case e := <-ended:
			ending = &e
			return finish(e.code, e.err)
		case event := <-requests:
			if absorbEnd() {
				return finish(ending.code, ending.err)
			}
			req := event.req
			switch req.Type {
			case "hello":
				if greeted || opening || conn != nil {
					return finish("invalid", errInvalidFrame)
				}
				greeted = true
				if err := emit(helloReply{Type: "hello", Version: version, Protocol: protocolVersion}); err != nil {
					if absorbEnd() {
						return finish(ending.code, ending.err)
					}
					return err
				}
			case "open":
				if !greeted || opening || conn != nil {
					return finish("invalid", errInvalidFrame)
				}
				opening = true
				go func() {
					c, code := openTCP(ctx, req, opt)
					select {
					case connected <- connectResult{c, code}:
					case <-ctx.Done():
						if c != nil {
							_ = c.Close()
						}
					}
				}()
			case "send":
				if conn == nil {
					return finish("not_open", errInvalidFrame)
				}
				if writing {
					return finish("invalid", errFlowControl)
				}
				writing = true
				c := conn
				data := event.data
				// Wall-clock timer in addition to SetWriteDeadline: this also bounds a
				// broken/injected Conn which ignores deadlines but honors Close.
				writeTimer = time.NewTimer(opt.writeTimeout)
				writeDeadline = writeTimer.C
				connectionWG.Add(1)
				go func() {
					defer connectionWG.Done()
					err := c.SetWriteDeadline(time.Now().Add(opt.writeTimeout))
					if err == nil {
						err = writeAll(c, data)
					}
					if err == nil {
						err = c.SetWriteDeadline(time.Time{})
					}
					select {
					case writes <- err:
					case <-ctx.Done():
					}
				}()
			case "ack":
				if !waitingAck {
					return finish("invalid", errFlowControl)
				}
				waitingAck = false
				ackTimer.Stop()
				ackDeadline = nil
				if afterAck != nil {
					if errors.Is(afterAck, io.EOF) {
						return finish("", nil)
					}
					return finish("unreachable", afterAck)
				}
				readNext()
			}
		case result := <-connected:
			opening = false
			if absorbEnd() {
				if result.conn != nil {
					_ = result.conn.Close()
				}
				return finish(ending.code, ending.err)
			}
			if result.code != "" {
				return finish(result.code, nil)
			}
			conn = result.conn
			// Close interrupts real net.Conn Read/Write on every platform. Register
			// it before any output, so stdin EOF also interrupts a blocked stdout.
			connectionWG.Add(1)
			go func(c net.Conn) { defer connectionWG.Done(); <-ctx.Done(); _ = c.Close() }(conn)
			if err := emit(typeMessage{Type: "opened"}); err != nil {
				if absorbEnd() {
					return finish(ending.code, ending.err)
				}
				return err
			}
			readNext()
		case result := <-reads:
			if absorbEnd() {
				return finish(ending.code, ending.err)
			}
			if len(result.data) > 0 {
				waitingAck = true
				afterAck = result.err
				if err := emit(dataMessage(result.data)); err != nil {
					if absorbEnd() {
						return finish(ending.code, ending.err)
					}
					return err
				}
				ackTimer = time.NewTimer(opt.ackTimeout)
				ackDeadline = ackTimer.C
			} else if errors.Is(result.err, io.EOF) {
				return finish("", nil)
			} else {
				return finish("unreachable", result.err)
			}
		case err := <-writes:
			writeTimer.Stop()
			writeDeadline = nil
			writing = false
			if absorbEnd() {
				return finish(ending.code, ending.err)
			}
			if err != nil {
				code := "unreachable"
				var ne net.Error
				if errors.As(err, &ne) && ne.Timeout() {
					code = "timeout"
				}
				return finish(code, err)
			}
			// Release before publishing sent: an immediate next request may arrive
			// as soon as Chrome receives the frame. No second write can execute until
			// this synchronous frame publication has completed.
			sendBusy.Store(false)
			if err := emit(typeMessage{Type: "sent"}); err != nil {
				if absorbEnd() {
					return finish(ending.code, ending.err)
				}
				return err
			}
		case <-ackDeadline:
			return finish("timeout", context.DeadlineExceeded)
		case <-writeDeadline:
			return finish("timeout", context.DeadlineExceeded)
		}
	}
}
