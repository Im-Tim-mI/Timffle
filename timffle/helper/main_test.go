package main

import (
	"bytes"
	"strings"
	"testing"
)

type forbiddenReader struct{ t *testing.T }

func (r forbiddenReader) Read([]byte) (int, error) {
	r.t.Error("invalid invocation read stdin")
	return 0, nil
}

func TestCallerOriginExact(t *testing.T) {
	good := [][]string{{callerOrigin}, {callerOrigin, "--parent-window=0"}, {callerOrigin, "--parent-window=18446744073709551615"}}
	for _, args := range good {
		if !validInvocation(args) {
			t.Errorf("rejected valid caller: %v", args)
		}
	}
	bad := [][]string{
		nil, {""}, {"--version", callerOrigin}, {strings.TrimSuffix(callerOrigin, "/")}, {strings.ToUpper(callerOrigin)},
		{callerOrigin + "extra"}, {callerOrigin + "?x=1"}, {callerOrigin + "#x"}, {"chrome-extension://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/"},
		{"https://eandddnbchclalbjkhfelhjhpijifcog/"}, {callerOrigin, "--allow-private"}, {callerOrigin, "--parent-window=-1"},
		{callerOrigin, "--parent-window=1e2"}, {callerOrigin, "--parent-window="}, {callerOrigin, "--parent-window=18446744073709551616"},
		{callerOrigin, "--parent-window=1", "extra"},
	}
	for _, args := range bad {
		if validInvocation(args) {
			t.Errorf("invalid caller accepted: %v", args)
		}
		var out bytes.Buffer
		if run(args, forbiddenReader{t}, &out) != 1 || out.Len() != 0 {
			t.Errorf("invalid invocation produced output: %v", args)
		}
	}
}
func TestVersionOutsideChrome(t *testing.T) {
	var out bytes.Buffer
	if code := run([]string{"--version"}, forbiddenReader{t}, &out); code != 0 || out.String() != "timffle-socket-helper 1.2.0\n" {
		t.Fatalf("version: %d %q", code, out.String())
	}
}
