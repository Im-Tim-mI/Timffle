# api100 pending：leftovers 批次

## (a) CHANGELOG 條目

- **AMF0 物件參照與 AuthorizedFeaturesLoader**：`ByteArray.writeObject`（AMF0）對同一物件/陣列的第二次出現與循環參照，改為依 AMF0 規格 2.9 寫出 `reference` 標記（0x07）加上「依出現順序」的參照表索引，不再重寫整個物件（原本是 Ruffle 最後一個 `writeObject` stub）；vendored flash-lso 的 AMF0 解碼器參照表改為只收複合物件（匿名/具型別物件、陣列）並標上 ObjectId，`readObject` 讀回同一實例。新增 `flash.system.AuthorizedFeaturesLoader`（本播放器不連 Adobe 授權伺服器：兩個 load 方法非同步派發 `error` 事件、`authorizedFeatures` 永遠 null、null ByteArray 丟 #2007）。驗證：`bytearray_amf0_references`（位元組依 AMF0 規格手算核對）、`authorized_features_loader_members`，既有 `amf` / `bytearray` / `shared_object` 套件維持原狀（`avm1/amf0_serde_suite`、`avm1/amf_array_serialization` 為既知失敗）。

## (b) CHANGES-FROM-RUFFLE 段落

### 第 N 組：leftovers（AMF0 參照、AuthorizedFeaturesLoader）

- **flash.utils.ByteArray.writeObject（AMF0 參照）**：`core/src/avm2/amf.rs` 的 `ObjectTable` 新增 `amf0_references`（物件 → u16 索引）。序列化走到 `Value::Object` 時，若編碼為 AMF0 且物件屬於 AMF0 的複合物件（`is_amf0_complex`：陣列，或非 Function / DisplayObject / Vector / Date / XML / ByteArray / Dictionary 的物件），第一次出現時在寫出子內容**之前**登記索引（父先於子，與 Flash 相同），之後再遇到（重複或循環）即回傳 `AmfValue::Reference(index)`；Date、XML 等每次都以完整值寫出，與 Flash 相同。AMF3 路徑不變（flash-lso 的 AMF3 編碼器本來就會把重複 ObjectId 轉成參照），所以 `get_or_create_value` 的 stub 整個移除。反序列化：`AmfValue::Reference(n)` 以 `ObjectId(AMF0_REFERENCE_ID_BASE + n)` 在 object_map 查回同一物件。vendored `flash-lso/src/amf0/read.rs`：參照表只收 Object / TypedObject / ECMAArray / StrictArray，在讀子內容前佔位（`claim_reference_id`）、讀完填入（`store_reference`），並以 `ObjectId(1<<32 + index)` 標記以免和內嵌 AMF3 的 id 相撞；`types/reference.rs` 的 `Reference` 欄位改為 `pub`。
- **flash.system.AuthorizedFeaturesLoader**（新檔 `core/src/avm2/globals/flash/system/AuthorizedFeaturesLoader.as`，純 AS）：繼承 EventDispatcher。這個播放器不連 Adobe 授權服務，等同 Flash Player 連不到伺服器：`loadAuthorizedFeatures()` 與 `loadAuthorizedFeaturesFromData(data)` 都以 `setTimeout(…, 0)` 非同步派發 `ErrorEvent.ERROR`（text「Error #2032: Stream Error.」，bubbles/cancelable 皆 false），`authorizedFeatures` 永遠 null（`AuthorizedFeatures` 本來就假設沒有 token）；`loadAuthorizedFeaturesFromData(null)` 丟 `TypeError #2007`。成員：`authorizedFeatures`、`loadAuthorizedFeatures()`、`loadAuthorizedFeaturesFromData()`。airsdk.dev 該頁回 404，簽章依 api-report 規格；事件型別依記憶中的 Adobe 參考（`error` / `complete`），見 (c)。
- **flash.ui.Mouse.registerCursor / unregisterCursor / supportsNativeCursor**：本批次**未動**（時間盒 35 分鐘用罄），三個 stub 仍在；設計已確認可行：`UiBackend` 加 `supports_native_cursor()`（預設 false）與 `set_custom_cursor(Option<&CustomCursor>)`，`MouseData.custom_cursors` 由 HashSet 改成 name → 影格（RGBA）/hotSpot/frameRate 的 map，`Mouse.cursor = name` 時呼叫 backend，web 端以 `cursor: url(data:image/png;base64,…) x y, auto`（web crate 已有 base64，PNG 編碼可用 core 的 image crate）、desktop 以 winit `CustomCursor`（容器無 ALSA 無法編譯）。

## (c) 「已知與真 Flash 還不同的地方」表格列

| 類別/成員 | 差異 |
|---|---|
| `AuthorizedFeaturesLoader` 事件 | 失敗時派發 `ErrorEvent.ERROR`、text「Error #2032: Stream Error.」；Adobe 參考頁已下線（404），實際事件型別/文字未能對照真 Flash 確認。 |
| AMF0 `SharedObject` 參照表範圍 | 一個 `flush()` 共用一張參照表（跨頂層屬性）；真 Flash 的 .sol 是否每個頂層屬性重置參照表未驗證。 |
| `shared_object_self_ref_avm1` | 此 AVM1 測試在本批次後輸出 `Foo.self: undefined`（期望值是 Flash 讀回一份複本：`[object Object]` / `eq foo: false`）；由於期望輸出本身不是「同一實例」，疑為既有失敗，但未能在基底重跑確認——merger 請在 PRO_bata 跑一次 `cargo test -p tests --test tests -- shared_object_self_ref_avm1` 對照。 |

## (d) queue.json

```json
[
  {"class": "flash.utils.ByteArray", "status": "done", "note": "batch leftovers: writeObject AMF0 object references real (reference marker 0x07 + occurrence index for repeated/cyclic objects and arrays; decoder resolves them to the same instance). Test bytearray_amf0_references."},
  {"class": "flash.system.AuthorizedFeaturesLoader", "status": "done", "note": "batch leftovers: authorizedFeatures null, loadAuthorizedFeatures/loadAuthorizedFeaturesFromData dispatch ErrorEvent.ERROR asynchronously (no authorization server), null data #2007. Test authorized_features_loader_members. Event type unverified against Flash (reference page 404)."},
  {"class": "flash.ui.Mouse", "status": "partial", "note": "batch leftovers: registerCursor/unregisterCursor/supportsNativeCursor not started (time box); design in pending/leftovers.md (UiBackend set_custom_cursor + supports_native_cursor, web CSS cursor url(), desktop winit CustomCursor)."}
]
```
