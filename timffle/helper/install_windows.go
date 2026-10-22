//go:build windows

package main

import (
	"errors"
	"io"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"unsafe"
)

// kernel32 and advapi32 are KnownDLLs, always loaded from System32.
var (
	procCopyFileW       = syscall.NewLazyDLL("kernel32.dll").NewProc("CopyFileW")
	advapi32            = syscall.NewLazyDLL("advapi32.dll")
	procRegCreateKeyExW = advapi32.NewProc("RegCreateKeyExW")
	procRegSetValueExW  = advapi32.NewProc("RegSetValueExW")
	procRegDeleteValueW = advapi32.NewProc("RegDeleteValueW")
)

const chromiumKey = `Software\Chromium`

const errorSharingViolation = syscall.Errno(32) // ERROR_SHARING_VIOLATION

// transientReplaceError reports the errors MoveFileEx returns while another
// process (a running copy of the helper) still holds the file being replaced.
func transientReplaceError(err error) bool {
	return errors.Is(err, errorSharingViolation) || errors.Is(err, syscall.ERROR_ACCESS_DENIED)
}

func platformInstaller(out io.Writer) (*installer, error) {
	self, err := os.Executable()
	if err != nil {
		return nil, err
	}
	local, err := os.UserCacheDir() // %LOCALAPPDATA%
	if err != nil || !filepath.IsAbs(local) {
		return nil, errors.New("找不到 %LOCALAPPDATA% / cannot find %LOCALAPPDATA%")
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return nil, err
	}
	trustedHome, err := canonicalHome(home)
	if err != nil {
		return nil, err
	}
	// Resolve only the trusted home, not LOCALAPPDATA: junctions/reparse
	// points below home must remain visible to the common path checks.
	local = relocateHomePath(home, trustedHome, local)
	reg := winRegistry{}
	chromium, err := reg.keyExists(chromiumKey)
	if err != nil {
		return nil, err
	}
	return &installer{layout: windowsLayout(local, chromium), self: self, copy: copyFileW, reg: reg, out: out}, nil
}

// Chrome reads the manifest path from the default value of an HKCU key; all
// Chrome channels share Google Chrome's key. Chromium only if used.
func windowsLayout(localAppData string, chromium bool) installLayout {
	dir := filepath.Join(localAppData, "TimffleSocketHelper")
	l := installLayout{
		dir:       dir,
		binary:    filepath.Join(dir, "timffle-socket-helper.exe"),
		manifests: []string{filepath.Join(dir, hostName+".json")},
		registry:  []string{`Software\Google\Chrome\NativeMessagingHosts\` + hostName},
	}
	if chromium {
		l.registry = append(l.registry, chromiumKey+`\NativeMessagingHosts\`+hostName)
	}
	return l
}

func samePath(a, b string) bool { return strings.EqualFold(filepath.Clean(a), filepath.Clean(b)) }

func isLinkLike(info os.FileInfo) bool {
	if info.Mode()&os.ModeSymlink != 0 {
		return true
	}
	// Junctions and other reparse points need not have ModeSymlink set.
	data, ok := info.Sys().(*syscall.Win32FileAttributeData)
	return ok && data.FileAttributes&syscall.FILE_ATTRIBUTE_REPARSE_POINT != 0
}

// CopyFileW keeps alternate data streams, including the download's
// Zone.Identifier mark. It never overwrites an existing file.
func copyFileW(src, dst string) error {
	s, err := syscall.UTF16PtrFromString(src)
	if err != nil {
		return err
	}
	d, err := syscall.UTF16PtrFromString(dst)
	if err != nil {
		return err
	}
	if r, _, err := procCopyFileW.Call(uintptr(unsafe.Pointer(s)), uintptr(unsafe.Pointer(d)), 1); r == 0 {
		return err
	}
	return nil
}

type winRegistry struct{}

// keyExists is only for Chromium detection; a browser key normally has no
// default value. Registration ownership instead uses get's value existence.
func (winRegistry) keyExists(key string) (bool, error) {
	k, err := syscall.UTF16PtrFromString(key)
	if err != nil {
		return false, err
	}
	var h syscall.Handle
	if err := syscall.RegOpenKeyEx(syscall.HKEY_CURRENT_USER, k, 0, syscall.KEY_QUERY_VALUE, &h); err != nil {
		if errors.Is(err, syscall.ERROR_FILE_NOT_FOUND) {
			return false, nil
		}
		return false, err
	}
	defer syscall.RegCloseKey(h)
	return true, nil
}

// get returns the key's default value. A key with only named values or
// subkeys has no default value and therefore returns exists=false.
func (winRegistry) get(key string) (string, bool, error) {
	k, err := syscall.UTF16PtrFromString(key)
	if err != nil {
		return "", false, err
	}
	var h syscall.Handle
	if err := syscall.RegOpenKeyEx(syscall.HKEY_CURRENT_USER, k, 0, syscall.KEY_QUERY_VALUE, &h); err != nil {
		if errors.Is(err, syscall.ERROR_FILE_NOT_FOUND) {
			return "", false, nil
		}
		return "", false, err
	}
	defer syscall.RegCloseKey(h)
	return queryDefaultValue(h)
}

// queryDefaultValue reads through an already-open handle, so removal checks
// ownership on the exact key whose default value it will delete.
func queryDefaultValue(h syscall.Handle) (string, bool, error) {
	var kind, size uint32
	if err := syscall.RegQueryValueEx(h, nil, nil, &kind, nil, &size); err != nil {
		if errors.Is(err, syscall.ERROR_FILE_NOT_FOUND) {
			return "", false, nil
		}
		return "", true, err
	}
	if kind != syscall.REG_SZ || size > 64<<10 || size%2 != 0 {
		// Never ours: report a value that cannot match any path.
		return "\x00", true, nil
	}
	buf := make([]uint16, size/2+1)
	if err := syscall.RegQueryValueEx(h, nil, nil, &kind, (*byte)(unsafe.Pointer(&buf[0])), &size); err != nil {
		if errors.Is(err, syscall.ERROR_FILE_NOT_FOUND) {
			return "", false, nil
		}
		return "", true, err
	}
	// The type/length may have changed between the two queries. Never treat
	// a different type or a malformed/truncated string as an owned path.
	if kind != syscall.REG_SZ || size > 64<<10 || size%2 != 0 || size/2 > uint32(len(buf)) {
		return "\x00", true, nil
	}
	buf = buf[:size/2]
	if len(buf) > 0 && buf[len(buf)-1] == 0 {
		buf = buf[:len(buf)-1]
	}
	for _, c := range buf {
		if c == 0 {
			return "\x00", true, nil
		}
	}
	return syscall.UTF16ToString(buf), true, nil
}

func (winRegistry) set(key, value string) error {
	k, err := syscall.UTF16PtrFromString(key)
	if err != nil {
		return err
	}
	v, err := syscall.UTF16FromString(value)
	if err != nil {
		return err
	}
	var h syscall.Handle
	var disposition uint32
	if r, _, _ := procRegCreateKeyExW.Call(uintptr(syscall.HKEY_CURRENT_USER), uintptr(unsafe.Pointer(k)), 0, 0, 0,
		uintptr(syscall.KEY_SET_VALUE|syscall.KEY_QUERY_VALUE), 0, uintptr(unsafe.Pointer(&h)), uintptr(unsafe.Pointer(&disposition))); r != 0 {
		return syscall.Errno(r)
	}
	defer syscall.RegCloseKey(h)
	if r, _, _ := procRegSetValueExW.Call(uintptr(h), 0, 0, syscall.REG_SZ, uintptr(unsafe.Pointer(&v[0])), uintptr(len(v)*2)); r != 0 {
		return syscall.Errno(r)
	}
	return nil
}

// removeDefault never deletes a key, its named values, or its subkeys. Check
// ownership again using the same handle used for RegDeleteValueW, rather than
// relying on an earlier path-based query or a racy enumeration of the key.
func (winRegistry) removeDefault(key, expected string) (bool, error) {
	k, err := syscall.UTF16PtrFromString(key)
	if err != nil {
		return false, err
	}
	var h syscall.Handle
	if err := syscall.RegOpenKeyEx(syscall.HKEY_CURRENT_USER, k, 0, syscall.KEY_QUERY_VALUE|syscall.KEY_SET_VALUE, &h); err != nil {
		if errors.Is(err, syscall.ERROR_FILE_NOT_FOUND) {
			return false, nil
		}
		return false, err
	}
	defer syscall.RegCloseKey(h)
	value, exists, err := queryDefaultValue(h)
	if err != nil || !exists {
		return false, err
	}
	if !samePath(value, expected) {
		return false, nil
	}
	// A nil name denotes only the default value. Even an empty key remains.
	if r, _, _ := procRegDeleteValueW.Call(uintptr(h), 0); r != 0 {
		if syscall.Errno(r) == syscall.ERROR_FILE_NOT_FOUND {
			return false, nil
		}
		return false, syscall.Errno(r)
	}
	return true, nil
}
