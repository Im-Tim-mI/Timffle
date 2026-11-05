# api100 第 3 組：flash.text.engine（待合併，**尚未跑 SWF 測試**）

分支：`worktree-agent-a11dc893ce160dc72`（自 PRO_bata `ab258ca6` 分出）。只跑過 `cargo check -p ruffle_core`（含 playerglobal 的 asc 編譯）；磁碟不足（剩 2～5 GB）無法在自己的 target 目錄做完整 debug build，所以 **沒有跑** `fte_members`、`textblock_*`、`textline_*`、`text_engine_*`、`element_format_*`、`groupelement_text`。合併前請務必跑這些；測試檔在 `timffle/docs/api100/pending/fte_members/`（Test.as + test.toml），搬到 `tests/tests/swfs/avm2/fte_members/` 跑一次、逐行對 Adobe 文件後再寫 output.txt。

## (a) CHANGELOG 條目

- **flash.text.engine 補齊（ContentElement、GroupElement、GraphicElement、TextBlock、TextLine、TextLineMirrorRegion、TextJustifier、FontDescription、ElementFormat）**：`ContentElement.textBlock`／`groupElement`／`textBlockBeginIndex`／`rawText` 改成真的從元素樹算（GroupElement 插入／移除與 TextBlock.content 會記錄擁有者，GraphicElement 在 rawText 佔一個 U+FDEF）；GroupElement 新增 `getElementAtCharIndex`／`groupElements`／`ungroupElements`／`mergeTextElements`；GraphicElement 的 `graphic`／`elementWidth`／`elementHeight` 真的儲存；TextBlock 新增 `getTextLineAtCharIndex`、`findNext/PreviousAtomBoundary`（UAX #29 字素）、`findNext/PreviousWordBoundary`（UAX #29 字界）、`releaseLineCreationData`、`dump`，`firstInvalidLine`／`lastLine` 真的看行的 validity；`createTextLine`／`recreateTextLine` 現在一行只放版面的第一視覺行（之前一個 TextLine 會含整段自動換行的文字）、`lineOffset` 當首行縮排、`fitSomething=false` 且放不下時回 null 與 `insufficientWidth`、`tabStops` 真的進版面、`lineRotation` 轉整個 TextLine；TextLine 的 atom 查詢（atomCount、getAtomBounds／Center／IndexAtPoint／IndexAtCharIndex／TextBlockBeginIndex／EndIndex／WordBoundaryOnLeft、getAtomGraphic、getAtomTextRotation、getAtomBidiLevel、hasGraphicElement、totalAscent／Descent／Height、unjustifiedTextWidth、getBaselinePosition）改成從實際字形位置算，新增 `mirrorRegions`／`getMirrorRegion`／`dump` 與真的 `TextLineMirrorRegion`；`TextJustifier.getJustifierForLocale`、`FontDescription.isFontCompatible`／`isDeviceFontCompatible`（查內嵌 CFF 字型／裝置字型）、`ElementFormat.getFontMetrics`（依字型 ascent/descent 與 OS/2 慣例比例）。驗證：`cargo check`；SWF 測試 `fte_members` 待跑（見上）。

## (b) CHANGES-FROM-RUFFLE 段落

### 第 3 組：flash.text.engine

Ruffle 上游的 FTE 只有骨架：一個 TextLine 用一個 EditText 排整段文字，atom／mirror／群組操作全是空殼或缺少。Timffle：

- **ContentElement**（`content_element_object.rs`、`content_element.rs`）：新增 `group_element`／`text_block` 擁有者欄位，`GroupElement.setElements`／`replaceElements` 插入時記錄、移除時清掉，`TextBlock.content` 設定時記錄（同一個元素再放進另一個 block 時由後者接管，不丟錯——既有測試 `textblock_createline_errors` 把同一個 content 放進兩個 block，真 Flash 不丟錯）。`textBlock` 沿群組鏈往上找根元素的 block；`textBlockBeginIndex` 沿鏈加總前面兄弟的 rawText 長度，不在 block 時 -1；`rawText` 與 `text` 同，但 GraphicElement 貢獻 U+FDEF。`eventMirror`／`textRotation` 的 stub 巨集移除：值真的儲存、驗證並由 `TextLine.mirrorRegions`／`getAtomTextRotation` 讀取（字形本身還沒有旋轉繪製，見差異表）。
- **GroupElement**（AS）：`getElementAtCharIndex`（超出 rawText 範圍 RangeError #2006）、`groupElements(begin, end)`（把區段搬進新的 GroupElement 並放回原位，索引錯 #2006）、`ungroupElements(index)`（不是 GroupElement → ArgumentError #2004）、`mergeTextElements(begin, end)`（任一不是 TextElement → #2004；文字接到第一個元素，其餘移除）。
- **GraphicElement**（`graphic_element.rs`）：`ElementData::Graphic { graphic, element_width, element_height }`，建構子經 setter 填值；版面裡以一個 U+FDEF 字元佔位（用該元素的 elementFormat，沒有 format 時與 TextElement 一樣丟 #2175）。
- **TextBlock**（`text_block.rs`、AS）：`DoCreateTextLine` 排完版後只保留 fallback EditText 第一視覺行的字元（其餘留給下一次 createTextLine），`lineOffset` → `TextFormat.indent`，`fitSomething` false 且第一行放不下任何字元（或唯一字元寬過 width）→ 回 null、`textLineCreationResult = insufficientWidth`；`tabStops` 的 position 進 `TextFormat.tab_stops`；`lineRotation` 用 `set_rotation` 轉整個 TextLine。`firstInvalidLine` 回第一個 validity ≠ valid 的行；`getTextLineAtCharIndex` 超出 block 文字長度丟 #2006；四個 boundary 方法用 `unicode-segmentation`（已在 Cargo.lock），索引超出丟 #2006、沒有更多邊界回 -1；`releaseLineCreationData` 是真的無事可做（本播放器不快取 shaping 資料，文件註明）；`dump` 輸出自訂 XML（Flash 的格式無文件）。`applyNonLinearFontScaling`／`baselineFontDescription`／`baselineFontSize`／`baselineZero`／`textJustifier` 的 setter 空殼巨集移除（值儲存並驗證；對版面的影響見差異表）；`bidiLevel` 仍留空殼（沒有雙向排版）。
- **TextLine**（`text_line.rs`、AS）：atom = UAX #29 字素；`getAtomBounds`／`getAtomCenter` 取該字素每個字元的 `EditText::char_bounds` 聯集；`getAtomIndexAtPoint` 把舞台座標 `global_to_local` 後找含該點的 atom；`getAtomWordBoundaryOnLeft` 用 UAX #29 字界；索引超出丟 #2006。`getAtomGraphic`／`getAtomTextRotation`／`hasGraphicElement` 經新的 internal native `ContentElement.leafAtCharIndex` 找到葉元素；`getAtomBidiLevel` 回 block 的 `bidiLevel`；`getBaselinePosition` 以 roman 基線為 0，由行的 ascent/descent 推 ascent/descent/ideographic*（無效名稱 #2008）；`totalAscent`／`totalDescent`／`totalHeight` 等於文字值（圖形還沒有獨立 inline box）；`unjustifiedTextWidth` = `textWidth`（沒有套 justification）。`mirrorRegions`：對每個 atom 沿群組鏈找最近有 `eventMirror` 的元素，連續同元素合併成一個區域（bounds 聯集），串成 previous/next 鏈；沒有 → null。`TextLineMirrorRegion` 改成真類別（internal 欄位 + 唯讀 getter）。
- **TextJustifier.getJustifierForLocale**：ja／zh／ko → EastAsianJustifier，其餘 SpaceJustifier，lineJustification 皆 unjustified；null → TypeError #2007、少於 2 字元 → #2004（與建構子相同）。
- **FontDescription.isFontCompatible**：`library.get_embedded_font_by_name(name, EmbeddedCFF, bold, italic)` 有無；`isDeviceFontCompatible`：`get_or_load_device_font` 有無（後端解析不到時仍會退到內建預設字型，所以多半為 true，如同 Flash 在有系統預設字型的機器）。fontName null → #2007，weight／posture 不合法 → #2008。
- **ElementFormat.getFontMetrics**：emBox = (0, -size×ascent 比例, size, size)，ascent 比例取該格式字型（內嵌 CFF → 裝置字型）的 `FontMetrics` ascent/(ascent+descent)，找不到用 0.8；其餘比例為 OS/2 慣例：strikethrough -0.26 em／0.075 em、underline 0.15 em／0.075 em、sub/superscript 0.15／-0.35 em、scale 0.65，lineGap 0。

## (c) 已知與真 Flash 還不同的地方

| 項目 | 差異 |
|---|---|
| ContentElement.textRotation／TextBlock.baselineZero／applyNonLinearFontScaling／textJustifier／baselineFont* | 值儲存、驗證並可讀回，但版面不旋轉個別字形、不換基線零點、不做 justification 與非線性縮放；`getBaselinePosition` 以 roman 基線為 0 回報，而 TextLine 的繪製原點仍是 EditText 的左上角（上游既有差異）。 |
| TextBlock.bidiLevel | 仍是空殼（沒有雙向排版）；`getAtomBidiLevel` 一律回 block 的 bidiLevel。 |
| TextBlock.dump()／TextLine.dump() | Flash 的 XML 格式無文件，輸出為自訂格式。 |
| GraphicElement 版面 | 佔一個 U+FDEF 字元而不是 elementWidth × elementHeight 的 inline box；`graphic` 不會被加成 TextLine 的子物件；totalAscent/Descent 不含圖形高度。 |
| 同一元素放進第二個 TextBlock／GroupElement | 不丟 ArgumentError（既有 Flash 錄製測試顯示 content 可重複），由後者接管擁有權。 |
| ElementFormat.getFontMetrics | underline／strikethrough／sub/superscript 不是從字型 OS/2 表讀，而是慣例比例。 |
| createTextLine 的行切割 | 依 EditText 的自動換行結果取第一行；`fitSomething=false` 的判定用「第一行放不下任何字元或唯一字元寬過 width」。**未以 SWF 測試驗證，`textline_splitting_basic`、`textblock_*` 可能受影響，請先跑。** |

## (d) queue.json

```json
[
  {"class": "flash.text.engine.ContentElement", "status": "partial", "note": "6 個成員真實作（擁有者記錄、rawText U+FDEF）；textRotation 只儲存不旋轉字形；SWF 測試未跑"},
  {"class": "flash.text.engine.ElementFormat", "status": "partial", "note": "getFontMetrics 依字型 ascent/descent + OS/2 慣例比例；未讀字型 OS/2 表"},
  {"class": "flash.text.engine.FontDescription", "status": "done", "note": "isFontCompatible 查內嵌 CFF 字型、isDeviceFontCompatible 查裝置字型；SWF 測試未跑"},
  {"class": "flash.text.engine.GraphicElement", "status": "partial", "note": "graphic/elementWidth/elementHeight 真儲存；版面只佔 U+FDEF，沒有 inline box"},
  {"class": "flash.text.engine.GroupElement", "status": "done", "note": "4 個方法（AS，錯誤碼 2004/2006）；SWF 測試未跑"},
  {"class": "flash.text.engine.TextBlock", "status": "partial", "note": "7 個缺少成員補齊、createTextLine 真的切行 + lineOffset/fitSomething/tabStops/lineRotation；bidiLevel 仍空殼；dump 格式自訂；SWF 測試未跑"},
  {"class": "flash.text.engine.TextJustifier", "status": "done", "note": "getJustifierForLocale（ja/zh/ko → EastAsianJustifier）"},
  {"class": "flash.text.engine.TextLine", "status": "partial", "note": "atom 查詢由字形位置算、mirrorRegions/getMirrorRegion/dump/totalHeight；圖形 inline box 與 justification 未做；SWF 測試未跑"},
  {"class": "flash.text.engine.TextLineMirrorRegion", "status": "done", "note": "真類別，由 TextLine.mirrorRegions 建立；SWF 測試未跑"}
]
```
