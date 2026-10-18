# 擴充功能 ↔ 連線小幫手 通訊協定（protocol 2，小幫手 1.2.0）

這是 Chrome 背景服務與 `timffle-socket-helper` 之間的 Native Messaging 協定。**一個小幫手程序只負責一條 TCP 連線。**原始碼：小幫手 [`helper/bridge.go`](../helper/bridge.go)、[`helper/connect.go`](../helper/connect.go)；擴充功能 `socket-bridge-protocol.ts`（在 [`web/packages/extension/src/`](../../web/packages/extension/src/) 內）。

## 1. 傳輸與啟動

- Native Messaging 主機名稱：`timffle_socket_helper`。
- 每則訊息 = **4 位元組長度（小端）＋ UTF-8 JSON**，經由 stdin／stdout。擴充功能 → 小幫手的單則訊息上限 1 MiB。
- Chrome 啟動小幫手時，第一個命令列引數是呼叫者來源 `chrome-extension://<擴充功能 ID>/`（Windows 另有 `--parent-window=<數字>`）。小幫手要求它**完全等於**內建的來源，否則在讀 stdin、解析名稱或寫任何訊息之前就結束。
- 非 Chrome 叫用時只有三個旗標：`--version`（印出 `timffle-socket-helper 1.2.0`）、`--install`、`--uninstall`。

## 2. 訊息

擴充功能 → 小幫手：

| `type` | 欄位 | 說明 |
|---|---|---|
| `hello` | — | 第一則，只能一次。用來協商版本 |
| `open` | `host`、`port`（1～65535）、`timeoutMs`（選用，1000～120000，預設 20000） | 連線；`host` 是 DNS 名稱或 IP 字面值（IPv6 可加方括號），不接受網址、連接埠、帳密、空白、IPv6 區域 |
| `send` | `data`（base64，解碼後 ≤ 65536 位元組） | 寫入 TCP。同時只能有一個未確認的 `send` |
| `ack` | — | 確認收到上一則 `data`，小幫手才會繼續讀 TCP |
| `close` | — | 正常關閉；已排隊的 `send` 會先寫完（或逾時） |

小幫手 → 擴充功能：

| `type` | 欄位 | 說明 |
|---|---|---|
| `hello` | `version`（`"1.2.0"`）、`protocol`（`2`） | 擴充功能要求 `protocol === 2`，否則回報「不相容」 |
| `opened` | — | **TCP 已連上之後**才送 |
| `sent` | — | 上一個 `send` 已完整寫入 TCP |
| `data` | `data`（base64，解碼後 ≤ 32768 位元組） | 從 TCP 讀到的資料。同時只有一個 `data` 在飛，等 `ack` |
| `error` | `code` | 見下表；之後一定接 `closed` |
| `closed` | — | 連線結束，小幫手隨後退出。每條連線 `error` 與 `closed` 各最多一次 |

## 3. 順序與流量控制

```
擴充功能                          小幫手
   │── hello ─────────────────────▶│
   │◀───────────────── hello(1.2.0, 2)
   │── open(host, port) ───────────▶│   解析 DNS → 檢查所有位址 → 連線
   │◀──────────────────────── opened │
   │── send(≤64KiB) ───────────────▶│
   │◀────────────────────────── sent │   （寫完才回；再送下一個）
   │◀──────────────── data(≤32KiB) ──│
   │── ack ────────────────────────▶│   （收到 ack 才會再讀）
   │── close ──────────────────────▶│
   │◀──────────────────────── closed │
```

- `hello` → `open` 的順序固定；在 `opened` 之前不能 `send`；沒有 `data` 在飛時不能 `ack`。違反就回 `error: invalid` 再 `closed`。
- 在 `send` 未確認時再送 `send`、或 `ack` 的時機不對，視為流量控制違規，連線終止。
- 頁面端把大於 64 KiB 的寫入切塊，並限制緩衝量（1 MiB）、佇列（1024 筆）與停滯時間（30 秒沒有進展就關閉），所以兩個方向都沒有無限成長的佇列。
- 小幫手的 stdin 讀到 EOF（Chrome 關閉 Port）、輸出被卡住、或寫入／等待確認逾時，都會關閉 TCP 並結束。
- 連線中途取消（還在 `open` 階段就關閉）會立刻中止撥號。

## 4. 錯誤碼

| `code` | 意思 |
|---|---|
| `invalid` | 訊息格式、欄位、順序或參數不合法 |
| `timeout` | 解析名稱、撥號、寫入或等待確認逾時 |
| `dns` | 名稱解析失敗或沒有任何結果 |
| `blocked` | 任何一個解析結果不是公開位址（整批拒絕） |
| `refused` | 對方拒絕連線 |
| `unreachable` | 網路無法到達，或連線在傳輸中斷開 |

擴充功能收到 `error` 時一律關閉這條連線，不論 `code` 是否認得；頁面端把它轉成 WebSocket 的 `error` 與 `close` 事件交給 Ruffle。頁面端與背景服務自己也會產生原因碼（`socket_limit`、`buffer_limit`、`bridge_closed`、`connection_cancelled`、`close_timeout`、`not_allowed`（這個來源沒有被允許，或使用者在詢問視窗拒絕了）、`prompt_timeout`（等不到使用者回答）等），那些不屬於本協定。

## 5. 位址政策

見 [`ARCHITECTURE.md`](ARCHITECTURE.md#4-安全模型)。重點：所有解析結果都要是公開位址才連、連線時釘住驗證過的位址（不再把主機名稱交給撥號函式）、IPv4 對映的 IPv6 套用 IPv4 規則、正式版沒有放寬的開關。測試用的 `-tags localtest` 版本才允許私網位址。

## 6. 版本相容

- `protocol` 是整數，不相容的變更才會加一。擴充功能只接受它認得的版本。
- `version` 是小幫手本身的版本，供選項頁顯示（「已安裝（版本 1.2.0）」）和除錯。
- 更新擴充功能時，只要 `protocol` 沒變，**不需要重新執行安裝程式**。
