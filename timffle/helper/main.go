// Command timffle-socket-helper is a per-socket Chrome native messaging host.
// It never listens on a port or installs a daemon.
package main

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"runtime"
	"strconv"
	"strings"
)

const version = "1.4.0"
const callerOrigin = "chrome-extension://eandddnbchclalbjkhfelhjhpijifcog/"

// stdinIsTerminal reports whether in is an interactive console; a variable so
// tests can force either answer. /dev/null and NUL are character devices too,
// but reading them ends at once, so the Enter prompt cannot hang there.
var stdinIsTerminal = func(in io.Reader) bool {
	f, ok := in.(*os.File)
	if !ok {
		return false
	}
	info, err := f.Stat()
	return err == nil && info.Mode()&os.ModeCharDevice != 0
}

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

// runDownloaded is what running the downloaded file without arguments does
// (a double-click on Windows and macOS): install, then keep a console window
// open until Enter so the result can be read, also after a failure.
func runDownloaded(in io.Reader, out io.Writer) int {
	fmt.Fprintf(out, "Timffle 連線小幫手 %s / Timffle socket helper %s\n", version, version)
	fmt.Fprintln(out, "只替目前的使用者安裝，不需要系統管理員權限。/ Installs for the current user only; no administrator rights needed.")
	fmt.Fprintln(out)
	code := runInstaller(out, false)
	if code == 0 {
		if runtime.GOOS == "windows" {
			fmt.Fprintln(out, "日後要移除：用 --uninstall 執行下載的這個檔案（不是已安裝的複本）。/ To remove it later, run this downloaded file (not the installed copy) with --uninstall.")
		} else {
			fmt.Fprintln(out, "日後要移除：在終端機用 --uninstall 執行這個檔案。/ To remove it later, run this file with --uninstall in a terminal.")
		}
	}
	if stdinIsTerminal(in) {
		fmt.Fprint(out, "\n按 Enter 關閉 / Press Enter to close. ")
		if line, err := bufio.NewReader(in).ReadString('\n'); err != nil || !strings.HasSuffix(line, "\n") {
			fmt.Fprintln(out)
		}
	}
	return code
}

func run(args []string, in io.Reader, out io.Writer) int {
	// Chrome always passes the caller origin first, so it can never reach these.
	// Zero arguments therefore means that someone ran the file directly, which
	// is no new attack surface: whoever can do that could pass --install too.
	if len(args) == 0 {
		return runDownloaded(in, out)
	}
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
