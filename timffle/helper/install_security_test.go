//go:build linux

package main

import (
	"errors"
	"os"
	"path/filepath"
	"testing"
)

func TestAncestorLinkRejectedBeforeInstallMutation(t *testing.T) {
	e := newInstallEnv(t)
	parent := filepath.Dir(e.manifest("google-chrome"))
	outside := filepath.Join(e.home, "outside")
	if err := os.MkdirAll(filepath.Dir(parent), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(outside, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(outside, parent); err != nil {
		t.Fatal(err)
	}
	if err := e.installer().install(); err == nil {
		t.Fatal("followed ancestor symlink")
	}
	if exists(e.dir()) || exists(filepath.Join(outside, hostName+".json")) {
		t.Fatal("mutated paths after refusing link")
	}
}

func TestAncestorLinkRejectedBeforeUninstallMutation(t *testing.T) {
	e := newInstallEnv(t)
	if err := e.installer().install(); err != nil {
		t.Fatal(err)
	}
	parent := filepath.Dir(e.manifest("google-chrome"))
	outside := filepath.Join(e.home, "moved")
	if err := os.Rename(parent, outside); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(outside, parent); err != nil {
		t.Fatal(err)
	}
	if err := e.installer().uninstall(); err == nil {
		t.Fatal("followed ancestor symlink")
	}
	if !exists(e.binary()) || !exists(filepath.Join(outside, hostName+".json")) || !exists(filepath.Join(e.dir(), receiptName)) {
		t.Fatal("partially uninstalled despite foreign link")
	}
}

func TestChangedBinaryPreservedOnInstallAndUninstall(t *testing.T) {
	e := newInstallEnv(t)
	if err := e.installer().install(); err != nil {
		t.Fatal(err)
	}
	manifest := readText(t, e.manifest("google-chrome"))
	receipt := readText(t, filepath.Join(e.dir(), receiptName))
	if err := os.WriteFile(e.binary(), []byte("foreign same-named file"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := e.installer().install(); err == nil {
		t.Fatal("overwrote changed binary")
	}
	if err := e.installer().uninstall(); err == nil {
		t.Fatal("deleted changed binary")
	}
	if readText(t, e.binary()) != "foreign same-named file" || readText(t, e.manifest("google-chrome")) != manifest || readText(t, filepath.Join(e.dir(), receiptName)) != receipt {
		t.Fatal("changed unrelated file/registration")
	}
}

func TestLegacyNewFilePreserved(t *testing.T) {
	e := newInstallEnv(t)
	if err := e.installer().install(); err != nil {
		t.Fatal(err)
	}
	path := e.binary() + ".new"
	if err := os.WriteFile(path, []byte("foreign staging file"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := e.installer().install(); err == nil {
		t.Fatal("accepted unowned staging")
	}
	if err := e.installer().uninstall(); err == nil {
		t.Fatal("deleted unowned staging")
	}
	if readText(t, path) != "foreign staging file" || !exists(e.binary()) || !exists(e.manifest("google-chrome")) {
		t.Fatal("did not preserve files")
	}
}

func TestLegacyReceiptRejectedWithoutMutation(t *testing.T) {
	e := newInstallEnv(t)
	if err := e.installer().install(); err != nil {
		t.Fatal(err)
	}
	p := filepath.Join(e.dir(), receiptName)
	if err := os.WriteFile(p, []byte("{\"schema\":1,\"host\":\"timffle_socket_helper\"}"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := e.installer().install(); err == nil {
		t.Fatal("accepted legacy receipt")
	}
	if err := e.installer().uninstall(); err == nil {
		t.Fatal("deleted via legacy receipt")
	}
	if !exists(e.binary()) || !exists(e.manifest("google-chrome")) {
		t.Fatal("changed files")
	}
}

func TestFailedCopyCleansOnlyOwnStagingAndAllowsRepair(t *testing.T) {
	e := newInstallEnv(t)
	if err := e.installer().install(); err != nil {
		t.Fatal(err)
	}
	e.writeSelf("helper v2")
	in := e.installer()
	in.copy = func(src, dst string) error {
		if err := os.WriteFile(dst, []byte("partial"), 0o700); err != nil {
			return err
		}
		return errors.New("injected copy failure")
	}
	if err := in.install(); err == nil {
		t.Fatal("copy failure ignored")
	}
	if readText(t, e.binary()) != "helper v1" {
		t.Fatal("destroyed old executable")
	}
	noLeftovers(t, e.dir())
	if err := e.installer().install(); err != nil {
		t.Fatal(err)
	}
	if readText(t, e.binary()) != "helper v2" {
		t.Fatal("repair did not upgrade")
	}
	receipt, err := readReceipt(e.dir())
	if err != nil {
		t.Fatal(err)
	}
	want, err := digestString(e.binary())
	if err != nil {
		t.Fatal(err)
	}
	if receipt.Schema != 2 || receipt.InstalledBinarySHA256 != want || receipt.PendingBinarySHA256 != "" {
		t.Fatal("receipt does not bind installed bytes")
	}
}

func TestCopyMismatchDoesNotReplaceOwnedBinary(t *testing.T) {
	e := newInstallEnv(t)
	if err := e.installer().install(); err != nil {
		t.Fatal(err)
	}
	// A same-bytes reinstall skips the copy (fc796a33e), so the copy only runs,
	// and can only be corrupt, when the installer is a different build.
	e.writeSelf("helper v2")
	in := e.installer()
	in.copy = func(src, dst string) error { return os.WriteFile(dst, []byte("corrupt"), 0o700) }
	if err := in.install(); err == nil {
		t.Fatal("accepted corrupt copy")
	}
	if readText(t, e.binary()) != "helper v1" {
		t.Fatal("replaced executable")
	}
	noLeftovers(t, e.dir())
}

func TestHomeAliasCanonicalizedWithoutFollowingDescendantLinks(t *testing.T) {
	home := t.TempDir()
	alias := filepath.Join(t.TempDir(), "home-link")
	if err := os.Symlink(home, alias); err != nil {
		t.Fatal(err)
	}
	real, err := canonicalHome(alias)
	if err != nil || real != home {
		t.Fatalf("canonical home: %q %v", real, err)
	}
	path := relocateHomePath(alias, real, filepath.Join(alias, ".config", "google-chrome"))
	if path != filepath.Join(home, ".config", "google-chrome") {
		t.Fatal("home path not relocated")
	}
}
