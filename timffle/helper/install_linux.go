//go:build linux

package main

import (
	"errors"
	"io"
	"os"
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
	layout := linuxLayout(realHome, relocateHomePath(home, realHome, os.Getenv("XDG_DATA_HOME")), relocateHomePath(home, realHome, os.Getenv("XDG_CONFIG_HOME")), relocateHomePath(home, realHome, os.Getenv("CHROME_CONFIG_HOME")))
	return &installer{layout: layout, self: self, copy: copyPlain, out: out}, nil
}

// Chrome looks for user hosts in <user data dir>/NativeMessagingHosts, and its
// default user data dir is under CHROME_CONFIG_HOME, XDG_CONFIG_HOME or ~/.config.
// Google Chrome is always registered; other channels and Chromium only if used.
func linuxLayout(home, dataHome, configHome, chromeConfigHome string) installLayout {
	if !filepath.IsAbs(dataHome) {
		dataHome = filepath.Join(home, ".local", "share")
	}
	if !filepath.IsAbs(configHome) {
		configHome = filepath.Join(home, ".config")
	}
	if !filepath.IsAbs(chromeConfigHome) {
		chromeConfigHome = configHome
	}
	dir := filepath.Join(dataHome, "timffle-socket-helper")
	l := installLayout{dir: dir, binary: filepath.Join(dir, "timffle-socket-helper")}
	for i, browser := range []string{"google-chrome", "google-chrome-beta", "google-chrome-unstable", "google-chrome-canary", "chromium"} {
		data := filepath.Join(chromeConfigHome, browser)
		if i > 0 && !isDir(data) {
			continue
		}
		l.manifests = append(l.manifests, filepath.Join(data, "NativeMessagingHosts", hostName+".json"))
	}
	return l
}
