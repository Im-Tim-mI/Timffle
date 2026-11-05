# 待合併：textblock2（flash.text.engine.TextBlock 最後 3 個空殼）

## (a) CHANGELOG 條目

- **第 3 組（文字引擎）：`flash.text.engine.TextBlock` 最後 3 個空殼（`createTextLine`、`recreateTextLine`、`bidiLevel` setter）**：`createTextLine`／`recreateTextLine` 現在真的照 `width` 斷行——一個 TextLine 最多一個視覺行：整段（到下一個明確換行為止）先用後備 EditText 以 `width` 自動換行排版，取它第一行的結尾（最後一個放得下的斷行機會，空白歸前一行）作為這一行的 `rawTextLength`，剩下的留給下一次 `createTextLine`；明確換行字元仍屬於前一行（Flash 錄的 `textline_splitting_basic`／`textline_raw_text_length` 黃金輸出不變）。`textLineCreationResult` 依 Adobe 參考：`success`、`emergency`（`width` 內沒有斷行機會、在字中間硬斷）、`insufficientWidth`（第一個 atom 都放不下且 `fitSomething` false → 回 null）、`complete`（沒有文字了）；`fitSomething` true 時至少放一個 atom。`bidiLevel` 用 `unicode-bidi`（新依賴，純 Rust）做 UAX #9：以 `bidiLevel` 為段落嵌入層級解析每一行，右到左的 run 反轉後交給後備 EditText 繪製，`TextLine.getAtomBidiLevel` 回每個 atom 解析出的層級，atom 的邊界由邏輯位置對應到視覺位置；改 `bidiLevel` 把已斷的行全設為 `invalid`（文件規定）。FTE 的 TextLine 排版寬度不再扣 EditText 的 2 px 邊溝（`width` 就是可用寬度）。驗證：新測試 `textblock_width_splitting`（Noto Sans 裝置字型，寬度由量到的 `textWidth` 推算：兩字／一字放得下、字寬剛好、字中硬斷、放不下＋`fitSomething`、明確換行混合、GroupElement、`recreateTextLine` 重斷、`bidiLevel` 0／1 的層級與視覺順序、負值 `ArgumentError #2004`、改值使行 invalid），既有 `textblock_*`／`textline_*`／`fte_members`／`text_engine_*` 全綠。

## (b) CHANGES-FROM-RUFFLE 段落（接在「### 第 3 組：flash.text.engine」的 TextBlock／TextLine 條目之後）

- **TextBlock.createTextLine／recreateTextLine 真的斷行**（`text_block.rs` `do_create_text_line`）：上游把整段（到下一個 `\n`／`\r`／`\r\n`／U+2028／U+2029 為止）排進一個 TextLine、不管 `width`、忽略 `fitSomething`。Timffle：段落先以 `width` 自動換行排進後備 EditText（`EditText::relayout` 對 FTE 行不再扣 2 px 邊溝，所以斷行點正好在 `width`），取其第一個版面行的結尾（`LayoutLine::end` 等於下一行的起點，因此斷行機會的空白歸前一行，與 Flash 的 `rawTextLength` 相同）當作這一行的長度；若段落放得下，整段連同明確換行字元是一行（Flash 錄製的 `textline_splitting_basic`／`textline_raw_text_length` 黃金輸出因此不變）；放不下時只把這一行的文字重新排進 EditText，剩餘文字由下一次 `createTextLine(previousLine)` 從 `previousLine.textBlockEnd` 接著排。`textLineCreationResult`：`success`；`emergency` = 斷在非斷行機會（前一字元不是空白／tab／U+200B，即 `width` 內沒有斷行機會、在字中間硬斷）；`insufficientWidth` = 第一個 atom（UAX #29 字素）的右緣超過 `width` 且 `fitSomething` false → 回 null、不接進行串；`fitSomething` true 時至少放第一個 atom；`complete` = 沒有文字了（上游）。`recreateTextLine` 走同一條路（重設該行後重排），所以用更窄的 `width` 重建會重新斷行。
- **TextBlock.bidiLevel**（`text_block.rs` `resolve_bidi`、`display_object/text_line.rs` `LineBidi`）：以 `unicode-bidi` 0.3.18（新依賴，純 Rust；desktop 已在 Cargo.lock 用它）做 UAX #9：`bidiLevel` 當段落嵌入層級（0 LTR、1 RTL，較大的值照 UAX #9 當明確層級），`BidiInfo::visual_runs` 取視覺順序的 run，RTL run 的字元反轉後組成視覺字串交給後備 EditText 繪製；TextLine 另存邏輯字串、邏輯→視覺的 UTF-16 位置對應與每個單元的解析層級。`rawTextLength`／`textBlockBeginIndex`／atom 索引都以邏輯順序計，`getAtomBounds`／`getAtomCenter`／`getAtomIndexAtPoint` 經對應表找視覺位置的字形邊界；`getAtomBidiLevel` 改為 native，回 atom 第一個字元的解析層級（例如 `"abc"` 在 `bidiLevel = 1` 下全是 2；`"12 34"` 在 1 下是 2,2,1,2,2、視覺順序是「34 12」；`"ab 12"` 在 1 下全是 2——UAX #9 W7 把跟在 L 後面的數字當 L）。`recreateTextLine` 會把重用行的後備 EditText 寬度改成新的 `width` 再排（否則沿用舊寬度不會重新斷行）。改 `bidiLevel`（值不同時）把 block 已有的行全設 `invalid`（Adobe 文件：「Changing it sets all previously broken lines to INVALID」）；負值 `ArgumentError #2004`（原有）。全 LTR 的文字在層級 0 下對應表是恆等，既有行為不變。含孤立代理對的文字無法轉成 UTF-8 做解析，維持邏輯順序、層級＝段落層級。
- 新測試 `textblock_width_splitting`（Noto Sans 裝置字型，`test.toml` 的 `[default_fonts]`／`[fonts.noto_sans]` 與 `text_members` 相同）：寬度由量到的 `"aaaa"`／`"aaaa aaaa"` 的 `textWidth` 推算，涵蓋兩字／一字放得下、字寬剛好等於 `width`、字中硬斷（emergency）、放不下（null＋insufficientWidth）、`fitSomething`、明確換行與自動斷行混合、GroupElement、`recreateTextLine` 重斷與 insufficientWidth、`bidiLevel` 層級與視覺順序、負值錯誤、改值使行 invalid。

## (c) 「已知與真 Flash 還不同的地方」表格列

| 區域 | 差異 |
|---|---|
| `TextBlock.createTextLine` 的斷行機會 | 斷行機會沿用 EditText 的換行規則（空白／tab；U+200B 不是斷點，Flash 的 UAX #14 會在 ZWSP、連字號後、CJK 字之間等處斷行）；`emergency` 的判定是「斷在非空白之後」。`lineOffset` 仍當第一行縮排（前一批的做法），Flash 的 `lineOffset` 只影響 tab 原點。`insufficientWidth` 的判定是第一個字素的右緣超過 `width`，Flash 以第一個 atom 的 advance 判定（含字距時可能差一點）。 |
| `TextBlock.bidiLevel` | 層級解析與 run 反轉照 UAX #9（`unicode-bidi`），但沒有阿拉伯文連寫字形、鏡像括號（`TextLineMirrorRegion` 以外的 glyph mirroring）與 RTL 段落的行原點對齊（Flash 在 `bidiLevel = 1` 時行從右邊的 `width` 起算、`textWidth` 以右為基準）；`getAtomBidiLevel` 的預期值取自 UAX #9，未用真 Flash 錄製。 |

## (d) queue.json

```json
[
  {"class": "flash.text.engine.TextBlock", "status": "done", "note": "createTextLine/recreateTextLine 真的照 width 斷行（一個 TextLine 一個視覺行、空白歸前一行、明確換行字元屬前一行）、fitSomething、textLineCreationResult success/emergency/insufficientWidth/complete；bidiLevel 用 unicode-bidi 做 UAX #9 解析與視覺反轉、改值使行 invalid；getAtomBidiLevel 回解析層級；測試 textblock_width_splitting；Flash 錄的 textline_splitting_basic/textline_raw_text_length 仍綠"}
]
```
