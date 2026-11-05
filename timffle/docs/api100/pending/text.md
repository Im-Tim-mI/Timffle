# api100 待合併：第 2 組：文字（flash.text.Font、TextField、TextRenderer、TextSnapshot）

分支 `worktree-agent-a51b9f9001c7b4362`（自 PRO_bata 分出）。合併者把下面各段搬進 `timffle/CHANGELOG.md`、`timffle/docs/CHANGES-FROM-RUFFLE.md`、`timffle/docs/api100/queue.json`。

## (a) CHANGELOG 一行

- **第 2 組（文字）：`flash.text` 的 Font 1 空殼、TextField 2 缺 + 6 空殼、TextRenderer 1 缺 + 3 空殼、TextSnapshot 9 空殼**：`TextSnapshot` 整個成為真的實作（新物件 `TextSnapshotObject` 包住 `display_object::text::TextSnapshot`，`DisplayObjectContainer.textSnapshot` 不再是空殼）——`charCount`、`getText`、`findText`、`getSelected`／`setSelected`／`getSelectedText`／`setSelectColor`（選取狀態記在靜態文字物件上，選到的字後面真的畫出選取色的矩形）、`getTextRunInfo`（每個字一個物件：`indexInRun`、`selected`、`font`、`color`（含 alpha）、`height`、`matrix_a…ty`、`corner0x…corner3y`，座標在父容器空間）、`hitTestTextNearPos`（`maxDistance` 0 要落在字框內，否則取中心點最近的字）；`TextField.mouseWheelEnabled` 真的接到 `EditText` 的滾輪旗標（之前永遠回 true 且不存）、`useRichTextClipboard` 接到複製／剪下／貼上（開著時複製把選取範圍的 Flash HTML 放進剪貼簿的 `air:html`，貼上時讀回並保留格式）、`isFontCompatible` 查內嵌字型（不認識的 `fontStyle` `ArgumentError #2008`）、`textInteractionMode` 桌面版固定 `normal`、未文件化的 `getRawText`／`getXMLText`／`insertXMLText`（純文字、範圍的 Flash HTML、以 HTML 取代範圍並保留格式）；`getImageReference` 回 null（這個播放器不載入 `<img>`，見 CHANGES）；`TextRenderer.antiAliasType`（缺）、`displayMode`、`maxLevel`、`setAdvancedAntiAliasingTable` 照 AS3 參考驗證並存起來（`maxLevel` 只收 3／4／7、`displayMode` 只收 `TextDisplayMode` 的值、表格項目必須是 `CSMSettings`），這個播放器的光柵器沒有 CSM 階段所以不影響繪圖；`Font.enumerateFonts(true)` 列出這個播放器知道的裝置字型（已載入的加上內建名稱 `_sans`／`_serif`／`_typewriter`／日文三種的實作），不再標空殼。驗證：新測試 `text_members`（63 行，含滾輪輸入：`mouseWheelEnabled=false` 時 `scrollV` 不動、改 true 後捲到 4）、`textsnapshot_members`（44 行，用 Loader 載入 `static_text/test.swf` 的 DefineText）；既有 `textfield`（28）、`edittext`（123；`avm1/edittext_ime_focus_lost` 在未改的 PRO_bata 上就已失敗，與本批無關）、`static_text`、`textsnapshot`（gnash AVM1，8）、`clipboard` 測試通過；`cargo check`、`cargo clippy -p ruffle_core`（只剩工具鏈既有的 3 個錯誤）。

## (b) CHANGES-FROM-RUFFLE 一節

### 第 2 組：文字（flash.text.Font.enumerateFonts、TextField 8 個成員、TextRenderer 4 個成員、TextSnapshot 9 個成員）

- **參考值來自 AS3 參考**（airsdk.dev 的 `TextField`、`TextRenderer`、`TextSnapshot` 頁），沒有跑真 Flash（這一批沒有 difftest 黃金答案）。`getRawText`／`getXMLText`／`insertXMLText` 在 AS3 參考裡沒有條目（只在 playerglobal.swc 宣告），做法照名稱與簽章：`getRawText()` 回純文字、`getXMLText(beginIndex = 0, endIndex = int.MAX)` 回那段字的 Flash HTML（與 `htmlText` 同樣的 `<P>`／`<FONT>`／`<B>` 格式，索引夾到文字範圍）、`insertXMLText(beginIndex, endIndex, richText, pasting)` 用 HTML 解析器解析 `richText` 後取代那段並逐段套用格式（`pasting` 不改變行為）。
- **`TextSnapshot`**（`TextSnapshot.as`、新檔 `text_snapshot.rs`、`text_snapshot_object.rs`、`display_object/text.rs`、`DisplayObjectContainer.as`／`display_object_container.rs`）：`DisplayObjectContainer.textSnapshot` 回一個真的快照——該容器的子物件裡所有靜態文字（`DefineText`）依顯示順序串起來（AVM1 的 `MovieClip.getTextSnapshot()` 用同一份程式，所以 `TextSnapshot::new` 改收任何容器）。索引規則照參考：`beginIndex` 負數當 0、最多 `charCount − 1`，`endIndex` 最多 `charCount`、不大於 `beginIndex` 時當 `beginIndex + 1`。`setSelected` 累加（不會取消之前的選取）、`getSelected` 範圍裡任一字選到就 true、`getSelectedText` 回選到的字（`includeLineEndings` 時在不同文字物件之間補 `\n`，與 `getText` 相同）、`setSelectColor` 永遠不透明；選取狀態記在每個靜態文字物件上（`Text::snapshot_selection`），所以再取一次 `textSnapshot` 看到的還是同一份，而且繪圖時在每個選到的字後面畫出選取色的矩形（字框＝字寬 × 字型的 ascent + descent）。`getTextRunInfo` 每個字一個物件，19 個屬性：`indexInRun`、`selected`、`font`（字型名）、`color`（`0xAARRGGBB`）、`height`（像素）、`matrix_a…matrix_ty`（字的位置，父容器座標：文字物件自己的矩陣 × DefineText 的矩陣，直立文字是 `[1 0 0 1 x y]`）、`corner0x…corner3y`（字框四角，左上、右上、右下、左下）。`hitTestTextNearPos(x, y, maxDistance)` 的 `x`／`y` 在父容器座標：`maxDistance` 0 時點要落在某個字框內，否則取「字框中心到點的距離」最小且不超過 `maxDistance` 的字；都沒有回 −1。`new TextSnapshot()` 可以建（Flash 的建構子是公開的），內容為空。
- **`TextField`**（`TextField.as`、`text_field.rs`、`edit_text.rs`、`clipboard.rs`）：`mouseWheelEnabled` 讀寫 `EditText` 處理 `ClipEvent::MouseWheel` 時看的那個旗標（上游的 getter 固定 true、setter 丟掉）；`useRichTextClipboard` 存成 `EditTextFlag::USE_RICH_TEXT_CLIPBOARD`，複製／剪下時若開著就把選取範圍的 Flash HTML 放進 `Clipboard.generalClipboard` 的 `air:html`（關著時把先前的 `air:html` 清掉，純文字照常進 `air:text`／主機剪貼簿），貼上時若開著且 `air:html` 有字串就以 HTML 插入並保留格式（同樣先送可取消的 `textInput`、之後 `change`），否則貼純文字；`isFontCompatible(fontName, fontStyle)` 查 `Font.registerFont` 註冊的與呼叫端 SWF 內嵌的 `FontType.EMBEDDED` 字型（`fontStyle` 不是 `FontStyle` 的四個值 `ArgumentError #2008`、兩個參數 null `TypeError #2007`）；`textInteractionMode` 唯讀、固定 `TextInteractionMode.NORMAL`（`selection` 只有行動版的內建選單能切到，桌面版沒有）；`getImageReference(id)` 回 null——這個播放器的 HTML 解析器會記下 `<img>` 的 `src`／`id`／寬高／對齊，但不載入圖片、不建 Loader，所以沒有 DisplayObject 可回，與 Flash 找不到該 id 時相同。
- **`TextRenderer`**（`TextRenderer.as`）：靜態設定真的存起來並照參考驗證——`antiAliasType`（playerglobal 仍宣告的舊全域開關，起始 `normal`，只收 `AntiAliasType` 的兩個值）、`displayMode`（起始 `default`，只收 `TextDisplayMode` 的 `default`／`lcd`／`crt`）、`maxLevel`（起始 4，「只接受 3、4、7」）、`setAdvancedAntiAliasingTable(fontName, fontStyle, colorType, table)`（`fontStyle` 要是 `FontStyle`、`colorType` 要是 `TextColorType`、表格每項要是 `CSMSettings`，同一個字型／樣式／色別再設就整個取代）；非法值 `ArgumentError #2008`、null `TypeError #2007`。這個播放器的字型光柵器沒有 CSM（連續筆畫調變）階段，所以這些值不改變繪圖——Flash Player 在沒有 CSM 光柵器的平台上也是存著不用。
- **`Font.enumerateFonts(true)`**（`font.rs`、`library.rs`）：裝置字型列出這個播放器知道的——某個 SWF 已經向主機要過的，加上主機對內建名稱（`_sans`、`_serif`、`_typewriter`、`_ゴシック`、`_等幅`、`_明朝`）的實作（還沒載入就現在載入，`Library::known_device_fonts`）。主機後端沒有「列出系統全部字型」的呼叫，所以從來沒被要過的系統字型不會出現（Flash 列出作業系統全部的字型）。

## (c) 已知與真 Flash 還不同的地方

| 區域 | 差異 |
|---|---|
| `Font.enumerateFonts(true)` | Flash 列出作業系統全部的裝置字型；Timffle 只列已載入的與內建名稱的實作（主機沒有列舉 API）。 |
| `TextSnapshot` 的字框 | 字框高度用字型的 ascent／descent；DefineFont 沒有版面資訊（Flash 文件說的「沒有字元度量」）時高度是 0，`hitTestTextNearPos` 只有點剛好在基線上才命中（Flash 文件說回 −1）；`getTextRunInfo` 的四角順序（左上、右上、右下、左下）與 `includeLineEndings` 在同一個 DefineText 的多行之間不補換行，都沒有在真 Flash 量過。 |
| `TextRenderer` 的錯誤 | 非法的 `displayMode`／`maxLevel`／`antiAliasType`／表格項目丟 `ArgumentError #2008`，參考只寫「只接受哪些值」沒寫錯誤碼，未在真 Flash 量過。 |
| `TextField.useRichTextClipboard` 的貼上 | 富文字貼上不套 `restrict`／`maxChars`（純文字貼上照常）；Flash 的 `air:html` 是否也在 `useRichTextClipboard` 關著時清掉沒有量過。 |
| `TextField.getImageReference` | Flash 對載入成功的 `<img>` 回 Loader；Timffle 不載入圖片，一律 null。 |
| `getRawText`／`getXMLText`／`insertXMLText` | 未文件化；行為照名稱推定（見上），未在真 Flash 量過。 |

## (d) queue.json

```json
[
  {"class": "flash.text.Font", "status": "partial", "note": "enumerateFonts(true) 列出已載入的裝置字型與內建名稱的實作；主機沒有列舉系統全部字型的 API（desktop fontconfig／web 都沒有），要列全部需要新的 UiBackend 呼叫。"},
  {"class": "flash.text.TextField", "status": "partial", "note": "8 個都做了；getImageReference 一律 null（播放器不載入 <img>）、getRawText/getXMLText/insertXMLText 未文件化照名稱推定。"},
  {"class": "flash.text.TextRenderer", "status": "done", "note": "antiAliasType/displayMode/maxLevel/setAdvancedAntiAliasingTable 驗證並存起來；光柵器沒有 CSM 階段所以不影響繪圖（Flash 在沒有 CSM 的平台亦然）。錯誤碼未在真 Flash 量過。"},
  {"class": "flash.text.TextSnapshot", "status": "done", "note": "9 個全部真的實作（含選取高亮繪圖）；字框順序與無度量字型的行為未在真 Flash 量過。"}
]
```
