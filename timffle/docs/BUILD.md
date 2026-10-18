# 從原始碼建置

本 repo 包含建置所需的全部原始碼（Ruffle、修補過的 rust-flash-lso、Timffle 的擴充功能與小幫手），不需要另外下載或套補丁。建置分三步：建置擴充功能（含 WebAssembly 核心）→ 交叉編譯連線小幫手 → 封裝發行 ZIP。每一步都有腳本，**在 repo 根目錄執行**；腳本只在 Unix 殼層（Linux、macOS、WSL）測試過。

## 1. 需要的工具

| 工具 | 版本（開發時使用） | 用途 |
|---|---|---|
| git | 任何較新版本 | 取得原始碼 |
| Rust（rustup） | 1.99.0，加上 `wasm32-unknown-unknown` 目標 | 編譯 Ruffle 核心成 WebAssembly |
| wasm-bindgen CLI | **0.2.127**，必須與 `Cargo.lock` 裡的 `wasm-bindgen` crate 版本完全一致 | 產生 JS 綁定（腳本會檢查版本） |
| binaryen（`wasm-opt`） | version_133 | 最佳化 wasm（沒有也能建置，但較大較慢） |
| Node.js、npm | 24.21.0、11.19.0 | 建置擴充功能與網頁套件 |
| Go | 1.27.2（`helper/go.mod` 要求 1.27） | 編譯連線小幫手 |
| Python | 3.12（選用 Pillow：只有重新產生圖示時需要） | 封裝腳本、品牌檢查、差異測試 |
| Haxe（選用） | 4.3.7 | 編譯差異測試的 SWF |
| Adobe Flash Player 32 standalone＋Wine（選用） | 32.0.0.465 | 產生差異測試的標準答案；**Adobe 的軟體不在本 repo，須自行取得** |

## 2. 步驟

```sh
git clone https://github.com/Im-Tim-mI/Timffle.git && cd Timffle

# 1. 建置擴充功能 → web/packages/extension/dist/ruffle_extension.zip
VERSION4=0.8.0.26302 timffle/scripts/build-extension.sh

# 2+3. 交叉編譯小幫手（7 個平台），並封裝成發行 ZIP（含 LICENSES/ 與 NOTICE.md）→ timffle/build/out/
VERSION4=0.8.0.26302 timffle/scripts/package-release.sh
```

- `VERSION4` 是擴充功能版本，四段數字；最後一段只是流水號。
- `build-extension.sh` 的順序是：品牌檢查（`timffle/scripts/rebrand.py --check`；有 Pillow 時也檢查圖示）→ 介面文字檢查（`timffle/scripts/sync_locales.py --check`）→ `npm ci` → 建置 Ruffle 核心（呼叫 cargo 編出一份 wasm，使用 SIMD 等擴充指令的版本；再跑 wasm-bindgen 與 wasm-opt。Ruffle 另有給舊瀏覽器的 MVP 版本，需設 `BUILD_WASM_MVP=true`，本專案沒有用）→ 擴充功能型別檢查與單元測試 → `build:generic` 產生擴充功能 ZIP（`CFG_RELEASE_CHANNEL=local-native-auto`，並把 `timffle/extension-key/` 的公鑰放進 `manifest.json`）。`SKIP_TESTS=1` 可略過測試。輸出檔名 `ruffle_extension.zip` 是上游建置腳本的內部名稱；發行 ZIP 叫 `timffle-chrome-<版本>.zip`。
- 型別檢查需要先建好核心（它從核心的建置輸出取型別宣告）。擴充功能的單元測試（`cd web && npm ci && npm test --workspace=ruffle-extension`）不需要 wasm。
- `package-release.sh` 需要 Go 的授權檔（從 `go env GOROOT` 取得），並把 Ruffle、Timffle、rust-flash-lso 與 Go 的授權檔放進 ZIP 的 `LICENSES/`。
- **建置路徑不進發行檔**：Rust 的 panic 訊息會把原始碼路徑寫進 wasm，沒處理的話發行 ZIP 會帶著建置機的家目錄與使用者名稱。`build-extension.sh` 預設用 `--remap-path-prefix` 把它們改寫成 `/h`、`/cargo`、`/rustup`、`/src`（`KEEP_BUILD_PATHS=1` 可關閉，只限不會離開這台機器的建置）；`package-release.sh` 在打包前與打包後都用 `timffle/scripts/check-no-build-paths.py` 檢查，發現就拒絕產出，並刪掉剛做好的 ZIP（`SKIP_PATH_CHECK=1` 可略過，同樣只限本機）。要上傳到 GitHub 的發行檔都必須通過這個檢查。
- 腳本都拒絕覆寫既有輸出；要重來請先刪掉對應的資料夾。

### 只建置小幫手

```sh
cd timffle/helper
GO=/path/to/go INCLUDE_LINUX_ARM64=1 sh ./build.sh ../build/helper-bin     # 輸出資料夾必須是不存在的新資料夾
go test ./...                                                              # 單元測試
go test -tags localtest ./...                                              # 含只在測試版才有的私網位址允許
```

`build.sh` 以 `-trimpath -buildvcs=false -tags= -ldflags='-s -w'` 編譯 `windows/{amd64,arm64,386}`、`darwin/{amd64,arm64}`、`linux/amd64`（`INCLUDE_LINUX_ARM64=1` 另加 `linux/arm64`），全部 `CGO_ENABLED=0`，並拒絕環境裡殘留的 `GOFLAGS`／`GOWORK`。輸出只是「交叉編譯產物」，**沒有簽章，也不代表在該平台實機測試過**。

## 3. 驗證過什麼、沒驗證什麼

各版本實際跑過的建置與測試記在 [`../CHANGELOG.md`](../CHANGELOG.md)。0.8.0.26296（Timffle 第一版）的情況：

| 項目 | 結果 |
|---|---|
| 原始碼 | Ruffle 與 rust-flash-lso 的修改由前身專案的五份補丁（0.8.0.26295）原封不動地轉成 commit（`git apply` 全部乾淨套用）；之後只改了品牌、小幫手名稱與 `flash-lso` 的路徑。 |
| **WebAssembly 核心與擴充功能** | 在本 repo 的樹上用 `timffle/scripts/build-extension.sh` **完整建置成功**（`web-wasm-extensions` profile；`flash-lso` 確實從 `vendor/rust-flash-lso` 編譯），擴充功能型別檢查通過、單元測試 38/38。wasm 內含編譯路徑等資訊，不會與舊版逐位元組相同。 |
| 連線小幫手 | `go vet`、`go test ./...`、`go test -tags localtest ./...` 通過；7 個平台交叉編譯成功。Windows 版的安裝／移除登錄測試（`installer-tests/test_windows_registry.py`）在 Wine 通過。 |
| 發行 ZIP | `package-release.sh` 產生 91 個檔案的 ZIP（含 `LICENSES/` 與 `NOTICE.md`）；封裝測試 23/23。 |
| 瀏覽器＋小幫手整合測試 | 對最終 ZIP 73/73（localtest 28、missing 12、delayed 13、incompatible 12、manual 8）。機器負載很高（load ≈ 35）時，localtest 的計時敏感項目 `local-close-no-remote-close-event` 失敗過一次，之後連續 3 次 28/28。 |
| 其他 | 本機代理 10/10、差異測試比對工具 11/11、品牌檢查通過；選項頁、彈出視窗、播放器頁在無頭 Chrome 155 目視確認。 |
| **沒有做** | 對真 Flash 的差異測試（核心程式碼與 0.8.0.26295 相同，沒有重跑）、完整的上游 `cargo test`、真實帳號登入、Windows／macOS 實機、Firefox。 |

## 4. 使用自己的擴充功能金鑰

如果你要散布自己的版本，請不要沿用 `timffle/extension-key/` 的公鑰（見 [`../extension-key/README.md`](../extension-key/README.md) 的信任模型說明）。

```sh
openssl genrsa -out my-extension.pem 2048                      # 私鑰：自己保管，絕不提交、絕不放進發行 ZIP
openssl rsa -in my-extension.pem -pubout -outform DER | openssl base64 -A > timffle/extension-key/chrome-extension-public.b64
python3 -I timffle/scripts/extension-id.py > timffle/extension-key/extension-id.txt
```

然後把舊 ID（`eandddnbchclalbjkhfelhjhpijifcog`）換成新的，位置有：

| 位置 | 內容 |
|---|---|
| `timffle/helper/main.go` | `callerOrigin` 常數（小幫手只接受這個來源的呼叫） |
| `timffle/helper/main_test.go` | 測試用的來源字串 |
| `timffle/helper/package.py` | `EXPECTED_ID`（封裝時驗證） |
| `web/packages/extension/tests/socket-background.test.mjs` | 測試的常數 `ID` |
| `timffle/tools/native-regress/browser-auto-tests.mjs` | 一個 `assert.equal(ID, …)` |
| 文件 | `README.md`、`README.zh-TW.md`、`README.zh-CN.md`、`timffle/extension-key/extension-id.txt` |

這份清單可以用 `grep -rn eandddnbchclalbjkhfelhjhpijifcog .` 重新確認。只在要簽署 `.crx` 或上架商店時才會用到私鑰；`timffle/helper/package.py` 會拒絕含 PEM 私鑰標記的檔案。

## 5. 常見問題

- **`wasm-bindgen CLI is X but Cargo.lock needs Y`**：安裝指定版本，例如 `cargo install wasm-bindgen-cli --version 0.2.127 --locked`，或下載對應版本的預編譯檔。
- **`npm ci` 提示有套件的安裝指令碼沒被核准**：這是 npm 11 的提示，建置不受影響。
- **編譯 wasm 很慢、占很多磁碟**：第一次建置要編譯上千個 crate；`target/` 可能長到數 GB。之後增量建置會快很多。
- **`build-extension: Timffle's interface texts are not in the message catalogs`**：`timffle/locales/` 改過、或跟進上游後 `messages.json` 被換成上游版本；執行 `python3 timffle/scripts/sync_locales.py`（見 [`../locales/README.md`](../locales/README.md)）。
- **`build-extension: user-visible texts still say Ruffle`**：跟進上游後有新的文字，執行 `python3 timffle/scripts/rebrand.py`（見 [`BRANDING.md`](BRANDING.md)）。
- **只想建置 Ruffle 原有的其他部分（桌面版等）**：與上游相同（見根目錄 `README.ruffle.md`），但它們還沒改名，不能以 Timffle 名義散布。
