# 測試

## 1. 總覽

| 測試 | 驗證什麼 | 怎麼跑 | 需要 |
|---|---|---|---|
| 小幫手單元測試 | 協定、位址政策、流量控制、安裝／移除（含符號連結與外來檔案保護）、不帶引數的安裝（只有零引數會提示或讀 stdin） | `cd timffle/helper && go test ./... && go test -tags localtest ./...` | Go 1.27 |
| 擴充功能單元測試 | 設定與允許／拒絕清單（兩種連線方式各一份）、頁面橋接、背景權限、第一次連線的詢問（詢問管理、單次造訪的回答、各種回答與清理路徑、等待中的 Socket 不佔名額）、輸入防護規則、設定寫入的鎖與比對、舊設定的升級、介面語言（36 種語言每一句都有、佔位符與技術用詞沒被翻掉、按鈕與說明用詞一致、各語言用自己的文字）、`i18n.ts`（含圖片、替代文字的取用與依介面語言顯示或隱藏元素）與彈出視窗的狀態文字、羅技折扣碼區塊（只有英文與中文有那六句文字、區塊預設隱藏、連結網址一字不差、橫幅檔案存在且尺寸對、頁面不從網路載入東西、程式碼不提到該網站）、系統判斷與安裝檔下載（`helper-download.ts`：每種系統與處理器對到哪個安裝檔、Mac 只看處理器、不猜、下載方式與網址、檔名與釘住的版本和 `main.go` 及封裝腳本一致、彈出視窗按鈕的各種情形）、「請先安裝小幫手」視窗（`helper-prompt.ts`：一次一個、同一次頁面載入只提示一次且服務工作者重啟後仍記得、還開著的視窗讓位給下一次頁面載入的視窗（含視窗開到一半、分頁被關、Timffle 被關掉）、每分鐘 3 個、被拒絕的不記、開不了視窗的不重試、視窗開到一半被關、儲存損壞或讀不到；背景把失敗的 Socket 接到視窗並帶上瀏覽器報的頁框資訊、其他種失敗不開、沒有原生訊息的瀏覽器不開、與詢問視窗的先後；提示頁的元素與腳本對得上、標題在 36 種語言都有），共 257 項 | `cd web && npm ci && npm test --workspace=ruffle-extension` | 不需要 wasm |
| 封裝測試 | 發行 ZIP 的內容、權限、授權檔與私鑰檢查（24 項）；每個系統的安裝檔（`package-installers.py`：檔名、處理器標頭、zip／tar.gz 的內容與權限、可重現、拒絕的情形，另有一次真的建置＋解開＋不帶引數執行＋Wine，24 項）；路徑檢查（`check-no-build-paths.py` 看 ZIP、資料夾、zip 與 tar.gz 成員，13 項） | `cd timffle/helper/installer-tests && python3 -I test_package.py && python3 -I test_installers.py && python3 -I test_check_paths.py` | Python 3；真的建置那項另需 Go，Wine 那項另需 Wine（沒有就跳過） |
| 品牌檢查 | 使用者看得到的文字沒有「Ruffle」產品名、手改的連結都還在 | `python3 timffle/scripts/rebrand.py --check` | Python 3 |
| 語言檢查 | `timffle/locales/` 與擴充功能的訊息目錄一致，每種語言都有每一句，佔位符與標記沒被翻掉 | `python3 timffle/scripts/sync_locales.py --check` | Python 3 |
| 本機代理測試 | `relay/` 的來源、token、私網位址拒絕等（10 項） | `node --test timffle/relay/relay.test.mjs` | Node 22+ |
| 比對工具測試 | 差異測試的比對規則（11 項） | `cd timffle/difftest && python3 test_compare.py` | Python 3 |
| **差異測試** | Ruffle 與真 Flash 逐行相同 | 見第 2 節 | Haxe、Xvfb、Ruffle 桌面版；產生答案另需 Flash 32＋Wine |
| 網頁版冒煙測試 | 在 Chrome 裡用擴充功能跑差異測試 SWF | 見第 3 節 | Chrome、建好的擴充功能 |
| 瀏覽器＋小幫手整合測試 | 無頭 Chrome＋真小幫手，只連 localhost | 見第 4 節 | 解壓後的發行包、測試版小幫手 |
| 介面語言測試 | 每種語言各開一個真 Chrome：頁面顯示該語言的文字、語言與方向屬性正確、沒有東西超出框 | `node timffle/tools/native-regress/locale-tests.mjs <解壓後的擴充功能資料夾> [語言…]` | Chrome、建好的擴充功能 |
| 真實帳號冒煙測試 | 登入並走一段遊戲流程 | 見第 5 節 | 你自己的帳號；手動、不屬於自動化測試 |
| Ruffle 自身回歸 | 上游測試套件加上本專案新增的測試 | 在 repo 根目錄 `cargo test -p tests --test tests` | 完整 Rust 工具鏈 |

## 2. 差異測試（difftest）

**想法：** 把一個小的 ActionScript 3 測試程式（用 Haxe 編成 SWF）分別在真 Flash Player 32 和在 Ruffle 裡執行，兩邊都把「觀察到的行為」一行一行回報給本機的測試伺服器，再逐行比對。真 Flash 的輸出存成**黃金答案**（`difftest/expected/<測試>.txt`）；之後只要 Ruffle 的輸出與黃金答案相同，就代表行為與 Flash 一致。以真實播放器的輸出當標準，比對規格書或猜測可靠得多——本專案的 3D、`Matrix3D`、命中測試規則都是這樣量出來的（見 [`FLASH-NOTES.md`](FLASH-NOTES.md)）。

目前收錄 30 個黃金答案：`t*`（LocalConnection、URLStream 基本行為）、`r*`（回歸：循環參照、`client` 為原始型別、`URLStream` 狀態與 API、AMF3 循環、`Loader`／`URLLoader` 取消與事件時序）、`d13`～`d40`（3D、`Matrix3D`、`Utils3D`、`BitmapData.draw`）。需要遊戲檔案才能跑的測試**不在** repo 內。

### 環境變數

| 變數 | 說明 |
|---|---|
| `FLASH_EXE` | `flashplayer_32_sa.exe`（Adobe 的 standalone projector）的路徑。**Adobe 的軟體不在本 repo**，需自行取得合法的副本 |
| `WINE_DIR` | 放 `wine` 與 `wineserver` 的資料夾（空白＝用 PATH） |
| `WINEPREFIX` | 專用的 Wine prefix（預設 `difftest/.wineprefix`） |
| `RUFFLE_BIN` | 要測的 Ruffle 桌面版執行檔（預設 PATH 裡的 `ruffle`）。**環境變數不會跨 shell 保留**，請寫在同一個指令列上，否則會悄悄用到舊的執行檔 |
| `HAXE` | `haxe` 的路徑（預設 PATH；需要設好 `HAXE_STD_PATH`） |

### 流程

```sh
cd timffle/difftest
./build_all.sh                      # 編出所有測試 SWF 到 bin/
python3 server.py                   # 另一個終端機：HTTP 18765（發 SWF、收報告）、TCP 18766（Socket 測試）

RUFFLE_BIN=/path/to/ruffle ./run_all.sh               # 只跑 Ruffle，與 expected/ 比對
RUFFLE_BIN=/path/to/ruffle ./run_all.sh d19render3d   # 只跑一個
RUFFLE_BIN=/path/to/ruffle ./run_all.sh --flash       # 也跑真 Flash（需要 FLASH_EXE 與 Wine）
./compare.py --bless 新測試                           # 確認 Flash 的輸出可信後，存成新的黃金答案
python3 verify_flash_goldens.py                       # 只檢查最新一次 Flash 輸出是否仍等於黃金答案
```

比對時會忽略以 `~` 開頭的行（計時、版本、各播放器容許不同的原始數值）。一個黃金答案**至少要跑兩次真 Flash**確認輸出穩定才存。

### 新增一個測試

1. 在 `src/` 放一個 Haxe 類別：`H.init("測試名")` → 一連串 `H.log("…")` → `H.done()`。想當 Ruffle 自身回歸測試用的，改用 `Out.start/line/finish`（`-D harness` 時走回報，否則是 `trace`，格式對得上 Ruffle 的 `output.txt`）。
2. 在 `build_all.sh` 加一行 `./build.sh 類別 測試名 [-swf-version 17] [-D swf-header=寬:高:幀率:背景色]`。
3. 先在真 Flash 跑（兩次）看輸出，再 `--bless`。
4. 實作／修正 Ruffle，直到 `./run_all.sh` 全部通過。

### 踩過的坑

- **會讓 Ruffle 崩潰的案例放在自己的 SWF**（用 `-D` 變數切換），因為崩潰會讓整份報告遺失。
- **`LocalConnection` 物件要放在靜態欄位**：Flash 會回收區域變數，連線就悄悄消失。
- **Haxe 的 `catch (e:Dynamic)` 會把例外包成 `haxe.Exception`**，它的堆疊正規化在發行版播放器（Flash 與 Ruffle 都一樣）會丟 `TypeError #1009`，整個步驟悄悄中止。要用 `catch (e:flash.errors.Error)` 並印 `e.errorID`／`e.name`。把有風險的呼叫寫成「步驟」，用 `haxe.Timer.delay` 串起來執行（範本：`D26Steps.hx`），一步中止不會蓋掉後面。
- **`Math.round` 回傳 `Int`**：NaN 印成 0，乘上 10000 後超過 2³¹ 會繞回。NaN／Inf／很大的數要單獨一個分支印。
- **`~` 行**：例如 `Matrix3D.decompose` 對奇異矩陣會回傳未初始化的記憶體（每次不同），那一行必須標 `~`。
- **`BitmapData.draw(stage)`** 只畫到舞台子物件的 2D 邊界：畫 3D 內容時，測試要放一個與舞台一樣大的底圖。
- **事件順序的測試要看「真 Flash 在 Wine 下的 standalone」**，這不是原生 Windows 上的結果，結論要保守。

## 3. 網頁版冒煙測試（`timffle/tools/chrome-smoke/`）

把建好的擴充功能（解壓後的資料夾）載入一個全新的無頭 Chrome 設定檔，再把差異測試的 SWF 丟進去跑，輸出放進 `difftest/results/chromeext/`，同樣可以和黃金答案比對：

```sh
python3 difftest/server.py &      # 或另開終端機
node timffle/tools/chrome-smoke/smoke.mjs <解壓後的extension資料夾> <全新設定檔資料夾> <輸出資料夾> - d19render3d d13perspective …
diff <(grep -v '^[#~]' difftest/expected/d19render3d.txt) <(grep -v '^[#~]' difftest/results/chromeext/d19render3d.txt)
```

注意：正式版的 Chrome 會忽略 `--load-extension`，所以腳本是經由 CDP（`--remote-debugging-pipe --enable-unsafe-extension-debugging` 加 `Extensions.loadUnpacked`）載入。Chrome 會把 `_metadata/` 寫進它載入的資料夾，比對檔案時請另外解壓一份乾淨的。**Ruffle 網頁版的堆疊溢位之後，主控台記錄會長到數百 KB（"Unable to lock Ruffle core"），不要直接 `cat`。**

`smoke-shot.mjs` 同理，另外會截圖（`SHOT_ONLY=1 SHOT_DIR=…`）。`timffle/tools/screenshots/shot.py` 則是在私有的 Xvfb 裡用真 Flash 或 Ruffle 桌面版截圖，方便把兩邊的畫面並排比較。

## 4. 瀏覽器＋小幫手整合測試（`timffle/tools/native-regress/`）

用**測試版小幫手**（以 `-tags localtest` 編譯，允許連 localhost）加無頭 Chrome，驗證擴充功能與小幫手的整條鏈：只連本機，**從不連真正的遊戲伺服器**。

```sh
(cd timffle/helper && CGO_ENABLED=0 go build -tags localtest -o ../build/localtest/timffle-socket-helper .)
PACKAGE_DIR=<解壓後的發行包資料夾，內含 extension/ 與 helper/> \
LOCALTEST_HELPER=$PWD/timffle/build/localtest/timffle-socket-helper \
TEST_FONTCONFIG=<選用：給無頭 Chrome 的 fontconfig 檔，用來顯示中日韓字型> \
  timffle/tools/native-regress/run-regression.sh
```

涵蓋六種情境（最近一次：前五種共 154 項、第六種 66 項，全部通過；另有 `production` 情境 22 項，檢查正式版小幫手拒絕私網位址）：

**小幫手提示與「直接下載安裝程式」的檢查**（`browser-auto-tests.mjs` 的每個情境都跑；缺小幫手的情境檢查提示出現，其他情境檢查提示不出現）：

- **假的 GitHub**（`fake-github.mjs`）：測試瀏覽器用 `--host-resolver-rules` 把 `github.com` 與 `release-assets.githubusercontent.com` 導到本機的 TLS 伺服器（自簽憑證，加 `--ignore-certificate-errors`），伺服器照真的 GitHub 的方式回應：release 網址轉址（302），檔案伺服器以附件（`Content-Disposition: attachment`）回應。**測試從來不連真的 GitHub**；沒有這兩個旗標的瀏覽器不會跑到這裡。下載用 CDP 的 `Browser.setDownloadBehavior` 存到測試資料夾，並以 `Browser.downloadProgress` 事件確認「存好了」與檔名。
- **按鈕**：設定頁的「直接下載安裝程式」真的畫在頁面上（不只是沒有 `hidden`）或真的不在；按鈕下面那一行（「適用於 Linux x64」）與「其他系統與安裝說明」連結（`target=_blank`、`rel=noopener noreferrer`、指向 `helper.html`）；彈出視窗的提示文字與按鈕（等頁面與樣式表載完才讀，並且用計算後的 `display` 與高度判斷，因為單靠 `hidden` 類別看不出樣式是否蓋掉它）。
- **點擊**：腳本產生的點擊什麼都不做（假 GitHub 沒收到任何請求、沒有檔案被存下來）；真的滑鼠點擊（`Input.dispatchMouseEvent`）立刻開始下載——假 GitHub 收到對的路徑（`/Im-Tim-mI/Timffle-Helper/releases/download/v1.4.0/<檔名>`）、檔案存好且內容正確、提示換成「已開始下載…」、開去抓檔案的分頁自己關掉（沒有 GitHub 的分頁、也沒有開安裝頁）；連點兩下只下載一次；連結開安裝頁。
- **每一種系統**（`missing` 情境）：用 `Emulation.setUserAgentOverride` 的 `userAgentMetadata` 讓 Chrome 以為自己在 Windows 64-bit／ARM64／32-bit、macOS Apple silicon／Intel、Linux x64／ARM64 上，各按一次真的按鈕，檢查按鈕下面的標籤、存下來的檔名與向 GitHub 要的路徑；Chrome OS、Android、處理器不明的 Mac 沒有按鈕、不下載、仍有「其他系統與安裝說明」。**release 不存在**（假 GitHub 回 404）時沒有存任何檔案，開出來的分頁停在 GitHub 的「找不到頁面」。
- **安裝頁**：狀態、標題、每個系統一組（每個安裝檔的直接下載連結：網址、順序、**這台電腦的排最前並標記**、檔名在由左到右的 `code` 裡）、Linux 那行指令與它的 `code`、連結（`target=_blank`、`rel=noopener noreferrer`）、「重新檢查」，真的點一個連結會下載那個檔案，以及分頁回到前景時自動再檢查一次（狀態句子先變「檢查中」再回到原來的結果）；遊戲分頁因找不到小幫手而得到紅色「!」（顏色 `[217,48,37,255]`），分頁導覽走之後徽章消失；小幫手正常的情境裡沒有任何分頁有徽章。

- **「請先安裝小幫手」視窗**（`missing` 與 `incompatible` 情境，`notice-window-*`）：遊戲的頁面一需要 TCP 連線就開一個視窗（網址是 `prompt.html?id=…`）；視窗寫的是那個頁面的來源、標題、出了什麼問題（`missing`：「尚未安裝」；`incompatible`：「版本不相容」）、為什麼需要小幫手、安裝程式的保證，下載按鈕與「適用於 Linux x64」都在，「關閉」有焦點，沒有詢問的區塊也沒有「已失效」；腳本點擊什麼都不做、真的點擊下載（假 GitHub 收到對的路徑、存好內容正確的檔案、句子換成「已開始下載…」、沒有 GitHub 的分頁留下、視窗還在）、連點兩下只下載一次、「其他系統與安裝說明」在瀏覽器的一般視窗開出安裝頁而視窗還在、「關閉」關掉視窗。**同一次頁面載入只提示一次**：同一頁在視窗還開著時再連線，不多開、也不換掉它（`notice-window-same-page-load-keeps-its-one-window`）；重新整理那一頁，新的頁面載入的視窗**取代**還開著的舊視窗，一共只有一個（`notice-window-next-page-load-replaces-the-window-that-is-still-open`）；視窗關掉之後，同一頁再開一條 Socket 不會再開（`notice-window-not-again-for-the-same-page-load`）。**第一刻的輸入保護**（`notice-window-ignores-clicks-and-escape-in-its-first-moment`）：把視窗頁面重新載入，0.7 秒就重新開始，在這一刻內用 `Input.dispatchMouseEvent` 的真實點擊分別點下載、其他系統、關閉，再按 Escape，全都什麼也不做（假 GitHub 沒收到請求、沒存檔案、沒開安裝頁、視窗還在；只有真的落在這一刻內的嘗試才算數，沒趕上的會重試）；過了這一刻，只是自動重複的 Escape 與 Enter（`Input.dispatchKeyEvent` 的 `autoRepeat: true`，等於遊戲裡按住的鍵一直重複進來）仍什麼也不做（`notice-window-ignores-a-key-that-only-repeats`），單獨按一下 Escape 才關得掉視窗（`notice-window-closes-with-escape-after-the-moment`）。視窗的 `document.title` 是它自己的標題，不是詢問視窗的。有畫面的 Chrome（`CHROME_HEADED=1 CHROME_WINDOW_SIZE=none`，例如 `xvfb-run`）另外檢查真的 540 × 620 視窗裡內容不用捲動（`notice-window-fits-its-window-without-scrolling`；無頭模式的 Chrome 自己決定視窗大小，只記錄不判斷）。

**對照實驗**：把彈出視窗樣式表裡 `.helper-notice.hidden { display: none }` 拿掉，`localtest` 的 `popup-no-notice-when-helper-works` 與 `ask-tests.mjs` 的 `popup-controls-and-the-discount-summary-fit-the-600px-chrome-allows`（提示佔掉高度，區塊標題列掉到 610 px）都失敗；原因是 `.helper-notice` 自己的 `display: flex` 贏過 `.hidden`，提示在小幫手正常時也畫出一個空框。

| 情境 | 項數 | 內容 |
|---|---|---|
| localtest | 36 | 正常連線、二進位傳輸、拒絕未允許的網站、流量控制、關閉與清理；小幫手正常時彈出視窗沒有提示、安裝頁顯示已安裝並列出所有安裝檔 |
| missing | 80 | 找不到小幫手時的錯誤與選項頁的訊息；彈出視窗的提示、按鈕與下載（七種系統、三種沒有安裝檔的系統、release 不存在）、設定頁的按鈕、安裝頁、遊戲分頁的紅色「!」與「請先安裝小幫手」視窗（見上） |
| delayed | 21 | 小幫手很慢才回應 |
| incompatible | 53 | 協定不相容（提示、按鈕與下載、安裝頁、徽章與視窗同 missing，不含七種系統的巡禮） |
| manual | 8 | 自訂 WebSocket 代理模式 |
| ask | 67 | 第一次連線的詢問、字型設定與彈出視窗（見下） |

### 第一次連線的詢問（`ask-tests.mjs`）

單獨執行：`node timffle/tools/native-regress/ask-tests.mjs <解壓後的extension資料夾> <測試版小幫手>`（約 4 分鐘；`run-regression.sh` 也會跑）。在無頭 Chrome 裡用真的測試版小幫手與真的擴充功能頁面——**詢問視窗與彈出視窗都是真的**（彈出視窗用 `chrome.action.openPopup()` 開，按鈕與下拉選單用 CDP 的真實輸入事件操作，因為頁面不接受腳本產生的點擊）：

| 區段（`ASK_ONLY=` 的名稱） | 驗證什麼 |
|---|---|
| `basics` | 沒有 Flash 的網頁保有原生 `WebSocket`；第一次連線開出詢問視窗、文字與警告、預設選取「拒絕」、問題開著時不連線；「允許」連上並且什麼都不存、重新整理同一頁不再問、另一個分頁再問；「拒絕」與不再重問；「一律允許」連上、存進設定、不再問；「一律拒絕」拒絕、存進設定、之後該網站收不到 `socketProxy` 且 `WebSocket` 仍是原生的 |
| `popup` | 彈出視窗：一鍵加入「一律允許」且不需輸入、改成一律拒絕／每次造訪時詢問／一律允許、允許後「重新載入」按鈕亮起、頁面照新設定連線；高度 ≤ 600 px（Chrome 彈出視窗的上限；英文與中文的折扣區塊預設展開，所以那兩種改量區塊之上的部分，細節見下）；頁框內另一個網站被詢問後列在彈出視窗並可單獨允許；非網站的分頁、Socket 已停用、自訂代理模式的顯示 |
| `framing` | 網頁把 `popup.html`、`options.html`、`onboard.html`、`prompt.html`、`helper.html` 嵌進頁框：瀏覽器拒絕載入（對照：manifest 開放的 `player.html` 載得進來）；網頁拿得到 Ruffle 與 wasm 但拿不到那四個頁面；SWF 位址（直接輸入、或從網頁上的連結點進去）仍被導向獨立播放器（`player.html` 在開放清單裡的原因）；萬一被嵌入（改由擴充功能自己的頁面去嵌），設定頁與詢問頁什麼都不顯示、彈出視窗的 Socket 區塊不顯示 |
| `dismissal` | 關掉詢問視窗＝這次造訪拒絕，重新整理不會再問 |
| `guard` | 詢問視窗的輸入防護：腳本產生的點擊不能回答；Tab 到「允許」再按 Enter／Space 不能回答；沒有先在按鈕上移動指標的按下不能回答；視窗沒有焦點時不算、取得焦點後 0.7 秒內不算；之後真的點擊可以回答；鍵盤可以「拒絕」；自動重複的 Enter／Escape（`autoRepeat: true`）不回答、也不關視窗 |
| `options` | 設定頁：小幫手與自訂代理各有自己的清單、切換時保留各自輸入、儲存只改目前方式的清單；自訂代理的 token 只給它自己清單裡的網站（真的頁面讀 `RufflePlayer.config.socketProxy`，只在小幫手清單裡的網站讀不到）；沒有編輯的表單跟著別處的變更更新；有編輯的表單收到警告，儲存時被拒絕並顯示最新設定，**舊表單不能把「一律拒絕」改回去** |
| `keepalive` | 詢問視窗開著、什麼都不做，等 75 秒（超過 MV3 service worker 30 秒閒置回收）後仍能回答。**對照實驗**：把詢問頁的保活 Port 拿掉，同一個測試會失敗（視窗還在，但回答不被接受，因為 service worker 已被回收、問題丟了）；所以這個測試確實量到保活機制，等待時間可用 `ASK_IDLE_MS` 調整 |
| `fonts` | 網站的 Socket 決定不影響文字怎麼畫：「一律允許」「每次造訪時詢問」「一律拒絕」「停用 Socket」四種狀態下，頁面收到的 `deviceFontRenderer` 都是 `canvas`（Ruffle 內建的字型沒有中文字，只有瀏覽器字型畫得出中文；曾經只有「一律允許」是 `canvas`，被詢問或拒絕的遊戲中文會消失）；使用者在選項頁明確選的渲染器仍然優先 |

`ASK_ONLY=popup,framing` 只跑指定的區段。輸入防護用真的 CDP 輸入事件測（`Input.dispatchMouseEvent`／`dispatchKeyEvent`，鍵盤要送帶字元的 `keyDown` 才會啟動按鈕）；沒有移動指標的按下是只送 `mousePressed`／`mouseReleased`。「按下發生在 0.7 秒之前」這類時間規則由 `tests/prompt-guard.test.mjs` 單元測試涵蓋（端對端測試做不到精確的時間控制）。

### 介面語言

整合測試的 Chrome 預設用英文；`TEST_LOCALE=zh_TW`（或 `ar`、`ja`…）讓整套 `ask-tests.mjs`、`browser-auto-tests.mjs` 改用那種語言跑（Chrome 以環境變數 `LANGUAGE` 決定介面語言）。預期的文字一律從擴充功能的訊息目錄讀（`catalog.mjs`），測試裡沒有寫死任何語言。擴充功能每分鐘最多開 6 個詢問視窗（`MAX_PROMPTS_PER_MINUTE`），所以 `ask-tests.mjs` 自己控制節奏（`spacing()`），跑得再快也不會被這個上限擋掉。

`locale-tests.mjs` 逐一用每種語言開真 Chrome（不需要小幫手或網路；沒有小幫手，所以彈出視窗的提示、設定頁的按鈕與安裝頁都在顯示狀態），檢查設定頁、詢問視窗、安裝頁與彈出視窗：Chrome 真的在那種語言下執行、頁面每個標記的元素都是該語言目錄裡的文字、`lang` 與 `dir`（阿拉伯文、希伯來文為 `rtl`，按鈕順序跟著反過來）、聲明裡的兩個連結、粗體警告的位置、沒有水平溢出或被截斷的按鈕。Chrome 沒有波士尼亞文、世界語、加利西亞文與韃靼文的介面語言，這四種只確認 Chrome 退回英文且頁面顯示英文而不是鍵名（它們的目錄內容由單元測試涵蓋）。另外檢查羅技折扣碼區塊（只有英文與中文介面顯示，因為那是台灣商店的優惠）：英文、繁體中文與簡體中文的設定頁標題、聲明與替代文字是該語言的文字、橫幅是該語言的那一張（中文用中文橫幅、英文用英文橫幅）且以 720×405 載入、兩個連結的網址與 `rel` 一字不差；彈出視窗裡的區塊預設展開（標題列一行、不被截斷、不超過 28 px，內容與設定頁相同），折疊後頁面縮小至少 140 px。**其他語言**（有 Chrome 介面的 29 種）設定頁與彈出視窗都確認看不到這個區塊（隱藏、不繪製、高度 0）。`SHOTS=<資料夾>` 另外存每種語言的詢問視窗與設定頁截圖（英文與中文還有彈出視窗），用來肉眼檢查版面。最近一次（0.8.0.26305）：36 種語言、1064 項檢查，全部通過（每種有 Chrome 介面的語言也檢查按鈕下面那一行與「其他系統與安裝說明」連結放得進提示框，並檢查安裝頁每個系統一組的結構，以及「請先安裝小幫手」視窗放得進 540 × 620 的視窗：用很長的網站名稱與最長的系統名稱，內容高度不超過 580 px［真視窗還有標題列］、沒有東西超出寬度、標題與「嵌入在…」那一行是那種語言的、三個控制項由上而下）。`ask-tests.mjs` 量真的彈出視窗：沒有折扣區塊的語言，整個彈出視窗不超過 600 px（最高是阿拉伯文 569 px，其次日文 563 px、俄文 546 px；`popup-fits-the-600px-chrome-allows`），並檢查沒有區塊（`popup-has-no-discount-box-in-this-language`）。英文與中文的區塊預設展開，彈出視窗因此比 600 px 高（內容英文 867 px、中文 841 px），所以改檢查三件事：區塊之上的控制項加上標題列放得進 600 px（英文 539 px、中文 550 px；`popup-controls-and-the-discount-summary-fit-the-600px-chrome-allows`）；展開的區塊在真的彈出視窗裡可以捲到最底、整個聲明看得到、沒有橫向溢出（出現捲軸時 Chrome 會把彈出視窗加寬 15 px，內容維持 340 px；`popup-discount-box-is-open-and-scrolls-to-its-end`）；按標題列真的可以折疊，折疊後整個彈出視窗不超過 600 px（英文 522 px、中文 533 px；`popup-discount-box-can-be-folded-and-then-the-popup-fits-600px`）。

**已知會偶爾失敗的一項**：`browser-auto-tests.mjs` 的 localtest 情境裡的 `local-close-no-remote-close-event`（頁面在連線完成前就關掉 Socket，測試 SWF 的 `connect` 事件偶爾晚到）。用舊版（0.8.0.26300）與舊腳本跑 8 次失敗 4 次，所以與介面語言的改動無關；重跑通常就過，原因還沒查清。

另外 `timffle/tools/screenshots/socket-ui-shots.mjs` 用同樣的環境產生 README 用的設定頁、彈出視窗、詢問視窗截圖（`SHOT_LOCALE=zh_TW` 等指定語言，預設英文）（詢問視窗與彈出視窗顯示的網站名稱換成範例的 `https://game.example`，其餘是真的頁面）。

## 5. 真實帳號冒煙測試（`timffle/tools/real-login/`，手動）

用你**自己的帳號**驗證登入與基本遊戲流程。`rl-driver.mjs` 啟動無頭 Chrome（載入擴充功能、在拋棄式的 HOME 裡安裝小幫手），提供一個只聽 127.0.0.1 的小型控制 API（截圖、點擊、輸入、讀取主控台、導覽…），由你的步驟檔驅動。

- 帳號與密碼放在權限 0600 的兩行檔案（帳號、密碼）。驅動程式只用 `/cred` 把它們逐鍵輸入頁面，並且在所有輸出（含主控台、`/eval` 結果）裡遮蔽帳號、密碼與密碼的 MD5。
- `redact_png.py` 可以把截圖中的指定區域塗黑，發布截圖前請使用。
- **不要把憑證檔、含帳號的截圖或日誌提交到 repo**；測試完畢請銷毀憑證檔。若曾把密碼貼進聊天或日誌，請改密碼。
- 這個測試會連到真正的遊戲伺服器，請遵守遊戲的服務條款，自行承擔風險。

## 6. Ruffle 自身回歸

```sh
cargo test -p tests --test tests      # 在 repo 根目錄
```

Timffle 新增了 5 個測試在 `tests/tests/swfs/avm2/`（`localconnection_cyclic_args`、`localconnection_client_primitive`、`urlstream_initial_state`、`urlstream_optional_api`、`bytearray_amf3_cycles`），它們是差異測試黃金答案的 `trace` 版本。

**誠實的說明：** 發行 0.8.0.26294 時，我們是在只簽出 40 個上游 SWF 測試的稀疏 checkout 上跑這個套件（共 46 項通過），渲染單元測試 60/60。**修補後的樹沒有跑過完整的上游測試套件**；在把任何補丁回饋上游之前，必須在完整 checkout 上跑完。
