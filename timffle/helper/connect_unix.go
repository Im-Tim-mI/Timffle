//go:build !windows

package main

import (
	"errors"
	"syscall"
)

// isRefused reports whether a dial error is the peer's refusal (ECONNREFUSED),
// found through the net.OpError/os.SyscallError wrapping. Any other failure,
// including a textual "refused" from an injected dialer, is not a refusal.
func isRefused(err error) bool {
	return errors.Is(err, syscall.ECONNREFUSED)
}
