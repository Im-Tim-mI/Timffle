# Timffle 對 Ruffle 的修正

基底：Ruffle `nightly-2026-10-13`（commit `46fec3f`）。Timffle 的修正是在它之後的 git commit；下面的 0001～0005 對應前身專案的五份補丁，在 Timffle 的歷史裡是這幾個 commit：

| 編號 | Commit 標題 |
|---|---|
| 0001 | `extension: Native socket helper bridge and socket settings` |
| 0002 | `web: WebSocket socket backend fixes and canvas generic fonts` |
| 0003 | `avm2: Network, LocalConnection, URLStream and loader fixes`（以及 `build: Use the vendored flash-lso …`） |
| 0004 | `render: 3D transforms, Matrix3D semantics and perspective projection` |
| 0005 | `flash-lso: Fix AMF3 encoder reference indices`（`vendor/rust-flash-lso/`） |

品牌改名（`web: Rebrand …`）不改變行為，見 [`BRANDING.md`](BRANDING.md)。被修改的檔案清單見 [`../MODIFIED-FILES.md`](../MODIFIED-FILES.md)。這份文件說明**每項修正做了什麼、為什麼**，以及已知與真 Flash 還不同的地方。

每個修正都以「真 Flash Player 32 的實際行為」為準，先寫能在 Flash 上通過的測試（[差異測試](TESTING.md)），再讓 Timffle 通過。括號裡的小寫名稱是 [`../difftest/expected/`](../difftest/expected/) 裡的黃金答案。

---

## 0001 — Chrome 擴充功能：Socket 橋接與設定（23 個檔案）

讓擴充功能能把 Ruffle 的 `flash.net.Socket` 接到連線小幫手（架構見 [`ARCHITECTURE.md`](ARCHITECTURE.md)）。

- **橋接**：`socket-bridge-page.ts`（頁面端，只攔截保留網址 `ws://timffle-socket.invalid/connect?host=…&port=…` 的 `WebSocket`）、`socket-bridge-content.ts`、`socket-bridge-background.ts`（來源重新驗證、全域／每頁框上限、頁面導覽與設定撤銷時關閉）、`socket-bridge-protocol.ts`（常數與訊息格式驗證）。
- **設定**：`socket-proxy.ts`（模式、允許的網站來源、預設清單與升級規則、代理網址樣板驗證）、`proxy-settings.ts`（只存 `storage.local`，不同步）、`proxy-options.ts` 與選項頁的「Socket 連線」區塊（中英對照，整個區塊 `translate="no"`，避免 Chrome 自動翻譯弄錯遊戲名稱）。
- **整合**：`utils.ts` 的 `getOptions(origin)` 只對「允許使用 Socket 的網站」注入 `socketProxy` 設定；使用者沒有自己指定渲染器時，所有網頁（以及選項頁的顯示）預設把裝置字型改成 `canvas`（用瀏覽器字型畫中文），與 Socket 的任何決定無關——以前只有「一律允許」的網站才有，被詢問或拒絕的遊戲中文會消失（見 CHANGELOG 0.8.0.26299）。不在清單內的網站與本機檔案收不到任何 Socket 設定。`build.ts` 加上 `nativeMessaging` 權限，並把環境變數 `EXTENSION_PUBLIC_KEY` 寫成 `manifest.key`（固定 ID）。
- **`web/packages/core/.../load-options.ts`**：`socketProxy` 設定的型別與文件，說明萬用字元對應（`host:"*"`、`port:0`）、`{host}`／`{port}` 樣板、精確對應優先，以及「成功＝WebSocket OPEN」的語意（見 0002）。
- **測試**：3 個測試檔共 38 項（設定與允許清單、頁面橋接、背景權限）。
- **之後新增（發行前）**：第一次連線時的詢問、「一律拒絕」清單、彈出視窗的「允許此網站使用 Socket 連線」按鈕。這些在原本的補丁之後以獨立 commit 加入，說明見 [`ARCHITECTURE.md`](ARCHITECTURE.md) 第 3a 節與 [`../CHANGELOG.md`](../CHANGELOG.md)。同一批改動還把 `manifest.json5` 的 `web_accessible_resources` 從 `*` 縮到 `dist/*` 與 `player.html`（上游是整個資料夾對所有網頁開放，網頁可以把擴充功能自己的頁面嵌進頁框）。

## 0002 — 網頁版執行期：Socket 後端與 canvas 通用字型（3 個檔案）

- **`web/src/navigator.rs`（Socket 後端）**
  - 支援**萬用字元代理對應**與 `{host}`／`{port}` 樣板；主機名稱以 URL 元件編碼（IPv6 的冒號、方括號與查詢分隔符都當資料）；只接受 `ws:`／`wss:`；**精確對應優先於萬用字元，被選中的對應若無效就失敗，不會落到別的目的地**。
  - 回報「已連線」**只在瀏覽器的 WebSocket OPEN 事件之後**，並且把 Flash 的 Socket 逾時套用在這段握手上（原本被忽略）。這個語意要求代理在目標 TCP 連上之後才回 HTTP 101——連線小幫手的橋接就是這樣做的（TCP 成功才回 `opened`）；舊式代理做不到，Ruffle 也無從得知。
  - 握手期間本機關閉／重連會立刻取消；OPEN 之前排隊的寫入與收到的資料都保留；不再用 `expect` 讓通道錯誤變成 panic；**不記錄代理網址或瀏覽器錯誤細節**（可能含 token）。
  - 尊重 `Request.preserve_error_body`（見 0003），HTTP 錯誤回應的內容可以讀到。
- **`web/src/builder.rs`、`web/src/ui/canvas_font_renderer.rs`（canvas 通用字型）**
  - 問題：`deviceFontRenderer=canvas` 時，具名裝置字型（SimSun、Arial…）交給瀏覽器畫，但 Flash 的通用名稱 `_sans`／`_serif`／`_typewriter` 仍綁在 Ruffle 內建、只含拉丁字母的 Noto Sans，**中日韓文字寬度為 0、整段消失**；遊戲用 `textWidth` 決定欄寬，欄位縮成幾像素，畫面上只剩圖示。
  - 修正：canvas 模式下把六個預設字型對應到瀏覽器的 `sans-serif`／`serif`／`monospace`（使用者的 `defaultFonts` 優先，內建 Noto Sans 只當最後備援）；CSS 通用名稱不加引號。嵌入式字型模式行為不變。
  - 重現方法：任何 `_sans` 欄位含中文的 SWF 都可以；測試機沒有中日韓字型時，用私有的 fontconfig 檔給測試用的 Chrome 一份 Noto Sans CJK，不要改系統字型。
  - 行位置：Flash 把第一行的基線放在「欄位頂端 2 px ＋ 它指定的那個 Windows 字型的上緣」，行高是上緣＋下緣＋行距。瀏覽器沒有該字型時，頂替字型的上下緣常常差很多，所以 `line_metrics` 先按字型名稱查表（SimSun 系列、Microsoft YaHei、Arial Black、Tahoma、Verdana、Arial、Times New Roman、Courier New），用 Windows 的上下緣排版，頂替字型只畫字形；表外的字型維持瀏覽器自己的數值（太高的頂替字型改用中文字框，見 0.8.0.26297）。

## 0003 — AVM2 網路、載入與 LocalConnection（53 個檔案）

| 主題 | 內容 | 黃金答案 |
|---|---|---|
| **LocalConnection** | 循環參照的參數不再崩潰（序列化時給物件 ID、遇到循環輸出 AMF3 參照）；`client` 設成原始型別時丟 `TypeError #2004` 而不是 panic；網域名稱用 `host_str`，IP 位址不再被「超網域」處理截成最後一段；錯誤 #2085 的代碼填對；動態 `client` 缺方法時靜默忽略；`AsyncErrorEvent` 的 `errorID` 取自 `error`；`isPerUser` 屬性；**訊息大小上限**依真 Flash 量測建模：`連線名稱(UTF-8) + 方法名稱(UTF-8) + AMF3 參數 ≤ 40943`，接收端存在再扣 32，超過丟 #2084（不是單一字串長度門檻） | `r1lc_cyclic_args`、`r2lc_client_primitive`、`r4lc_limit`、`t2localconn`、`t3lc_*` |
| **URLStream** | 漸進傳輸（每收到一塊就累積到緩衝並派發 `progress`；事件順序 `open → progress* → httpStatus → complete`）；`bytesAvailable` 帳務；開啟前／`close()` 後讀取丟 #2029；`objectEncoding`、FP 11.4 的 `stop`／`position`／`length`；HTTP 404 的內容保留（`Request.preserve_error_body`，僅 URLStream 開啟，之後 `httpStatus` ＋ `ioError #2032`）；`close()` 之後舊下載迴圈立刻停止（以世代隔離舊請求）；**`httpStatus` 的監聽器裡 `close()`，Flash 仍會送 `complete`**（實測，已建模） | `t1urlstream`、`r3stream_state`、`r5stream_api` |
| **Loader／URLLoader** | `close()` **真正取消**載入並壓住之後的事件；`URLLoader` 的 `open` 事件改在**收到回應標頭時**就發（原本要等整個內容下載完才發；請求失敗或非 2xx 一律不發 `open`）——有些遊戲的佇列載入器若 5 秒內沒收到 `open` 就放棄並重試，大檔案會因此被一再重試，舊請求的內容還可能被當成新項目的結果 | `r7loader_cancel`、`r8urlloader_cancel`、`r9urlloader_open_timing` |
| **AMF3** | `ByteArray` 的 AMF3 往返在循環圖形下不再崩潰、參照指到正確的物件（與 0005 搭配） | `r6amf_cycles` |
| **網域名稱查找** | **改成「先找父網域」**（`Domain::get_defining_script`、`get_class_inner`）。真 Flash 對名稱的解析是父網域優先；Ruffle 原本先找自己的網域，於是載入進子網域的函式庫若定義了與內建同名的套件層級函式（例如 `flash.system.trace`），就會蓋掉內建的，呼叫簽章不符而丟 `ArgumentError #1063`，使某些事件監聽器根本沒掛上。證據用「真的函式庫＋真的地圖 SWF」在 Flash 與 Ruffle 各跑一次（11/11 對 0/11） | （需要遊戲檔案，不在 repo） |
| **網頁版遞迴深度保護** | WebAssembly 的呼叫堆疊比 Flash 淺（Flash 約 2400 層含 try/catch、約 12000 層不含；Chrome 155 無頭實測 1300 層可行）。僅 wasm 的 `MAX_CALL_DEPTH = 900`，超過就丟**可被 `catch` 的** `flash.errors.StackOverflowError`，而不是讓 wasm 堆疊溢位後整個播放器死掉（之後每個 tick 都印 "Unable to lock Ruffle core"） | `d11recursion` 為探針，非黃金答案 |
| **測試** | `tests/tests/swfs/avm2/` 新增 5 個回歸測試（差異測試黃金答案的 `trace` 版本） | — |
| **相依** | `Cargo.toml`／`Cargo.lock`：`flash-lso` 改指向 `../rust-flash-lso/flash-lso`（0005） | — |

## 0004 — 3D 與 Matrix3D（23 個檔案）

登入畫面把人物節點放在 3D 轉盤上（每個節點設 `x = sin(角度)·R`、`z = R − cos(角度)·R`，外層容器設了 `perspectiveProjection.projectionCenter`）。真 Flash 把遠處的節點縮小並拉向投影中心，排成一道弧；Ruffle 原本忽略 `z`，畫成一排。要修好它，必須把 Flash 的整個 3D 模型補齊——全部以真 Flash 32 量測，不是照文件猜的。完整的規則見 [`FLASH-NOTES.md`](FLASH-NOTES.md)。

- **顯示物件**：`z`、`rotationX/Y/Z`、`scaleZ`、`transform.matrix3D`（與物件**即時連動**）、容器的 `transform.perspectiveProjection`（含 `fieldOfView`、`focalLength`、`projectionCenter`）。對物件設定任何 3D 屬性就會讓它變成 3D 物件（`transform.matrix` 變 `null`）。
- **幾何**：含 3D 子物件的容器，其 `getBounds`、`hitTestPoint`、`getObjectsUnderPoint`、`mouseX/Y`、`localToGlobal` 都使用投影後的座標（`render/src/transform.rs` 的 `Mat4`／`ChainState`／`TransformStack` 讓幾何與繪圖共用同一套計算）。
- **`Matrix3D` 與 `Utils3D`**：`pointAt`（原本是空殼）、`recompose`／`decompose`／`interpolate`／`appendRotation` 的邊界行為、`Utils3D.pointTowards`、`projectVector(s)`；以 float32 運算。
- **`BitmapData.draw`**：畫 3D 內容時依投影繪製（含被畫物件自己的 `perspectiveProjection`），且與 Flash 一樣在子樹有 3D 時**忽略傳入的 matrix 參數**（顏色轉換仍有效）。
- **渲染**：wgpu 後端每次繪製接收 4×4 的 `world_matrix`。
- 黃金答案：`d13perspective`（登入轉盤）、`d16props3d`、`d18matrix3d`、`d19render3d`、`d22pointat`、`d26steps`／`d28steps`／`d29steps`／`d31steps`／`d32steps`、`d33utils3d`／`d34utils3dw`／`d40utils3dnull`、`d36pointtowards`、`d38drawbitmap`。

## 0005 — flash-lso：AMF3 編碼器的參照索引（2 個檔案）

套在 `rust-flash-lso`。問題：編碼器的參照表依「值」去重，而解碼器依「出現順序」編索引；物件一律完整寫出卻重用了快取索引，XML 不入表，Date 只算長度不登記——於是只要在循環之前序列化過 XML 或 Date，之後的參照就會指到錯的物件。修正：所有完整複合值先佔一個索引，只有「相同的 ObjectId」才能被參照；無效的 AMF3 參照回傳 `InvalidInput` 而不是悄悄寫出 `undefined`；LocalConnection 訊息大小的計量改用原始 AMF3 序列寫入器並共用參照表。

---

## 已知與真 Flash 還不同的地方

| 區域 | 差異 |
|---|---|
| LocalConnection 的幀排程 | 真 Flash 在同一幀處理 `status`、之後分散 1～3 幀送達 `receiver`；Ruffle 在下一幀一次處理完。事件**內容與順序**相同，幀號不同；差異測試的比對器只在 `t2localconn` 這一項略過幀號（`[f+N]`），並對 `asyncError` 的 release／debugger 兩種文字做精確的整行對應。 |
| `AsyncErrorEvent.text` | Ruffle 給的是 debugger 版的長訊息，release 版 Flash 是 `Error #2095`；`errorID` 一致。 |
| `Socket`／計時器的事件順序 | 腳本被占住時，真 Flash 的順序是 `enterFrame` < 到期的 `setTimeout`/`Timer` < `frameConstructed` < `exitFrame` < `socketData`；Ruffle 桌面版是所有幀事件 < `socketData` < 計時器；Ruffle 網頁版因為資料經過小幫手、擴充功能、頁面的多層非同步，`socketData` 剛好排在最後，與 Flash 一致。（Flash 參考值取自 Wine 下的 standalone，沒有在原生 Windows 驗證。） |
| 重複的 `Timer` 卡住之後 | Ruffle 一次補跑所有錯過的 tick；Flash 只跑一次再等一個週期。 |
| `ByteArray` | `writeBytes(src, offset, length)` 越界：Flash 丟 `RangeError #2006`，Ruffle 丟 `EOFError #2030`；`ba.readBytes(ba, 0, n)`（自己讀自己）Flash 會推進 `position`，Ruffle 不會。 |
| 3D | 巢狀的「投影擁有者」（有自己 `perspectiveProjection` 的 3D 容器放進另一個擁有者）與 Flash 不同——Flash 自己的繪圖與 `getBounds` 就彼此不一致；Flash 對 3D 圖會做約 1 像素的雙線性濾波，Ruffle 邊緣較俐落；canvas／WebGL 後備渲染器只畫仿射近似（未驗證）；`Matrix3D.determinant`／`invert` 與 Flash 差在最後一位有效數字。 |
| `hitTestPoint(x, y, true)` | Flash 以整數像素量化（±0.5 像素內答案相同），Ruffle 用精確座標；在輪廓邊緣 1～2 像素內有少數格子不同（一張每格 8×8 像素、共 8960 格的可走格地圖，18 格不同）。**刻意不修**：Flash 的規則像是掃描線光柵化，最接近的常數取樣偏移仍留下 8 格差異，重現的成本與風險太高。見 [`FLASH-NOTES.md`](FLASH-NOTES.md)。 |
| 遞迴深度 | 網頁版保護上限 900 層；需要更深遞迴的演算法（例如遠距離的 A* 尋路）結果會被截斷，桌面版不受影響。 |
| URLStream／LocalConnection 其他 | 未證明所有協定、所有外部接收端、跨使用者隔離都與 Flash 相同；AMF3 中沒有 `ObjectId` 型別（Date、XML、ByteArray、數值 Vector）的共享身分仍以完整寫出處理。 |

> 這些差異都是已知的，**沒有被藏起來**——黃金答案不會為了讓測試通過而被改寫。其中一部分是用需要遊戲檔案的探針量到的，那些探針沒有放進 repo，所以上表是結論而不是可直接重現的測試。
