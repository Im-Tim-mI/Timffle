package main

import (
	"bytes"
	"io"
	"strings"
	"testing"
)

type forbiddenReader struct{ t *testing.T }

func (r forbiddenReader) Read([]byte) (int, error) {
	r.t.Error("invalid invocation read stdin")
	return 0, nil
}

// forceTerminal makes stdinIsTerminal give a fixed answer for one test.
func forceTerminal(t *testing.T, terminal bool) {
	t.Helper()
	saved := stdinIsTerminal
	stdinIsTerminal = func(io.Reader) bool { return terminal }
	t.Cleanup(func() { stdinIsTerminal = saved })
}

func TestCallerOriginExact(t *testing.T) {
	good := [][]string{{callerOrigin}, {callerOrigin, "--parent-window=0"}, {callerOrigin, "--parent-window=18446744073709551615"}}
	for _, args := range good {
		if !validInvocation(args) {
			t.Errorf("rejected valid caller: %v", args)
		}
	}
	// Zero arguments is the downloaded file's installer, never a Chrome
	// invocation (tested with a redirected HOME in interactive_test.go).
	if validInvocation(nil) || validInvocation([]string{}) {
		t.Error("zero arguments accepted as a Chrome invocation")
	}
	bad := [][]string{
		{""}, {"--version", callerOrigin}, {strings.TrimSuffix(callerOrigin, "/")}, {strings.ToUpper(callerOrigin)},
		{callerOrigin + "extra"}, {callerOrigin + "?x=1"}, {callerOrigin + "#x"}, {"chrome-extension://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/"},
		{"https://eandddnbchclalbjkhfelhjhpijifcog/"}, {callerOrigin, "--allow-private"}, {callerOrigin, "--parent-window=-1"},
		{callerOrigin, "--parent-window=1e2"}, {callerOrigin, "--parent-window="}, {callerOrigin, "--parent-window=18446744073709551616"},
		{callerOrigin, "--parent-window=1", "extra"},
		{"--install", "x"}, {"--uninstall", callerOrigin}, {"--INSTALL"}, {"-install"}, {"install"}, {"--version", "x"}, {"", ""},
	}
	// Not even an interactive console makes an invalid invocation read stdin.
	for _, terminal := range []bool{false, true} {
		forceTerminal(t, terminal)
		for _, args := range bad {
			if validInvocation(args) {
				t.Errorf("invalid caller accepted: %v", args)
			}
			var out bytes.Buffer
			if run(args, forbiddenReader{t}, &out) != 1 || out.Len() != 0 {
				t.Errorf("invalid invocation produced output: %v (terminal %v)", args, terminal)
			}
		}
	}
}
func TestVersionOutsideChrome(t *testing.T) {
	forceTerminal(t, true)
	var out bytes.Buffer
	if code := run([]string{"--version"}, forbiddenReader{t}, &out); code != 0 || out.String() != "timffle-socket-helper 1.4.0\n" {
		t.Fatalf("version: %d %q", code, out.String())
	}
}
