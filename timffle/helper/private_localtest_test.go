//go:build localtest

package main

import "testing"

func TestLocaltestPrivatePermission(t *testing.T) {
	t.Setenv("TIMFFLE_SOCKET_HELPER_ALLOW_PRIVATE", "")
	if localTestPrivatePermission() {
		t.Fatal("test permission enabled by default")
	}
	t.Setenv("TIMFFLE_SOCKET_HELPER_ALLOW_PRIVATE", "1")
	if !localTestPrivatePermission() {
		t.Fatal("localtest env permission did not work")
	}
	t.Setenv("TIMFFLE_SOCKET_HELPER_ALLOW_PRIVATE", "true")
	if localTestPrivatePermission() {
		t.Fatal("test permission requires exact 1")
	}
}
