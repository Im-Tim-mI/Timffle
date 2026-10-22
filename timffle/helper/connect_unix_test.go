//go:build !windows

package main

import (
	"errors"
	"fmt"
	"net"
	"os"
	"syscall"
	"testing"
)

func TestIsRefusedUnix(t *testing.T) {
	for _, err := range []error{syscall.ECONNREFUSED, refusedError(), fmt.Errorf("wrapped: %w", refusedError())} {
		if !isRefused(err) {
			t.Errorf("%v not recognized as refused", err)
		}
	}
	reset := &net.OpError{Op: "dial", Err: &os.SyscallError{Syscall: "connect", Err: syscall.ECONNRESET}}
	for _, err := range []error{reset, syscall.ENETUNREACH, errors.New("connection refused"), errors.New("REFUSED")} {
		if isRefused(err) {
			t.Errorf("%v taken for a refusal", err)
		}
	}
}
