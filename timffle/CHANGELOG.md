# CHANGELOG

版本號 `0.8.0.N`：前三段是基底 Ruffle 的版本（0.8.0），最後一段 `N` 是流水號（沿用前身專案的編號）。擴充功能與小幫手分開記版本：小幫手目前是 **1.2.0（protocol 2）**，只有在下面明確寫「小幫手有更新」時才需要重跑安裝程式。日期為 UTC。0.8.0.26295 以前是前身專案的紀錄。

## 未發布

**第一次連線時的詢問、「一律拒絕」清單，以及彈出視窗的一鍵允許。**只有 Chrome 擴充功能改變；小幫手仍是 1.2.0（**不需要重跑安裝程式**）、通訊協定不變、Ruffle 核心（wasm）沒有動。

- **第一次連線時的詢問**：不在「一律允許」也不在「一律拒絕」清單的網站，第一次嘗試使用 Socket 連線時，Timffle 會跳出**插件自己的視窗**（獨立視窗，網頁無法遮住或替你按），警告「預設建議拒絕，只有線上遊戲可以允許」，並提供「拒絕（建議）」「允許」「一律拒絕」「一律允許」。「允許」「拒絕」只對這個分頁這次造訪有效（存在 `storage.session`：關閉分頁或最上層頁面換到別的網站後清除，重新整理同一頁不算；service worker 重啟後還在）；「一律」存進設定。直接關掉視窗＝拒絕這次造訪。淘米的四個遊戲網站仍在預設允許清單，不會被問。只有「連線小幫手」模式會問；「自訂 WebSocket 代理」模式不問，沒列出的網站一律拒絕（代理網址含 token，不給沒被允許的網站）。
- **彈出視窗**：新增「Socket 連線」區塊，顯示目前分頁的網站。「**允許此網站使用 Socket 連線**」一鍵加進「一律允許」清單，不必輸入網址；下拉選單可改成「**每次造訪時詢問**」（從清單移除）、「一律允許」、「一律拒絕」；這個分頁裡被詢問過的其他網站的頁框也會列出，各有按鈕。存不了時（例如自訂代理模式下拿掉最後一個允許的網站）會顯示原因。彈出視窗改為 340 px 寬、標頭與狀態列壓縮，高度維持在 Chrome 彈出視窗的 600 px 上限內（ask 狀態 527 px，有回歸檢查）。
- **選項頁**：新增「一律拒絕的網站來源」清單；同一個來源同時在「允許」與「拒絕」清單時儲存會提醒（真的同時存在時拒絕優先）。helper 模式不再要求至少一個允許的來源（沒有就全部詢問）；自訂代理模式仍要。**兩種連線方式各有自己的「一律允許」清單**（見下），切換方式時文字方塊換成該方式的清單；表單載入後如果設定在別處（彈出視窗、詢問視窗）被改過，儲存會被拒絕並改為顯示最新設定，沒有編輯過的表單則自動跟著更新。
- **設定格式**：新增 `deniedOrigins`（這個欄位出現之前存的設定視為空清單）與 `proxyOrigins`（自訂代理的「一律允許」清單；沒有這個欄位的舊設定兩種方式沿用同一份清單，行為與以前完全相同）。
- **頁面端**：只會被詢問的網站，不會一載入就被換掉 `WebSocket`：轉接要等 Ruffle 第一次讀 `socketProxy`（電影要載入之前）才安裝，所以沒有 Flash 內容的網頁保有原生 `WebSocket`（網頁含同源 `iframe` 時，Ruffle 的頁框偵測會讀設定而提早安裝，行為仍與原生相同）。已允許的網站行為與以前完全相同（立刻安裝、不詢問）。
- **防護**：一次只開一個視窗；同一個網站的多條連線共用一個問題；排隊上限 8 個網站；每個分頁每次造訪最多 3 個視窗、整個擴充功能每分鐘最多 6 個；預設選取的是「拒絕」；背景服務只接受來自「那個問題自己的視窗」的回答；詢問視窗開著時用一個 Port 保持 MV3 service worker 不被閒置回收（對照實驗：拿掉這個 Port，等 75 秒後回答會失敗）。輸入要符合的條件見下一條。
- **發行前的獨立安全審查與修正**（沒有 critical／high；4 個 medium 與其餘 low 都處理了，沒處理的列在 [`ARCHITECTURE.md`](docs/ARCHITECTURE.md) 的「詢問機制的已知限制」）：
  1. **沒人回答的問題不再佔住連線名額**：等待回答的 Socket 不算進全域 16 條／每頁框 8 條的上限，另有上限（每分頁 4 條、全部 8 條）；以前一個沒人理的問題最多可佔住 16 個名額，讓已允許網站（例如摩爾莊園）的 Socket 拿到 `socket_limit`，選項頁的小幫手檢查也被擋（審查重現過）。回答「允許」時名額已滿就回 `socket_limit`，不會卡住。
  2. **擴充功能自己的頁面不能被網頁嵌進頁框**：manifest 的 `web_accessible_resources` 從 `*` 縮到 `dist/*`（Ruffle）與 `player.html`（SWF 連結導向的獨立播放器）。以前網頁可以把設定頁嵌進頁框、蓋上假畫面，騙人在「允許的網站」文字方塊裡打字再按儲存；現在彈出視窗、設定頁、歡迎頁與詢問頁都載不進頁框。設定頁、詢問頁、彈出視窗的 Socket 區塊在被嵌入時仍什麼都不顯示（雙重防護）。
  3. **自訂代理的 token 只給它自己清單裡的網站**：以前兩種方式共用一份「一律允許」清單，在小幫手模式按過「允許」的網站，使用者之後切到自訂代理就會立刻拿到帶 token 的代理網址（審查重現）。現在 `proxyOrigins` 另立一份。另外，詢問開著時把設定切到自訂代理或停用 Socket，問題現在會自動結束（以前視窗不關、Socket 繼續等，還能在自訂代理的設定下被存成「一律允許」）；收到答案時會先確認模式沒變，寫入時再檢查一次。
  4. **設定頁的舊表單不再悄悄把「一律拒絕」改回去**：以前表單開著時，在彈出視窗把某網站設成「一律拒絕」，回到舊表單按儲存會把它放回允許清單。現在所有設定寫入都在一個跨頁面共用的 Web Lock 裡（不會互相蓋掉），設定頁儲存前比對設定有沒有被改過。
  5. **輸入防護不再只靠時間**：按下要發生在視窗出現／取得焦點後 0.7 秒之後（按著鍵進來、之後才放開不算）；**「允許」只接受指標點擊，鍵盤永遠不能允許**（Tab、Enter、Space 是遊戲登入常打的鍵），滑鼠或觸控筆必須在那 0.7 秒之後在那顆按鈕上移動過；視窗沒有焦點時完全不算。「拒絕」任何輸入都可以。鍵盤使用者要允許請用彈出視窗的按鈕。
  6. 其餘：Ruffle 讀設定時橋接安裝失敗不再讓 Ruffle 的載入跟著失敗；視窗在瀏覽器回報視窗 ID 前就被關掉不再讓問題佇列卡死；瀏覽器沒有 `windows` 事件（Safari）時不再讓整個背景腳本中止；`tabs.onReplaced` 會結束被換掉的分頁的問題；沒有 `nativeMessaging` 的建置（Firefox）不再問一個無法兌現的問題；玩家開關被關掉時問題結束；彈出視窗存不了時不再出現沒處理的錯誤；瀏覽器不告訴分頁網址時，彈出視窗只採用最上層頁框回報的來源（不再採用第一個回應的頁框）。
- **沒有改**：Android 版 Timffle 瀏覽器——它固定使用舊版 Timffle，沒有詢問視窗與彈出視窗，預設允許清單的行為不變。
- 驗證：擴充功能單元測試 144 項（新增：單次造訪紀錄、詢問管理、背景判斷與清理路徑、設定的三態與相容性、兩種方式各自的清單、名額與上限、輸入防護規則、設定寫入的鎖與比對、橋接安裝）；`ask-tests.mjs` 60 項（無頭 Chrome 155＋真的測試版小幫手，**詢問視窗與彈出視窗都是真的**：四種回答、重新整理／另一個分頁／關窗、彈出視窗按鈕與選單、網頁無法嵌入擴充功能的頁面、腳本點擊／鍵盤／沒有移動指標的點擊都不能允許、設定頁的清單切換與舊表單、75 秒後仍可回答）；原有整合測試 73/73（`manual` 預期的設定多了 `allowedOrigins`／`proxyOrigins` 兩份清單；`unapproved-origin` 走詢問路徑，結果仍是沒有連線）；在有畫面的 Chrome（Xvfb）確認詢問視窗 540×680 不需要捲動；型別檢查、品牌檢查通過。**沒有**在 Windows、macOS、Firefox、Safari 驗證，**沒有**用真實遊戲帳號跑，沒有在全螢幕遊戲中試（新視窗可能使全螢幕結束）。

## 0.8.0.26297 — 2026-10-18

- **wgpu 渲染器在只有 256 個頂點 uniform 向量的 GPU 上不再當掉**（Android 模擬器與許多手機 GPU 都是這個 WebGL 2 最低值）。上游 Ruffle 從 2026-09 起每次繪製把最多 200 組 transform 放進一個 uniform 陣列（約 1200 個向量）；有些 WebGL 實作會把它算進 `GL_MAX_VERTEX_UNIFORM_VECTORS`，建立管線時驗證失敗，播放器整個停掉。網頁版建立 wgpu-webgl 前先查這個上限，每次繪製的 transform 數改成「(上限 − 64) ÷ 6」（256 時為 32），超出的照常分批畫；上限夠大的裝置（一般 PC 是 4096）維持 200，行為不變。改動在 `render/wgpu/src/dynamic_transforms.rs`、`render/wgpu/src/lib.rs`、`web/src/builder.rs`。
- **系統語言是中文的 Android 上，遊戲的裝置字型文字不再偏低**（例如摩爾莊園登入失敗提示框的文字）。遊戲指定的 SimSun 在 Android 上不存在，瀏覽器改用 Noto Sans CJK，它的行高是 1.16 + 0.29 em，比 Flash 排版時用的 Windows SimSun（0.86 + 0.14 em）高很多，基線因此往下約 0.28 個字高（12px 字約 3 px）。現在只有在「要求的字型不存在或是 `_sans` 這類通用字型」而且瀏覽器實際用的字型行高超過 1.25 em 時，才改用該字型的中文字框（以 ideographic 基線為底：0.88 + 0.12 em）；裝了該字型的電腦與一般的退回字型（例如 Arial、Roboto）不受影響。改動在 `web/src/ui/canvas_font_renderer.rs`。驗證：Android 模擬器把 App 語言設成 zh-TW 時，提示框文字比修正前高約 4 個 CSS 像素，且比英文系統（Roboto）略高，符合 SimSun 的上緣比 Roboto 低；英文系統下行為不變（判斷不觸發）。**沒有**在實體手機與 Windows 上比對。
- 驗證：在回報 256 的 Android 模擬器（`-gpu swiftshader_indirect`）裡，原本 wgpu-webgl 會 panic，改後能建立渲染器並載入摩爾莊園，Timffle 瀏覽器的 10 項裝置測試（含 Ruffle 的 8 個 socket SWF）通過；該模式的 GPU 轉譯層連一般 WebGL 都畫不對，所以畫面另外在桌面無頭 Chrome 把上限假裝成 256 檢查（每次 32 組）：摩爾莊園首頁與真實上限（200 組）的畫面一致。回報 4096 的 `-gpu swangle_indirect` 模擬器畫面正常。**沒有**在實體手機上試、沒有跑完整上游測試。

- 發行驗證：擴充功能單元測試 38/38、封裝測試 23/23、品牌檢查、本機代理 10/10、比對工具、小幫手 `go test`（含 localtest）通過；對最終 ZIP 的整合測試 73/73；無頭 Chrome 載入這份擴充功能跑 8 個差異測試（3D、透視、drawBitmap、Utils3D、pointTowards、AMF、URLLoader 時序）全部與真 Flash 相同（URLLoader 時序第一次誤判，之後 3 次相同）。小幫手仍是 1.2.0，不需要重裝。
- **發行包**（tag `v0.8.0.26297` = `44f25d94b`）：打包前後的路徑檢查通過，上傳後下載回來再檢查一次也通過。未簽章、未公證。發行包 SHA-256：`d279fa1a10c33f47d5504963f5e953dacf21ab34935b64fb2ac4eef7ae1eeb36`。

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
- **發行包**（tag `v0.8.0.26296` = `d45117e93`）：wasm 以 `--remap-path-prefix` 編譯，`build-extension.sh` 預設就會這樣做；`package-release.sh` 在打包前後用 `check-no-build-paths.py` 檢查，ZIP 裡沒有建置機的家目錄或使用者名稱（先前一份未發布的 ZIP 有帶，沒有上傳）。逐檔掃描也沒有私鑰、憑證區塊與遊戲內部名稱。與那份未發布的 ZIP 相比，91 個檔案中只有 wasm（路徑）、`NOTICE.md`、`README.txt`、介面 CSS、5 張圖示與 5 個 JS 檔（建置資訊，其中 2 個再加播放鍵顏色）不同；小幫手與安裝程式位元組相同，所以整合測試 73/73 沒有重跑。在無頭 Chrome 載入這份擴充功能跑 8 個差異測試：6 個與真 Flash 逐行相同，另 2 個只差已知的 `playerType` 與 LocalConnection 的 release／debugger 錯誤字樣（一個以 400 ms 計時的測試在同一份 wasm 的另一次執行中偶發誤判過一次，之後 4 次通過）。未簽章、未公證。發行包 SHA-256：`3b1f1909e569ee687237f123b1d888e03b82120ce22025861b124610a4745f60`。

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
