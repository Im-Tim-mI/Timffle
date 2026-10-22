//go:build windows

package main

import (
	"errors"
	"os"
	"syscall"
	"testing"
)

// The errors a rename over a running helper produces are retried; anything
// else fails at once.
func TestTransientReplaceErrorWindows(t *testing.T) {
	wrap := func(err error) error { return &os.LinkError{Op: "rename", Old: "a", New: "b", Err: err} }
	for _, err := range []error{errorSharingViolation, wrap(errorSharingViolation), wrap(syscall.ERROR_ACCESS_DENIED)} {
		if !transientReplaceError(err) {
			t.Errorf("%v not retried", err)
		}
	}
	for _, err := range []error{wrap(syscall.ERROR_FILE_NOT_FOUND), wrap(syscall.ERROR_PATH_NOT_FOUND), errors.New("sharing violation")} {
		if transientReplaceError(err) {
			t.Errorf("%v retried", err)
		}
	}
}
