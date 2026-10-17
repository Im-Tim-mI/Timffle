//go:build !linux && !darwin && !windows

package main

import (
	"errors"
	"io"
)

func platformInstaller(io.Writer) (*installer, error) {
	return nil, errors.New("此平台不支援自動安裝 / automatic installation is not supported on this platform")
}
