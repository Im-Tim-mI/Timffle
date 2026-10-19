# Timffle Helper — installers

English · [繁體中文](#繁體中文)

Installers for the **Timffle connection helper** (also called the socket helper): a small program that the [Timffle](https://github.com/Im-Tim-mI/Timffle) Chrome extension uses to open TCP connections for Flash online games. Chrome extensions cannot open TCP connections themselves, so the extension asks this helper to.

**You normally do not need this page.** When the helper is missing, Timffle's toolbar popup shows a **Download the installer** button: it detects your system and downloads the matching file from here.

This repository holds **only the installers** (release files), no source code. The helper is part of the Timffle project: the `timffle/helper` folder of <https://github.com/Im-Tim-mI/Timffle>.

## Download

Every file is in the [Releases](https://github.com/Im-Tim-mI/Timffle-Helper/releases) of this repository. The Timffle extension downloads the file of the helper version it was made for.

| System | File |
|---|---|
| Windows 64-bit (most PCs) | `timffle-helper-windows-x64.exe` |
| Windows on ARM | `timffle-helper-windows-arm64.exe` |
| Windows 32-bit | `timffle-helper-windows-x86.exe` |
| macOS, Apple silicon (M1 and newer) | `timffle-helper-macos-arm64.zip` |
| macOS, Intel | `timffle-helper-macos-x64.zip` |
| Linux, x64 | `timffle-helper-linux-x64.tar.gz` |
| Linux, ARM64 | `timffle-helper-linux-arm64.tar.gz` |

`SHA256SUMS.txt` lists the checksum of every file; `LICENSES.txt` has the licences.

## Install (once)

- **Windows**: double-click the `.exe`. A window shows the result and waits for Enter. If Windows says it protected your PC, check that this is the file you meant, then "More info" → "Run anyway".
- **macOS**: open the zip and double-click the program inside; Terminal opens and shows the result. The program is not signed by Apple, so macOS may block it: open System Settings → Privacy & Security, press "Open Anyway" for it, then double-click it again.
- **Linux**: `tar xzf timffle-helper-linux-x64.tar.gz && ./timffle-helper-linux-x64` (use the `arm64` names on ARM).

Then reload the game page. The installer is per user: **no administrator rights, no background service, no security setting is changed**. It copies the helper into your user folder and registers it with Chrome (Windows: the `HKCU` registry; macOS and Linux: your `NativeMessagingHosts` folder). Only the Timffle extension (ID `eandddnbchclalbjkhfelhjhpijifcog`) is allowed to start it; Chrome starts it when a game connects (or when the extension checks that it is installed) and it exits again right afterwards.

## Remove

Run the downloaded file again with `--uninstall` (on Windows from a Command Prompt, for example `timffle-helper-windows-x64.exe --uninstall`). It removes only what its installer created.

## Good to know

- The helper is **not signed** (no Microsoft or Apple signature); the files were cross-compiled. Tested: Linux x64 with Chrome 155. Windows only under Wine; macOS and the ARM builds were not run on real hardware.
- Timffle is an **unofficial fork of [Ruffle](https://ruffle.rs/)** and has no affiliation with the Ruffle project.
- Licence: the helper is MIT OR Apache-2.0 (Timffle) and statically contains Go's runtime (BSD-3-Clause); see `LICENSES.txt`.

---

## 繁體中文

這裡是 **Timffle 連線小幫手**（Socket 小幫手）的安裝檔。它是一個小程式，[Timffle](https://github.com/Im-Tim-mI/Timffle) 的 Chrome 擴充功能靠它替 Flash 線上遊戲開 TCP 連線（Chrome 擴充功能自己不能開 TCP 連線）。

**一般不需要特地來這個頁面。**小幫手還沒安裝時，Timffle 工具列的彈出視窗會有「直接下載安裝程式」按鈕：它會判斷你的系統，從這裡下載對應的檔案。

這個倉庫**只放安裝檔**（release 檔案），不放原始碼。小幫手是 Timffle 專案的一部分：<https://github.com/Im-Tim-mI/Timffle> 的 `timffle/helper` 資料夾。

### 下載

檔案都在這個倉庫的 [Releases](https://github.com/Im-Tim-mI/Timffle-Helper/releases)。Timffle 擴充功能會下載它所對應的小幫手版本。

| 系統 | 檔案 |
|---|---|
| Windows 64 位元（大多數電腦） | `timffle-helper-windows-x64.exe` |
| Windows ARM | `timffle-helper-windows-arm64.exe` |
| Windows 32 位元 | `timffle-helper-windows-x86.exe` |
| macOS，Apple 晶片（M1 以後） | `timffle-helper-macos-arm64.zip` |
| macOS，Intel | `timffle-helper-macos-x64.zip` |
| Linux x64 | `timffle-helper-linux-x64.tar.gz` |
| Linux ARM64 | `timffle-helper-linux-arm64.tar.gz` |

`SHA256SUMS.txt` 列出每個檔案的雜湊值，`LICENSES.txt` 是授權檔。

### 安裝（只要一次）

- **Windows**：連按兩下 `.exe`，視窗會顯示結果並等你按 Enter。若出現「Windows 已保護您的電腦」，確認是這個檔案後按「其他資訊」→「仍要執行」。
- **macOS**：開啟 zip，連按兩下裡面的程式；會開啟「終端機」並顯示結果。程式沒有 Apple 簽章，macOS 可能擋下：到「系統設定」→「隱私權與安全性」，對它按「仍要打開」，再連按兩下一次。
- **Linux**：`tar xzf timffle-helper-linux-x64.tar.gz && ./timffle-helper-linux-x64`（ARM 請改用 `arm64` 的檔名）。

裝好後重新整理遊戲頁面。安裝程式只替目前的使用者安裝：**不需要系統管理員權限、不裝背景服務、不更動任何安全設定**。它把小幫手複製到使用者的資料夾，並向 Chrome 註冊（Windows 寫入 `HKCU` 登錄；macOS 與 Linux 寫入使用者的 `NativeMessagingHosts` 資料夾）。只有 Timffle 擴充功能（ID `eandddnbchclalbjkhfelhjhpijifcog`）能啟動它；Chrome 在遊戲連線時（或擴充功能檢查它有沒有裝好時）才啟動它，用完馬上結束。

### 移除

用 `--uninstall` 再執行一次下載的檔案（Windows 請在命令提示字元，例如 `timffle-helper-windows-x64.exe --uninstall`）。它只會移除安裝程式自己建立的東西。

### 注意

- 小幫手**沒有簽章**（沒有 Microsoft 或 Apple 的簽章），檔案是交叉編譯的。測試狀況：Linux x64 以 Chrome 155 驗證；Windows 只在 Wine 測過；macOS 與 ARM 版沒有在實機執行過。
- Timffle 是 **[Ruffle](https://ruffle.rs/) 的非官方分支**，與 Ruffle 專案沒有隸屬關係。
- 授權：小幫手是 MIT OR Apache-2.0（Timffle），並靜態包含 Go 執行環境（BSD-3-Clause）；詳見 `LICENSES.txt`。
