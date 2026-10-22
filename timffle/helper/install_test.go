//go:build linux

package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"
)

type fakeRegistry map[string]string

func (r fakeRegistry) get(key string) (string, bool, error) { v, ok := r[key]; return v, ok, nil }
func (r fakeRegistry) set(key, value string) error          { r[key] = value; return nil }
func (r fakeRegistry) removeDefault(key, expected string) (bool, error) {
	if value, exists := r[key]; exists && samePath(value, expected) {
		delete(r, key)
		return true, nil
	}
	return false, nil
}

type installEnv struct {
	t                  *testing.T
	home, data, config string
	self               string
	out                bytes.Buffer
}

func newInstallEnv(t *testing.T) *installEnv {
	root := t.TempDir()
	e := &installEnv{t: t, home: root, data: filepath.Join(root, "data"), config: filepath.Join(root, "config"), self: filepath.Join(root, "download", "timffle-socket-helper")}
	e.writeSelf("helper v1")
	return e
}

func (e *installEnv) writeSelf(content string) {
	e.t.Helper()
	if err := os.MkdirAll(filepath.Dir(e.self), 0o755); err != nil {
		e.t.Fatal(err)
	}
	if err := os.WriteFile(e.self, []byte(content), 0o755); err != nil {
		e.t.Fatal(err)
	}
}

func (e *installEnv) installer() *installer {
	return &installer{layout: linuxLayout(e.home, e.data, e.config, ""), self: e.self, copy: copyPlain, out: &e.out}
}

func (e *installEnv) dir() string    { return filepath.Join(e.data, "timffle-socket-helper") }
func (e *installEnv) binary() string { return filepath.Join(e.dir(), "timffle-socket-helper") }
func (e *installEnv) manifest(browser string) string {
	return filepath.Join(e.config, browser, "NativeMessagingHosts", hostName+".json")
}

func readText(t *testing.T, path string) string {
	t.Helper()
	b, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

func exists(path string) bool {
	_, err := os.Lstat(path)
	return err == nil
}

func noLeftovers(t *testing.T, dirs ...string) {
	t.Helper()
	for _, dir := range dirs {
		entries, _ := os.ReadDir(dir)
		for _, entry := range entries {
			if strings.Contains(entry.Name(), ".tmp-") || strings.HasSuffix(entry.Name(), ".new") || strings.HasPrefix(entry.Name(), ".install-") {
				t.Errorf("leftover %s in %s", entry.Name(), dir)
			}
		}
	}
}

func TestInstallWritesOwnedFiles(t *testing.T) {
	e := newInstallEnv(t)
	if err := e.installer().install(); err != nil {
		t.Fatal(err)
	}
	if got := readText(t, e.binary()); got != "helper v1" {
		t.Fatalf("binary %q", got)
	}
	if info, _ := os.Stat(e.binary()); info.Mode().Perm()&0o111 == 0 {
		t.Fatal("binary not executable")
	}
	var m hostManifest
	if err := json.Unmarshal([]byte(readText(t, e.manifest("google-chrome"))), &m); err != nil {
		t.Fatal(err)
	}
	want := hostManifest{Name: hostName, Description: hostDescription, Path: e.binary(), Type: "stdio", AllowedOrigins: []string{callerOrigin}}
	if !reflect.DeepEqual(m, want) {
		t.Fatalf("manifest %+v", m)
	}
	r, err := readReceipt(e.dir())
	if err != nil || r == nil || r.Version != version || !reflect.DeepEqual(r.Manifests, []string{e.manifest("google-chrome")}) {
		t.Fatalf("receipt %+v %v", r, err)
	}
	if exists(e.manifest("chromium")) {
		t.Fatal("registered an unused browser")
	}
	noLeftovers(t, e.dir(), filepath.Dir(e.manifest("google-chrome")))
}

func TestReinstallUpgradesAndRepairs(t *testing.T) {
	e := newInstallEnv(t)
	if err := e.installer().install(); err != nil {
		t.Fatal(err)
	}
	e.writeSelf("helper v2")
	if err := e.installer().install(); err != nil {
		t.Fatal(err)
	}
	if got := readText(t, e.binary()); got != "helper v2" {
		t.Fatalf("not upgraded: %q", got)
	}
	// An interrupted install leaves the receipt first; it must be repairable.
	if err := os.Remove(e.binary()); err != nil {
		t.Fatal(err)
	}
	if err := os.Remove(e.manifest("google-chrome")); err != nil {
		t.Fatal(err)
	}
	if err := e.installer().install(); err != nil {
		t.Fatal(err)
	}
	if readText(t, e.binary()) != "helper v2" || !exists(e.manifest("google-chrome")) {
		t.Fatal("not repaired")
	}
	noLeftovers(t, e.dir())
}

// Installing the same bytes again (a same-version reinstall, or a repeated
// double-click while the extension keeps probing the installed helper) must
// not replace a file that may be running; everything else is still redone.
func TestReinstallSameBytesSkipsCopy(t *testing.T) {
	e := newInstallEnv(t)
	if err := e.installer().install(); err != nil {
		t.Fatal(err)
	}
	before, err := os.Stat(e.binary())
	if err != nil {
		t.Fatal(err)
	}
	if err := os.Remove(e.manifest("google-chrome")); err != nil {
		t.Fatal(err)
	}
	copies := 0
	in := e.installer()
	in.copy = func(src, dst string) error { copies++; return copyPlain(src, dst) }
	if err := in.install(); err != nil {
		t.Fatal(err)
	}
	after, err := os.Stat(e.binary())
	if err != nil {
		t.Fatal(err)
	}
	if copies != 0 || !os.SameFile(before, after) || readText(t, e.binary()) != "helper v1" {
		t.Fatalf("identical helper replaced (copies %d)", copies)
	}
	if !exists(e.manifest("google-chrome")) {
		t.Fatal("manifest not rewritten")
	}
	want, _ := digestString(e.self)
	if r, err := readReceipt(e.dir()); err != nil || r == nil || r.InstalledBinarySHA256 != want || r.PendingBinarySHA256 != "" {
		t.Fatalf("receipt %+v %v", r, err)
	}
	noLeftovers(t, e.dir())
	// Different bytes are still copied.
	e.writeSelf("helper v2")
	if err := in.install(); err != nil {
		t.Fatal(err)
	}
	if copies != 1 || readText(t, e.binary()) != "helper v2" {
		t.Fatalf("upgrade not copied (copies %d)", copies)
	}
}

func TestRenameRetrying(t *testing.T) {
	transient := errors.New("transient")
	permanent := errors.New("permanent")
	isTransient := func(err error) bool { return errors.Is(err, transient) }
	failing := func(n int, err error) (func(string, string) error, *int) {
		calls := 0
		return func(string, string) error {
			calls++
			if calls <= n {
				return err
			}
			return nil
		}, &calls
	}
	rename, calls := failing(3, transient)
	if err := renameRetrying(rename, "a", "b", isTransient, 12, time.Millisecond); err != nil || *calls != 4 {
		t.Fatalf("transient failures not retried: %v after %d calls", err, *calls)
	}
	rename, calls = failing(100, transient)
	if err := renameRetrying(rename, "a", "b", isTransient, 12, time.Millisecond); !errors.Is(err, transient) || *calls != 13 {
		t.Fatalf("retry not bounded: %v after %d calls", err, *calls)
	}
	rename, calls = failing(1, permanent)
	if err := renameRetrying(rename, "a", "b", isTransient, 12, time.Millisecond); !errors.Is(err, permanent) || *calls != 1 {
		t.Fatalf("permanent failure retried: %v after %d calls", err, *calls)
	}
	rename, calls = failing(0, nil)
	if err := renameRetrying(rename, "a", "b", isTransient, 12, time.Millisecond); err != nil || *calls != 1 {
		t.Fatalf("success repeated: %v after %d calls", err, *calls)
	}
	// On this platform no error is transient: a failing rename fails at once.
	if transientReplaceError(&os.LinkError{Op: "rename", Old: "a", New: "b", Err: errors.New("busy")}) {
		t.Fatal("retried on a platform without sharing violations")
	}
	if err := replaceFile(filepath.Join(t.TempDir(), "missing"), filepath.Join(t.TempDir(), "dst")); err == nil {
		t.Fatal("renamed a missing file")
	}
}

func TestRunningInstalledCopyReinstalls(t *testing.T) {
	e := newInstallEnv(t)
	if err := e.installer().install(); err != nil {
		t.Fatal(err)
	}
	in := e.installer()
	in.self = e.binary()
	in.copy = func(string, string) error { t.Fatal("copied a file onto itself"); return nil }
	if err := in.install(); err != nil {
		t.Fatal(err)
	}
}

func TestRefusesForeignManifestWithoutChanges(t *testing.T) {
	e := newInstallEnv(t)
	foreign := `{"name":"timffle_socket_helper","path":"/opt/other/host","type":"stdio"}`
	if err := os.MkdirAll(filepath.Dir(e.manifest("google-chrome")), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(e.manifest("google-chrome"), []byte(foreign), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := e.installer().install(); err == nil {
		t.Fatal("replaced a foreign manifest")
	}
	if readText(t, e.manifest("google-chrome")) != foreign || exists(e.dir()) {
		t.Fatal("changed something before refusing")
	}
}

func TestRefusesForeignDirectory(t *testing.T) {
	e := newInstallEnv(t)
	if err := os.MkdirAll(e.dir(), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(e.dir(), "timffle-socket-helper"), []byte("someone else"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := e.installer().install(); err == nil {
		t.Fatal("took over a foreign folder")
	}
	if err := e.installer().uninstall(); err == nil {
		t.Fatal("uninstalled a foreign folder")
	}
	if readText(t, e.binary()) != "someone else" || exists(e.manifest("google-chrome")) {
		t.Fatal("changed a foreign folder")
	}
}

func TestRefusesLinks(t *testing.T) {
	e := newInstallEnv(t)
	target := filepath.Join(e.home, "elsewhere.json")
	if err := os.WriteFile(target, []byte("keep"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Dir(e.manifest("google-chrome")), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(target, e.manifest("google-chrome")); err != nil {
		t.Fatal(err)
	}
	if err := e.installer().install(); err == nil {
		t.Fatal("wrote through a link")
	}
	if readText(t, target) != "keep" || exists(e.dir()) {
		t.Fatal("changed something before refusing")
	}

	e = newInstallEnv(t)
	if err := e.installer().install(); err != nil {
		t.Fatal(err)
	}
	if err := os.Remove(e.binary()); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(target, e.binary()); err != nil {
		t.Fatal(err)
	}
	if err := e.installer().install(); err == nil {
		t.Fatal("replaced a linked binary")
	}
	if err := e.installer().uninstall(); err == nil {
		t.Fatal("removed a linked binary")
	}
	if readText(t, target) != "keep" {
		t.Fatal("followed a link")
	}
}

func TestOptionalBrowsersAndCleanUninstall(t *testing.T) {
	e := newInstallEnv(t)
	if err := os.MkdirAll(filepath.Join(e.config, "chromium"), 0o700); err != nil {
		t.Fatal(err)
	}
	if err := e.installer().install(); err != nil {
		t.Fatal(err)
	}
	if !exists(e.manifest("google-chrome")) || !exists(e.manifest("chromium")) || exists(e.manifest("google-chrome-beta")) {
		t.Fatal("wrong browser registrations")
	}
	// Chromium removed since: the receipt still lets uninstall find its file.
	e.out.Reset()
	if err := e.installer().uninstall(); err != nil {
		t.Fatal(err)
	}
	for _, path := range []string{e.manifest("google-chrome"), e.manifest("chromium"), e.dir()} {
		if exists(path) {
			t.Errorf("left %s", path)
		}
	}
	if !strings.Contains(e.out.String(), "removed") {
		t.Fatalf("output %q", e.out.String())
	}
	if !exists(filepath.Dir(e.manifest("google-chrome"))) {
		t.Fatal("removed the browser's own folder")
	}
}

func TestUninstallKeepsForeignFiles(t *testing.T) {
	e := newInstallEnv(t)
	if err := e.installer().install(); err != nil {
		t.Fatal(err)
	}
	foreign := `{"name":"timffle_socket_helper","path":"/opt/other/host"}`
	if err := os.WriteFile(e.manifest("google-chrome"), []byte(foreign), 0o644); err != nil {
		t.Fatal(err)
	}
	notes := filepath.Join(e.dir(), "notes.txt")
	if err := os.WriteFile(notes, []byte("mine"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := e.installer().uninstall(); err != nil {
		t.Fatal(err)
	}
	if readText(t, e.manifest("google-chrome")) != foreign || readText(t, notes) != "mine" {
		t.Fatal("removed foreign files")
	}
	if exists(e.binary()) || exists(filepath.Join(e.dir(), receiptName)) {
		t.Fatal("left owned files")
	}
}

func TestUninstallWhenNotInstalled(t *testing.T) {
	e := newInstallEnv(t)
	if err := e.installer().uninstall(); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(e.out.String(), "not installed") {
		t.Fatalf("output %q", e.out.String())
	}
}

func TestRegistryOwnership(t *testing.T) {
	root := t.TempDir()
	self := filepath.Join(root, "self.exe")
	if err := os.WriteFile(self, []byte("helper"), 0o755); err != nil {
		t.Fatal(err)
	}
	dir := filepath.Join(root, "TimffleSocketHelper")
	layout := installLayout{dir: dir, binary: filepath.Join(dir, "helper.exe"), manifests: []string{filepath.Join(dir, hostName+".json")}, registry: []string{`Software\A\` + hostName, `Software\B\` + hostName}}
	reg := fakeRegistry{`Software\B\` + hostName: `C:\other\host.json`}
	var out bytes.Buffer
	in := &installer{layout: layout, self: self, copy: copyPlain, reg: reg, out: &out}
	if err := in.install(); err == nil || exists(dir) {
		t.Fatal("took over a foreign registration")
	}
	delete(reg, `Software\B\`+hostName)
	if err := in.install(); err != nil {
		t.Fatal(err)
	}
	if reg[`Software\A\`+hostName] != layout.manifests[0] || reg[`Software\B\`+hostName] != layout.manifests[0] {
		t.Fatalf("registry %v", reg)
	}
	reg[`Software\B\`+hostName] = `C:\other\host.json`
	if err := in.uninstall(); err != nil {
		t.Fatal(err)
	}
	if _, ok := reg[`Software\A\`+hostName]; ok || reg[`Software\B\`+hostName] != `C:\other\host.json` || exists(dir) {
		t.Fatalf("registry %v", reg)
	}
}

func TestCommandLineInstallAndUninstall(t *testing.T) {
	root := t.TempDir()
	t.Setenv("HOME", root)
	t.Setenv("XDG_DATA_HOME", filepath.Join(root, "share"))
	t.Setenv("XDG_CONFIG_HOME", filepath.Join(root, "conf"))
	t.Setenv("CHROME_CONFIG_HOME", "")
	var out bytes.Buffer
	if code := run([]string{"--install"}, strings.NewReader(""), &out); code != 0 {
		t.Fatalf("install %d: %s", code, out.String())
	}
	binary := filepath.Join(root, "share", "timffle-socket-helper", "timffle-socket-helper")
	manifest := filepath.Join(root, "conf", "google-chrome", "NativeMessagingHosts", hostName+".json")
	self, _ := os.Executable()
	want, _ := fileDigest(self)
	if got, err := fileDigest(binary); err != nil || got != want {
		t.Fatalf("installed copy differs: %v", err)
	}
	if !strings.Contains(readText(t, manifest), `"path": "`+binary+`"`) {
		t.Fatal(readText(t, manifest))
	}
	if code := run([]string{"--uninstall"}, strings.NewReader(""), &out); code != 0 {
		t.Fatalf("uninstall %d: %s", code, out.String())
	}
	if exists(binary) || exists(manifest) {
		t.Fatal("not removed")
	}
	// Extra arguments are never an installer request.
	if code := run([]string{"--install", "x"}, strings.NewReader(""), &out); code != 1 || exists(binary) {
		t.Fatal("accepted a malformed installer request")
	}
}
