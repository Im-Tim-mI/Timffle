# CHANGELOG

版本號 `0.8.0.N`：前三段是基底 Ruffle 的版本（0.8.0），最後一段 `N` 是流水號（沿用前身專案的編號）。擴充功能與小幫手分開記版本：小幫手目前是 **1.2.0（protocol 2）**，只有在下面明確寫「小幫手有更新」時才需要重跑安裝程式。日期為 UTC。0.8.0.26295 以前是前身專案的紀錄。

## 0.8.0.26296 — 2026-10-17（Timffle 第一版）

**專案改名為 Timffle，並改成 Ruffle 的完整分支。** 行為與 0.8.0.26295 相同，只有名稱、圖示、連結與 repo 結構改變。

- **Repo 結構**：不再是「補丁組」，而是 Ruffle 的完整原始碼樹＋完整 git 歷史（到 `nightly-2026-10-13`，保留所有 Ruffle 貢獻者的作者紀錄），前身的五份補丁變成之後的 commit；rust-flash-lso 以 git subtree（含歷史）收錄在 `vendor/rust-flash-lso/`，`Cargo.toml` 直接指向它。原本的小幫手、代理、差異測試、工具與文件移到 `timffle/`。不再需要 `setup-ruffle.sh`／`make-patches.sh`。
- **品牌**：擴充功能名稱「Timffle - Flash Emulator」、Timffle 自己的圖示（天藍色圓角方塊上的白色「T」加一個黃色播放三角形）、載入畫面字標與藍色播放鍵（取代 Ruffle 的橘紅色漸層）、擴充功能介面的強調色改用圖示的黃色（取代 Ruffle 的橘色）、所有語系的介面文字、「關於」與「更新」連結、Firefox 附加元件 ID；錯誤畫面的「回報錯誤」改開 Timffle 的 issue（不再送到 Ruffle）。選項頁加上「Ruffle 的非官方分支」聲明與致謝。程式碼識別名稱與公開 API（`window.RufflePlayer` 等）不變。見 `timffle/docs/BRANDING.md`；`timffle/scripts/rebrand.py` 可在跟進上游後重新套用並檢查。
- **小幫手有更新（1.2.0）**：改名為 `timffle-socket-helper`（Native Messaging `timffle_socket_helper`、資料夾 `TimffleSocketHelper`、測試用環境變數 `TIMFFLE_SOCKET_HELPER_ALLOW_PRIVATE`）。功能與 1.1.0 相同，但**名稱不同，必須重跑安裝程式**；前身專案留下的舊小幫手（`ruffle-socket-helper`）請用它自己的移除程式移除。擴充功能 ID 不變。
- **發行 ZIP**：改名 `timffle-chrome-<版本>.zip`（根資料夾 `timffle/`），並附上 `NOTICE.md` 與 `LICENSES/`（Ruffle 的 `LICENSE.md`／`web/LICENSE.md`、Timffle 的 MIT／Apache-2.0、rust-flash-lso 的 MIT、Go 標準函式庫的 BSD-3-Clause）——補上前身的待辦。
- **授權**：Ruffle 的 `LICENSE.md` 留在根目錄原處；Timffle 的 `LICENSE-MIT`／`LICENSE-APACHE` 在 `timffle/`；新增 `NOTICE.md`、`timffle/MODIFIED-FILES.md`（Apache-2.0 第 4(b) 條的修改清單，腳本產生）。
- **說明文件**：`README.md`、`README.en.md` 改寫成正式發布版——簡介、特色、快速開始、支援狀態、安裝、設定（附選項頁截圖）、疑難排解、運作原理與安全設計、已知限制，開發相關內容移到最後；隨 ZIP 發出的 `README.txt` 同步整理。圖示的設計與色彩見 `timffle/docs/BRANDING.md`。
- **GitHub**：移除 Ruffle 的 CI workflow、dependabot 與 FUNDING 設定（它們屬於 Ruffle 的帳號與服務）；issue／PR 範本換成 Timffle 的。`CONTRIBUTING.md`、`CODE_OF_CONDUCT.md` 開頭加上 Timffle 的說明。
- 已知問題（沿用自 0.8.0.26295）：網域名稱「一律先父網域」的解析方式會讓上游的 `avm2/loader_duplicate_class` 測試失敗；改用混合規則的計畫見 `timffle/docs/UPSTREAM.md`「已知待辦」。
- 驗證：在本 repo 的樹上完整建置 wasm 與擴充功能成功（型別檢查、單元測試 38/38）；小幫手 `go test`（含 localtest）通過、Wine 上的 Windows 登錄測試通過；封裝測試 23/23；對最終 ZIP 的整合測試 73/73（高負載下一個計時敏感項目失敗過一次，重跑 3 次皆通過）；本機代理 10/10、比對工具 11/11、品牌檢查通過。**沒有重跑**對真 Flash 的差異測試（核心程式碼未變）、完整上游 `cargo test`、真實帳號登入。詳見 `timffle/docs/BUILD.md` 第 3 節。
- **發行包**（tag `v0.8.0.26296` = `864920ce1`）：wasm 以 `--remap-path-prefix` 編譯，`build-extension.sh` 預設就會這樣做；`package-release.sh` 在打包前後用 `check-no-build-paths.py` 檢查，ZIP 裡沒有建置機的家目錄或使用者名稱（先前一份未發布的 ZIP 有帶，沒有上傳）。逐檔掃描也沒有私鑰、憑證區塊與遊戲內部名稱。與那份未發布的 ZIP 相比，91 個檔案中只有 wasm（路徑）、`NOTICE.md` 與 5 個 JS 檔（建置資訊，其中 2 個再加播放鍵顏色）不同；小幫手與安裝程式位元組相同，所以整合測試 73/73 沒有重跑。在無頭 Chrome 載入這份擴充功能跑 8 個差異測試：6 個與真 Flash 逐行相同，另 2 個只差已知的 `playerType` 與 LocalConnection 的 release／debugger 錯誤字樣（一個以 400 ms 計時的測試在同一份 wasm 的另一次執行中偶發誤判過一次，之後 3 次通過）。未簽章、未公證。發行包 SHA-256：`aa06fa468917363546d0d87c22c257f354d31ed535ff8068d6e0fdd523a32473`。

## 0.8.0.26295 — 2026-10-17

選項頁的遊戲名稱正名。

- 選項頁「Socket 連線」的說明在英文那一半寫的是英文遊戲名，而頁面語言被設成瀏覽器介面語言，Chrome 自動翻譯整頁時把遊戲名翻錯（出現「鼴鼠世界、先知、花和蛋蛋堂」）。現在兩半都用正確的中文名（摩爾莊園、賽爾號、小花仙、彈彈堂）加主機名稱，並對整個區塊加上 `translate="no"`。
- 只改 `options.html` 與版本號；Ruffle 核心（wasm）與小幫手沒有動。與 26294 相比，84 個檔案中只有 3 個不同。
- 驗證：擴充功能型別檢查與單元測試 38/38；對最終 ZIP 的整合測試 73/73。
- 發行包 SHA-256：`ae829fa8aa3e31d001fb79a3b2575aaac412a46602ef403cea53ee5b8ab01d64`。

## 0.8.0.26294 — 2026-10-16

補齊 3D。

- `rotationX`／`rotationY`／`rotationZ`／`scaleZ`／`z`，`transform.matrix3D`（與物件即時連動），容器的 `getBounds`／`hitTestPoint`／`getObjectsUnderPoint`／`mouseX/Y` 納入子物件的投影。
- `Matrix3D`：`pointAt` 補實作；`recompose`／`decompose`／`interpolate`／`appendRotation` 邊界行為對齊 Flash。`Utils3D`：新增 `pointTowards`，`projectVector(s)` 對齊。
- `BitmapData.draw` 畫 3D 內容依投影繪製。
- 差異測試黃金答案從 21 項增為 33 項（新增 12 項），桌面版 33/33 與真 Flash 相同；網頁版 20 項逐行相同。
- 第一次用**真實帳號**驗證：登入、本地帳號頁、進入世界、走路、換地圖、賽車座位都正常（Linux＋Chrome 155）。
- 只動 Ruffle 核心與版本號；小幫手與安裝檔沒有動。

## 0.8.0.26293 — 2026-10-16

- 登入畫面的 3D 轉盤：補上 `z` 的透視（`perspectiveProjection`），圓圈排成弧形而不是一排；對真 Flash 逐項驗證。
- 預設允許的網站清單加入賽爾號、小花仙、彈彈堂（摩爾莊園本來就有），各含 `http` 與 `https`；舊版沒改過的預設清單會自動升級，使用者自訂的清單不動。
- 調查賽車地圖可走格 4744 對 4734：原因是 Flash 的 `hitTestPoint` 以整數像素量化、Ruffle 用精確座標；**刻意不修**（見 `docs/FLASH-NOTES.md`）。

## 0.8.0.26292 — 2026-10-16

- 網域名稱查找改成**先找父網域**（與 Flash 相同）：修正賽車座位點了沒反應——載入進子網域的函式庫定義了與內建同名的 `flash.system.trace`，蓋掉了內建函式。
- 網頁版 AS3 遞迴深度保護（上限 900 層，丟可被 `catch` 的 `StackOverflowError`），避免 WebAssembly 堆疊溢位後整個播放器死掉。
- 包含 26291 與 26290 的修正。

## 0.8.0.26291 — 2026-10-16

- `Loader.close()`／`URLLoader.close()` 真正取消載入並壓住之後的事件。
- `URLLoader` 的 `open` 事件改在收到回應標頭時就發（原本等整個內容下載完）；請求失敗或非 2xx 不發 `open`。

## 0.8.0.26290 — 2026-10-16

- canvas 裝置字型模式下，`_sans`／`_serif`／`_typewriter` 通用字型不再綁在只含拉丁字母的內建字型，修正 NPC 對話選項中文整段消失。

## 0.8.0.26289 — 2026-10-16

第一個「自動版」：不需要 Node.js、不需要填代理網址。

- 連線小幫手 1.1.0（protocol 2）：Chrome 的 Native Messaging，每個 Socket 一個程序，不監聽連接埠、不裝服務；只連公開網路位址。
- 每個平台的安裝／移除程式（每個使用者，不需要系統管理員）。
- 預設只允許摩爾莊園（`http` 與 `https`）。

## 0.8.0.26287 ～ 0.8.0.26288 — 2026-10-14 ～ 15

- 第一批 Ruffle 修補：`LocalConnection`（循環參照、原始型別 `client`、訊息大小上限）、`URLStream` 漸進傳輸、AMF3 參照索引（`flash-lso`）。
- 「自訂 WebSocket 代理」模式與本機代理 `relay/`（需要 Node.js）。
