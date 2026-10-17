# 架構與安全模型

這份文件說明各元件怎麼分工、一條 Socket 連線的完整流程，以及安全上的取捨。通訊協定的細節在 [`PROTOCOL.md`](PROTOCOL.md)。

## 1. 為什麼需要這些元件

- Flash 遊戲用 `flash.net.Socket` 直接連 TCP。瀏覽器網頁與 Chrome 擴充功能**都不能**開 TCP 連線，只能開 WebSocket。
- Ruffle 的網頁版對此的做法是：把 `Socket` 的連線轉成 **WebSocket 連到一個「代理」**，由代理再去連 TCP（設定項 `socketProxy`：`{ host, port, proxyUrl }`）。官方做法需要使用者自己架代理。
- 本專案的做法：**代理就是 Chrome 的 Native Messaging 小幫手**。擴充功能把 `socketProxy` 設成一個保留網址，頁面端攔下這個網址的 `WebSocket`，改走「內容腳本 → 背景服務 → Native Messaging → 小幫手 → TCP」。使用者不必架代理，也不必填網址。
- 另保留傳統做法作為進階選項：[`relay/`](../relay/) 是本機 WebSocket↔TCP 代理，擴充功能的「自訂 WebSocket 代理」模式把 `socketProxy` 指向它。

## 2. 元件

```
┌───────────────────────────── Chrome 分頁（遊戲網站，例如 mole.61.com.tw）─────────────────────────────┐
│  Ruffle（WebAssembly，修補版）                                                                       │
│    flash.net.Socket ──▶ WebSocket("ws://timffle-socket.invalid/connect?host=…&port=…")                  │
│                                   │  ← 頁面端橋接 socket-bridge-page 只攔截這個保留網址，                │
│                                   │    其他 WebSocket 完全不受影響                                    │
└───────────────────────────────────┼──────────────────────────────────────────────────────────────────┘
                                    │ window message（同一分頁內）
                         內容腳本 socket-bridge-content（每個頁框，限制 8 條）
                                    │ runtime Port（每條 Socket 一個）
┌───────────────────────────────────▼──────────────────────────────────────────────────────────────────┐
│  背景服務 socket-bridge-background（Manifest V3 service worker）                                     │
│    · 用瀏覽器提供的 sender（擴充功能 ID、分頁、頁框、網址）重新驗證「這個頁框的來源在不在允許清單」     │
│    · 全域最多 16 條 Socket；頁面導覽／設定撤銷時關閉                                                   │
│    · 每條 Socket 一個 chrome.runtime.connectNative("timffle_socket_helper")                          │
└───────────────────────────────────┬──────────────────────────────────────────────────────────────────┘
                                    │ Native Messaging（stdio；長度前綴的 JSON；協定版本 2）
┌───────────────────────────────────▼──────────────────────────────────────────────────────────────────┐
│  連線小幫手 timffle-socket-helper（Go，每條 Socket 一個程序，連線結束就退出）                            │
│    · 驗證呼叫者來源 chrome-extension://<固定 ID>/                                                     │
│    · 解析 DNS → 檢查每個位址都是公開位址 → 釘住該位址 → 連 TCP                                          │
│    · 單向流量控制；不記錄內容；不監聽任何連接埠                                                         │
└───────────────────────────────────┬──────────────────────────────────────────────────────────────────┘
                                    ▼
                              遊戲伺服器（公開網路上的 TCP）
```

| 元件 | 位置 | 說明 |
|---|---|---|
| 核心（WASM） | `core/`、`render/`、`web/src/` 等（Ruffle＋Timffle 的修正） | 模擬 Flash；相容性修正見 [`CHANGES-FROM-RUFFLE.md`](CHANGES-FROM-RUFFLE.md) |
| 擴充功能 | `web/packages/extension/` | Manifest V3；`socket-bridge-{page,content,background,protocol}.ts`、設定頁、`socket-proxy.ts`（設定與允許清單邏輯） |
| 連線小幫手 | [`helper/`](../helper/) | Go；沒有第三方相依套件；內建安裝／移除程式 |
| 安裝啟動檔 | `helper/installers/` | 只是薄薄的啟動器，真正的安裝程式在小幫手執行檔裡（`--install`／`--uninstall`） |
| 封裝工具 | `helper/package.py` | 驗證輸入（拒絕符號連結、私鑰標記、過大檔案）並產生發行 ZIP |
| 進階代理 | [`relay/`](../relay/) | Node 22+；自訂 WebSocket 代理模式用 |

## 3. 一條連線的生命週期

1. 遊戲呼叫 `socket.connect(host, port)`。Ruffle 依 `socketProxy` 的萬用字元對應（`host:"*"`, `port:0`）得到代理網址 `ws://timffle-socket.invalid/connect?host={host}&port={port}`，建立 WebSocket。
2. 頁面端橋接認出這個網址（`.invalid` 是保留的頂級網域，永遠不會真的解析），驗證 `host`／`port` 參數的格式，向內容腳本要求開啟 Socket。
3. 內容腳本開一個專屬的 runtime Port 連到背景服務；背景服務從瀏覽器提供的 sender 取得頁框真正的來源，比對允許清單，檢查全域與每頁框的上限，然後啟動小幫手並先送 `hello` 協商協定版本（不相容或找不到就回報錯誤，選項頁會顯示原因）。
4. 小幫手收到 `open` 後解析 DNS、檢查位址、連 TCP；**TCP 連上之後**才回 `opened`。
5. 傳輸：每次最多送 64 KiB，且同時只有一個未確認的 `send`（小幫手整個寫完 TCP 才回 `sent`）；收到的資料每次最多 32 KiB，頁面確認（`ack`）之後小幫手才繼續讀。因此兩個方向的佇列都有上限，不會無限成長。
6. 任一端關閉、逾時（30 秒沒有進展）、頁面導覽或設定被撤銷時，整條鏈一起關閉，小幫手程序退出。

## 4. 安全模型

### 保護的目標

- **不讓任意網站使用 Socket**：只有「允許的網站來源」清單內的網站可以；內嵌播放器以所在頁框的來源判斷，獨立播放器以 SWF 網址的來源判斷，**本機檔案永遠不能用**。清單只接受完整的 `http(s)` 來源（協定＋主機＋選用連接埠），不接受萬用字元、路徑、帳密、查詢。
- **不讓其他擴充功能或程式叫用小幫手**：Chrome 只允許 Native Messaging 主機清單的 `allowed_origins` 內的擴充功能啟動它；小幫手自己還會檢查 Chrome 傳入的第一個引數必須剛好是 `chrome-extension://eandddnbchclalbjkhfelhjhpijifcog/`（Windows 另可多一個 `--parent-window=<數字>`）。
- **不讓小幫手變成打進內網的跳板**：只連**公開位址**。DNS 解析的結果只要有任何一個不是公開位址就整批拒絕，通過後釘住該位址連線（避免 DNS rebinding）；封鎖 IPv4 的私網、迴路、連結本地、CGNAT、文件／測試／保留／多播區段，IPv6 只允許 `2000::/3` 並排除 Teredo、6to4、文件、基準測試、ORCHID 等特殊用途區段；IPv4 對映的 IPv6 位址套用 IPv4 規則。
- **正式版沒有任何可以放寬位址限制的開關**：允許私網位址的行為只存在於以 `-tags localtest` 編譯的測試版（自動化測試要連 localhost 用），`helper/build.sh` 明確以空的 tags 編譯，並拒絕環境裡殘留的 `GOFLAGS`。頁面訊息無法要求放寬。
- **資源上限**：全域 16 條、每頁框 8 條、單次送出 ≤ 64 KiB、單次接收 ≤ 32 KiB、緩衝 ≤ 1 MiB、佇列 ≤ 1024 筆、停滯 30 秒逾時、連線預設 20 秒（可設 1～120 秒）。
- **隱私**：小幫手不記錄連線內容或帳密；沒有任何程式碼把資料送往本專案以外的地方。

### 安裝程式

- 只做每個使用者的安裝，不需要系統管理員，不裝系統服務，不開機自動啟動。
- 不自動移除下載標記（Windows 的 Mark of the Web、macOS 的 quarantine），也不停用任何系統安全功能。
- 寫檔用暫存檔加改名（盡量原子）；拒絕符號連結與 Windows reparse point；遇到內容不符的既有檔案或外來登錄項目就不覆寫。
- 安裝收據（`install.json`）綁定原生檔案的雜湊；移除時只刪收據列出且雜湊相符的檔案，Windows 登錄只清除本元件的預設值。
- 註冊的瀏覽器：Google Chrome 正式版一律註冊。Windows 上 Chrome 各頻道共用同一個登錄 key；Linux／macOS 的 Beta、Dev、Canary 與 Chromium 只在使用者目錄裡已有該瀏覽器的資料夾（用過）時才註冊。Edge、Brave 等其他瀏覽器不註冊。

### 仍然存在的風險（請誠實看待）

1. **被允許的網站可以透過小幫手連到公開網路上的任何 TCP 位址**——這正是 Socket 功能本身。所以「允許清單」只放你信任的網站。若那個網站被入侵，攻擊者可以把你的電腦當成連到公開網路的 TCP 出口（但到不了你的內網）。
2. **擴充功能 ID 來自公開的公鑰。** 任何人把同一把公鑰放進自己擴充功能的 `manifest.json`，載入後就是同一個 ID，也就能叫用你電腦上的小幫手。這是「發行未封裝擴充功能」的固有限制；因此只載入來自可信來源的擴充功能。要自行散布請換成自己的金鑰（見 [`BUILD.md`](BUILD.md#4-使用自己的擴充功能金鑰)）。
3. **小幫手沒有 Microsoft／Apple 簽章或公證。** Windows 的 Smart App Control 等政策可能直接擋下；請不要為此停用系統保護。發行 ZIP 附 SHA-256，請核對。
4. **依賴瀏覽器行為**：Native Messaging、MV3 service worker 的生命週期（自訂代理模式另有 Local Network Access 權限）會隨 Chrome 版本變動，目前只在 Chrome 155 驗證過。

## 5. 設定與模式

設定存在擴充功能的 `storage.local`（不使用同步儲存）：

| 設定 | 說明 |
|---|---|
| `mode` | `helper`（預設）或 `websocket`（自訂代理）。舊版沒有 `mode` 的設定：有代理網址的視為 `websocket`（行為不變），沒有的視為 `helper` |
| `allowedOrigins` | 允許使用 Socket 的網站來源清單 |
| `defaultsVersion` | 預設清單的版本。版本升級時，若使用者儲存的清單恰好等於舊預設值，就換成新預設；使用者自訂過的清單不動 |
| 代理網址樣板 | 只用於 `websocket` 模式，必須含 `{host}`、`{port}`，不得含帳密或片段 |

`helper` 模式下，擴充功能在允許的網站上把 Ruffle 的 `socketProxy` 設成 `[{ host: "*", port: 0, proxyUrl: <保留網址樣板> }]`；不在清單內的網站與本機檔案**完全收不到**這項設定，也不會有任何對外連線。

## 6. 為什麼是「每個 Socket 一個程序」

- 簡單：沒有多工、沒有程序間狀態，小幫手一個程序只管一條 TCP；Chrome 關掉 Port 或擴充功能 service worker 被回收，stdin EOF 就讓小幫手關閉 TCP 並退出，不會留下常駐程序。
- 安全：沒有可供他人連入的連接埠；也沒有一個長期存在的程序累積狀態。
- 代價：每條連線啟動一個程序；Windows 上啟動程序的成本比 Linux 高。我們沒有量測這個開銷，也沒有在 Windows 實機上確認過。
