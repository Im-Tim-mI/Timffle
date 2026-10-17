# PROVENANCE（來源紀錄）

> **English summary.** This document records where the behaviour implemented in this project comes from and how it was checked: (1) differential tests run in Adobe Flash Player 32 whose output is stored as golden files, (2) Ruffle's own source code, (3) public documentation and Adobe's open-source avmplus, and (4) standard mathematics. The repository contains no game assets. Last updated 2026-10-17.

## 1. 這份文件在說什麼

對我們改動的每一項行為，記下「這個行為是從哪裡知道的」以及「怎麼驗證的」。這樣任何人（包括 Ruffle 維護者）都能檢查：

- 我們實作的行為都能追溯到第 2 節列出的來源，並且大多有「真 Flash 的實測輸出」當證據（第 3 節）。
- 倉庫裡沒有遊戲素材，也沒有 Adobe 或遊戲營運商未公開的原始碼（第 5 節）。

## 2. 行為依據的來源

| 等級 | 來源 | 怎麼用 |
|---|---|---|
| **A** | **真 Flash Player 的黑箱量測**（差異測試） | 我們自己寫小型測試程式（Haxe／AS3），在 Adobe Flash Player 32（standalone projector 及其 debugger 版，於 Wine 下執行）與 Ruffle 各跑一次，逐行比對；Flash 的輸出存成「黃金答案」，每份至少跑兩次確認穩定。播放器本身**不隨本專案散布**。方法見 [TESTING.md](TESTING.md) |
| **B** | **Ruffle 自己的原始碼**（基底 nightly-2026-10-13） | 我們的修改都是在這份獨立實作上進行；Ruffle 的測試套件也是證據 |
| **C** | **公開文件與開放原始碼** | Adobe 的 ActionScript 3 語言參考（`Socket`、`LocalConnection` 等的事件與錯誤語意）、AMF3 公開規格、Chrome Native Messaging 文件、Adobe 以 MPL 釋出的 avmplus（例如 `core/DomainMgr.cpp` 對名稱查找順序的說明） |
| **D** | **教科書數學** | Gram-Schmidt 正交化、四元數球面內插、透視投影公式等；Matrix3D／3D 的**具體規則**則來自 A 的量測，不是來自文件猜測 |
| **E** | **遊戲本身的偵錯** | 只用來決定「要去驗證哪個行為」，不提供實作內容 |

## 3. 逐項對照

黃金答案都在 [`timffle/difftest/expected/`](../difftest/expected/)（共 30 份，檔名如下）。「無對照」表示那一項沒有真 Flash 的比對，依據是 B／C。

| 項目 | 主要依據 | 證據 |
|---|---|---|
| LocalConnection：循環參照的參數 | A | `r1lc_cyclic_args`、`t3lc_cycle_obj`、`t3lc_cycle_arr` |
| LocalConnection：`client` 設成基本型別 | A | `r2lc_client_primitive`、`t3lc_client_prim` |
| LocalConnection：訊息大小上限（#2084） | A（對 0～50000 二分搜尋） | `r4lc_limit` |
| LocalConnection：事件、錯誤碼、`errorID`、`isPerUser`、網域 | A | `t2localconn` |
| URLStream：漸進傳輸、狀態、選用 API | A | `t1urlstream`、`r3stream_state`、`r5stream_api` |
| `Loader.close()`／`URLLoader.close()`、`open` 事件時序 | A | `r7loader_cancel`、`r8urlloader_cancel`、`r9urlloader_open_timing` |
| AMF3 往返（含循環）與編碼器參照索引 | A、C（AMF3 規格）；另有 crate 內單元測試 | `r6amf_cycles` |
| 網域名稱查找：多命名空間的名稱從根網域優先 | C（avmplus `DomainMgr` 的說明）、A | 上游的 `loader_duplicate_class`；上游貢獻分支的新測試 `domain_lookup_parent_first`（輸出取自 Flash debugger）。**已知偏差**見 [CHANGES-FROM-RUFFLE.md](CHANGES-FROM-RUFFLE.md) |
| 網頁版遞迴深度保護（900 層） | A（量測 Flash 約 2400／12000 層）加瀏覽器實測 | 探針 `d11recursion`（不是黃金答案） |
| 3D：`z`、`rotationX/Y/Z`、`scaleZ`、`matrix3D`、透視、投影後的邊界與命中測試 | A | `d13perspective`、`d16props3d`、`d19render3d` |
| `Matrix3D`／`Utils3D`／`BitmapData.draw` 與 3D | A | `d18matrix3d`、`d22pointat`、`d26steps`、`d28steps`、`d29steps`、`d31steps`、`d32steps`、`d33utils3d`、`d34utils3dw`、`d36pointtowards`、`d38drawbitmap`、`d40utils3dnull` |
| `hitTestPoint` 以整數像素量化（刻意不修） | A | 探針 `d15hit_edge` |
| Socket 的 WebSocket 後端：萬用字元對應、連線成功語意、逾時 | B、C（AS3 參考文件的 `connect`／`ioError`／逾時語意） | 無對照；以擴充功能單元測試與瀏覽器＋小幫手整合測試驗證實作本身 |
| Chrome 擴充功能、連線小幫手、安裝程式、本機代理 | 我們的設計；C（Chrome Native Messaging、Go 標準函式庫文件） | 無對照（不是 Flash 行為） |
| canvas 裝置字型的通用名稱（`_sans`／`_serif`） | C（CSS 通用字型家族） | 無對照（顯示層） |

上游貢獻分支（`avm2-localconnection-client-primitive`、`avm2-localconnection-error-2085`、`avm2-domain-lookup-parent-first`）的預期輸出，都是用 Flash Player 32 debugger 跑兩次、結果一致後記錄的。

## 4. 怎麼自己檢查

```sh
# 1. 黃金答案確實存在，且與測試程式一一對應
ls timffle/difftest/expected | wc -l          # 30

# 2. 用自己的 Flash Player 重新產生黃金答案（播放器不在本倉庫，需自備），做法見 TESTING.md
```

## 5. 沒有使用的東西

- 其他模擬器或 Flash 相關專案（Lightspark、Gnash、Shumway、OpenFL、Away3D 等）的程式碼：沒有已知的複製；我們新增的程式碼裡沒有「based on／ported from」之類的出處標註。
- Adobe 或遊戲營運商未公開的原始碼、內部文件、素材：沒有。
- 遊戲的程式碼、封包格式、加解密、伺服器位址：**不在倉庫裡**。

## 6. AI 協助

本專案大部分程式碼與文件是在 AI 助理（Claude，Anthropic）協助下撰寫，由維護者審閱。向上游提交的 commit 會以 `Assisted-by:` 標示。AI 有可能無意間重現訓練資料中的程式碼片段；我們用「沒有出處標註」與黃金答案比對的做法降低風險，但無法保證零風險。

## 7. 今後的規則

1. 新增行為時：先在真 Flash 取得黃金答案，再實作；把證據補進第 3 節的表。
2. 查不到可靠依據的行為就不實作，並如實標為未對照。
3. 遊戲的程式碼、封包格式、加解密、伺服器位址不放進倉庫。
4. 接受外部貢獻時，要求貢獻者說明內容的來源，並遵守 Ruffle 的 `CONTRIBUTING.md`。
