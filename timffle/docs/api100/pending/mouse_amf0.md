# 待合併：mouse_amf0（flash.ui.Mouse 自訂游標、ByteArray.writeObject AMF0 參照）

分支 `worktree-agent-af0c5115d53de2be6`（自 PRO_bata `833e6095` 切出）。

## (a) CHANGELOG 一行（放在「## 未發布（PRO_bata：API 補齊）」底下）

- **mouse_amf0（flash.ui.Mouse 自訂游標、AMF0 物件參照）**：`Mouse.registerCursor`／`unregisterCursor`／`supportsNativeCursor` 真的生效——`MouseCursorData` 的影格（每張最多 32×32，讀成直通 alpha 的 RGBA）、`hotSpot`、`frameRate` 存進播放器的游標登錄表，`Mouse.cursor = 名稱` 透過新的 `UiBackend::set_custom_cursor` 顯示到宿主指標（網頁版 canvas 的 CSS `cursor: url(data:image/png;base64,…) x y, auto`，多張影格依 `frameRate` 以 `setInterval` 輪播；桌面版 winit `CustomCursor`，只顯示第一張），`auto`／內建名稱或 `unregisterCursor` 正在顯示的游標就回到內建游標；null 參數 `TypeError #2007`，`data` 為 null／空、影格已 dispose 或大於 32×32、名稱是內建名稱 → `ArgumentError #2004`（參考沒寫錯誤碼，見差異表）。`ByteArray.writeObject`（AMF0）的最後一個空殼移除（順帶：AMF0 下 `registerClassAlias` 的實例改寫成 typed object 0x10，讀回是該類別）：重複或循環的複合物件（Object／TypedObject／ECMAArray／StrictArray）依 AMF0 規格 2.9 寫成 `reference`（0x07）＋在「複合物件表」裡的索引（父先於子登記，所以自我參照是 `07 0000`）；讀回時 vendored flash-lso 的 AMF0 解碼器給每個複合物件 `ObjectId(2^32 + 索引)`，AVM2 與 AVM1 反序列化都查回**同一個**實例；AVM1 `.sol` 的「每個值都算一號」編號（真 Flash 寫出的 `shared_object_self_ref` 黃金檔就是這樣）維持不變，兩套編號並存。驗證：新測試 `mouse_register_cursor`（測試宿主 `supportsNativeCursor` false、所有錯誤、游標指定語意）與 `bytearray_amf0_references`（位元組逐一對照 AMF0 規格、讀回 identity），`flash_ui_mouse_cursor`、`-- mouse`、`-- amf`（只剩原本就失敗的 `avm1/amf0_serde_suite`、`avm1/amf_array_serialization`）、`-- bytearray`、`-- shared_object`（含 `shared_object_self_ref_avm1`）、`-- localconnection`（含 `localconnection_cyclic_args`）、`-- netconnection` 全綠；`cargo check -p ruffle_web --target wasm32-unknown-unknown` 通過；桌面版（winit）這個容器沒有 ALSA 無法編譯，未驗證。

## (b) CHANGES-FROM-RUFFLE 的一節

### 第 N 組：mouse_amf0（flash.ui.Mouse 自訂游標、AMF0 物件參照）

- **flash.ui.Mouse.registerCursor / unregisterCursor / supportsNativeCursor / cursor（自訂名稱）**（`core/src/avm2/globals/flash/ui/mouse.rs`、`Mouse.as`、`core/src/backend/ui.rs`、`core/src/player.rs`、`web/src/ui.rs`、`desktop/src/backends/ui.rs`、`desktop/src/gui/controller.rs`、`desktop/src/app.rs`、`desktop/src/custom_event.rs`）：
  - `UiBackend` 新增 `supports_native_cursor(&self) -> bool`（預設 false）與 `set_custom_cursor(&mut self, Option<CustomCursor>)`（預設不做事）；`CustomCursor { frames: Vec<RgbaFrame{width,height,rgba}>, hot_spot: (u32,u32), frame_rate: f64 }`，`CustomCursor::MAX_SIZE = 32`。
  - `MouseData.custom_cursors` 由 `FnvHashSet<AvmString>` 改成 `FnvHashMap<AvmString, RegisteredCursor(Rc<CustomCursor>)>`。`registerCursor` 讀 `MouseCursorData.data`（`Vector.<BitmapData>`，每張 `read_area` 整張、`to_un_multiplied_alpha` 成直通 RGBA）、`hotSpot`（null 視為 (0,0)，負值夾成 0）、`frameRate`；同名重註冊會取代，若正在顯示就立刻換成新的。`Mouse.cursor = 已註冊名稱`：`current_custom_cursor = 名稱`、`forced_cursor = None`（底下維持 auto）、呼叫 `set_custom_cursor(Some)`；設成 `auto` 或內建名稱、或 `unregisterCursor` 正在顯示的名稱 → `set_custom_cursor(None)`，getter 回到 `auto`／內建名稱（與既有 `flash_ui_mouse_cursor` 黃金輸出一致：unregister 正在顯示的游標後 `Mouse.cursor` 是 `auto`，unregister 沒顯示的不影響 `button`）。`supportsNativeCursor` 改為 native，直接回 backend 的答案：測試宿主 false（登錄表與 `Mouse.cursor` 仍照常運作，等同 Flash 在沒有原生游標的組態），web／desktop true。
  - 錯誤（Adobe 參考 `Mouse.registerCursor` 與 `MouseCursorData` 頁都**沒有** Throws 段落，只寫「The maximum cursor size is 32x32 pixels」）：`name`／`cursor` 為 null → `TypeError #2007`（既有黃金輸出證實 name 的情形）；`data` 為 null 或空向量、任一影格已 `dispose()`（走 `check_valid`，實際是 #2015）或寬／高大於 32、名稱是 `auto`／`arrow`／`button`／`hand`／`ibeam` → `ArgumentError #2004`（通用「One of the parameters is invalid」，**未經真 Flash 驗證**，見 (c)）。
  - 網頁版：每張影格用 `image` crate（新加到 `web/Cargo.toml`，workspace 版本、`png` feature）編成 PNG、base64 成 `url(data:image/png;base64,…) hx hy, auto`；多於一張且 `frameRate > 0` 時以 `window.setInterval(1000/frameRate)` 輪播（Closure 與 handle 存在 `WebCustomCursor`，Drop 時 `clearInterval`）；`Mouse.hide()` 的 `none` 優先；`set_mouse_cursor`（內建游標變化）在自訂游標顯示期間不覆蓋它。
  - 桌面版（**未編譯驗證**，容器無 ALSA）：`DesktopUiBackend::set_custom_cursor` 以 `winit::window::CustomCursor::from_rgba(第一張影格, hotSpot 夾在影格內)` 建 `CustomCursorSource`，經 `RuffleEvent::SetCustomCursor(Option<CustomCursorSource>)` 送到事件迴圈，`App::user_event` 用 `ActiveEventLoop::create_custom_cursor` 建出來交給 `GuiController::set_custom_cursor`，它 `window.set_cursor(custom)`；因為 egui-winit 只在它的 cursor icon 改變時才呼叫 `window.set_cursor`，`GuiController::render` 記住上一幀的 icon，在 egui-winit 改寫過視窗游標的那一幀重新套用自訂游標（egui 自己的 UI 要指標時不套用）；清除時依最後的 icon 還原成 winit 的 Default／Pointer／Text／Grab。winit 0.30 的動畫游標只有 web 平台有，桌面版只顯示第一張影格。
  - 測試後端（`tests/framework`）沒有改：預設 `supports_native_cursor` false、`set_custom_cursor` 不做事（測試框架沒有 UI 事件記錄）。
- **flash.utils.ByteArray.writeObject（AMF0 物件參照）**（`core/src/avm2/amf.rs`、`core/src/avm1/amf.rs`、`core/src/avm1/globals/{shared_object,netconnection}.rs`、vendored `flash-lso/src/amf0/read.rs`、`types/reference.rs`）：
  - 序列化：`ObjectTable` 新增 `amf0_references: FnvHashMap<Object, u16>`。AMF0 且物件屬於 AMF0 複合物件（`is_amf0_complex`：Array，或非 Function／DisplayObject／Vector／Date／XML／ByteArray／Dictionary 的物件）時，第一次遇到就在寫子內容**之前**登記索引，再遇到（重複或循環）回傳 `AmfValue::Reference(index)`；該複合物件的 `ObjectId` 改用 `2^32 + index`，所以不經位元組、直接在記憶體交付的值樹（`LocalConnection.send` 到 AVM2 接收端、`twoArgs`）也能用同一套規則解參照。AMF3 路徑不變；`get_or_create_value` 的 stub 整個移除。`[o, o]` → `08 00000002 00 01 30 03 … 00 00 09 00 01 31 07 0001 00 00 09`、自我參照 → `03 … 07 0000 00 00 09`（手算對照 AMF0 規格 2.9／2.10／2.11）。每次 `writeObject()` 呼叫是一張新表（同一物件連寫兩次都是完整值）。另外 `registerClassAlias` 註冊過的類別實例在 AMF0 本來被寫成匿名物件（0x03）、讀回不是該類別；現在寫成 AMF0 typed object（0x10＋別名），讀回 `is Typed` true，與 Flash 相同（`[t, t]` → `08 … 10 00 01 54 … 07 0001 …`）。
  - 解碼（vendored）：`AMF0Decoder` 多一個 `complex_count`，Object／TypedObject／ECMAArray／StrictArray 在讀子內容**之前**領取 `ObjectId(AMF0_REFERENCE_ID_BASE + n)`（`1 << 32`，避免與內嵌 AMF3 從 0 起算的 id 相撞），自我參照因此能解；原本「每個值都進 cache」的 `as_reference()` 編號**保留**，因為 AVM1 的 `Amf0Writer` 和真 Flash 寫出的 AVM1 `.sol`（`shared_object_self_ref` 黃金檔 `RuffleTestRef.sol`：`saved`=0、`foo`=1，`foo.self` 是 `07 0001`）就是每個值算一號——上一次失敗的嘗試就是把這個編號也改掉。
  - AVM2 反序列化：`AmfValue::Reference(n)` 查 `object_map[ObjectId(2^32 + n)]`；`deserialize_lso` 改成整個檔案共用一張 object_map（AMF0 `.sol` 屬性間的參照、AMF3 的物件表才能跨屬性解到同一實例）。
  - AVM1 反序列化：`reference_cache` 改成 `ReferenceCache { by_reference, by_id }`：先查解碼器的每值編號（`.sol`、黃金行為不變），查不到再以 `ObjectId(2^32 + n)` 查——AVM2 經 `LocalConnection` 送到 AVM1 的重複／循環物件因此也解回同一實例（之前是完整複本）。`shared_object_self_ref_avm1` 的黃金輸出（Flash 讀回自我參照得到複本、`eq foo: false`）不變。
  - 成員：`writeObject()`（AMF0 重複物件）空殼移除；`ByteArray.shareable`／atomics 之前已完成。
  - 既有測試 `ui_members`（上一批寫的，黃金來自 Ruffle 而非 Flash）的 AMF0 兩行更新：`{x: s, y: s, list: [s, s]}` 從 94 位元組（重複寫完整值、讀回不同實例）變成 55 位元組（手算：`03` ＋ x 19 ＋ y `07 0001` 6 ＋ list 26 ＋ 結尾 3）且 identity 全 true。

## (c) 「已知與真 Flash 還不同的地方」表格列

| 區域 | 差異 |
|---|---|
| `Mouse.registerCursor` 的錯誤碼 | Adobe 參考沒有 Throws：null 參數 `TypeError #2007` 有黃金輸出證實；`data` 為 null／空、影格大於 32×32、名稱是內建名稱時 Timffle 丟 `ArgumentError #2004`，已 dispose 的影格丟 `ArgumentError #2015`——真 Flash 丟哪個碼（或是否默默接受再不顯示）未驗證。`hotSpot` 為 null 視為 (0,0)、負值夾成 0，未驗證。 |
| 自訂游標的顯示 | 桌面版只顯示第一張影格（winit 0.30 桌面無動畫游標）且未編譯驗證；網頁版的輪播用 `setInterval`，`frameRate` 很高時瀏覽器會節流；游標離開 canvas 時瀏覽器自然回到系統游標（Flash 也是「只在 stage 內顯示」）。 |
| AMF0 參照編號 | AVM2（`ByteArray`／`LocalConnection`／`NetConnection`／AMF0 `SharedObject`）依規格只給複合物件編號；AVM1 `.sol` 依真 Flash 黃金檔每個值編號。AVM1 寫、AVM2 讀（或反過來）同一個含參照的 AMF0 `.sol` 時，兩套編號對不上；真 Flash 在這種跨 VM 情形的行為未驗證。AVM1 `LocalConnection`／`NetConnection` 的值樹在記憶體中沒有解碼器，AVM1 → AVM2 的參照仍是 undefined（之前就是）。 |

## (d) queue.json

```json
[
  {"class": "flash.ui.Mouse", "status": "done", "note": "mouse_amf0: registerCursor/unregisterCursor/supportsNativeCursor real (UiBackend::supports_native_cursor + set_custom_cursor; web CSS cursor url() PNG + setInterval animation, desktop winit CustomCursor first frame only, unverified build); errors: null -> #2007, data null/empty, frame >32x32, builtin name -> ArgumentError #2004 (unverified in Flash), disposed frame -> #2015. Test mouse_register_cursor."},
  {"class": "flash.ui.MouseCursorData", "status": "done", "note": "used by Mouse.registerCursor (frames copied at registration)."},
  {"class": "flash.utils.ByteArray", "status": "done", "note": "mouse_amf0: writeObject AMF0 object references real (spec 2.9 complex-object table, parent before children; decoder ids 2^32+n; AVM1 .sol every-value numbering kept, shared_object_self_ref_avm1 and localconnection_cyclic_args green). Test bytearray_amf0_references."}
]
```
