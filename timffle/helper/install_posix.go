//go:build !windows

package main

import (
	"io"
	"os"
	"path/filepath"
)

func samePath(a, b string) bool { return filepath.Clean(a) == filepath.Clean(b) }

func isLinkLike(info os.FileInfo) bool { return info.Mode()&os.ModeSymlink != 0 }

// A rename over a running helper succeeds here; nothing is worth retrying.
func transientReplaceError(error) bool { return false }

func isDir(path string) bool {
	info, err := os.Stat(path)
	return err == nil && info.IsDir()
}

func copyPlain(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	out, err := os.OpenFile(dst, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o700)
	if err != nil {
		return err
	}
	_, err = io.Copy(out, in)
	if err == nil {
		err = out.Sync()
	}
	if closeErr := out.Close(); err == nil {
		err = closeErr
	}
	return err
}
