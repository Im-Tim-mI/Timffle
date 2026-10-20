//go:build linux

package main

import (
	"bytes"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

const (
	downloadHeader = "Timffle 連線小幫手 1.4.0 / Timffle socket helper 1.4.0\n"
	adminText      = "只替目前的使用者安裝，不需要系統管理員權限"
	uninstallHint  = "run this file with --uninstall"
	enterPrompt    = "按 Enter 關閉 / Press Enter to close."
)

// downloadEnv points the real platform installer at a throw-away HOME.
type downloadEnv struct{ dir, binary, manifest string }

func newDownloadEnv(t *testing.T) downloadEnv {
	t.Helper()
	root := t.TempDir()
	t.Setenv("HOME", root)
	t.Setenv("XDG_DATA_HOME", filepath.Join(root, "share"))
	t.Setenv("XDG_CONFIG_HOME", filepath.Join(root, "conf"))
	t.Setenv("CHROME_CONFIG_HOME", "")
	dir := filepath.Join(root, "share", "timffle-socket-helper")
	return downloadEnv{dir: dir, binary: filepath.Join(dir, "timffle-socket-helper"), manifest: filepath.Join(root, "conf", "google-chrome", "NativeMessagingHosts", hostName+".json")}
}

func (e downloadEnv) checkInstalled(t *testing.T) {
	t.Helper()
	self, err := os.Executable()
	if err != nil {
		t.Fatal(err)
	}
	want, err := fileDigest(self)
	if err != nil {
		t.Fatal(err)
	}
	if got, err := fileDigest(e.binary); err != nil || got != want {
		t.Fatalf("installed binary differs from the running file: %v", err)
	}
	if got := readText(t, e.manifest); got != string(installLayout{binary: e.binary}.manifestBytes()) {
		t.Fatalf("manifest %s", got)
	}
	if r, err := readReceipt(e.dir); err != nil || r == nil || r.Version != version {
		t.Fatalf("receipt %+v %v", r, err)
	}
}

func (e downloadEnv) uninstall(t *testing.T) {
	t.Helper()
	var out bytes.Buffer
	if code := run([]string{"--uninstall"}, forbiddenReader{t}, &out); code != 0 || exists(e.dir) || exists(e.manifest) {
		t.Fatalf("uninstall %d: %s", code, out.String())
	}
}

func TestNoArgumentsInstallsForTheCurrentUser(t *testing.T) {
	e := newDownloadEnv(t)
	forceTerminal(t, false)
	for _, args := range [][]string{nil, {}} {
		var out bytes.Buffer
		// Not a console: the result is printed and stdin is never read.
		if code := run(args, forbiddenReader{t}, &out); code != 0 {
			t.Fatalf("install %d: %s", code, out.String())
		}
		text := out.String()
		if !strings.HasPrefix(text, downloadHeader) || !strings.Contains(text, adminText) {
			t.Fatalf("header missing: %q", text)
		}
		installed := strings.Index(text, "Socket helper 1.4.0 installed:\n  "+e.binary+"\n  "+e.manifest+"\n")
		hint := strings.Index(text, uninstallHint)
		if installed < 0 || hint < installed || strings.Count(text, uninstallHint) != 1 || !strings.Contains(text, "日後要移除：在終端機用 --uninstall 執行這個檔案") {
			t.Fatalf("install result or uninstall hint missing: %q", text)
		}
		if strings.Contains(text, "Press Enter") || strings.Contains(text, "Error") {
			t.Fatalf("unexpected output: %q", text)
		}
		e.checkInstalled(t)
		e.uninstall(t)
	}
}

// syncBuffer lets a test read output while run is still waiting for Enter.
type syncBuffer struct {
	mu  sync.Mutex
	buf bytes.Buffer
}

func (b *syncBuffer) Write(p []byte) (int, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.buf.Write(p)
}

func (b *syncBuffer) String() string {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.buf.String()
}

func TestNoArgumentsWaitsForEnterInAConsole(t *testing.T) {
	e := newDownloadEnv(t)
	forceTerminal(t, true)
	stdin, typed := io.Pipe()
	defer typed.Close()
	var out syncBuffer
	done := make(chan int, 1)
	go func() { done <- run(nil, stdin, &out) }()
	deadline := time.Now().Add(10 * time.Second)
	for !strings.HasSuffix(out.String(), enterPrompt+" ") {
		select {
		case code := <-done:
			t.Fatalf("returned %d without waiting for Enter: %q", code, out.String())
		case <-time.After(10 * time.Millisecond):
		}
		if time.Now().After(deadline) {
			t.Fatalf("no Enter prompt: %q", out.String())
		}
	}
	// The window stays open (run keeps waiting) until a line arrives.
	select {
	case code := <-done:
		t.Fatalf("returned %d before Enter", code)
	case <-time.After(100 * time.Millisecond):
	}
	text := out.String()
	if !strings.HasPrefix(text, downloadHeader) || strings.Index(text, uninstallHint) > strings.Index(text, enterPrompt) {
		t.Fatalf("output order: %q", text)
	}
	e.checkInstalled(t)
	if _, err := typed.Write([]byte("\n")); err != nil {
		t.Fatal(err)
	}
	select {
	case code := <-done:
		if code != 0 {
			t.Fatalf("exit %d", code)
		}
	case <-time.After(10 * time.Second):
		t.Fatal("Enter did not close")
	}
	// The console echoes the typed Enter; nothing more is printed.
	if !strings.HasSuffix(out.String(), enterPrompt+" ") {
		t.Fatalf("output after Enter: %q", out.String())
	}
	e.uninstall(t)
}

func TestNoArgumentsPromptEndsAtEndOfInput(t *testing.T) {
	e := newDownloadEnv(t)
	forceTerminal(t, true)
	var out bytes.Buffer
	if code := run(nil, strings.NewReader(""), &out); code != 0 || !strings.HasSuffix(out.String(), enterPrompt+" \n") {
		t.Fatalf("exit %d: %q", code, out.String())
	}
	e.uninstall(t)
}

func TestNoArgumentsReportsFailures(t *testing.T) {
	foreign := `{"name":"timffle_socket_helper","path":"/opt/other/host","type":"stdio"}`
	plant := func(t *testing.T, path string) {
		t.Helper()
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(foreign), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	setups := map[string]func(*testing.T, downloadEnv) (string, string){
		"foreign manifest": func(t *testing.T, e downloadEnv) (string, string) {
			plant(t, e.manifest)
			return e.manifest, "is used by another program"
		},
		"file where the install folder goes": func(t *testing.T, e downloadEnv) (string, string) {
			plant(t, e.dir)
			return e.dir, "not a directory"
		},
	}
	for name, setup := range setups {
		for _, terminal := range []bool{false, true} {
			t.Run(fmt.Sprintf("%s/console=%v", name, terminal), func(t *testing.T) {
				e := newDownloadEnv(t)
				forceTerminal(t, terminal)
				kept, message := setup(t, e)
				var in io.Reader = forbiddenReader{t}
				if terminal {
					in = strings.NewReader("\n")
				}
				var out bytes.Buffer
				code := run(nil, in, &out)
				text := out.String()
				if code == 0 || !strings.HasPrefix(text, downloadHeader) || !strings.Contains(text, "錯誤 / Error: ") || !strings.Contains(text, message) {
					t.Fatalf("exit %d: %q", code, text)
				}
				if strings.Contains(text, "installed") || strings.Contains(text, uninstallHint) {
					t.Fatalf("reported success: %q", text)
				}
				// A double-clicked console must stay open after a failure too.
				if prompted := strings.Index(text, enterPrompt) > strings.Index(text, "Error"); prompted != terminal {
					t.Fatalf("prompt shown %v, console %v: %q", prompted, terminal, text)
				}
				if readText(t, kept) != foreign || exists(e.binary) {
					t.Fatal("changed something while refusing")
				}
			})
		}
	}
}

func TestOnlyZeroArgumentsPromptOrReadStdin(t *testing.T) {
	e := newDownloadEnv(t)
	forceTerminal(t, true)
	for _, args := range [][]string{{"--install", "x"}, {"--INSTALL"}, {"install"}, {""}, {callerOrigin + "x"}} {
		var out bytes.Buffer
		if code := run(args, forbiddenReader{t}, &out); code != 1 || out.Len() != 0 || exists(e.dir) {
			t.Fatalf("%v: exit %d, %q", args, code, out.String())
		}
	}
	// The explicit flags keep their old behaviour: no header, hint or prompt.
	var out bytes.Buffer
	if code := run([]string{"--install"}, forbiddenReader{t}, &out); code != 0 {
		t.Fatalf("install %d: %s", code, out.String())
	}
	if text := out.String(); strings.Contains(text, "Timffle 連線小幫手") || strings.Contains(text, "--uninstall") || strings.Contains(text, "Press Enter") {
		t.Fatalf("--install output changed: %q", text)
	}
	e.checkInstalled(t)
	out.Reset()
	if code := run([]string{"--uninstall"}, forbiddenReader{t}, &out); code != 0 || strings.Contains(out.String(), "Press Enter") || exists(e.dir) {
		t.Fatalf("uninstall %d: %q", code, out.String())
	}
}
