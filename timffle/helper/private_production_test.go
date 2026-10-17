//go:build !localtest

package main

import "testing"

func TestProductionRejectsRuntimePrivateBypass(t *testing.T) {
	for _, value := range []string{"1", "true", "yes", "*"} {
		t.Setenv("TIMFFLE_SOCKET_HELPER_ALLOW_PRIVATE", value)
		if localTestPrivatePermission() {
			t.Fatal("production enabled environment bypass")
		}
	}
}
