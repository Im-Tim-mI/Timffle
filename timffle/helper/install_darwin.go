//go:build darwin

package main

import (
	"errors"
	"io"
	"os"
	"os/exec"
	"path/filepath"
)

func platformInstaller(out io.Writer) (*installer, error) {
	self, err := os.Executable()
	if err != nil {
		return nil, err
	}
	home, err := os.UserHomeDir()
	if err != nil || !filepath.IsAbs(home) {
		return nil, errors.New("找不到家目錄 / cannot find the home folder")
	}
	realHome, err := canonicalHome(home)
	if err != nil {
		return nil, err
	}
	return &installer{layout: darwinLayout(realHome), self: self, copy: copyKeepingAttributes, out: out}, nil
}

// Google Chrome is always registered; other channels and Chromium only if used.
func darwinLayout(home string) installLayout {
	support := filepath.Join(home, "Library", "Application Support")
	dir := filepath.Join(support, "TimffleSocketHelper")
	l := installLayout{dir: dir, binary: filepath.Join(dir, "timffle-socket-helper")}
	for i, browser := range []string{"Google/Chrome", "Google/Chrome Beta", "Google/Chrome Dev", "Google/Chrome Canary", "Chromium"} {
		data := filepath.Join(support, filepath.FromSlash(browser))
		if i > 0 && !isDir(data) {
			continue
		}
		l.manifests = append(l.manifests, filepath.Join(data, "NativeMessagingHosts", hostName+".json"))
	}
	return l
}

// /bin/cp copies extended attributes, so the installed copy keeps the
// download's quarantine state (and any approval the user gave it).
func copyKeepingAttributes(src, dst string) error {
	return exec.Command("/bin/cp", src, dst).Run()
}
