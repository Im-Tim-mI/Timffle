# 小幫手的獨立下載（「直接下載安裝程式」）

插件工具列彈出視窗（與設定頁）在小幫手還沒裝好時有一顆「直接下載安裝程式」按鈕：它判斷使用者的系統，**一點就開始下載**對的安裝檔。這份文件說明下載位置、檔案、插件怎麼選檔案、檔案怎麼做出來、怎麼發佈新版，以及這個做法的限制。介面與判斷的程式在 `web/packages/extension/src/helper-download.ts`（設計見 [`ARCHITECTURE.md`](ARCHITECTURE.md) 的 3b）。

## 1. 下載位置

| 項目 | 內容 |
|---|---|
| GitHub 倉庫 | [`Im-Tim-mI/Timffle-Helper`](https://github.com/Im-Tim-mI/Timffle-Helper)：**只放安裝檔**（release 的檔案），不放原始碼；README 與授權檔的樣本在 [`../helper/downloads-repo/`](../helper/downloads-repo/) |
| release 標籤 | `v<小幫手版本>`，例如 `v1.3.0`（小幫手的版本是 `timffle/helper/main.go` 的 `version`）。每個小幫手版本一個 release |
| 下載網址 | `https://github.com/Im-Tim-mI/Timffle-Helper/releases/download/<標籤>/<檔名>`；GitHub 會轉址到它的檔案伺服器，並把檔案當成附件（`Content-Disposition: attachment`）回應 |
| 要讓別人點得開 | 倉庫必須是**公開**的。私人倉庫的 release 檔案只有登入且有權限的人拿得到：其他人的下載會得到 GitHub 的「找不到頁面」 |

為什麼用另一個倉庫而不是 Timffle 自己的 Releases：Timffle 倉庫在公開之前是私人的；而且 Timffle 的 Releases 放的是插件包，「最新版」會隨插件更新而變，和小幫手的版本無關。小幫手的安裝檔另開一個倉庫，就能不公開原始碼、單獨公開下載。

## 2. 檔案

| 系統 | 檔名 | 格式 | 打開的方式 |
|---|---|---|---|
| Windows 64-bit | `timffle-helper-windows-x64.exe` | 小幫手本身（單一 `.exe`） | 雙擊 |
| Windows ARM64 | `timffle-helper-windows-arm64.exe` | 同上 | 雙擊 |
| Windows 32-bit | `timffle-helper-windows-x86.exe` | 同上 | 雙擊 |
| macOS Apple silicon | `timffle-helper-macos-arm64.zip` | zip，裡面只有小幫手一個檔案（保留可執行權限） | 開啟 zip，雙擊裡面的程式（在「終端機」執行） |
| macOS Intel | `timffle-helper-macos-x64.zip` | 同上 | 同上 |
| Linux x64 | `timffle-helper-linux-x64.tar.gz` | tar.gz，裡面只有小幫手一個檔案 | `tar xzf … && ./timffle-helper-linux-x64` |
| Linux ARM64 | `timffle-helper-linux-arm64.tar.gz` | 同上 | 同上 |
| （每個 release 另有） | `SHA256SUMS.txt`、`LICENSES.txt` | 文字檔 | 比對雜湊、授權檔 |

這些檔案**和發行 ZIP 的 `helper/bin/<平台>/` 裡的小幫手是逐位元組相同的程式**（同一個 `build.sh`、同樣的 `-trimpath -buildvcs=false -ldflags='-s -w'`），只是外面包法不同。小幫手從 1.3.0 起，**不帶任何引數直接執行**（雙擊）就是互動式安裝：印出說明、替目前使用者安裝、停下來等 Enter（只在有終端機時等，所以不會卡住自動化的環境）。Chrome 呼叫小幫手時一定帶著呼叫者的 origin 當第一個引數，所以這個新入口不可能由網頁或 Chrome 觸發；`--install`、`--uninstall`、`--version` 與其他情形都和以前一樣。要移除：對下載的檔案加上 `--uninstall` 再執行一次（Windows 不能用已安裝的那份移除自己，所以要用下載的那份）。

為什麼不是單一格式：瀏覽器下載的檔案沒有可執行權限，所以 macOS 與 Linux 需要壓縮檔來保留它；Windows 的 `.exe` 本身就能雙擊。檔案沒有簽章：Windows 會出現 SmartScreen 的警告，macOS 會被 Gatekeeper 擋下（要到「系統設定」→「隱私權與安全性」按「仍要打開」）；這一點與發行 ZIP 裡的小幫手相同，沒有辦法在不付費取得簽章的情形下解決。

## 3. 插件怎麼選檔案、怎麼下載

- **選檔案**：`chooseInstaller()` 依 `navigator.userAgentData` 的作業系統與**處理器**（`x86`／`arm`、32／64 位元）選出上表的一列。macOS 只看處理器，因為 Apple silicon 的 Mac 上 Chrome 的 User-Agent 也寫 Intel；沒有處理器資訊就不猜（猜錯的程式開不起來），按鈕不出現，只剩「其他系統與安裝說明」（安裝頁列出所有檔案）。Chrome OS 與 Android 沒有安裝檔。
- **下載**：`tabs.create({ url, active: false })`。GitHub 的回應是附件，Chrome 存檔、顯示自己的下載提示並自己關掉那個分頁。**不需要任何新權限**（不用 `downloads`），插件不抓取、不檢查、不解壓縮、不執行檔案。
- **沒有事先檢查**：檔案不存在（標籤打錯、release 還沒發佈、倉庫是私人的）時，那個分頁會停在 GitHub 的「找不到頁面」，沒有東西被存下來，而提示仍寫「已開始下載」。這是已知的取捨（換來不需要權限、也不依賴彈出視窗開著）；發佈新版的流程因此要在公開前自己下載一次驗證（見下）。
- **釘住版本**：`HELPER_RELEASE`（`helper-download.ts`）是一個固定的標籤，不是「最新版」。插件永遠下載它所對應的小幫手；之後如果出了通訊協定不同的小幫手，舊插件不會裝到它用不了的版本。單元測試 `helper-download.test.mjs` 檢查 `HELPER_RELEASE` 等於 `main.go` 的版本，並檢查表裡的檔名與 `package-installers.py` 寫出的檔名一致。

## 4. 做出檔案

```sh
# 在 Timffle 的乾淨提交上（小幫手的原始碼都已提交）。GO 要是 Go 1.27 以上。
GO=/path/to/go timffle/scripts/package-helper-installers.sh timffle/build
# → timffle/build/installers/  七個安裝檔、LICENSES.txt、SHA256SUMS.txt
```

腳本做的事：用 `helper/build.sh`（`INCLUDE_LINUX_ARM64=1`）把小幫手交叉編譯到 `<BUILD_DIR>/installers-bin`，再由 `helper/package-installers.py` 檢查每個輸入（PE／Mach-O／ELF 的標頭要是對的處理器、沒有私鑰標記）、寫出上表的檔案（zip 與 tar.gz 是可重現的：固定時間、固定權限 0755）、`LICENSES.txt`（Timffle 的 MIT 與 Apache-2.0、Go 的授權）與 `SHA256SUMS.txt`，最後用 `check-no-build-paths.py` 掃整個輸出資料夾，**發現建置機的家目錄或使用者名稱就刪掉整個輸出**（和 `package-release.sh` 同樣的規矩，見 [`BUILD.md`](BUILD.md)）。腳本不會上傳任何東西。

## 5. 發佈一個小幫手版本

1. 小幫手有變動時，先改 `main.go` 的 `version`，並同步 `helper-download.ts` 的 `HELPER_RELEASE`、各處文件的版本字串（`grep -rn '1\.3\.0' .`），讓單元測試通過。
2. 上面的腳本做出檔案；用對應的建置跑 `go test ./...`、`go test -tags localtest ./...`、`cd timffle/helper/installer-tests && python3 -I test_installers.py`。
3. **第一次**才需要建立倉庫（這裡的可見度是作者的決定；要讓插件的按鈕對所有人有效必須公開）：
   ```sh
   gh repo create Im-Tim-mI/Timffle-Helper --public --description "Installers for the Timffle socket helper"
   ```
   把 [`../helper/downloads-repo/README.md`](../helper/downloads-repo/README.md) 放成倉庫的 `README.md`。
4. 建立 release 並上傳（標籤 `v<版本>`，附上 `SHA256SUMS.txt` 與 `LICENSES.txt`）：
   ```sh
   gh release create v1.3.0 timffle/build/installers/* --repo Im-Tim-mI/Timffle-Helper --title "Timffle helper 1.3.0" --notes-file <說明檔>
   ```
5. **下載回來驗證**：在一個全新的空資料夾，用沒有登入的方式（`curl -L`，不帶 token）把七個檔案抓下來，`sha256sum -c SHA256SUMS.txt`，再用 `python3 -I timffle/scripts/check-no-build-paths.py` 掃一遍（GitHub 上的那一份，不是本機的那一份）。倉庫還是私人時這一步會得到 404，這是預期的。
6. 用真的 Chrome 按一次按鈕（或 `timffle/tools/native-regress/browser-auto-tests.mjs`，它用假的 GitHub 驗證流程）。

## 6. 限制

- 沒有簽章；Windows 只在 Wine 測過，macOS 與 ARM 版沒有在實機執行過（Linux x64 用 Chrome 155 驗證）。
- 倉庫是私人的期間，按鈕對沒有權限的人無效（得到 GitHub 的「找不到頁面」）。
- 瀏覽器要允許從 `github.com` 下載可執行檔：Chrome 對不常見的 `.exe` 可能顯示「這個檔案不常被下載」的警告，使用者要按「保留」；這是 Chrome 的下載保護，插件無法也不應該繞過。
- 企業環境若封鎖 `github.com` 或 `githubusercontent.com`，按鈕不會有效；安裝頁仍可由發行 ZIP 裡的 `helper/` 安裝程式取代。
