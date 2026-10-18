# Timffle 本機 WebSocket → TCP 代理

需要 Node.js 22 或更新版本（https://nodejs.org 下載 LTS 版）。已附 `ws` 8.21.0（MIT）函式庫，不必 npm install。代理必須與 Chrome 跑在同一台電腦；它不是能直接在網頁裡執行的 TCP 程式。

## 啟動

- macOS：雙擊 `start-mole.command`。第一次若被系統擋下，在 Finder 對它按右鍵 →「打開」。
- Windows：雙擊 `start-mole.cmd`。
- Linux 或手動：在此目錄開終端機執行

```sh
node relay.mjs --origin https://mole.61.com.tw --origin http://mole.61.com.tw
```

保留終端機視窗；Ctrl+C 停止。預設只監聽 `127.0.0.1:18770`。第一次啟動會產生驗證權杖，寫入此目錄的 `connection.json`（Linux/macOS 權限 0600）；之後啟動沿用同一個權杖，擴充功能設定只需填一次。終端機會顯示 `Proxy URL unchanged`（設定不用改）或 `New proxy URL`（需重貼）。要換新權杖時加 `--new-token`，再把新的 `proxyUrl` 貼回擴充功能。不要分享此檔或將它一起壓縮。

## Chrome 設定

1. 載入這次修正版擴充功能後，開啟它的設定頁。
2. 在「Socket 代理」區啟用代理。將 `connection.json` 的 `proxyUrl` 值貼入 WebSocket 網址模板（保留 `{host}` 與 `{port}`）。
3. 允許的網站來源一行一個，必須和啟動參數一致，例如 `https://mole.61.com.tw`、`http://mole.61.com.tw`。
4. 進階選項的「Device font renderer」預設就是 `Canvas`（伺服器名稱等中文才會顯示），不用改；除非你自己選過 `Embedded`，那樣中文會消失。
5. 儲存並重新整理遊戲頁。從官網 `https://mole.61.com.tw/` 進入，不直接開 Client.swf（會被遊戲判定為非法客戶端）。輸入 http 網址時 Chrome 會自動升級成 https。
6. 第一次按登入時，Chrome 會詢問是否允許 mole.61.com.tw 存取這台裝置上的其他應用程式／本機網路，請按「允許」。沒有允許時 Chrome 會擋下連線（主控台顯示 `ERR_BLOCKED_BY_LOCAL_NETWORK_ACCESS_CHECKS`），遊戲連不上伺服器。若曾按過封鎖，到網址列左側的網站設定改回允許後重新整理。不要停用瀏覽器安全檢查。

## 動態目的地與限制

- 模板自動帶入遊戲要求的主機與連接埠，包含登入後才取得的伺服器，不需逐一填寫 IP。目的地支援公網 DNS、IPv4、IPv6；埠號 1–65535。DNS 目前選第一個有效地址，不會在多筆地址間自動重試。
- 預設拒絕內網、loopback、link-local 與保留位址，避免網站把本機代理當作內網掃描器。若確實要連自有內網伺服器，需在啟動時額外指定 `--allow-private-host exact-host`；不是放寬監聽介面。
- 只接受設定過的精確 Origin 和 `connection.json` 裡的隨機權杖。沒有萬用來源設定，也不對外網監聽。
- 只有 TCP 真正接通後才完成 WebSocket 握手，因此搭配修正版 Ruffle 不會提前觸發 connect。舊的第三方代理若提前回應 101，單靠 WebSocket OPEN 仍不能保證 TCP 已通。
- 雙向轉發原始 binary bytes；不解析、不重寫遊戲登入封包，不記錄封包內容。TCP 傳輸本身是否加密取決於原遊戲協定，此代理不會替原協定加密。
- 驗證權杖因 Ruffle 的網頁執行架構，會提供給明確允許的網站；只允許信任的來源。瀏覽器擴充功能設定存於本機，不同步到 Chrome Sync。
- 最多 16 條同時／待連線通道、每個 WebSocket frame 最大 1 MiB、代理端連線逾時 20 秒。

## 驗證

```sh
node --test --test-timeout=8000 relay.test.mjs
```

測試僅連本機測試伺服器；涵蓋動態埠、binary bytes、延遲握手、拒絕、逾時、Origin／權杖、DNS 回到內網的拒絕。

## 為什麼不是直接使用 websockify

已檢查 noVNC/websockify。其一般流程先完成 WebSocket 握手，再建立 TCP，無法直接滿足此修正所需的「OPEN 代表 TCP 已連線」。此程式只實作受限的轉接與驗證層，WebSocket 協定交由成熟的 `ws` 函式庫處理。
