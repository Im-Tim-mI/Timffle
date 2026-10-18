<p align="center">
  <img src="timffle/branding/timffle-icon.svg" alt="" width="112" height="112">
</p>

<h1 align="center">
  <img src="timffle/branding/timffle-logo.svg" alt="Timffle" width="420">
</h1>

<p align="center"><b>讓淘米台灣的 Flash 遊戲，在 Chrome 裡繼續玩。</b></p>

<p align="center">摩爾莊園 ・ 賽爾號 ・ 小花仙 ・ 彈彈堂</p>

<p align="center">
  <a href="https://github.com/Im-Tim-mI/Timffle/releases/latest"><b>下載最新版</b></a> ・
  <a href="#安裝方法">安裝方法</a> ・
  <a href="#疑難排解">疑難排解</a> ・
  <a href="README.en.md">English</a>
</p>

<p align="center">版本 <code>0.8.0.26299</code>（基於 Ruffle nightly 2026-10-13）｜ 授權 MIT 或 Apache-2.0（任選其一）</p>

> [!IMPORTANT]
> **Timffle 是 [Ruffle](https://ruffle.rs/) 的非官方分支，與 Ruffle 專案、Ruffle LLC、淘米網絡（Taomee）沒有隸屬或合作關係，也沒有得到它們的認可。** Flash 模擬核心幾乎全部是 Ruffle 與其[數百位貢獻者](https://github.com/ruffle-rs/ruffle/graphs/contributors)的成果；本 repo 保留了 Ruffle 完整的 git 歷史、作者紀錄與授權檔。
> **Timffle 的問題請回報到 [Timffle 的 Issues](https://github.com/Im-Tim-mI/Timffle/issues)，不要回報給 Ruffle。** 「Ruffle」名稱與標誌屬於 Ruffle 專案，所以本分支使用 Timffle 這個名字與自己的圖示（見 [`timffle/docs/BRANDING.md`](timffle/docs/BRANDING.md)）。Ruffle 原本的說明文件保留在 [`README.ruffle.md`](README.ruffle.md)。

---

## 簡介

Adobe 已在 2020 年底終止 Flash，Chrome 也早已移除它。淘米台灣的《摩爾莊園》《賽爾號》《小花仙》《彈彈堂》仍是 Flash（ActionScript 3）網頁遊戲，而且**透過 TCP Socket 連線遊戲伺服器**。要在現在的 Chrome 裡玩，光有一個 Flash 模擬器還不夠：

1. 模擬器要完整支援這些遊戲用到的 Flash 功能（`LocalConnection`、`URLStream`、`Loader`／`URLLoader` 的取消、3D 透視、`Matrix3D`…），否則遊戲會卡住、點了沒反應，或畫面位置錯誤。
2. Chrome 擴充功能不能直接開 TCP 連線，需要一個本機的小程式幫忙轉接。

Timffle 把這兩件事一起做好：**修補過的 Ruffle（WebAssembly）加上只需安裝一次的連線小幫手**，打包成一個 Chrome 插件包。下載、安裝，打開遊戲網址就能登入、玩。

> [!NOTE]
> Timffle 只是讓瀏覽器能執行這些遊戲，不修改遊戲的內容、規則或資料，也不包含任何遊戲素材。它不是遊戲的官方軟體；使用第三方執行環境是否符合各遊戲的服務條款，請自行確認，風險由使用者自負。請只使用自己的帳號。

## 特色

- **一個插件包就夠**：[Releases](https://github.com/Im-Tim-mI/Timffle/releases/latest) 提供 `timffle-chrome-<版本>.zip`，內含 Chrome 插件、連線小幫手（Windows／macOS／Linux）與安裝程式。
- **不用設定代理**：預設允許四個遊戲網站使用 Socket 連線，不需要另外開任何服務或視窗；其他網站第一次想用時，Timffle 會先跳出視窗詢問你（建議拒絕，只有線上遊戲可以允許）。
- **以真 Flash 為標準答案**：對 Ruffle 的相容性修正，都用 Adobe Flash Player 32 的實際輸出逐行比對（30 項黃金答案）。
- **保守的安全設計**：只有你允許的網站能使用連線（不在清單的網站要先經過你同意）；小幫手只連公開網路位址、不監聽任何連接埠、不常駐、不記錄連線內容。
- **開源，並保留上游歷史**：完整保留 Ruffle 的 git 歷史、作者紀錄與授權；Timffle 自己的部分以 MIT 或 Apache-2.0（任選其一）授權，與 Ruffle 相同。

## 快速開始

1. 到 [Releases](https://github.com/Im-Tim-mI/Timffle/releases/latest) 下載最新版的 `timffle-chrome-<版本>.zip`（**Chrome 插件包**），解壓縮到一個固定的位置。
2. 執行 `helper` 資料夾裡的安裝程式：Windows `install-windows.cmd`、macOS `install-macos.command`、Linux `sh install-linux.sh`。**只要一次。**
3. 開啟 `chrome://extensions` → 打開「開發人員模式」→「載入未封裝項目」→ 選擇 `extension` 資料夾。
4. 打開遊戲網站，例如 https://mole.61.com.tw/ ，按播放器的播放鍵，照常登入。

詳細步驟與注意事項見[安裝方法](#安裝方法)。

## 支援狀態

| 遊戲 | 網址 | 狀態 |
|---|---|---|
| 摩爾莊園 | https://mole.61.com.tw/ | **已用真實帳號驗證**（Linux＋Chrome 155，版本 0.8.0.26294；之後的版本行為相同，只有名稱、美術與結構改變）：登入、本地帳號頁（3D 轉盤）、進入世界、走路、換地圖、賽車座位。 |
| 賽爾號 | http://seer.61.com.tw/ | 預設放行 Socket 連線，**未實測遊玩**。 |
| 小花仙 | http://hua.61.com.tw/ | 預設放行 Socket 連線，**未實測遊玩**。 |
| 彈彈堂 | http://ddt.61.com.tw/main_index.php | 預設放行 Socket 連線，**未實測遊玩**。 |

| 平台 | 驗證程度 |
|---|---|
| Linux x64＋Chrome 155 | **實機驗證**：安裝／移除、自動啟停、二進位傳輸、連線失敗處理、摩爾莊園遊戲流程 |
| Windows 10／11 x64 | 小幫手與安裝／移除程式在 **Wine 模擬環境**測試（Wine 不是 Windows 實機） |
| Windows 32 位元與 ARM64、macOS（Intel／Apple Silicon）、Linux ARM64 | 只做了交叉編譯，**未實機測試** |

安裝程式替 **Google Chrome** 註冊小幫手（Linux／macOS 上，Beta／Dev／Canary 與 Chromium 只在你用過、使用者資料夾已存在時才註冊）；Edge、Brave 等其他 Chromium 系瀏覽器不會被註冊。小幫手尚未取得 Microsoft 或 Apple 的簽章／公證。

## 安裝方法

### 需求

- **Chrome 桌面版**（Windows 10/11、macOS、Linux；實測 Chrome 155），需要 Manifest V3 擴充功能與 Native Messaging。
- 不需要 Node.js、不需要系統管理員權限、不需要另外開任何服務或視窗。

### 步驟

1. **下載**：到 [Releases](https://github.com/Im-Tim-mI/Timffle/releases/latest) 下載 `timffle-chrome-<版本>.zip`，並核對 SHA-256：

   ```sh
   sha256sum -c timffle-<版本>-SHA256SUMS.txt     # Linux
   shasum -a 256 -c timffle-<版本>-SHA256SUMS.txt # macOS
   ```

   解壓縮後會得到 `timffle/`，裡面有 `extension/`（Chrome 插件）、`helper/`（連線小幫手與安裝／移除程式）、`LICENSES/`（授權檔）、`NOTICE.md`、`README.txt`。**請把整個資料夾放在固定位置**，之後不要刪除或搬移。

2. **安裝連線小幫手（只要一次）**——它讓 Chrome 插件能連到遊戲伺服器：

   | 系統 | 做法 |
   |---|---|
   | Windows 10/11 | 開啟 `helper` 資料夾，雙擊 `install-windows.cmd`。若出現「Windows 已保護您的電腦」，確認是這個檔案後按「其他資訊」→「仍要執行」。看到「已安裝連線小幫手」即完成。 |
   | macOS | 雙擊 `helper/install-macos.command`。小幫手沒有 Apple 簽章，若被擋下：「系統設定」→「隱私權與安全性」→ 找到被擋的項目按「仍要打開」，再雙擊一次。 |
   | Linux | 在 `helper` 資料夾開終端機：`sh install-linux.sh` |

   安裝程式只做「每個使用者」的安裝：把小幫手放到使用者目錄，並向 Chrome 註冊 Native Messaging（Windows 寫入 `HKCU` 登錄、macOS／Linux 寫入使用者的 `NativeMessagingHosts` 資料夾）。不裝系統服務、不開機自動啟動、不會自動解除下載標記或停用任何安全功能。

3. **載入 Chrome 插件**：
   1. 開啟 `chrome://extensions`，打開右上角的「**開發人員模式**」。
   2. 按「**載入未封裝項目**」，選擇解壓縮出來的 `extension` 資料夾。
   3. 如果裝過官方的 Ruffle 擴充功能，請先停用或移除，避免兩個插件搶著接管。

4. **確認小幫手有裝好**：在插件的「選項」頁找到「Socket 連線」，「連線小幫手」旁應顯示「已安裝（版本 1.2.0）」。若顯示找不到：重新執行安裝程式，**完全關閉 Chrome 再開**。

5. **開始玩**：打開 https://mole.61.com.tw/ ，按播放器的播放鍵後照常登入，不用設定代理。賽爾號、小花仙、彈彈堂同樣直接打開各自的網站。首次載入插件後請重新整理已開啟的遊戲頁；若仍顯示下載 Flash 的提示，等幾秒再重新整理一次。

### 更新

用新版 ZIP 的 `extension/` 內容覆蓋原本載入的資料夾 → 到 `chrome://extensions` 對該插件按「重新載入」→ 遊戲頁強制重新整理（Windows／Linux：`Ctrl+Shift+R`，macOS：`Cmd+Shift+R`）。只有在 [CHANGELOG](timffle/CHANGELOG.md) 寫明小幫手有更新時，才需要重跑安裝程式。

### 移除

1. 執行 `helper` 資料夾裡的 `uninstall-windows.cmd`、`uninstall-macos.command` 或 `uninstall-linux.sh`（只會刪除安裝程式自己建立的檔案和設定）。
2. 到 `chrome://extensions` 移除插件。

小幫手的安裝位置：Windows `%LOCALAPPDATA%\TimffleSocketHelper`、macOS `~/Library/Application Support/TimffleSocketHelper`、Linux `~/.local/share/timffle-socket-helper`。

## 設定

插件的「選項」頁有一個「**Socket 連線（遊戲伺服器）**」區塊（中英對照）：

<p align="center"><img src="timffle/docs/images/options-socket.png" alt="插件選項頁的「Socket 連線（遊戲伺服器）」區塊：連線小幫手顯示已安裝，下方是允許的網站來源清單" width="560"></p>

- **連線方式**：預設且建議「連線小幫手」；進階使用者可改成「自訂 WebSocket 代理」，自己執行 [`timffle/relay/`](timffle/relay/) 裡的本機 WebSocket↔TCP 代理（需要 Node.js 22+，Chrome 可能詢問本機網路存取權限）。
- **一律允許的網站來源（每行一個）**：清單內的網站來源（協定＋主機＋選用連接埠，不接受 `*` 或路徑）可以直接使用 Socket 連線，不會詢問。預設是摩爾莊園、賽爾號、小花仙、彈彈堂的 `mole／seer／hua／ddt.61.com.tw`，各含 `http://` 與 `https://`。要加其他網站**不必自己輸入**：用下面的「第一次連線時的詢問」或「在彈出視窗直接設定」。**只允許你信任的線上遊戲**，因為被允許的網站可以透過小幫手連到任何公開網路上的 TCP 位址。
- **一律拒絕的網站來源（每行一個）**：這些網站不會被詢問，也不能使用 Socket 連線（兩種連線方式都一樣）。同一個網站不能同時在「允許」與「拒絕」清單裡（儲存時會提醒；若真的同時存在，拒絕優先）。
- **兩種連線方式各有自己的「一律允許」清單**：切到「自訂 WebSocket 代理」時，文字方塊會換成代理自己的清單，只有那份清單裡的網站拿得到代理網址與 token。所以在連線小幫手模式按過「允許」的網站，不會因為你之後改用自訂代理就拿到 token。
- **設定頁開著的時候**，若你在彈出視窗改了設定（例如把某網站設成「一律拒絕」），沒有編輯過的表單會自動更新；有編輯過的表單在儲存時會被擋下並顯示最新設定，不會把那邊的決定改回去。
- 儲存或停用後，請重新載入遊戲頁。

### 第一次連線時的詢問

連線方式是「連線小幫手」時，**不在上面兩個清單的網站**第一次嘗試使用 Socket 連線，Timffle 會跳出**插件自己的視窗**詢問你。它是獨立視窗，不是網頁裡的東西，所以網頁不能遮住它、也不能替你按：

<p align="center"><img src="timffle/docs/images/socket-question.png" alt="詢問視窗：顯示網站來源 https://game.example，警告「預設建議拒絕。只有線上遊戲可以允許。」，下方四個按鈕：拒絕（建議）、允許、一律拒絕、一律允許" width="420"></p>

| 按鈕 | 效果 |
|---|---|
| **拒絕（建議）** | 這個分頁這次造訪拒絕。關閉分頁、或這個分頁換到別的網站後，下次再問 |
| **允許** | 這個分頁這次造訪允許。同上，下次再問（重新整理同一頁不算新的造訪） |
| **一律拒絕** | 存進「一律拒絕」清單，不再詢問 |
| **一律允許** | 存進「一律允許」清單，不再詢問 |

- **預設建議拒絕，只有線上遊戲可以允許。** 視窗會明確警告，並把「拒絕」放在最顯眼、預設選取的位置。
- 直接關閉視窗等於「拒絕」（這次造訪）。為了避免你正在遊戲裡點擊或打字時誤按：視窗出現或取得焦點後的 0.7 秒內，所有輸入都被忽略；「允許」**只接受滑鼠（或觸控）點擊，鍵盤永遠不能允許**（Tab、Enter、Space 是遊戲登入常打的鍵），而且滑鼠要在那 0.7 秒之後移到按鈕上才算；「拒絕」任何輸入都可以。需要用鍵盤允許時，請用工具列彈出視窗裡的按鈕。
- 同一個網站同時要求多條連線只會問一次；一次只會有一個視窗；同一個分頁每次造訪最多跳出 3 次視窗、整個擴充功能每分鐘最多 6 次，超過的網站直接拒絕。等你回答的連線不佔用連線名額，所以沒人理的問題不會影響已允許的遊戲。
- 你回答之前，遊戲通常已經等到逾時並顯示連線失敗：**允許後請在遊戲裡再試一次**；若文字顯示不正常，請重新載入頁面。
- 內嵌在別的網站頁面裡的遊戲（`iframe`）以**它自己的來源**詢問，視窗會同時顯示外面那個頁面的來源。
- 只有「連線小幫手」模式會詢問。「自訂 WebSocket 代理」模式不會詢問，沒列出的網站一律不能使用（代理網址含 token，不會給沒被允許的網站）。
- 沒有 Flash 內容的網頁不受影響，Timffle 也不會替它們改動瀏覽器的 `WebSocket`（例外：網頁含有同源的 `iframe` 時，Ruffle 自己的頁框偵測會讀設定而提早安裝轉接，行為仍與原生 `WebSocket` 相同）。
- 擴充功能自己的頁面（彈出視窗、設定頁、歡迎頁、詢問視窗）網頁**無法嵌進頁框**，所以網頁不能偽造它們或蓋住它們。

### 在彈出視窗直接設定

點瀏覽器工具列上的 Timffle 圖示，彈出視窗的「Socket 連線」區塊會顯示**目前分頁的網站**：

<p align="center"><img src="timffle/docs/images/socket-popup.png" alt="彈出視窗的 Socket 連線區塊：顯示 https://game.example 與狀態「每次造訪時詢問」，一顆黃色的「允許此網站使用 Socket 連線」按鈕，下面是設定下拉選單與「預設建議拒絕」的提醒" width="300"></p>

- **允許此網站使用 Socket 連線**：一鍵把這個網站加進「一律允許」清單，不用輸入網址。按下後已開啟的分頁要重新載入才會套用（彈出視窗的「重新載入」按鈕會亮起）。
- 下拉選單可改成「**每次造訪時詢問**」（從兩個清單移除，下次再問）、「**一律允許**」或「**一律拒絕**」。要取消一律允許或一律拒絕，就改回「每次造訪時詢問」。
- 這個分頁裡**其他網站的頁框**如果已經被詢問過，也會列在下面，各有自己的按鈕與選單。
- 狀態列也會顯示這個分頁「本次造訪」的允許或拒絕。
- 同一頁的其他選項是 Ruffle 原有的播放設定（裝置字型、模擬的 Flash 版本、ActionScript 執行時間上限等）。

## 疑難排解

| 症狀 | 可能原因／處理 |
|---|---|
| 選項頁顯示找不到小幫手 | 重新執行 `helper` 裡的安裝程式，然後**完全關閉 Chrome**（含背景程序）再開。Chrome 只在啟動時讀取 Native Messaging 註冊。 |
| 打開遊戲仍顯示「下載 Flash」 | 確認插件已啟用且沒有官方 Ruffle 擴充功能同時啟用；重新整理，等幾秒再重新整理一次。 |
| 第一次點擊（播放鍵或遊戲裡的「開始」）沒反應 | 再點一次。自動化測試中觀察到第一次點擊偶爾不起作用，原因沒有查明。 |
| 畫面上的中文變成方框或消失 | Linux 缺少中日韓字型：安裝 `fonts-noto-cjk` 之類的字型套件後重開 Chrome。本插件對這些遊戲預設使用瀏覽器字型繪製裝置文字。 |
| Windows／macOS 擋下安裝程式或小幫手 | 未簽章的預期行為，請確認檔案來源後依提示執行；不要為此停用系統的安全保護。 |
| 登入後主控台出現 `Error #2030`（來自遊戲的登入禮包模組） | 已知：遊戲自己的競態條件；重現實驗中真 Flash 32 也丟同一個錯誤。 |
| 想回報問題 | 到 [Timffle Issues](https://github.com/Im-Tim-mI/Timffle/issues)，附上 Chrome 版本、作業系統與開發人員工具 Console 的輸出（先遮蔽帳號、密碼與 token）。**請不要把 Timffle 的問題回報給 Ruffle。** 懷疑是安全問題時，請不要公開貼出細節，先開一個只說明「有安全問題想私下回報」的 Issue。 |

## 運作原理與安全設計

```
遊戲頁面  https://mole.61.com.tw/
   │   Timffle（WebAssembly，Ruffle 核心＋修正）接管 Flash 元件；遊戲呼叫 flash.net.Socket
   ▼
Chrome 擴充功能（Manifest V3）
   │   page bridge → content script → service worker
   │   只放行「允許的網站來源」，其他網站先詢問使用者；每個 Socket 對應一條 Native Messaging 連線
   ▼
連線小幫手 timffle-socket-helper（Go；由 Chrome 按需啟動，用完退出）
   │   只連公開網路位址：擋私網、本機、連結本地、多播與保留位址（含 IPv4 對映 IPv6）
   ▼
遊戲伺服器（TCP）
```

- **Chrome 不允許擴充功能開 TCP**，所以需要原生程式；Native Messaging 是 Chrome 官方支援的做法。小幫手**不監聽任何連接埠、不裝服務、不常駐**，每個 Socket 一個程序，連線結束就退出。
- **只有一個擴充功能 ID 能叫用小幫手**：`eandddnbchclalbjkhfelhjhpijifcog`（由 [`timffle/extension-key/`](timffle/extension-key/) 的公鑰決定）。
- 小幫手**不記錄連線內容**，有流量控制與上限（單次送出 ≤ 64 KiB、單次接收 ≤ 32 KiB、緩衝 ≤ 1 MiB、停滯 30 秒逾時、全域最多 16 個 Socket）。
- 安裝與移除只動安裝程式自己建立的檔案；遇到內容已變更的原生元件、外來的同名檔案，或受操作目錄中的符號連結時，會拒絕處理、不會覆寫。

完整說明：[`timffle/docs/ARCHITECTURE.md`](timffle/docs/ARCHITECTURE.md)、[`timffle/docs/PROTOCOL.md`](timffle/docs/PROTOCOL.md)。

## 已知限制

- **平台**：Windows 只在 Wine 測過、macOS 未實測；小幫手**未簽章**。詢問視窗與彈出視窗只在 Chrome 155 桌面版（無頭模式）驗證過；沒有在有畫面的 Chrome、Windows、macOS、Firefox 與 Safari 上試過。
- **其他遊戲**：賽爾號、小花仙、彈彈堂只是預設放行 Socket，沒有實測遊玩。
- **品牌**：只有網頁版（擴充功能、網頁 Demo、播放器畫面）改成 Timffle；桌面版、Safari 擴充功能、npm 套件的文字與識別碼仍是上游 Ruffle 的，**不要以 Timffle 名義散布它們的建置**（見 [`timffle/docs/BRANDING.md`](timffle/docs/BRANDING.md)）。
- **3D**：巢狀的「投影擁有者」與 Flash 不同；Flash 對 3D 圖做約 1 像素的雙線性濾波，Timffle 邊緣較俐落；透視只在 wgpu 渲染器實作。`Matrix3D.determinant`／`invert` 與 Flash 差在最後一位有效數字。
- **命中測試**：Flash 的 `hitTestPoint(x, y, true)` 以整數像素判斷，Timffle 用精確座標；邊緣偶有 1～2 格差異。
- **網頁版遞迴深度**：WebAssembly 呼叫堆疊比 Flash 淺，保護上限 900 層；賽車地圖少數遠距離尋路會被截斷。
- 其他已知差異：[`timffle/docs/CHANGES-FROM-RUFFLE.md`](timffle/docs/CHANGES-FROM-RUFFLE.md) 末尾與 [`timffle/docs/FLASH-NOTES.md`](timffle/docs/FLASH-NOTES.md)。

## 與 Ruffle 的關係

Timffle 以 Ruffle `nightly-2026-10-13`（commit [`46fec3f`](https://github.com/ruffle-rs/ruffle/commit/46fec3f1b2e625fae7035bb3b00d6d5c0ec0d413)）為基底，之後的每一項改動都是獨立的 commit：

| Commit 標題 | 內容 |
|---|---|
| `extension: Native socket helper bridge and socket settings` | Chrome 擴充功能的 Socket 橋接、與小幫手通訊、「Socket 連線」設定頁、四站預設允許清單、單元測試 |
| `web: WebSocket socket backend fixes and canvas generic fonts` | 網頁版 Socket 後端、canvas 裝置字型的通用名稱修正（否則中文會消失） |
| `avm2: Network, LocalConnection, URLStream and loader fixes` | `LocalConnection`、`URLStream`、`Loader`／`URLLoader` 取消、AMF3 循環參照、網域名稱「先父網域」解析、網頁版遞迴深度保護 |
| `render: 3D transforms, Matrix3D semantics and perspective projection` | `z`／`rotationX/Y/Z`／`scaleZ`／`matrix3D`、`perspectiveProjection`、`Matrix3D`、`Utils3D`、投影後的 `getBounds`／命中測試／`BitmapData.draw` |
| `vendor: Add rust-flash-lso …` ＋ `flash-lso: Fix AMF3 encoder reference indices` | 以 subtree 收錄 [rust-flash-lso](https://github.com/ruffle-rs/rust-flash-lso)（含其完整歷史）並修正 AMF3 編碼器 |
| `web: Rebrand the web extension and player UI as Timffle` | 使用者看得到的名稱、圖示與連結改成 Timffle（見 [`timffle/docs/BRANDING.md`](timffle/docs/BRANDING.md)） |

每項修正的細節與原因：[`timffle/docs/CHANGES-FROM-RUFFLE.md`](timffle/docs/CHANGES-FROM-RUFFLE.md)。所有被修改過的 Ruffle 檔案清單（Apache-2.0 第 4(b) 條的「修改聲明」）：[`timffle/MODIFIED-FILES.md`](timffle/MODIFIED-FILES.md)。要看完整差異：`git diff 46fec3f -- . ':!timffle'`。

## 開發

### 從原始碼建置

需要：git、Rust 1.99（含 `wasm32-unknown-unknown`）、wasm-bindgen CLI 0.2.127（要與 `Cargo.lock` 一致）、binaryen（`wasm-opt`）、Node.js 24＋npm、Go 1.27、Python 3。本 repo 已包含所有原始碼（含修補過的 flash-lso），**不需要另外下載 Ruffle**：

```sh
git clone https://github.com/Im-Tim-mI/Timffle.git && cd Timffle
VERSION4=0.8.0.26299 timffle/scripts/build-extension.sh   # 建置 wasm 與 Chrome 擴充功能 → web/packages/extension/dist/ruffle_extension.zip
VERSION4=0.8.0.26299 timffle/scripts/package-release.sh   # 交叉編譯小幫手（7 個平台）並封裝發行 ZIP（含授權檔）→ timffle/build/out/
```

建置腳本預設會把建置機的家目錄與使用者名稱從 wasm 裡改寫掉，打包腳本打包前後都會檢查，發現就拒絕產出發行 ZIP。步驟、工具版本、擴充功能金鑰與常見問題：[`timffle/docs/BUILD.md`](timffle/docs/BUILD.md)。Ruffle 原有的桌面版等其他部分，建置方式與上游相同（見 [`README.ruffle.md`](README.ruffle.md)），但請先讀 [`timffle/docs/BRANDING.md`](timffle/docs/BRANDING.md)。

### 測試

| 測試 | 內容 | 位置 |
|---|---|---|
| 差異測試（對真 Flash） | 用 Haxe 寫小 SWF，在 Adobe Flash Player 32（Wine）與 Timffle 各跑一次，逐行比對；30 項黃金答案。 | [`timffle/difftest/`](timffle/difftest/) |
| 小幫手單元測試 | Go：協定、連線政策、流量控制、安裝／移除 | `timffle/helper/*_test.go` |
| 封裝測試 | 發行 ZIP 的內容、權限與私鑰檢查 | `timffle/helper/installer-tests/` |
| 擴充功能單元測試 | 設定、頁面橋接、背景權限 | `web/packages/extension/tests/` |
| 品牌檢查 | 使用者看得到的文字不得再出現「Ruffle」產品名 | `python3 timffle/scripts/rebrand.py --check` |
| 瀏覽器＋小幫手整合測試 | 無頭 Chrome＋真小幫手，只連 localhost | [`timffle/tools/native-regress/`](timffle/tools/native-regress/) |
| Ruffle 自身回歸測試 | 上游測試套件加上我們新增的測試 | `cargo test -p tests --test tests` |

方法與重現步驟：[`timffle/docs/TESTING.md`](timffle/docs/TESTING.md)。每個版本實際跑過哪些測試、結果如何，記在 [`timffle/CHANGELOG.md`](timffle/CHANGELOG.md)。

### Repo 結構

本 repo 就是 Ruffle 的完整原始碼樹（`core/`、`web/`、`desktop/`、`render/`、`swf/`… 與上游相同的位置），再加上：

```
README.md / README.en.md   Timffle 的說明（本檔與英文版）
README.ruffle.md           Ruffle 原本的 README（原樣保留）
LICENSE.md                 Ruffle 的授權檔（原樣保留；含第三方相依的授權清單）
NOTICE.md                  Timffle 的聲明、著作權、第三方元件與商標說明
vendor/rust-flash-lso/     rust-flash-lso（git subtree，含歷史；MIT，見其 LICENSE）
timffle/                   Timffle 自己的部分：
  LICENSE-MIT / LICENSE-APACHE   Timffle 原創部分的授權
  CHANGELOG.md                   版本歷史
  MODIFIED-FILES.md              修改過的 Ruffle 檔案清單（腳本產生）
  docs/                          架構、通訊協定、建置、測試、品牌、跟進上游、對 Ruffle 的修正、Flash 行為紀錄
  helper/                        連線小幫手（Go）、安裝／移除程式、封裝腳本
  relay/                         進階：本機 WebSocket↔TCP 代理（內含 MIT 授權的 ws 函式庫）
  extension-key/                 擴充功能公鑰與 ID（私鑰不在 repo 內）
  difftest/                      差異測試：Haxe 測試、真 Flash 的黃金答案、執行／比對腳本
  tools/                         Chrome 冒煙測試、整合測試、真實帳號測試、截圖工具
  branding/                      Timffle 圖示與標誌的產生程式
  scripts/                       建置、封裝、路徑檢查、品牌替換與檢查、修改清單
```

### 跟進上游 Ruffle

Timffle 會持續跟進 Ruffle。做法（細節見 [`timffle/docs/UPSTREAM.md`](timffle/docs/UPSTREAM.md)）：

```sh
git remote add upstream https://github.com/ruffle-rs/ruffle.git   # 只需一次
git fetch upstream tag nightly-YYYY-MM-DD --no-tags
git merge nightly-YYYY-MM-DD           # 用 merge 保留雙方歷史，不要 rebase 已公開的分支
python3 timffle/scripts/rebrand.py     # 上游新增或翻譯的文字重新換成 Timffle
python3 timffle/scripts/rebrand.py --check
timffle/scripts/list-modified-files.sh > timffle/MODIFIED-FILES.md
```

### 貢獻

歡迎在 [Issues](https://github.com/Im-Tim-mI/Timffle/issues) 回報問題或提出建議，也歡迎送 Pull Request。請先讀 [`CONTRIBUTING.md`](CONTRIBUTING.md)（上游 Ruffle 的貢獻指南，原樣保留）與 [`timffle/docs/UPSTREAM.md`](timffle/docs/UPSTREAM.md) 的「貢獻規則」。Flash 行為的修正請附能在真 Flash Player 上產生標準答案的差異測試，或 Ruffle 風格的 SWF 回歸測試。

## 授權、致謝與聲明

- **Ruffle**：Copyright (c) 2018-2022 Ruffle LLC 與 Ruffle 貢獻者，MIT 或 Apache-2.0 雙授權，授權全文與第三方相依清單在 [`LICENSE.md`](LICENSE.md)（原樣保留）。Ruffle 的貢獻者紀錄完整保留在本 repo 的 git 歷史中（`git shortlog -sn 46fec3f`）。
- **rust-flash-lso**：Copyright (c) 2020 Callum Thomson，MIT，見 [`vendor/rust-flash-lso/LICENSE`](vendor/rust-flash-lso/LICENSE)。
- **Timffle 的修改與原創部分**：Copyright (c) 2026 Im-Tim-mI 與 Timffle 貢獻者，**MIT 或 Apache-2.0，任選其一**：[`timffle/LICENSE-MIT`](timffle/LICENSE-MIT)、[`timffle/LICENSE-APACHE`](timffle/LICENSE-APACHE)。Timffle 的圖示與標誌是原創作品，同樣適用上述授權。
- 除非你明確另外聲明，你有意提交到本專案的任何貢獻，依 Apache-2.0 對「貢獻」的定義，都以上述雙授權提供，不附加任何額外條款。
- **商標**：「Ruffle」名稱與標誌屬於 Ruffle 專案；Timffle 只以描述方式提及（例如「Ruffle 的分支」「基於 Ruffle」）。「摩爾莊園」「賽爾號」「小花仙」「彈彈堂」「淘米」「Flash」「Adobe」「Chrome」等屬於各自的權利人。
- **本 repo 不包含任何遊戲素材**（遊戲的 SWF、DLL、圖片、遊戲程式碼、伺服器位址、封包格式與加解密），也不修改遊戲檔案。請遵守遊戲的服務條款，只用自己的帳號。完整聲明見 [`NOTICE.md`](NOTICE.md)。行為的來源與驗證方式記在 [`timffle/docs/PROVENANCE.md`](timffle/docs/PROVENANCE.md)。
