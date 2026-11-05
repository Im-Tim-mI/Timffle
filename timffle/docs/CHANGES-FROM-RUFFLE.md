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
- **設定**：`socket-proxy.ts`（模式、允許的網站來源、預設清單與升級規則、代理網址樣板驗證）、`proxy-settings.ts`（只存 `storage.local`，不同步）、`proxy-options.ts` 與選項頁的「Socket 連線」區塊（文字來自訊息目錄，跟著瀏覽器的 36 種介面語言，見 [`ARCHITECTURE.md`](ARCHITECTURE.md) 第 7 節）。
- **整合**：`utils.ts` 的 `getOptions(origin)` 只對「允許使用 Socket 的網站」注入 `socketProxy` 設定；使用者沒有自己指定渲染器時，所有網頁（以及選項頁的顯示）預設把裝置字型改成 `canvas`（用瀏覽器字型畫中文），與 Socket 的任何決定無關——以前只有「一律允許」的網站才有，被詢問或拒絕的遊戲中文會消失（見 CHANGELOG 0.8.0.26299）。不在清單內的網站與本機檔案收不到任何 Socket 設定。`build.ts` 加上 `nativeMessaging` 權限，並把環境變數 `EXTENSION_PUBLIC_KEY` 寫成 `manifest.key`（固定 ID）。
- **`web/packages/core/.../load-options.ts`**：`socketProxy` 設定的型別與文件，說明萬用字元對應（`host:"*"`、`port:0`）、`{host}`／`{port}` 樣板、精確對應優先，以及「成功＝WebSocket OPEN」的語意（見 0002）。
- **測試**：3 個測試檔共 38 項（設定與允許清單、頁面橋接、背景權限）。
- **之後新增（發行前）**：第一次連線時的詢問、「一律拒絕」清單、彈出視窗的「允許此網站使用 Socket 連線」按鈕。這些在原本的補丁之後以獨立 commit 加入，說明見 [`ARCHITECTURE.md`](ARCHITECTURE.md) 第 3a 節與 [`../CHANGELOG.md`](../CHANGELOG.md)。0.8.0.26301 起這些頁面的文字全部來自訊息目錄（新增 `i18n.ts`、`timffle/locales/`、`scripts/sync_locales.py`，`utils.ts` 的 `setPageLanguage()` 多設 `dir`）；選項頁、彈出視窗與詢問視窗的 HTML 不再自帶文字。同一批改動還把 `manifest.json5` 的 `web_accessible_resources` 從 `*` 縮到 `dist/*` 與 `player.html`（上游是整個資料夾對所有網頁開放，網頁可以把擴充功能自己的頁面嵌進頁框）。

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

## API 補齊（PRO_bata，`api100`）

目標是把 Ruffle 的 `stub-report`（README 的「Timffle 對 Ruffle 的修補」圖）補到 0 個缺少、0 個空殼。每一批都附回歸測試（`tests/tests/swfs/avm2/`），瀏覽器沒有的功能一律做成「沒有該功能的機器上 Flash Player 的行為」，不假裝成功。

### 第 1 組：網路（LocalConnection、LoaderInfo、Loader、URLLoader、URLStream；加上 Security.allowDomain）

- **`LocalConnection.allowDomain()` / `allowInsecureDomain()`**（原本是空殼）：每個接收端記住自己的允許清單（`core/src/avm2/object/local_connection_object.rs`）；`send()` 送達時（`core/src/local_connection.rs`）依 Flash 的規則檢查寄件端的網域：同一個上層網域預設允許；HTTPS 接收端只透過 `allowInsecureDomain()` 接受非 HTTPS 寄件端（同網域也一樣）；其餘要在清單裡（確切網域、`*` 只涵蓋遠端、`localhost` 涵蓋本機檔案），被拒絕時寄件端收到 `status` 事件 `level="error"`。參數不是字串丟 `ArgumentError #2052`。連線名稱改以**建立該物件的 SWF** 的網域限定（原本一律用根 SWF），`domain` 取呼叫端 SWF 的網域。AVM1 接收端不檢查（AVM1 的 `allowDomain` 是回呼，未實作）。測試 `localconnection_allowdomain`。
- **`Security.allowDomain()` / `allowInsecureDomain()`**（原本是空殼）：記在呼叫端 SWF 上（`SwfMovieData::allow_domains`，`core/common/src/sandbox.rs` 的 `AllowedDomains`）。Ruffle 不執行跨 SWF 的腳本沙箱，所以這份清單只供 Flash 會回報的屬性使用（下一項）。`loadPolicyFile`／`showSettings` 仍是空殼（第 2 組）。
- **`LoaderInfo.sameDomain` / `childAllowsParent` / `parentAllowsChild`**（原本是空殼或只比主機名稱）：`sameDomain` 比較載入端與內容的安全網域（協定＋主機；`http` 與 `https` 不同）；兩個 allows 屬性在同網域為 true，否則看對方有沒有 `Security.allowDomain()` 自己的網域。根 SWF 與舞台沒有載入端，一律 true。**不讀取 crossdomain.xml 政策檔**（下載本身受瀏覽器 CORS 管理），所以只靠政策檔授權的情況 Flash 會回 true、Timffle 回 false。
- **`LoaderInfo.isURLInaccessible`**：尚未載入（`url` 為 null）時 true——這是從 Ruffle 內附的真 Flash 輸出 `from_shumway/as3-loader/loaderinfo/loaded-content-properties` 量到的，該測試的 `sameDomain: true` 也一併對上了；載入後，只有「HTTP 轉址到別的安全網域，而且內容沒有允許載入端」才 true，此時 `url` 只給來源（`http://www.example.com`），與 Flash 文件相同。轉址旗標來自載入器（`core/src/loader.rs`）。
- **`LoaderInfo.parentSandboxBridge` / `childSandboxBridge`**（原本是空殼）：真的存在 LoaderInfo 上；只有載入端 SWF 的程式可以設 parent 端、只有被載入的內容可以設 child 端，否則 `SecurityError #2047`（Flash 的通用沙箱錯誤；文件只說 SecurityError，錯誤號未經真 Flash 驗證）。內容卸載後 child 端清空。
- **`LoaderInfo.getLoaderInfoByDefinition()`**：Flash 文件說只有本機信任沙箱可呼叫，而且發行版播放器回 null；Timffle 照做——`localTrusted`／`application` 沙箱回 null，其餘丟 `SecurityError #2047`（錯誤號同上，未驗證）。測試 `loaderinfo_security_properties`。
- **`Loader.load()` / `loadBytes()` 重複使用**：移除「重複使用 Loader」的空殼標記；取消前一次載入、卸載舊內容、沿用同一個 `contentLoaderInfo` 早已實作，由 `loader_reuse` 測試涵蓋。
- **`URLLoader.addEventListener()`**：Flash 的 playerglobal 在 URLLoader 上宣告了這個覆寫（只為了文件化事件），行為與 `EventDispatcher` 相同；補上覆寫。**`URLStream.diskCacheEnabled`**：只有 AIR 會把下載快取到磁碟，瀏覽器裡的 Flash Player 永遠是 false（唯讀）。測試 `urlloader_urlstream_members`。
- 與真 Flash 仍不同：被載入的子 SWF 在自己的建構式裡讀 `loaderInfo.sameDomain` 等屬性，Ruffle 會丟 `Error #2099`（載入串流要到第一幀之後才切換成已載入；上游既有）。
- **`Loader.load()` 的「加入子物件的時機」空殼**（`core/src/loader.rs`）暫緩：Flash 是在一次 `enterFrame` 之後才把載入的內容掛到 Loader 底下，Ruffle 在第一幀跑完就立刻掛上；要改動載入排程並重新量 `large_preload_*` 三個測試的時序，需要真 Flash 的時序黃金答案，列為待決。

### 第 2 組：系統（flash.system.Capabilities，全部 37 個成員）

- **一個來源**：原本 AVM2 的 `Capabilities` 有 26 個 getter 是空殼常數、`_internal` 與 `cpuAddressSize` 不存在，而 AVM1 的 `System.capabilities` 另外讀 `core/src/system_properties.rs`，且那裡的旗標全部是 false（`hasAudio` 在 AVM1 回 false）。現在兩個 VM 都讀 `SystemProperties`（`capabilities.rs` 全部改成 native）。
- **旗標照「這個播放器真的有什麼」設**：Flash Player 本身固定具備的為 true——`hasAudio`、`hasStreamingAudio`、`hasStreamingVideo`、`hasEmbeddedVideo`、`hasMP3`、`hasAudioEncoder`／`hasVideoEncoder`（Speex／H.264 編碼器內建於播放器，沒有麥克風、攝影機的機器上 Flash 也回 true）、`hasTLS`、`supports32BitProcesses`；`avHardwareDisable`／`localFileReadDisable` 為 false（沒有 mms.cfg 的管理禁用）。**沒有該功能的機器上 Flash 的行為**：`hasAccessibility` false（沒有無障礙橋接）、`hasIME` false（與 `IME.isSupported` 一致）、`hasPrinting` false（沒有 `PrintJob`）、`hasScreenBroadcast`／`hasScreenPlayback` false（FMS 螢幕分享；桌面版 Flash 32 兩者都是 false）、`isDebugger` false（發行版）、`isEmbeddedInAcrobat` false、`touchscreenType` "none"、`hasMultiChannelAudio()` 對任何參數（含 `""`、null）都 false（Dolby／DTS 直通只有電視版有）。
- **依機器而定的**：`cpuArchitecture` 取建置目標（x86／ARM／PowerPC／SPARC；wasm 看不到主機 CPU，跟假裝的 Windows 一樣報 x86）；`cpuAddressSize` 是播放器的指標寬度（64 位元原生 → 64，wasm32 → 32；Flash 32 standalone 32 位元也報 32）；`supports64BitProcesses` 在 64 位元建置與瀏覽器裡 true；`manufacturer` 與 `os`／`version` 同一份主機描述（Flash Player 執行期一律「Adobe Windows」／「Windows 8」／「WIN 32,0,0,0」，AIR 執行期照真實 OS）；`maxLevelIDC` "5.1"、`screenColor` "color"、`_internal` 37（未文件化；真 Flash 32.0.0.465 對任何 SWF 都回 37）。`cpuAddressSize` 是 Flash 32 才有的 API，Ruffle 的 API 版本表只到 AIR 29，所以所有 SWF 版本都看得到。
- **`serverString` 重做**：欄位與順序照 Flash Player 32 量到的（`A,SA,SV,EV,MP3,AE,VE,ACC,PR,SP,SB,DEB,V,M,R,COL,AR,OS,ARCH,L,IME,PR32,PR64,CAS,PT,AVD,LFD,WD,TLS,ML,DP`），編碼同 `escape()`（字母、數字、`-_.` 不編碼，空白是 `%20`）。Ruffle 原本（只有 AVM1 用）少了 `V`、`ARCH`、`PR32`、`PR64`、`CAS`、`WD`、`TLS`、`ML` 八個欄位、`ACC` 的真假相反、`M` 與 `OS` 被編碼兩次。
- **參考值來自真 Flash**：`timffle/difftest/src/D41Capabilities.hx`（探測用，沒有黃金答案）在 Wine 下的 Flash Player 32.0.0.465 standalone 跑出每個成員與 `serverString`；與 Timffle 唯一刻意不同的是 `hasPrinting`／`PR`（Wine 的 Windows 有列印功能，Timffle 沒有）。測試 `capabilities_members`（依機器而定的成員只檢查與 `serverString` 一致，不印值）。

### 第 2 組：顯示（flash.display.Stage，14 個空殼）

- **參考值來自真 Flash**：`timffle/difftest/src/D42Stage.hx`（每個成員的值、非法值的錯誤、`constructor` 寫入、唯讀成員的 `ReferenceError #1074`）與 `D43StageFull.hx`（`fullScreenSourceRect` 的夾限規則、實際進全螢幕後的 `mouseLock`、離開全螢幕後的狀態），在 Wine 下的 Flash Player 32.0.0.465 standalone 跑出；測試 `stage_members` 的 49 行輸出與它逐行相同（唯一例外：測試主機沒有滑鼠鎖定，所以全螢幕時 `mouseLock = true` 讀回 false——這正是 Flash 在沒有該功能的平台上的行為）。
- **`fullScreenSourceRect`**（`core/src/display_object/stage.rs`）：存的是 Flash 的整數化副本——座標四捨六入五成雙（1.5 → 2、0.5 → 0）、NaN → -2147483648、寬高夾在 302×74 到 2880×2880 之間（Flash 32 量到的常數；是否隨螢幕大小變動未驗證）；getter 每次給新的 Rectangle（改它不影響舞台）。全螢幕時只把那一塊舞台等比例放大、置中、四周黑邊（不管 `scaleMode`），`stageWidth`／`stageHeight` 不變（真 Flash 亦然）；全螢幕中改值立即生效；設成 null 回到整個舞台。
- **`mouseLock`**：真的鎖定指標——瀏覽器用 Pointer Lock API（鎖在 canvas 上，滑鼠事件照常送到播放器；使用者按 Esc 或離開全螢幕時瀏覽器解除，`pointerlockchange` 會把狀態同步回 Stage），桌面版用 winit 的 `set_cursor_grab`（Locked，不支援時退成 Confined）。Flash 的規則：非全螢幕時設 true 或 false 都丟 `Error #3707`；離開全螢幕後讀回 false。主機拒絕鎖定時保持 false。`MouseEvent.movementX`／`movementY` 仍是 0（上游既有，不在 stub-report 範圍）。
- **`allowsFullScreen`／`allowsFullScreenInteractive`**：照播放器的 `allowFullScreen` 設定（網頁版的 `allowFullScreen` 參數）；Timffle 的全螢幕從不限制鍵盤，所以互動式全螢幕只要能全螢幕就允許（真 Flash standalone 的 `allowsFullScreenInteractive` 是 false 但 `displayState` 卻回 `fullScreenInteractive`，自己就不一致）。
- **`fullScreenWidth`／`fullScreenHeight`**：與 `Capabilities.screenResolutionX`／`Y` 同一個函式（`capabilities.rs::screen_resolution`，視口大小除以縮放係數）；真 Flash 兩者都回主螢幕解析度（1024×768），Timffle 看不到螢幕只看得到視口，兩個 API 至少彼此一致。
- **`focus` 與 `isFocusInaccessible()`**：焦點物件所屬 SWF 不允許呼叫端的 SWF 存取（不同安全網域且沒有 `Security.allowDomain`）時，`focus` 讀成 null、`isFocusInaccessible()` 為 true；用第 1 組的 `SwfMovie::allows_access_from`。
- **`colorCorrection`**：Flash 在不支援色彩校正的機器上仍記住設定值；`"on"`／`"off"`／`"default"` 以外的字串 `ArgumentError #2008`，null `TypeError #2007`。**`colorCorrectionSupport`** "unsupported"：繪圖後端不套 ICC 色彩描述檔，就是 Flash「沒有色彩管理的機器」的回答。
- **`stageVideos`**：Flash 32 不論有沒有 GPU 都給 8 個 `StageVideo`（同一個 Vector、同一批物件；`new StageVideo()` 是 `ArgumentError #2012`）；物件由 Rust 建立（`createStageVideos`），`StageVideo` 本身的成員屬第 5 組。
- **`wmodeGPU`**：頁面要求 `wmode=gpu` 且由 GPU 繪圖後端（WebGPU／WebGL／wgpu）繪製時 true，否則 false（真 Flash standalone：false）。
- **沒有該功能的機器上 Flash 的行為**：`softKeyboardRect` 永遠 (0,0,0,0) 且每次同一個物件（播放器沒有自己的軟鍵盤；瀏覽器的螢幕鍵盤在舞台之外、大小不公開）；`displayContextInfo` null、唯讀；`constructor` 讀 null、寫入忽略（Flash 32 量到）。

### 第 2 組：系統與網路（flash.system.System 12 項、flash.net.SharedObject 12 項）

- **參考值來自真 Flash**：`timffle/difftest/src/D44System.hx`（ime、processCPUUsage、useCodePage、vmVersion、三個記憶體值的關係、disposeXML 前後每個節點的狀態、pauseForGCIfCollectionImminent 的各種參數）、`D46SystemExit.hx`（pause／resume 期間 enterFrame 是否前進、exit 在 remote 沙箱的錯誤；每個危險呼叫前先回報一次）與 `D45SharedObject.hx`（每個成員的回傳值與錯誤碼、AMF0／AMF3 的 size、getRemote 的鍵、connect 的事件順序），在 Wine 下的 Flash Player 32.0.0.465 standalone 跑出。測試 `shared_object_members` 的 98 行與它逐行相同；`system_members` 除了本機沒有 IME（`IME.isSupported` false）與記憶體數值只比性質（>0、4 KiB 整數倍）外相同。
- **記憶體**（`core/src/memory.rs`）：Flash 回報自己的堆積（`totalMemory` 使用中、`freeMemory` 配置但未用、`privateMemory` 整個行程，都是 4 KiB 頁）。Ruffle 沒有自己的堆積，所以 `CountingAllocator` 包住桌面版、網頁版與測試二進位的全域配置器（desktop/src/main.rs 在 `tracy` 特性外、web/src/lib.rs、tests/tests/regression_tests.rs），算出 Rust 目前配置的位元組當 `totalMemory`；`privateMemory` 問平台（wasm 線性記憶體大小、Linux 的 `/proc/self/statm` RSS）；`freeMemory` = private − total。沒裝計數器的前端 total 退成行程大小。測試執行檔跟別的測試共用行程，所以測試只比每個值自己的性質。
- **`disposeXML`**：Flash 量到的規則是把節點**以下**拆開——每個子孫 `parent()` 成 null（根節點的 `parent()` 仍是 undefined，所以 `E4XNodeData` 多一個 `disposed` 旗標讓 `XML.parent()` 分辨）、子節點清單清空，節點本身保留子節點清單、名稱與屬性，屬性保留父節點；文字節點與 null 不動。
- **`pauseForGCIfCollectionImminent(imminence)`**：gc-arena 的 `allocation_debt() / total_gc_count()` 當「下次回收有多近」的估計，達到 `imminence`（NaN 當 0.75，夾在 0..1）就設 `full_gc_requested`，跟 `Loader.unloadAndStop(true)` 一樣在這次更新後跑完整週期。
- **`exit(code)`**：瀏覽器 `SecurityError #2018`，非 local-trusted `#2017`（真 Flash standalone 從 HTTP 載入也是 remote 沙箱、丟 #2017），其餘呼叫新的 `UiBackend::exit`——桌面版送 `RuffleEvent::ExitRequested` 結束事件迴圈，沒有這能力的宿主忽略。
- **`ime`**：`IME` 是 `[Ruffle(Abstract)]`，物件由 Rust 建立（`SystemClasses::ime`），每個播放器一個；`IME` 的成員本身屬第 5 組。**`useCodePage`** 讀寫 `SystemProperties::use_codepage`（AVM1 `System.useCodePage` 同一個，`loader.rs` 用它決定文字解碼）。**`vmVersion`** "2.1 sec cyclone"（Flash 32 的 AVM2 版本字串）。
- **沒有該功能的機器上 Flash 的行為**：`pause()`／`resume()` 是除錯器掛鉤，發行版播放器不停（量到 pause 後 500 ms 內 enterFrame 前進了 17 次），所以是真的什麼都不做；`processCPUUsage` 是 AIR 專屬，Flash Player 回 int 0。
- **`SharedObject.objectEncoding`／`defaultObjectEncoding`**：`SharedObjectObject` 記住 AMF 版本，`new_lso` 用它序列化（上游一律 AMF3）；只接受 0／3（`ArgumentError #2008`）。`defaultObjectEncoding` 存在 `Avm2` 上、照 Flash 不驗證（量到 1、2、5 都存得進去），新物件 0 → AMF0、其餘 AMF3。`preventBackup` 也在 `Avm2` 上：設定前讀回 null（Flash Player 的回答），所以 getter 是 native。
- **遠端共用物件**（`getRemote`）：路徑必須是 rtmp／rtmpt／rtmps／rtmpe／rtmpte／rtmfp（量到 null 與 http 路徑都是 `Error #2134`；name null `TypeError #2007`）；鍵是 (name, path, persistence)，放在 `avm2_shared_objects` 同一張表、鍵以 `rtmp-remote://` 開頭（本機鍵一定以主機名開頭，不會撞）；`flush()` `#2130`、`clear()` 不碰磁碟、播放器結束時的統一 flush 跳過它們。`connect()`：本機物件、null 或未連線的 NetConnection 丟 `#2139`；已連線（Ruffle 只有 `connect(null)` 與 Flash Remoting，沒有 RTMP）先對物件派送 `NetStatusEvent` code "SharedObject.UriMismatch"、level "error"，再丟 `#2139`——與真 Flash 對 URI 不符的連線一樣。`send()`、`setDirty()`（null `#2007`）、`close()`、`fps` 在沒有伺服器連線時沒有可做的事（Flash 也不報錯；`setProperty()` 現在會呼叫 `setDirty()`）。`client` 預設是物件本身，null 或非物件 `TypeError #2004`。
- **AIR 專屬**：`deleteAll(url)`／`getDiskUsage(url)` 在 Flash Player 對任何 URL（含自己的 URL）都是 `Error #2014`，null `#2007`，Timffle 照做，不刪也不算。AVM1 的 `SharedObject.deleteAll`／`getDiskUsage` 仍是上游的 stub（不在 AVM2 stub-report 範圍）。

### 第 2 組：E4X（XML 5 缺 + 1 空殼、XMLList 5 缺、flash.xml.XMLDocument.toString）

- **參考值來自真 Flash**：`timffle/difftest/src/D47XmlProps.hx`（hasOwnProperty／propertyIsEnumerable 對各種名字的回答、prototype 上有哪些自己的屬性、valueOf 的身分、XMLDocument 各種輸入的 toString／xmlDecl／docTypeDecl／子節點數）、`D48XmlNotify.hx`（透過 `QName(AS3 命名空間, …)` 呼叫 `setNotification`，記錄每種修改送來的指令、value、detail）與 `D49XmlSetName.hx`（setName／setLocalName 各種參數的 nameSet 內容），在 Wine 下的 Flash Player 32.0.0.465 standalone 跑出。測試 `xml_members` 的 128 行期望值全部來自這些探針。
- **`hasOwnProperty`／`propertyIsEnumerable`**：`XML.as`／`XMLList.as` 以 `override AS3 native function` 宣告（Flash 的 playerglobal 也是類別自己的方法），Rust 端 `xml.rs`／`xml_list.rs` 的 `has_own_property`／`property_is_enumerable` 走既有的 `has_own_property_string`，`XmlObject`／`XmlListObject` 新增 `property_is_enumerable` 覆寫（XML 只有 `"0"`、XMLList 是 `ToString(ToUint32(P)) == P && P < length`）。prototype 版本與其他 E4X prototype 方法同一種寫法（`var self:XML = this` → 非 XML 的 `this` 是 `TypeError #1034`），`prototype.valueOf = Object.prototype.valueOf`（Flash 兩者是同一個函式；`Function` 類別初始化時已跑過 `Object.init()`，所以可以直接拿）。
- **`setNotification`**：原本只有 attributeAdded／attributeChanged／nameSet 三種指令、其餘沒有。現在 `E4XNode::trigger_notification` 從被改的節點往祖先走，對每個設有回呼的節點呼叫 `callback(那個節點, 指令, 被改的節點, value, detail)`（`this` 為 null），回呼丟出的錯誤往外傳（Flash 也是，而且修改已經生效）。指令：`nodeAdded`（`E4XNode::notify_node_added`：prependChild、insertChildAfter／Before、XMLList `[[Put]]` 追加新子節點——appendChild 走這條，以及用 XML 指派一個原本不存在的子節點）、`nodeChanged`（`notify_node_changed`：`replace()`、以 XML 指派既有子節點、XMLList 以索引指派既有節點）、`nodeRemoved`（`notify_nodes_removed`：`delete x.child`、XMLList 以索引 `delete`、`replace("*")`／`setChildren`／指派時先清掉的其餘同名子節點——Flash 由後往前報，`remove_matching_nodes` 現在把其餘被移除的節點一起回傳）、`textSet`（指派字串：目標是新建的文字節點、value 是字串、detail 是舊的文字節點或 null）、`attributeRemoved`（value 名字、detail 舊值）、`nameSet`（value 是傳入的字串或 QName、detail 是舊的 localName；量到有命名空間的 QName 時 Flash 的 detail 是新的 localName，照做——上游的 `xml_notification_bubbling` 測試就是這個案例）、`namespaceSet`／`namespaceAdded`／`namespaceRemoved`（value 是 Namespace 物件；removeNamespace 每個元素各一次、子節點先、自己最後，和 Flash 的順序相同）。`E4XNode::replace` 改成回傳放進去的節點，`XmlObject::delete_property_local` 與 XMLList 的 `delete` 在放開 `RefCell` 借用之後才呼叫回呼（回呼會跑 ActionScript）。`setNotification` 回 null（Flash 的回答），參數是 `f:Function`，傳非函式由 AS 的型別轉換丟 `#1034`。
- **`XMLDocument.toString()`**：`xmlDecl`（非 null 時 `String()`）＋ `docTypeDecl` ＋ 子節點依序；沒有子節點時 `<>`（Flash 對空文件就是印這個）。`parseXML` 新增 `_takeDeclarations`：把每個 `<?xml …?>` 與 `<!DOCTYPE …>`（含 `[ ]` 內部子集）取出存進 `xmlDecl`／`docTypeDecl`，剩下的片段各自用 E4X 解析後接起來——所以宣告前後的空白各是一個文字節點（Flash 量到 3 個子節點，之前是 2 個）。註解與處理指令照舊被 E4X 的預設設定丟掉（Flash 也不保留）。
- **已知未動**：`Object.prototype.hasOwnProperty.call(xml, "b")`（以及 `XML.prototype.hasOwnProperty.call({}, …)`）在 Ruffle 拿到的是綁在 prototype 物件本身的 AS3 方法，因此回答的是 prototype 物件自己有沒有該屬性；這是上游 vtable 對 public 名字也配到 AS3 命名空間方法的既有行為，與 XML 類別無關，列在下表。

### 第 2 組：桌面與無障礙（flash.desktop.Clipboard 7 空殼、flash.accessibility.Accessibility 2 空殼、flash.debugger.enterDebugger 缺少）

- **參考值來自真 Flash**：`timffle/difftest/src/D50ClipAcc.hx` 在 Wine 下的 Flash Player 32.0.0.465 standalone 跑出（`timffle/difftest/drive_flash.py` 用私用 Xvfb 與 XTest 送真的滑鼠點擊，所以「使用者事件內」那一段也是量到的）；`Event.PASTE` 在 Wine 下送不出去（Flash 只收到修飾鍵），貼上事件內的行為照 AS3 參考文件。測試 `clipboard_accessibility_members`（150 行）貼上事件之外的每一行都和真 Flash 相同。
- **`Clipboard`**（`core/src/avm2/globals/flash/desktop/clipboard.rs`，狀態放在 `Avm2::clipboard`）：Flash Player 只有作業系統剪貼簿這一個，`generalClipboard` 第一次取用時建立（Ruffle 在類別的靜態初始化期間拿不到類別物件，所以不能在宣告處 `new`），之後任何 `new Clipboard()` 都是 `IllegalOperationError #2178`。`setData` 接受 `air:text`（任何值轉成字串，並寫進主機剪貼簿 `UiBackend::set_clipboard_content`）、`air:html`、`air:rtf` 與任何自訂格式名，回 `true`；AIR 才有的 `air:url`、`air:bitmap`、`air:file list`、`air:file promise list` 回 `false` 不存；格式或資料為 null 是 `TypeError #2007`。`setDataHandler` 存函式並把格式列進 `formats`，讀取時才呼叫（參數是格式名）；null 函式／格式 `#2007`。`formats` 每次是新的 Array、依加入順序；主機剪貼簿有文字而清單裡沒有 `air:text` 時（別的程式複製了東西）會排在最前面。`hasFormat(null)` false。`clearData(air:text)`／`clear()` 也清掉主機剪貼簿。**`getData` 只在 `Event.PASTE` 派送期間允許**（`Avm2::in_paste_event`），其他任何時候——包括滑鼠事件內、格式不存在——都是 `SecurityError #2179`；null 格式在那之前就是 `TypeError #1009`（真 Flash 的順序）。貼上事件內：`air:text` 以主機剪貼簿為準（`setData` 寫進去的，或之後別的程式複製的），`air:html`／`air:rtf` 回副本（ByteArray 走 AMF3 來回），自訂格式照 `transferMode`：`originalPreferred`／`originalOnly` 原物件、`clonePreferred` 可序列化就給 AMF3 副本否則原物件、`cloneOnly` 不可序列化（`serializable=false`）回 null；不認得的 transferMode 丟 `ArgumentError #2008`（文件只說 Error，代碼是假設）。
- **`Event.PASTE`**：原本 Ruffle 不派送。現在貼上的文字控制碼（Ctrl+V、右鍵選單的貼上、網頁版的 JS `paste` 事件）先對焦點物件派送 `paste`（bubbles、不可取消；`EditText::text_control_input` 在插入文字之前，焦點不是文字欄位時由 `Player::handle_input_event` 派送），處理函式裡才能 `getData`。
- **瀏覽器外掛的「只能在使用者事件內寫入」規則**：`Player::handle_input_event` 處理滑鼠／鍵盤／文字輸入事件期間設 `Avm2::in_user_interaction`；網頁版（`target_family = "wasm"`）的 `Clipboard.clear`／`clearData`／`setData`／`setDataHandler` 在這之外丟 `SecurityError #2191`，`System.setClipboard` 丟 `#2176`（上游原本寫 `if false`，從不丟）。standalone 與桌面版沒有這條規則（真 Flash standalone 量到：事件外的 `setData` 也成功），和上游對 `setClipboard` 的分法相同。
- **`Accessibility`**：`updateProperties()`／`sendEvent()` 在 `Capabilities.hasAccessibility` 為 false 時丟 `IllegalOperationError #2014`（真 Flash 在沒有螢幕閱讀器橋接的機器上就是這樣，連 `sendEvent(null, …)` 也是），`active` 維持 false。這就是「沒有該功能的機器上 Flash 的行為」：Timffle 沒有 MSAA 橋接。
- **`flash.debugger.enterDebugger()`**：新的 `flash/debugger.as`，發行版播放器的這個函式立刻返回（只有 debugger 版會停在這裡），量到：回 void、帶參數是 `ArgumentError #1063`。

### 第 2 組：顯示雜項（flash.display.AVLoader.load、AVM1Movie.call／addCallback、BitmapData.generateFilterRect／encode、DisplayObjectContainer.getObjectsUnderPoint／areInaccessibleObjectsUnderPoint）

- **參考值來自真 Flash**：`timffle/difftest/src/D51DisplayMisc.hx`（總覽）、`D52DisplayEdge.hx`（邊緣像素、舞台外、scrollRect、遮罩）、`D53BlurRect.hx` 與 `D54BlurRect2.hx`（BlurFilter 每個 quality 的細網格與整數邊界）在 Wine 下的 Flash Player 32.0.0.465 standalone 跑出。測試 `avm2/display_misc_members` 的每一行期望值都來自這些探針（PNG／JPEG 的位元組長度跟編碼器有關，不印）。上游的 `from_shumway/getobjectsunderpoint` 與 `from_shumway/hittesting/hittesting` 原本標成已知失敗，現在與真 Flash 的黃金輸出逐行相同，標記已移除。
- **`AVLoader.load()`**：AVLoader 是載入 AVStream（HLS）內容的 Loader，Flash Player 沒有這條管線——真 Flash 32 對任何 `load()` 丟 `Error #2037`，其餘行為就是 Loader。這是「沒有該功能的機器上 Flash 的行為」。
- **`AVM1Movie.call()`／`addCallback()`**：AIR 才有的 AVM1 橋接；Flash Player 32 對任何參數（含 null）丟 `IllegalOperationError #2014`（Ruffle 原本丟的是一般 `Error`）。載入的 AVM1 內容仍照常播放，只是沒有這座橋。
- **`BitmapData.generateFilterRect()`**（`bitmap_data.rs` 的 `generate_filter_rect_internal`）：來源矩形先像其他 BitmapData 矩形一樣四捨六入到整數（每條邊各自 round-half-even：`(10.5,11.5,30.5,30.5)` → `(10,12,31,30)`），再夾到點陣圖內（`(-5,-5,20,20)` → `(0,0,15,15)`）；完全在外面或寬高為負時是 Flash 的「沒有區域」標記矩形 `(134217727,134217727,0,0)`，而且濾鏡的擴張照樣套在它上面（`(134217725,134217725,4,4)`）。擴張規則：**模糊** 每邊 `floor(S[quality] × max(blur, 1) + 0.75)` 像素，`S` 是 Ruffle 累積 pass 比例的一半（0.5、1.05、1.35、1.55、1.75、1.9、2.0、2.1、2.2、2.3、2.5、3.0、3.0、3.5、3.5）、以單精度常數相乘（所以 quality 2 的 blur 5 長 5 格、quality 3 的 blur 15 長 21 格，與 Flash 相同），quality 0 不擴張、超過 15 當 15、負的 blur 當 1；**Glow** 同模糊；**DropShadow／GradientGlow** 是「模糊後的矩形平移 `(floor(d·cos θ), floor(d·sin θ))`」與來源矩形的聯集（整數內的浮點誤差視為整數：4 像素 30° 往下 2 格、90°／180° 橫向 0 格）；**Bevel／GradientBevel** 再加上反向平移的那一份；**Convolution** 每邊 `floor(matrixX/2)`、`floor(matrixY/2)`；**ColorMatrix／DisplacementMap** 不變；**ShaderFilter**（連沒有 shader 的也算）一律整張點陣圖。null 矩形或 null 濾鏡 `TypeError #2007`、已 dispose `ArgumentError #2015`，每次回新的 Rectangle。
- **`BitmapData.encode()`**（`encode_internal`，`image` crate 的 `png`／`jpeg`）：矩形同樣四捨六入後夾到點陣圖，完全在外面或寬高 0 是 `ArgumentError #2006`、null 矩形 `TypeError #2007`；compressor null `TypeError #2007`、不是三種 EncoderOptions 的物件（含字串）`ArgumentError #2004`、JPEG quality 大於 100 `RangeError #2006`（0 當 1）；已 dispose `ArgumentError #2015`。PNG：透明點陣圖寫 RGBA（colorType 6）、不透明寫 RGB（colorType 2），`fastCompression` 用快的 zlib 等級；JPEG：丟掉 alpha、JFIF 標頭。給了 `byteArray` 就從它目前的 `position` 寫入並回同一個物件（`position` 停在資料尾端、前面的內容保留——與 Flash 的 `hello` + PNG 相同），否則回新的 big-endian ByteArray。**還沒做的**：`JPEGXREncoderOptions` 真 Flash 會輸出 JPEG XR（`4949bc01…`），Ruffle 附的 jxrlib 綁定只有解碼，這一支仍是空殼（回 null），要補 jxrlib 編碼器的 FFI。
- **`DisplayObjectContainer.getObjectsUnderPoint()`**（`display_object_container.rs` 的 `objects_under_point`）：照 Flash 的規則——先父後子、由後往前（`[a, b, inner]`、`[n1, n2, n3]`）；**容器自己的繪圖命中時也列進去**（`self.getObjectsUnderPoint(…)` 回 `[self, selfchild]`，Ruffle 原本把 `this` 排除）；Shape、Bitmap（整個邊界，透明像素也算）、TextField、`mouseEnabled=false`、`mouseChildren=false` 的子物件、alpha 0 的填色與 `alpha=0` 的物件都算；`visible=false` 的物件連同整個子樹不算、遮罩物件本身不算、被遮罩物件（含它的子樹）只在遮罩內算；`scrollRect` 不裁切（`(230,430)` 在 10×10 的 scrollRect 外仍命中）；**SimpleButton 列的是它正在顯示的狀態物件**（up state 的 Shape，`parent` 為 null），`hitTestState` 完全不影響（真 Flash 如此，這就是 shumway 兩個測試原本失敗的原因）；舞台與 Loader 本身沒有繪圖、不會出現。`null` 點 `TypeError #2007`。**沒有重現的**：真 Flash 先用「上次繪製時」的邊界篩選再精確命中（物件搬動後、下一次繪製前，舊位置與新位置都查不到），Ruffle 用目前的變換；舞台外（沒有加到舞台）的容器 Flash 的座標空間也受同一個快取影響，Ruffle 用該樹的全域座標；邊緣像素的量化同 `hitTestPoint` 那一列（Flash 的 x 是 `trunc(x) − 0.5`、y 是 `trunc(y) + 0.5` 取樣，刻意不修）。
- **`DisplayObjectContainer.areInaccessibleObjectsUnderPoint()`**：同一套列舉，只要有一個命中的物件來自呼叫端 SWF 不能存取的 SWF（不同安全網域且沒有 `Security.allowDomain` 給呼叫端）就 true；同網域一律 false、`null` 點 `TypeError #2007`。規則與 `LoaderInfo.childAllowsParent`／`Stage.isFocusInaccessible` 相同。

### 第 2 組：繪圖（flash.display.Graphics.drawPath／drawTriangles／drawGraphicsData）

- **參考值來自真 Flash**：`timffle/difftest/src/D55Graphics.hx`（readGraphicsData 的結構、drawTriangles 的 UV 貼圖與 drawPath 的線條／填色）、`D56Graphics2.hx`（透視 t、uvtData 長度錯誤、重疊三角形、線條順序與顏色捨入、漸層矩陣）、`D57Winding.hx`（同一個 fill 裡 drawRect／lineTo／drawPath／drawTriangles 怎麼分群）在 Wine 下的 Flash Player 32.0.0.465 standalone 跑出；像素以 `BitmapData.draw` + `getPixel32` 取樣，所以是文字報告。測試 `graphics_path_triangles_rules` 的每個取樣點都來自這些探針（只有 `e3` 的 (16,5) 是把原本落在貼圖格邊界的 (20,5) 往左移的推論值）。
- **填色群組**（`core/src/drawing.rs` 的 `FillOrigin`）：Flash 的一個 `beginFill` 不是單一路徑——一般指令共用一個 even-odd 群組；每次 `drawPath`／`GraphicsPath` 以自己的 winding 另開群組，緊接著的同 winding `drawPath` 併入同一群組（兩次 nonZero、一順一逆的方塊重疊處是洞）、不同 winding 或之後的一般指令另開群組；每次 `drawTriangles` 自成群組。所以 lineTo 兩個同向重疊方塊中間是洞，中間插一次 `drawTriangles` 就不是洞了（量到的 `c2`）。`Drawing::begin_path_group`／`begin_triangles_group`／`draw_command_in_group` 實作這些規則，`draw_command`（一般指令）遇到非一般群組時自動另開 even-odd 群組。
- **drawPath 的線條**：子路徑永遠不自動閉合（文件也這麼寫；lineTo 版在 fill 裡會補一段回起點的線）。`DrawingLine.auto_close` 旗標＋`begin_path_stroke`／`end_path_stroke` 把 drawPath 的線段獨立成不閉合的子路徑。**沒有重現**：真 Flash 在 `drawPath` 之後再 `lineTo` 時，drawPath 那段線條整個不畫（量到的 `w5`），Timffle 照常畫。
- **drawTriangles**（`graphics.rs` 的 `draw_triangles_internal`／`draw_textured_triangle`）：三角形先轉成一致方向再以 non-zero 畫，重疊處是聯集（順時針與逆時針、大小套疊都量過）；`uvtData` 長度不是頂點數的 2 或 3 倍就 `ArgumentError #2004`（連沒有填色也檢查）；點陣圖填色＋UV 時每個三角形各自成為一個點陣圖填色，矩陣由 3 個頂點的 (u·寬, v·高) → 座標解出（填色本身的矩陣忽略，沒有 UV 時照用）；有 `t` 時 u、v 以 t 加權內插（量到：右邊 t=0.25 時 u=0.5 的分界在 x=33、t=4 時在 x=8），做法是把 t 差超過 2% 的三角形遞迴細分（最多 5 層、邊長小於 4 px 停止）成仿射小片；漸層填色加 uvtData 時 Flash 什麼都不畫，照做；單色填色忽略 UV。畫完之後游標停在最後一個三角形的第一個頂點（之後的 lineTo 從那裡開始，量到的 `t11`）。
- **drawGraphicsData**：`Graphics.as` 改成 AS3 迴圈，`GraphicsPath` 走 `drawPathObject()` → `drawPath()`（Flash 的 playerglobal 就是這樣，錯誤堆疊多那兩層；commands／data 為 null 的 path 跳過，沿用上游），其餘項目交給新的 native `drawGraphicsDataItem`。
- **readGraphicsData／beginShaderFill／lineShaderStyle 還沒做**，Flash 的 readGraphicsData 結構已量完（`difftest/results/flash/d55graphics.txt`、`d56graphics2.txt`、`d57winding.txt`），留給下一批。

### 第 2 組：顯示小成員（InteractiveObject 軟鍵盤成員、MovieClip.trackAsMenu、Shader.precisionHint、ShaderJob、Sprite.startTouchDrag／stopTouchDrag、TransformGestureEvent.GESTURE_DIRECTIONAL_TAP）

- **參考值來自真 Flash**：`timffle/difftest/src/D58Misc.hx`（屬性、ShaderJob 的同步／非同步與錯誤、三次「在 A 按下、在 B 放開」的拖曳——由新的 `timffle/difftest/drive_drag.py` 透過私有 Xvfb＋XTest 送出真的按下、移動、放開）與 `D59ShaderQueue.hx`（佇列、ByteArray／Vector 目標）在 Wine 下的 Flash Player 32.0.0.465 standalone 跑出。測試 `avm2/display_small_members` 的每一行都來自這些探針（只有 `GESTURE_DIRECTIONAL_TAP` 例外，見下）。Wine 下真 Flash 的背景 ShaderJob 不穩定（D58 只有第一個工作完成，D59 一個都沒完成，`progress` 停在 0），非同步的時序只能確定「`start()` 回來時 target 還沒變、complete 在下一個 `enterFrame` 之前」。
- **`MovieClip.trackAsMenu`**（`movie_clip.rs` 的 `track_as_menu` 旗標、`player.rs` 的放開處理、新的 `ClipEvent::MenuRelease`）：在 A 上按下、在 B 上放開時，Flash 先給 A `releaseOutside`，然後——只有 B 的 `trackAsMenu` 為 true 時——給 B `click`；旗標是在派送 click 的那一刻讀的（在 `mouseUp` 處理函式裡把 B 的旗標打開，這次就有 click）。Ruffle 原本把旗標存起來但從不使用；現在放開時對滑鼠下的 AVM2 物件排一個 `MenuRelease`，它在派送時才檢查 `MovieClip.trackAsMenu` 或 AVM2 `SimpleButton` 的 menu tracking，成立就當 `Release`（click／doubleClick）。AVM1 不變。
- **上游的「同一個時間軸物件」判斷**（`Player::check_display_object_equality`）：原本只比 depth、character id 與所屬 SWF，目的是 goto 重建物件後仍算「在同一物件內放開」；兩個 `new Sprite()`／`new MovieClip()` 的 id 都是 0、depth 相同，所以在 A 按下、在 B 放開在 Ruffle 一律算成 A 的 click。現在只對時間軸放置的物件套這條規則。
- **`ShaderJob`**（`ShaderJob.as`、`shader_job.rs`）：`start()` 先驗證（第二次 `start()` 不論完成或取消都是 `ArgumentError #2172`；shader／target null `TypeError #2007`；target 不是 BitmapData／ByteArray／Vector.<Number>（字串也算）`ArgumentError #2004`；ByteArray／Vector 目標的 `width`／`height` 為 0 `ArgumentError #2004`；影像輸入沒給 `ArgumentError #2164`；固定長度的 Vector `RangeError #1126`；輸出不是 3／4 通道 `#2162`，沿用上游），然後把 shader 的 handle 與參數、輸入複製下來（Flash 也是在 `start()` 時複製）。`start(true)` 立刻執行；`start(false)` 把工作排進 `Avm2::shader_jobs`，`Player::run_actions` 在每一輪腳本結束時依序執行（`complete` 處理函式再 `start()` 的工作也在同一輪跑完），寫入 target 後派送 `ShaderEvent.COMPLETE`（bubbles／cancelable false，`bitmapData`／`byteArray`／`vector` 依目標型別其一非 null）；已 `dispose()` 的 BitmapData 目標不寫、照樣完成（文件行為）。`progress`：未開始 NaN、排隊中 0、完成 1；`cancel()` 把排隊中的工作標成取消（執行時跳過、不派送）並把 progress 設回 0（對已完成的工作也是 0，量到）。ByteArray 目標：浮點數依 ByteArray 自己的端序寫入（Flash 預設 big-endian 的 ByteArray `readFloat()` 讀回正確值；上游寫原始小端序位元組）；`render/wgpu` 讀回的緩衝區只取前 `height` 列（上游把多出的列也算進結果：2×2 的 Vector 長 32 而不是 16）。**假設**：同步的 `start(true)` 不派送 `complete`（Adobe 文件兩處說法相反，`ShaderEvent.COMPLETE` 的說明是「非同步才派送」）。
- **`Shader.precisionHint`**：只接受 `ShaderPrecision.FULL`／`FAST`，其他值（null、""、"FULL"）`ArgumentError #2004`；Ruffle 的 Pixel Bender 一律全精度執行，值只是存起來。
- **沒有該功能的機器上 Flash 的行為**（都在真 Flash 32 量到）：`InteractiveObject.requestSoftKeyboard()`——`needsSoftKeyboard` 為 true 且物件在舞台上時把 `stage.focus` 設成自己（false 時焦點不動），永遠回 false（沒有虛擬鍵盤）；`needsSoftKeyboard`／`softKeyboardInputAreaOfInterest`（同一個 Rectangle 物件讀回、改原物件會跟著變）／`accessibilityImplementation`（同一個物件讀回）照存，`Capabilities.hasAccessibility` 為 false 所以沒有人會查詢它；`Sprite.startTouchDrag()`／`stopTouchDrag()` 在 `Multitouch.supportsTouchEvents` 為 false 的機器上任何 touchPointID（含 -1、沒按過的 id、連 `startDrag` 混用）都接受、什麼都不拖、不丟錯——Ruffle 把觸控當滑鼠送，沒有可綁定的觸控點，行為相同。
- **`TransformGestureEvent.GESTURE_DIRECTIONAL_TAP`**：AIR 3.0 的常數，Flash Player 32 standalone 讀到 undefined（airglobal 才有），但在 Adobe 的 API 清單裡；照文件補上 `"gestureDirectionalTap"`，版本標記與 `MovieClip.isPlaying` 相同（`[API("674")]`）。

### 第 2 組：媒體（flash.media.Sound 8 個空殼、SoundMixer 2 缺、flash.media 套件函式 2 缺、Video 1 缺 + 4 空殼、VideoStreamSettings 4 空殼、H264VideoStreamSettings 4 缺、Transform.concatenatedColorTransform、ExternalInterface.marshallExceptions、flash.system.AuthorizedFeatures 3 缺）

- **參考值來自真 Flash**：`timffle/difftest/src/D60Media.hx`（Sound 的屬性與事件順序、close／extract／loadPCMFromByteArray 的錯誤與回傳、SoundMixer、套件函式、Transform、Video＋NetStream、VideoStreamSettings／H264VideoStreamSettings）與 `D61Extract.hx`（extract 的取樣值、端序、循序游標、PCM 的 16 位元量化）在 Wine 下的 Flash Player 32.0.0.465 standalone 跑出。測試 `avm2/media_members` 的期望值除了標示 `(Ruffle)` 的行以外都來自這兩個探針（MP3 解碼器相關的取樣值只比個數、位置與端序）。
- **`Sound`**（`sound.rs`、`sound_object.rs`、`loader.rs` 的 `load_sound_avm2`）：`url` 在第一個 `progress` 事件時才設（`open` 時仍是上一個值或 null，與 Flash 相同；轉址到別的來源時只剩來源、`isURLInaccessible` 為 true）；`bytesLoaded`／`bytesTotal` 是真的計數（程式庫與 ByteArray 的聲音為整個大小）；`isBuffering` 從 `load()` 起永遠 true（真 Flash 在 complete、close、ioError 之後都還是 true；程式庫／ByteArray 聲音 false）；`close()` 關掉 `load()` 開的串流（下載中的就丟掉、不再有事件、可以再 `load()`），沒有開著的串流——新物件、程式庫／ByteArray 聲音、第二次 close——丟 `IOError #2029`；`load()` 的事件順序改成 Flash 的 `open`、`progress 0/total`、`progress total/total`、`id3`、`complete`，不是 MP3 的資料照樣 complete 但 `length` 0（不報錯），失敗的請求是 `open` 再 `ioError`（文字 `Error #2032`，發行版 Flash 的訊息），`SoundLoaderContext` 不再標成空殼（`bufferTime` 在整檔下載完才播放的播放器永遠滿足，`checkPolicyFile` 守的是這個播放器從不限制的 `id3`／`computeSpectrum`）；`extract()` 真的解碼：寫入目前 `position`（位置跟著前進）、照 ByteArray 自己的端序寫 32 位元浮點數、回傳寫入的取樣框數，長度小於 1／NaN、目標 null、起點超過結尾都回 0，小數截斷，負的或 NaN 的 `startPosition` 接著上一次的位置（明確的起點也會移動游標），其他取樣率的聲音換算成 44.1 kHz（取樣保持，`floor(n×44100÷rate)` 框）；解碼器留在物件上，逐塊讀整首歌不用每次從頭解。`loadPCMFromByteArray()` 真的載入：從 `position` 讀 `samples` 框（float 夾在 ±1 後截成 16 位元、short 直接用，都照 ByteArray 的端序，單聲道複製到兩聲道），換算成 Flash 內部的 16 位元 44.1 kHz 立體聲（`length` = `floor(samples×44100÷rate)÷44.1` ms 與 Flash 相同）；`bytes` 或 `format` null `TypeError #2007`、別的格式 `ArgumentError #2005`、0 個取樣或位元組不夠 `ArgumentError #2084`、`bytesTotal` = `samples×聲道數×2`、已有資料的物件在位元組檢查之後忽略呼叫、`position` 前進讀掉的位元組——全部量到。`loadCompressedDataFromByteArray()` 改成先檢查位元組再看狀態（Flash 的順序）。**假設**：`sampleRate` 非正數或 NaN 當 44100（Flash 接受任何正數，含 12345）。
- **`SoundMixer.audioPlaybackMode`／`useSpeakerphoneForVoice`**：行動裝置的音訊工作階段設定，桌面播放器只是存起來（真 Flash 32 不驗證、任何值都收；設定前讀到 null——Boolean 的 getter 這裡讀 false）。Adobe 標成 AIR 3.0（API 675），但 Flash Player 32 對 SWF 13 以上的內容都有，所以版本標記用 674（與 `MovieClip.isPlaying` 相同）。
- **`flash.media.scanHardware()`／`avSendToURL()`**（新的 `flash/media.as`）與 **`flash.system.AuthorizedFeatures`**（新檔）：`scanHardware()` 重新列舉攝影機與麥克風——這個播放器一台裝置也沒有，所以什麼都找不到就回來（真 Flash 立即返回）；`avSendToURL()` 是 Primetime 版的 `sendToURL`，`features` 或 `request` 為 null 丟 `TypeError #2007`（量到），之後的路徑到不了：`AuthorizedFeatures` 不能直接建構（`ArgumentError #2012`，量到），只有 `AuthorizedFeaturesLoader` 向 Adobe 的授權伺服器拿得到，而這個播放器不連授權伺服器，所以 `enableAVLoader`／`enableDiskCache`／`enableHLSPlayback` 永遠 false——沒有該功能的機器上 Flash 的行為（其餘四個方法的參數型別 `ApplicationInstaller`／`AVURLLoader`／`AVURLStream`／`MediaPlayer` 還不存在，留給第 5 組）。
- **`ExternalInterface.marshallExceptions`**（`external.rs`、`external_interface.rs`、`web/src/lib.rs`、`web/src/external_interface.rs`）：預設 false；設成 true 之後，ActionScript 回呼丟出的錯誤會在頁面的 JavaScript 以 `Error`（訊息是 AS 的錯誤文字）重新丟出，`call()` 呼叫的 JavaScript 函式丟出的例外會在這裡以 `Error`（訊息是 JS 的 `message`）重新丟出；false 時沿用原本的行為（回呼回 null、`call()` 回 undefined）。桌面版沒有容器，`available` 為 false。
- **`Transform.concatenatedColorTransform`**：物件在舞台上時是從舞台往下每一層 `colorTransform` 的乘積（祖先的乘數乘上後代的位移，整數截斷，與 Flash 的 `(0.25,…|3,…)×…` 得 10 相同），不在顯示清單上時只有自己的（含 `alpha`）；每次新的物件。全部量到。
- **`Video`**（`Video.as`、`video.rs`、`display_object/video.rs`、`streams.rs`）：`videoWidth`／`videoHeight` 是串流畫面的大小（新物件 0；FLV 的 `onMetaData` 一到就是 metadata 的大小——回呼裡就讀得到——之後是解碼出的畫面大小；`attachNetStream(null)` 之後保留；SWF 內嵌影片是串流標頭的大小），不是 Video 物件的大小；`clear()` 清掉畫面但不動串流（NetStream 下一張解碼的畫面會再顯示；`videoWidth` 保留）；`attachNetStream(null)` 真的拆掉串流（不再畫、大小保留）；`attachCamera()` 在沒有攝影機的播放器上照 Flash 接受 null 什麼都不做（`Camera.getCamera()` 是 null，沒有別的 Camera 可以傳）。
- **`VideoStreamSettings`／`H264VideoStreamSettings`**：照真 Flash 存值並夾限——所有屬性起始 -1；`setKeyFrameInterval` 保留 -1、其他夾到 1～300；`setMode` 寬高保留 -1、其他小於 1 的提到 1，fps 保留 -1、其他（含 NaN）至少 0；`setQuality` 保留 -1、其他至少 0、quality 最多 100；H.264：codec `H264Avc`、預設 profile `baseline`、level `2.1`，`setProfileLevel` 的 profile 不分大小寫但照原樣存（`MAIN` 回 `MAIN`）、level 必須與 `H264Level` 的字串完全相同（`3.0`、空字串不行），錯的 `ArgumentError #2008`、null `TypeError #1009`。發布需要 Camera，這個播放器沒有，所以值只會被讀回。

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
| `getObjectsUnderPoint` | 真 Flash 先用上次繪製時的邊界篩選（物件搬動後、重繪前，新舊位置都查不到；沒加到舞台的樹也受影響），邊緣像素以 `trunc(x) − 0.5`、`trunc(y) + 0.5` 取樣；Ruffle 用目前的變換與精確座標。重繪之後（事件處理函式裡的一般用法）結果相同。 |
| `BitmapData.encode(…, JPEGXREncoderOptions)` | Flash 輸出 JPEG XR；Ruffle 的 jxrlib 綁定只有解碼，這一支仍是空殼（回 null，標在 stub-report）。 |
| `Graphics.drawPath` 之後的 `lineTo` | 真 Flash 在 drawPath 之後接著用 lineTo 時，drawPath 那段線條不畫（只剩 lineTo 的線段與閉合線）；Timffle 兩段都畫。填色相同。 |
| `Graphics.drawTriangles` 的貼圖取樣 | 真 Flash 取最近貼圖格時有半格的偏移（u=0.5 落在格 9 而不是格 10），Timffle 用 GPU 的 `floor(u·寬)`；只差在貼圖格邊界那一排像素。透視（t）是以細分的仿射小片逼近，邊界位置誤差小於 1 px。 |
| `ShaderJob` 的背景執行 | 真 Flash 在另一條執行緒跑背景的 ShaderJob、`complete` 回到主執行緒；Timffle 在同一輪腳本結束時（下一幀之前）同步執行並派送 `complete`，同時只會有一個工作在跑、順序相同，但 `progress` 不會出現 0 與 1 之間的值。 |
| `<prototype>.hasOwnProperty.call(…)` | `Object.prototype.hasOwnProperty`／`propertyIsEnumerable`（以及 `XML.prototype`、`XMLList.prototype` 上的同名函式）在 Ruffle 取出來的是綁在那個 prototype 物件上的 AS3 方法，`.call(other, name)` 因此忽略 `other`；直接呼叫 `obj.hasOwnProperty(name)` 正確。上游既有行為。 |
| `Sound.extract()` 的取樣值 | 真 Flash 對 `loadPCMFromByteArray` 載入的聲音，開頭十幾個取樣框回 0（像是濾波器暖機），Timffle 從第一框就回真的值；其他取樣率的聲音真 Flash 用它自己的重取樣濾波（22.05 kHz 的 ±0.5 方波讀回 0.75／0.25），Timffle 用取樣保持；MP3 的解碼器延遲由各自的解碼器決定，前幾框可能不同。個數、位置、端序、量化（16 位元截斷）相同。 |
| `Sound.load()` 失敗的請求 | 真 Flash 對 HTTP 404 也先送 `progress`（錯誤頁的位元組數）再 `ioError`，之後重新 `load()` 時 `bytesLoaded` 會累加；Timffle 送 `open` 後直接 `ioError`，`bytesLoaded` 不累加。 |
| `NetStream` 的狀態順序 | 真 Flash 在 `onMetaData` 之後才送 `NetStream.Play.Start`（那時 `Video.videoWidth` 已知）、`Buffer.Empty` 在 `Play.Stop` 之前；Ruffle 的順序相反（上游既有）。`onMetaData` 回呼裡的 `videoWidth` 相同。 |
| 遞迴深度 | 網頁版保護上限 900 層；需要更深遞迴的演算法（例如遠距離的 A* 尋路）結果會被截斷，桌面版不受影響。 |
| URLStream／LocalConnection 其他 | 未證明所有協定、所有外部接收端、跨使用者隔離都與 Flash 相同；AMF3 中沒有 `ObjectId` 型別（Date、XML、ByteArray、數值 Vector）的共享身分仍以完整寫出處理。 |

> 這些差異都是已知的，**沒有被藏起來**——黃金答案不會為了讓測試通過而被改寫。其中一部分是用需要遊戲檔案的探針量到的，那些探針沒有放進 repo，所以上表是結論而不是可直接重現的測試。
