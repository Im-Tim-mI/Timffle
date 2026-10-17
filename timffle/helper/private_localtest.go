//go:build localtest

package main

import "os"

// Deliberate test-only build; never distribute this build as the production host.
// It still validates the caller and otherwise uses the production protocol.
func localTestPrivatePermission() bool {
	return os.Getenv("TIMFFLE_SOCKET_HELPER_ALLOW_PRIVATE") == "1"
}
