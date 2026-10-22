//go:build windows

package main

import (
	"errors"
	"syscall"
)

// wsaeConnRefused is WSAECONNREFUSED, the Winsock error that a refused dial
// carries. syscall.ECONNREFUSED is a Go-invented number on Windows which
// never matches it, and the error text depends on the system language.
const wsaeConnRefused = syscall.Errno(10061)

// isRefused reports whether a dial error is the peer's refusal, found through
// the net.OpError/os.SyscallError wrapping rather than by matching text.
func isRefused(err error) bool {
	return errors.Is(err, wsaeConnRefused) || errors.Is(err, syscall.ECONNREFUSED)
}
