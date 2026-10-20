//go:build !localtest

package main

import (
	"errors"
	"io"
	"testing"
)

func TestProductionRejectsRuntimePrivateBypass(t *testing.T) {
	for _, value := range []string{"1", "true", "yes", "*"} {
		t.Setenv("TIMFFLE_SOCKET_HELPER_ALLOW_PRIVATE", value)
		if localTestPrivatePermission() {
			t.Fatal("production enabled environment bypass")
		}
	}
}

// The whole production entry point with the variable set: a private
// destination stays blocked, also next to a lanHost naming another address.
// Were the policy relaxed, the 1 s dial would end as refused or timeout.
func TestProductionEntryPointBlocksPrivate(t *testing.T) {
	t.Setenv("TIMFFLE_SOCKET_HELPER_ALLOW_PRIVATE", "1")
	lan := "192.168.0.163"
	for _, host := range []string{"127.0.0.1", "10.255.255.1"} {
		for _, lanHost := range []*string{nil, &lan} {
			c := startHost(t, func(in io.Reader, out io.Writer) error {
				if run([]string{callerOrigin}, in, out) != 0 {
					return errors.New("helper exited with 1")
				}
				return nil
			})
			c.hello()
			c.send(request{Type: "open", Host: host, Port: 9, TimeoutMs: 1000, LanHost: lanHost})
			c.terminal("blocked")
		}
	}
}
