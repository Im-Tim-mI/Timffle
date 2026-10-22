//go:build windows

package main

import (
	"errors"
	"net"
	"os"
	"syscall"
	"testing"
)

// A refused dial on Windows carries WSAECONNREFUSED, not the text that an
// English system happens to format for it.
func TestIsRefusedWindows(t *testing.T) {
	refused := &net.OpError{Op: "dial", Net: "tcp", Err: &os.SyscallError{Syscall: "connectex", Err: wsaeConnRefused}}
	if !isRefused(refused) {
		t.Fatal("WSAECONNREFUSED not recognized")
	}
	reset := &net.OpError{Op: "dial", Net: "tcp", Err: &os.SyscallError{Syscall: "connectex", Err: syscall.WSAECONNRESET}}
	for _, err := range []error{reset, errors.New("No connection could be made because the target machine actively refused it."), errors.New("連線被拒絕")} {
		if isRefused(err) {
			t.Errorf("%v taken for a refusal", err)
		}
	}
}
