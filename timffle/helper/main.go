// Command timffle-socket-helper is a per-socket Chrome native messaging host.
// It never listens on a port or installs a daemon.
package main

import (
	"fmt"
	"io"
	"os"
	"strconv"
	"strings"
)

const version = "1.2.0"
const callerOrigin = "chrome-extension://eandddnbchclalbjkhfelhjhpijifcog/"

// Chrome's Windows invocation also carries --parent-window=<decimal HWND>.
// An origin is an exact identity, not a URL prefix or a caller-supplied flag.
func validInvocation(args []string) bool {
	if len(args) < 1 || len(args) > 2 || args[0] != callerOrigin {
		return false
	}
	if len(args) == 2 {
		const prefix = "--parent-window="
		if !strings.HasPrefix(args[1], prefix) {
			return false
		}
		n := strings.TrimPrefix(args[1], prefix)
		if n == "" {
			return false
		}
		for _, c := range n {
			if c < '0' || c > '9' {
				return false
			}
		}
		if _, err := strconv.ParseUint(n, 10, 64); err != nil {
			return false
		}
	}
	return true
}

func run(args []string, in io.Reader, out io.Writer) int {
	// Chrome always passes the caller origin first, so it can never reach these.
	if len(args) == 1 {
		switch args[0] {
		case "--version":
			if _, err := fmt.Fprintln(out, "timffle-socket-helper", version); err != nil {
				return 1
			}
			return 0
		case "--install":
			return runInstaller(out, false)
		case "--uninstall":
			return runInstaller(out, true)
		}
	}
	// Fail before reading stdin, resolving names or writing native frames.
	if !validInvocation(args) {
		return 1
	}
	if err := serve(in, out, options{allowPrivate: localTestPrivatePermission()}); err != nil {
		return 1
	}
	return 0
}

func main() { os.Exit(run(os.Args[1:], os.Stdin, os.Stdout)) }
