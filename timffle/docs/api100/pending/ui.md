# api100 批次 `ui`（flash.ui、ByteArray、automation、printing、sampler、sensors、GeolocationEvent）

分支：`worktree-agent-a0b279a667522b5b4`（自 PRO_bata `244a861a`）。合併者請把下面四段分別併入 CHANGELOG、CHANGES-FROM-RUFFLE、已知差異表與 queue.json。

## (a) CHANGELOG 一行

- **第 2 組／第 5 組（flash.ui、ByteArray、automation、printing、sampler、sensors）：17 個類別、89 項**：`Keyboard.capsLock`／`numLock` 真的追蹤鎖定狀態（鎖定鍵切換、打字的大小寫與數字鍵盤的按鍵校正，`core/src/input.rs`）、`hasVirtualKeyboard`／`physicalKeyboardType` 與 `Capabilities.touchscreenType` 同一來源；`ContextMenu.clone()`（自訂項目逐一複製、內建與剪貼簿項目組複製、`link` 帶過去）、`link`、`isSupported` true（這個播放器一定有右鍵選單）；`Multitouch` 5 個成員照無觸控主機（`maxTouchPoints` 0、`supportedGestures` null、`inputMode` 驗證 `#2008`）；`Mouse.supportsCursor`、`MouseCursorData` 成為純資料；`ByteArray.atomicCompareAndSwapIntAt`／`atomicCompareAndSwapLength`（單執行緒的比較交換，`#2004`／`#2006`）、`shareable` 存值；`flash.sampler` 17 個函式照 release 版 AVM（沒有取樣器：不動作、計數 -1／0、`getSamples` undefined），`getMemberNames`／`isGetterSetter`／`getSavedThis`／`getLexicalScopes` 用 vtable 與閉包真的反射（新檔 `flash/sampler.rs`）；`GameInputDevice`／`GameInputControl`、`PrintJob`（`isSupported` false、`start()` false、`addPage` `#2057`）、`ActionGenerator`／`Configuration`／`StageCapture`、`Accelerometer`／`Geolocation`（`muted` true、負間隔 `#2004`）、新類別 `GeolocationEvent` 都照「沒有該功能的 Flash」。驗證：新測試 `avm2/ui_members`、`avm2/nofeature_ui_members`，`cargo check -p ruffle_core` 通過。

## (b) CHANGES-FROM-RUFFLE 段落

### 第 2 組／第 5 組：flash.ui（ContextMenu、Keyboard、Mouse、MouseCursorData、Multitouch、GameInputControl／GameInputDevice）、ByteArray 原子操作、flash.automation、PrintJob、flash.sampler、flash.sensors、GeolocationEvent

- **參考值來源**：Adobe AS3 參考（airsdk.dev）與 avmplus 的 `SamplerScript.cpp` 行為記憶；這一批沒有真 Flash 可量（容器沒有 Wine），所以錯誤碼以參考文件寫明的錯誤類別配 Flash 通用碼（`#2004`／`#2006`／`#2007`／`#2008`／`#2012`／`#2037`／`#2057`），未量到的標在已知差異表。測試 `avm2/ui_members`、`avm2/nofeature_ui_members`。
- **`Keyboard.capsLock`／`numLock`**（`keyboard.rs`、`core/src/input.rs`）：播放器從來沒被告知主機的鎖定狀態（winit 沒有鎖定鍵 API，網頁版只傳按鍵事件），所以用 AVM1 `Key.isToggled` 同一份切換狀態（按 Caps Lock／Num Lock 切換），再從打字校正：沒按 Shift 卻打出大寫字母（或按 Shift 打出小寫）就是 Caps Lock 開著；數字鍵盤的按鍵產生數字就是 Num Lock 開著、產生方向鍵就是關著（`InputManager::infer_lock_state`）。`hasVirtualKeyboard`、`physicalKeyboardType` 從 `Capabilities.touchscreenType` 推：`none` → 沒有虛擬鍵盤、`alphanumeric`；`finger` → true、`none`，三個屬性永遠一致。
- **`ContextMenu`**（`ContextMenu.as`）：`clone()` 回新的 `ContextMenu`：`customItems` 是新陣列、每個 `ContextMenuItem` 各自 `clone()`，`builtInItems`／`clipboardItems` 複製，`clipboardMenu` 與 `link` 帶過去（改副本不影響原物件）；`link` 存 `URLRequest`；`isSupported` true，因為 `Player::prepare_context_menu` 對每個前端（桌面、網頁）都建右鍵選單——沒有後端旗標可以是 false。**沒做完**：設了 `link` 之後 Flash 顯示的是「連結選單」（開啟連結／複製連結），Timffle 的原生選單還沒加這兩項（需要 `context_menu.rs` 新回呼與翻譯字串）。
- **`Multitouch`**（`Multitouch.as`）：無觸控主機上的 Flash（與 `Capabilities.touchscreenType` "none" 一致）：`maxTouchPoints` 0、`supportsTouchEvents`／`supportsGestureEvents` false、`supportedGestures` null（參考：不支援任何手勢時是 null）；`inputMode`（預設 `gesture`，非法值 `ArgumentError #2008`）與 `mapTouchToMouse`（預設 true）是存起來的設定。
- **`Mouse.supportsCursor`、`MouseCursorData`**（`Mouse.as`、`MouseCursorData.as`）：`supportsCursor` = `touchscreenType != "finger"`（有指標的主機顯示游標）；`MouseCursorData` 的 `data`／`frameRate`／`hotSpot` 是純資料（參考沒有任何驗證或錯誤；32×32 的限制在 `registerCursor` 檢查）。**沒做**：`registerCursor`／`unregisterCursor`／`supportsNativeCursor`／`Mouse.cursor = 自訂名稱` 仍是空殼——自訂點陣游標需要新的 `UiBackend` 方法（網頁 CSS `cursor: url(...)`、桌面 winit `CustomCursor`），這一批時間內沒做。
- **`ByteArray.atomicCompareAndSwapIntAt`／`atomicCompareAndSwapLength`、`shareable`**（`byte_array.rs`、`ByteArray.as`）：單執行緒的比較交換——`IntAt` 讀寫原始記憶體的 int32（AVM 的 `compareAndSwapInt32` 不看 `endian`，一律主機位元組序＝小端），相等才寫入、回傳舊值；`byteIndex` 負數或不是 4 的倍數 `ArgumentError #2004`、超過 `length - 4` `RangeError #2006`；`Length` 相等才改長度、回傳舊長度（負的新長度 `RangeError #2006`，假設）。`shareable` 存旗標：沒有 Worker 的播放器上只是記錄（初值 false）。`writeObject` 的「同一物件重複出現」空殼仍在 `amf.rs`（AMF3 已由修補過的 flash-lso 寫成參照，AMF0 仍寫完整物件，見已知差異）。
- **`flash.sampler`**（`sampler.as`、新檔 `sampler.rs`、`function.rs` 多 `BoundMethod::scope()`／`bound_receiver()`）：release 版 Flash Player 沒有取樣器（只在 debugger 版），AVM 的函式先檢查有沒有取樣器：`startSampling`／`stopSampling`／`pauseSampling`／`clearSamples`／`sampleInternalAllocs`／`setSamplerCallback` 不動作，`getSampleCount` 0、`getSize` 0、`getInvocationCount`／`getGetterInvocationCount`／`getSetterInvocationCount` -1、`getSamples` undefined。不需要取樣器的反射是真的：`getMemberNames(obj, instanceNames)` 回物件 vtable 所有特徵（含私有命名空間）加動態屬性的 `QName` 陣列（`instanceNames` 且 obj 是 Class 時改列實例特徵）；`isGetterSetter` 看 vtable 是否 `Virtual`；`getSavedThis` 回綁定方法的接收者（一般函式 undefined）；`getLexicalScopes` 回閉包作用域鏈的物件（最外層在前）；`getMasterString` 恆 null，因為這個播放器的字串不與子字串共用緩衝（沒有 dependent string）。`NewObjectSample.object` 以弱鍵 Dictionary 持有、`size` 存值（沒有取樣器所以永遠沒有實例）。
- **`GameInputDevice`／`GameInputControl`**（`GameInputDevice.as`、`GameInputControl.as`）：`GameInput.isSupported` false、`numDevices` 0，裝置只能由執行期建立，所以兩個類別從 AS 建構丟 `ArgumentError #2012`，成員照「已移除的裝置」：`enabled` 恆 false、`numControls` 0、`getControlAt` `RangeError #2006`、`getCachedSamples(null)` `ArgumentError #2007`、對停用裝置的操作 `Error #2037`、`sampleInterval` 負數 `RangeError #2006`、`startCachingSamples` 的 `numSamples <= 0` `RangeError #2006`／空清單 `ArgumentError #2007`。
- **`PrintJob`**（`PrintJob.as`）：無列印的平台（`Capabilities.hasPrinting` 也是 false）：`isSupported` false、`start()` false、`pageWidth`／`pageHeight`／`paperWidth`／`paperHeight` 0（只有 start 成功後才有值）、`addPage()` `Error #2057`（page could not be added）、`send()` 安靜地失敗（參考：不丟錯）、`orientation` 存值（預設 portrait，非法值 `#2008`）。
- **`flash.automation`**（新檔 `ActionGenerator.as`、`Configuration.as`、`StageCapture.as`）：只有自動化版 Flash Player 會動作；一般播放器裡類別存在但不產生任何事件：`generateAction(s)` 什麼都不注入（null `TypeError #2007`），`Configuration.deviceConfiguration` 存字串（初值空）、`testAutomationConfiguration` 空字串，`StageCapture.capture()` 不擷取也不送 `capture` 事件、`captureBitmapData()` null、`cancel()` 無事、`capturePTS` 0、`captureSource`（預設 `stage`）／`clipRect`／`fileNameBase`（預設 `capture`）存值，非法的 `type`／`captureSource` `#2008`。
- **`Accelerometer`／`Geolocation`**（`sensors/*.as`）：無感測器的裝置：`isSupported` false、`muted` true、永遠不送 `status`／`update`，`setRequestedUpdateInterval` 負數 `ArgumentError #2004`、其他值只是提示。
- **`GeolocationEvent`**（新檔 `events/GeolocationEvent.as`）：11 個成員的資料類別（建構子參數順序照參考：latitude、longitude、altitude、hAccuracy、vAccuracy、speed、heading、timestamp），`clone()`、`toString()` 用 `formatToString` 列 type、bubbles、cancelable、eventPhase 與 8 個欄位。

## (c) 已知與真 Flash 還不同的地方（新列）

| 區域 | 差異 |
|---|---|
| `Keyboard.capsLock`／`numLock` 的初值 | 真 Flash 直接問作業系統；Timffle 只能從按鍵事件推（開始時視為關，按過鎖定鍵、打過字母或數字鍵盤之後才正確）。網頁版可改用 `KeyboardEvent.getModifierState` 傳進來。 |
| `ContextMenu.link` | 真 Flash 顯示連結選單（開啟連結／複製連結）；Timffle 只存值，原生選單不變。 |
| `Mouse.registerCursor` | 自訂點陣游標仍是空殼（需要 `UiBackend` 新方法）。 |
| `ByteArray.writeObject` 的重複物件（AMF0） | Flash 以 AMF0 參照（0x07）寫第二次出現的物件；Timffle 的 flash-lso AMF0 寫入器仍寫完整物件（讀回時身分不同）。AMF3 已正確。 |
| `ByteArray.atomicCompareAndSwapLength` 負長度、自動化／遊戲輸入／列印的錯誤碼 | 文件只寫錯誤類別，碼是 Flash 通用碼的推測（`#2006`、`#2012`、`#2037`、`#2057`）。`GeolocationEvent.toString()` 的欄位順序未量到。 |
| `flash.sampler.getSamples()` | 無取樣器時依 avmplus 回 undefined（回傳型別 Object 所以讀到 null；文件寫「迭代器」）；`getMemberNames` 回 Array（Flash 是只能迭代的內部物件）；Object 的 AS3 命名空間方法（hasOwnProperty 等）也列在裡面，Flash 是否列出未量到。 |
| 共用 target 目錄 | 多個 worktree 同時建置時 `build_playerglobal` 的 `native_table.rs`（OUT_DIR）會被另一個 worktree 的 .as 覆蓋而編譯失敗；`touch core/src/avm2/globals/globals.as` 重跑即可（合併者注意，不是程式碼問題）。 |

## (d) queue.json

```json
[
  {"class": "flash.ui.ContextMenu", "status": "partial", "note": "clone/link/isSupported done (ui_members); link stored but the native menu does not show the link items yet"},
  {"class": "flash.ui.Keyboard", "status": "done", "note": "capsLock/numLock tracked from key events (InputManager::infer_lock_state), hasVirtualKeyboard/physicalKeyboardType from touchscreenType; isAccessible still a stub (not in this batch's list)"},
  {"class": "flash.ui.Mouse", "status": "partial", "note": "supportsCursor done; registerCursor/unregisterCursor/supportsNativeCursor need a UiBackend custom-cursor method (web CSS cursor url, winit CustomCursor) — not done"},
  {"class": "flash.ui.MouseCursorData", "status": "done", "note": "plain data holder per reference; used once Mouse.registerCursor is real"},
  {"class": "flash.ui.Multitouch", "status": "done", "note": "no-touch host values, inputMode validated"},
  {"class": "flash.utils.ByteArray", "status": "partial", "note": "atomics + shareable done; writeObject repeated-object stub remains for AMF0 (flash-lso amf0 writer writes no references)"},
  {"class": "flash.automation.ActionGenerator", "status": "done", "note": "inert in the non-automation player"},
  {"class": "flash.automation.Configuration", "status": "done", "note": "stored/empty strings; real automation values unknown"},
  {"class": "flash.automation.StageCapture", "status": "done", "note": "inert capture, settings stored"},
  {"class": "flash.events.GeolocationEvent", "status": "done", "note": "new data class; toString order unverified"},
  {"class": "flash.printing.PrintJob", "status": "done", "note": "no printing: isSupported false, start false, addPage #2057"},
  {"class": "flash.sampler", "status": "done", "note": "release-player AVM behaviour; getMemberNames/isGetterSetter/getSavedThis/getLexicalScopes real natives (sampler.rs)"},
  {"class": "flash.sampler.NewObjectSample", "status": "done", "note": "weak object + size"},
  {"class": "flash.sensors.Accelerometer", "status": "done", "note": "muted true, negative interval #2004"},
  {"class": "flash.sensors.Geolocation", "status": "done", "note": "muted true, negative interval #2004"},
  {"class": "flash.ui.GameInputControl", "status": "done", "note": "#2012 constructor, removed-device semantics"},
  {"class": "flash.ui.GameInputDevice", "status": "done", "note": "#2012 constructor, removed-device semantics"}
]
```
