package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"runtime"
	"time"
)

// Per-user installation, built into the helper so that no platform needs
// Python or PowerShell. Nothing here runs as a service, needs admin rights,
// touches download security marks, or replaces/deletes files it does not own.

const (
	hostName        = "timffle_socket_helper"
	hostDescription = "Timffle socket helper"
	receiptName     = "install.json"
	maxSmallFile    = 64 << 10
)

// installLayout is where this platform keeps the helper and where browsers
// look for native messaging host manifests.
type installLayout struct {
	dir       string   // created and owned by the installer
	binary    string   // the installed helper
	manifests []string // host manifests; on Windows one file inside dir
	registry  []string // Windows only: HKCU keys whose default value is manifests[0]
}

type registry interface {
	get(key string) (value string, exists bool, err error)
	set(key, value string) error
	removeDefault(key, expected string) (removed bool, err error)
}

type installer struct {
	layout installLayout
	self   string // the running helper, which copies itself
	copy   func(src, dst string) error
	reg    registry // nil where the platform has no registry
	out    io.Writer
}

type hostManifest struct {
	Name           string   `json:"name"`
	Description    string   `json:"description"`
	Path           string   `json:"path"`
	Type           string   `json:"type"`
	AllowedOrigins []string `json:"allowed_origins"`
}

// Schema 2 binds ownership to bytes, not merely a reserved filename. A pending
// digest journals an atomic binary replacement: after interruption, only the
// explicitly recorded old/new bytes are recognized, never arbitrary files.
type installReceipt struct {
	Schema                int      `json:"schema"`
	Host                  string   `json:"host"`
	Version               string   `json:"version"`
	Binary                string   `json:"binary"`
	InstalledBinarySHA256 string   `json:"installedBinarySHA256"`
	PendingBinarySHA256   string   `json:"pendingBinarySHA256,omitempty"`
	Manifests             []string `json:"manifests"`
	Registry              []string `json:"registry,omitempty"`
}

func runInstaller(out io.Writer, remove bool) int {
	in, err := platformInstaller(out)
	if err == nil {
		if remove {
			err = in.uninstall()
		} else {
			err = in.install()
		}
	}
	if err != nil {
		fmt.Fprintln(out, "錯誤 / Error:", err)
		return 1
	}
	return 0
}

func (l installLayout) manifestBytes() []byte {
	b, err := json.MarshalIndent(hostManifest{
		Name:           hostName,
		Description:    hostDescription,
		Path:           l.binary,
		Type:           "stdio",
		AllowedOrigins: []string{callerOrigin},
	}, "", "  ")
	if err != nil {
		panic(err)
	}
	return append(b, '\n')
}

// existingRegular never follows a link: a link or special file at a path we
// would write is someone else's, so it is refused rather than replaced.
func existingRegular(path string) (bool, error) {
	info, err := os.Lstat(path)
	if errors.Is(err, fs.ErrNotExist) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	if isLinkLike(info) || !info.Mode().IsRegular() {
		return true, fmt.Errorf("%s 不是一般檔案（可能是連結），不會更動 / is not a regular file; left unchanged", path)
	}
	return true, nil
}

func readSmall(path string) ([]byte, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	data, err := io.ReadAll(io.LimitReader(f, maxSmallFile+1))
	if err == nil && len(data) > maxSmallFile {
		err = fmt.Errorf("%s 太大 / is too large", path)
	}
	return data, err
}

// ownedManifest reports whether path names this host and points at our
// installed binary, i.e. whether we may replace or remove it.
func ownedManifest(path, binary string) (exists, owned bool, err error) {
	exists, err = existingRegular(path)
	if !exists || err != nil {
		return exists, false, err
	}
	data, err := readSmall(path)
	if err != nil {
		return true, false, err
	}
	var m hostManifest
	if json.Unmarshal(data, &m) != nil {
		return true, false, nil
	}
	return true, m.Name == hostName && samePath(m.Path, binary), nil
}

func readReceipt(dir string) (*installReceipt, error) {
	path := filepath.Join(dir, receiptName)
	exists, err := existingRegular(path)
	if !exists || err != nil {
		return nil, err
	}
	data, err := readSmall(path)
	if err != nil {
		return nil, err
	}
	var r installReceipt
	if json.Unmarshal(data, &r) != nil || r.Host != hostName {
		return nil, errors.New("安裝收據無效，保留所有檔案 / invalid install receipt; all files preserved")
	}
	if r.Schema != 2 {
		return nil, errors.New("不支援舊草稿安裝收據，保留所有檔案 / unsupported legacy draft receipt schema; all files preserved")
	}
	if !validDigest(r.InstalledBinarySHA256) || (r.PendingBinarySHA256 != "" && !validDigest(r.PendingBinarySHA256)) {
		return nil, errors.New("安裝收據缺少有效雜湊，保留所有檔案 / invalid receipt binary hash; all files preserved")
	}
	return &r, nil
}

func writeFileAtomic(path string, data []byte, perm fs.FileMode) error {
	if err := checkPathComponents(path); err != nil {
		return err
	}
	if _, err := existingRegular(path); err != nil {
		return err
	}
	f, err := os.CreateTemp(filepath.Dir(path), "."+filepath.Base(path)+".tmp-*")
	if err != nil {
		return err
	}
	tmp := f.Name()
	defer os.Remove(tmp) // Fails harmlessly after the rename.
	_, err = f.Write(data)
	if err == nil {
		err = f.Sync()
	}
	if closeErr := f.Close(); err == nil {
		err = closeErr
	}
	if err == nil {
		err = os.Chmod(tmp, perm)
	}
	if err == nil {
		err = checkPathComponents(path)
	}
	if err == nil {
		err = os.Rename(tmp, path)
	}
	return err
}

func fileDigest(path string) ([sha256.Size]byte, error) {
	var sum [sha256.Size]byte
	f, err := os.Open(path)
	if err != nil {
		return sum, err
	}
	defer f.Close()
	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return sum, err
	}
	copy(sum[:], h.Sum(nil))
	return sum, nil
}

func sameFile(a, b string) bool {
	ai, err := os.Stat(a)
	if err != nil {
		return false
	}
	bi, err := os.Stat(b)
	return err == nil && os.SameFile(ai, bi)
}

const (
	replaceRetries = 12
	replaceDelay   = 250 * time.Millisecond
)

// replaceFile moves tmp over dst. An installed helper that is still running
// (the extension probes it every two seconds while its install window is
// open, or a game is connected) makes Windows refuse to replace its file for
// a moment; such transient errors are retried for a few seconds instead of
// failing the whole install. Other platforms never report them.
func replaceFile(tmp, dst string) error {
	return renameRetrying(os.Rename, tmp, dst, transientReplaceError, replaceRetries, replaceDelay)
}

func renameRetrying(rename func(oldpath, newpath string) error, tmp, dst string, transient func(error) bool, retries int, delay time.Duration) error {
	err := rename(tmp, dst)
	for i := 0; i < retries && err != nil && transient(err); i++ {
		time.Sleep(delay)
		err = rename(tmp, dst)
	}
	return err
}

func appendMissing(list []string, more ...string) []string {
	for _, item := range more {
		found := false
		for _, have := range list {
			if samePath(have, item) {
				found = true
				break
			}
		}
		if !found {
			list = append(list, item)
		}
	}
	return list
}

func validDigest(value string) bool {
	b, err := hex.DecodeString(value)
	return err == nil && len(b) == sha256.Size && len(value) == sha256.Size*2
}

func digestString(path string) (string, error) {
	sum, err := fileDigest(path)
	return hex.EncodeToString(sum[:]), err
}

func saveReceipt(dir string, receipt installReceipt) error {
	data, err := json.MarshalIndent(receipt, "", "  ")
	if err != nil {
		return err
	}
	return writeFileAtomic(filepath.Join(dir, receiptName), append(data, '\n'), 0o644)
}

func verifyOwnedBinary(path string, receipt *installReceipt) error {
	if err := checkPathComponents(path); err != nil {
		return err
	}
	exists, err := existingRegular(path)
	if err != nil || !exists {
		return err
	}
	got, err := digestString(path)
	if err != nil {
		return err
	}
	if receipt == nil || (got != receipt.InstalledBinarySHA256 && got != receipt.PendingBinarySHA256) {
		return fmt.Errorf("%s 內容已更動，不會覆寫或刪除 / binary hash differs; file preserved", path)
	}
	return nil
}

// Shared install/uninstall preflight runs before ANY mutation (including
// registration removal). Legacy fixed .new files have no ownership evidence.
func (in *installer) inspectOwnedDirectory() (*installReceipt, bool, error) {
	l := in.layout
	if err := in.checkLayoutPaths(nil); err != nil {
		return nil, false, err
	}
	if _, err := os.Lstat(l.binary + ".new"); err == nil {
		return nil, false, fmt.Errorf("%s.new 已存在且無法確認所有權，保留所有檔案 / unowned legacy temporary file; all files preserved", l.binary)
	} else if !errors.Is(err, fs.ErrNotExist) {
		return nil, false, err
	}
	info, err := os.Lstat(l.dir)
	if errors.Is(err, fs.ErrNotExist) {
		return nil, false, nil
	}
	if err != nil {
		return nil, false, err
	}
	if isLinkLike(info) || !info.IsDir() {
		return nil, true, fmt.Errorf("%s 不是一般資料夾，不會更動 / is not a regular directory; left unchanged", l.dir)
	}
	receipt, err := readReceipt(l.dir)
	if err != nil {
		return nil, true, err
	}
	if receipt == nil || !samePath(receipt.Binary, l.binary) {
		return nil, true, fmt.Errorf("%s 不是本安裝程式建立的，未做任何變更 / was not created by this installer; nothing changed", l.dir)
	}
	if err := in.checkLayoutPaths(receipt); err != nil {
		return nil, true, err
	}
	if err := verifyOwnedBinary(l.binary, receipt); err != nil {
		return nil, true, err
	}
	return receipt, true, nil
}

// inspect checks every path the install would change before writing anything.
func (in *installer) inspect() (*installReceipt, error) {
	l := in.layout
	old, _, err := in.inspectOwnedDirectory()
	if err != nil {
		return nil, err
	}

	for _, path := range l.manifests {
		exists, owned, err := ownedManifest(path, l.binary)
		if err != nil {
			return nil, err
		}
		if exists && !owned {
			return nil, fmt.Errorf("%s 已被其他程式使用（同名 %s），未做任何變更 / is used by another program; nothing changed", path, hostName)
		}
	}
	if in.reg != nil {
		for _, key := range l.registry {
			value, exists, err := in.reg.get(key)
			if err != nil {
				return nil, fmt.Errorf("無法讀取登錄 HKCU\\%s / cannot read the registry: %w", key, err)
			}
			if exists && !samePath(value, l.manifests[0]) {
				return nil, fmt.Errorf("登錄 HKCU\\%s 已被其他程式使用，未做任何變更 / is used by another program; nothing changed", key)
			}
		}
	}
	return old, nil
}

func (in *installer) install() error {
	l := in.layout
	old, err := in.inspect()
	if err != nil {
		return err
	}
	want, err := digestString(in.self)
	if err != nil {
		return err
	}
	receipt := installReceipt{Schema: 2, Host: hostName, Version: version, Binary: l.binary, InstalledBinarySHA256: want, PendingBinarySHA256: want, Manifests: l.manifests}
	if in.reg != nil {
		receipt.Registry = l.registry
	}
	// The bytes already installed, if any; inspect verified they are ours.
	var installed string
	if old != nil {
		receipt.Manifests = appendMissing(append([]string(nil), receipt.Manifests...), old.Manifests...)
		if in.reg != nil {
			receipt.Registry = appendMissing(append([]string(nil), receipt.Registry...), old.Registry...)
		}
		if exists, err := existingRegular(l.binary); err != nil {
			return err
		} else if exists {
			installed, err = digestString(l.binary)
			if err != nil {
				return err
			}
			receipt.InstalledBinarySHA256 = installed
		}
	}
	if err := in.checkLayoutPaths(&receipt); err != nil {
		return err
	}
	if err := os.MkdirAll(l.dir, 0o755); err != nil {
		return err
	}
	if err := in.checkLayoutPaths(&receipt); err != nil {
		return err
	}
	// Journal both valid hashes before replacement, so interrupted upgrades can
	// be repaired without granting ownership to arbitrary same-named files.
	if err := saveReceipt(l.dir, receipt); err != nil {
		return err
	}
	// Identical bytes are left in place: a same-version reinstall then never
	// has to replace a helper that may be running, and only rewrites the
	// receipt, manifests and registrations.
	if !sameFile(in.self, l.binary) && installed != want {
		staging, err := os.MkdirTemp(l.dir, ".install-*")
		if err != nil {
			return err
		}
		tmp := filepath.Join(staging, "helper")
		defer os.Remove(staging)
		defer os.Remove(tmp) // Only this invocation's exclusively created staging.
		if err := in.copy(in.self, tmp); err != nil {
			return fmt.Errorf("copying helper failed: %w", err)
		}
		got, err := digestString(tmp)
		if err != nil {
			return err
		}
		if got != want {
			return errors.New("copied helper differs from source")
		}
		if err := os.Chmod(tmp, 0o755); err != nil {
			return err
		}
		if err := in.checkLayoutPaths(&receipt); err != nil {
			return err
		}
		if err := verifyOwnedBinary(l.binary, &receipt); err != nil {
			return err
		}
		if err := replaceFile(tmp, l.binary); err != nil {
			return fmt.Errorf("cannot replace helper; close Chrome and retry: %w", err)
		}
	}
	receipt.InstalledBinarySHA256 = want
	receipt.PendingBinarySHA256 = ""
	if err := saveReceipt(l.dir, receipt); err != nil {
		return err
	}
	manifest := l.manifestBytes()
	for _, path := range l.manifests {
		if err := checkPathComponents(path); err != nil {
			return err
		}
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			return err
		}
		if err := writeFileAtomic(path, manifest, 0o644); err != nil {
			return err
		}
	}
	if in.reg != nil {
		for _, key := range l.registry {
			if err := in.reg.set(key, l.manifests[0]); err != nil {
				return fmt.Errorf("cannot write registration: %w", err)
			}
		}
	}
	fmt.Fprintf(in.out, "已安裝連線小幫手 %s / Socket helper %s installed:\n  %s\n", version, version, l.binary)
	for _, path := range l.manifests {
		fmt.Fprintln(in.out, "  "+path)
	}
	fmt.Fprintln(in.out, "請重新載入遊戲網頁。/ Reload the game page.")
	return nil
}

func (in *installer) uninstall() error {
	l := in.layout
	receipt, dirExists, err := in.inspectOwnedDirectory()
	if err != nil {
		return err
	}
	if dirExists && runtime.GOOS == "windows" && sameFile(in.self, l.binary) {
		return errors.New("請改用下載的檔案加 --uninstall（或下載包 helper 資料夾裡的 uninstall-windows.cmd）/ run the downloaded file with --uninstall (or uninstall-windows.cmd from the download's helper folder) instead")
	}
	manifests := l.manifests
	var keys []string
	if in.reg != nil {
		keys = l.registry
	}
	if receipt != nil {
		manifests = appendMissing(append([]string(nil), manifests...), receipt.Manifests...)
		if in.reg != nil {
			keys = appendMissing(append([]string(nil), keys...), receipt.Registry...)
		}
	}

	removed := 0
	// Registrations first: Chrome stops finding the host before its files go.
	for _, key := range keys {
		value, exists, err := in.reg.get(key)
		if err != nil {
			return fmt.Errorf("無法讀取登錄 HKCU\\%s / cannot read the registry: %w", key, err)
		}
		if !exists {
			continue
		}
		if len(l.manifests) == 0 || !samePath(value, l.manifests[0]) {
			fmt.Fprintf(in.out, "保留 HKCU\\%s（不是本程式的）/ kept, not ours\n", key)
			continue
		}
		didRemove, err := in.reg.removeDefault(key, l.manifests[0])
		if err != nil {
			return fmt.Errorf("cannot remove registration default: %w", err)
		}
		if didRemove {
			removed++
		}
	}
	for _, path := range manifests {
		exists, owned, err := ownedManifest(path, l.binary)
		switch {
		case err != nil:
			fmt.Fprintf(in.out, "保留 %s：%v\n", path, err)
		case exists && !owned:
			fmt.Fprintf(in.out, "保留 %s（不是本程式的）/ kept, not ours\n", path)
		case exists:
			if err := os.Remove(path); err != nil {
				return err
			}
			removed++
		}
	}
	if dirExists {
		if exists, err := existingRegular(l.binary); err != nil {
			return err
		} else if exists {
			if err := os.Remove(l.binary); err != nil {
				return fmt.Errorf("無法刪除 %s；請關閉 Chrome 後再試 / cannot delete it; close Chrome and retry: %w", l.binary, err)
			}
			removed++
		}
		if err := os.Remove(filepath.Join(l.dir, receiptName)); err != nil {
			return err
		}
		if err := os.Remove(l.dir); err != nil {
			fmt.Fprintf(in.out, "資料夾內還有其他檔案，已保留 %s / kept the folder, it has other files\n", l.dir)
		}
	}
	if !dirExists && removed == 0 {
		fmt.Fprintln(in.out, "沒有找到已安裝的連線小幫手 / The socket helper is not installed.")
		return nil
	}
	fmt.Fprintln(in.out, "已移除連線小幫手 / Socket helper removed.")
	return nil
}
