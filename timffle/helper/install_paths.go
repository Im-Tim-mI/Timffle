package main

import (
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
)

// HOME is the explicit trust boundary. Resolve only HOME, not paths below it:
// macOS may spell a genuine home as /var/... while /var -> /private/var.
// Redirected HOME itself is supported; symlinks/reparse points in .config,
// .local, Library, AppData or other operated descendants are deliberately
// refused. Explicit data/config locations outside HOME must have link-free
// ancestry. We do not silently resolve an operated tree into another tree.
func canonicalHome(home string) (string, error) {
	if !filepath.IsAbs(home) {
		return "", errors.New("家目錄必須為絕對路徑 / HOME must be absolute")
	}
	real, err := filepath.EvalSymlinks(home)
	if err != nil {
		return "", err
	}
	info, err := os.Stat(real)
	if err != nil {
		return "", err
	}
	if !info.IsDir() {
		return "", errors.New("家目錄不是資料夾 / HOME is not a directory")
	}
	return real, nil
}

func relocateHomePath(oldHome, newHome, path string) string {
	if !filepath.IsAbs(path) {
		return path
	}
	rel, err := filepath.Rel(oldHome, path)
	if err == nil && rel != ".." && !strings.HasPrefix(rel, ".."+string(filepath.Separator)) && !filepath.IsAbs(rel) {
		return filepath.Join(newHome, rel)
	}
	return path
}

// Check every existing component, even when the leaf does not yet exist.
// Windows isLinkLike rejects ALL reparse points, not just symlink tags.
// Call this before the first mutation and again at individual write boundaries.
// This is a per-user installer, not a defence against a concurrent process
// with the same user's ability to replace arbitrary directories/handles.
func checkPathComponents(path string) error {
	if !filepath.IsAbs(path) {
		return fmt.Errorf("%s 不是絕對路徑 / is not an absolute path", path)
	}
	path = filepath.Clean(path)
	leaf := true
	for current := path; ; current = filepath.Dir(current) {
		info, err := os.Lstat(current)
		if err != nil && !errors.Is(err, fs.ErrNotExist) {
			return err
		}
		if err == nil {
			if isLinkLike(info) {
				return fmt.Errorf("%s 是連結或 reparse point，不會更動 / symlink or reparse point refused; left unchanged", current)
			}
			if !leaf && !info.IsDir() {
				return fmt.Errorf("%s 不是資料夾 / ancestor is not a directory", current)
			}
		}
		parent := filepath.Dir(current)
		if parent == current {
			return nil
		}
		leaf = false
	}
}

func (in *installer) checkLayoutPaths(receipt *installReceipt) error {
	l := in.layout
	paths := []string{l.dir, l.binary, l.binary + ".new", filepath.Join(l.dir, receiptName)}
	paths = append(paths, l.manifests...)
	if receipt != nil {
		paths = append(paths, receipt.Manifests...)
	}
	for _, path := range paths {
		if err := checkPathComponents(path); err != nil {
			return err
		}
	}
	return nil
}
