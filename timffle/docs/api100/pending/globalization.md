# api100 第 3 組：flash.globalization（待合併）

分支：`worktree-agent-ae8a38269d835ad07`（自 PRO_bata 分出）。測試：`cargo test -p tests --test tests -- globalization_members`（新）、`-- collator`（既有三支仍綠）。

## (a) CHANGELOG 條目

- **flash.globalization 六個類別全部真實作**（LocaleID、StringTools、NumberFormatter、CurrencyFormatter、DateTimeFormatter、Collator，共 57 個空殼歸零）。Flash Player 把這些交給作業系統的地區服務（Windows NLS／ICU）；本播放器在瀏覽器或桌面殼裡沒有逐地區的 OS 服務，因此把 Flash 會向 OS 讀的資料直接編進程式：`core/src/avm2/globals/flash/globalization/locale_data.rs` 收 22 個地區（en-US/GB/CA/AU、de-DE、fr-FR/CA、es-ES/MX、it-IT、pt-BR/PT、nl-NL、sv-SE、pl-PL、ru-RU、tr-TR、ja-JP、ko-KR、zh-CN/TW/HK）的數字分隔符、貨幣（ISO 碼、符號、小數位、正負版面）、月份／星期名稱、`DateTimeStyle` 的日期時間樣式與一週起始日。要求的地區不在表內時照 Adobe 文件退回：同語言其他地區 → `usingFallbackWarning`（fr-CH → fr-FR）、未知語言 → 播放器預設地區（由 `Capabilities.language` 推得）並回 `usingDefaultWarning`；`LocaleID.DEFAULT`（`i-default`）解析為播放器預設地區。沒有引入 ICU4X（體積與 API 成本太高，見下），只新增 `unicode-normalization`（Cargo.toml 要求 0.1.24，Cargo.lock 解析為 0.1.26；純 Rust，Collator 的 NFKD 分解用）。驗證：新 SWF 回歸測試 `globalization_members`（149 行輸出，en-US／zh-TW／ja／de 範例，逐行對照 Adobe 參考文件的範例）、既有 `collator_flags`、`collator_locale_ids_windows`、`collator_compare_basic`（已更新 `output.ruffle.txt`：é 現在排在 z 之前，與 Flash 的 `output.txt` 一致；忽略變音符號現在真的生效）。

## (b) CHANGES-FROM-RUFFLE 段落

### 第 3 組：flash.globalization

Ruffle 上游只有 `Collator` 的骨架（大小寫折疊後比較碼位），其餘五個類別全是回傳固定值的空殼。Timffle 全部改成真實作，資料編進程式、邏輯照 Adobe AS3 參考文件：

- **LocaleID**（`locale_id.rs`）：真的解析 BCP 47／UTS #35（語言-文字-地區-變體、`-u-` 延伸鍵如 `-u-co-phonebk` → `collation=phonebook`、`@key=value;…` 尾碼），`name` 回標準大小寫並把 `_` 換成 `-`（`EN_us` → `en-US`）。`getScript()`／`getRegion()` 名稱裡沒有時用 likely-subtags 表猜（`mn-CN` → `Mong`、`mn-MN` → `Cyrl`、`zh-TW` → `Hant`、`ja` → `JP`）並回 `usingFallbackWarning`，與文件一致。`isRightToLeft()` 看文字（Arab/Hebr/Thaa/Syrc/Nkoo/Adlm…）或語言（ar/he/fa/ur/yi/ps/sd/ug/dv…）。`getKeysAndValues()` 回鍵值 Object；`@` 尾碼有沒有 `=` 的 token（`en-US@Collation`）時狀態 `unexpectedToken`（文件範例）。`determinePreferredLocales(want, have, keyword)`：對每個 want 依序取 have 中「完全相同 → 互為前綴（`en`↔`en-US`）→ 同語言」的項目，去重；`keyword` 在 Flash 只用來選 OS 偏好清單，這裡沒有 OS 清單所以不影響結果（文件註明）。`null` 名稱丟 ArgumentError #2004。
- **StringTools**（`string_tools.rs`）：Rust 標準庫的完整 Unicode 大小寫對應（已含 `ß` → `SS`、希臘字尾 sigma），再加 SpecialCasing 的語言規則：土耳其／亞塞拜然的 `i`↔`İ`、`ı`↔`I`，立陶宛的 `i` 保留上點。`null` 丟 ArgumentError #2004（文件）。
- **NumberFormatter**（`number_formatter.rs`、`number_format.rs`）：`fractionalDigits`（預設 0，文件）、`useGrouping`、`groupingPattern`（`"3;*"`、`"3;2;*"`、`"3"` 三個文件範例全部吻合；`"3;"` → `illegalArgumentError`）、`groupingSeparator`／`decimalSeparator`（null 丟 TypeError #2007）、`digitsType`（任何 `NationalDigitsType` 數字集）、`leadingZero`／`trailingZeros`（文件的四格表全吻合）、`negativeNumberFormat` 0～4（超出範圍 → `invalidAttrValue`，照 LastOperationStatus 文件的 `9` 範例，不丟例外）、`negativeSymbol`。捨入是「四捨五入、離零進位」（Windows 行為），用 f64 的精確十進位展開做，不會出現 2.5 → 2。`parse()` 找字串裡第一個數字：整數部分可夾任意分組符、負號版面照 `negativeNumberFormat`（`(123)`、`- 123`、`123 -`）、`+` 視為非數字、不解析科學記號；找不到回 NaN 與 0x7fffffff 及 `parseError`。`parseNumber()` 只允許數字加 Zs 空白。
- **CurrencyFormatter**（`currency_formatter.rs`）：`currencyISOCode`／`currencySymbol`／小數位／`positiveCurrencyFormat`（0～3）／`negativeCurrencyFormat`（0～15）由地區表給，版面照文件的兩張表逐字實作（¤、n、- 的位置）。`format(value, withCurrencySymbol)` false 時用 ISO 碼、true 時用符號。`setCurrency()` 的 ISO 碼必須是三個大寫 A–Z，否則 `illegalArgumentError` 且兩個屬性不變。`formattingWithCurrencySymbolIsSafe()` 只在等於自己的 ISO 碼時 true。`parse()`：先去掉所有空白，數字兩側的文字只能在一側（另一側非空 → `parseError`）、括號或 `negativeSymbol` 表示負數、貨幣字串含數字（文件範例 `"12abc34"`）→ NaN、`currencyString` null、`parseError`。
- **DateTimeFormatter**（`date_time_formatter.rs`）：`setDateTimeStyles()` 由地區表的 long／medium／short 日期與時間樣式組出 `getDateTimePattern()`（非法樣式丟 ArgumentError #2008）；`setDateTimePattern()` 檢查語法（未引號的字母必須是文件列的 `G y M d E Q w W D F a h H K k m s S z Z v`，`"xx"` → `patternSyntaxError` 且樣式不變，文件範例）；渲染器實作文件表裡每個字母的每種長度（`yy`、`MMMMM`、`EEEE`、`Q`/`QQ`/`QQQ`、`w`/`W`/`D`/`F`、`K`/`k`、`S`×1～5、引號規則 `'o''clock'`、`mm''ss''`）。`z`／`v` 沒有 OS 時區名稱資料，照文件的備援用當地化 GMT 格式（`GMT+05:45`）；`Z` 1～3 個字母為 `+0545`、4 個為 `GMT+05:45`。`format()` 用播放器時區、`formatUTC()` 用 UTC；無效 Date 回空字串並設 `illegalArgumentError`。`getMonthNames()`／`getWeekdayNames()`（`full`／`longAbbreviation`／`shortAbbreviation`，`format`／`standalone`：波蘭文與俄文月份有格位差異；非法 nameStyle 丟 ArgumentError #2008）、`getFirstWeekday()`（en-US／zh-TW／ja-JP／ko-KR 為 0，歐洲與 zh-CN 為 1）。
- **Collator**（`collator.rs`）：比較改成仿 Unicode 排序演算法（UCA）的多層排序：NFKD 分解後，第一層比基礎字母（空白 < 標點 < 符號 < 數字 < 字母；é 與 e 同級，`æ`→ae、`ø`→o、`ß`→ss 等展開），第二層比變音符號，第三層比大小寫（小寫在前，`a` < `A`），再比全半形與片假名／平假名。`ignoreCase`／`ignoreDiacritics`／`ignoreCharacterWidth`／`ignoreKanaType` 各關掉一層，`ignoreSymbols` 從鍵裡拿掉空白與符號（`O'Brian` = `OBrian`），`numericComparison` 把連續數字當一個值比（`version2` < `version10`，文件範例）。地區客製：瑞典／芬蘭的 å ä ö 排在 z 後、丹麥／挪威的 æ ø å、德文 `@collation=phonebook`（ü → ue）。`actualLocaleIDName` 與建構子狀態照上面的退回規則（新增 `usingFallbackWarning`／`usingDefaultWarning` 到 `LastOperationStatus` 列舉與 common strings）；六個選項 setter 的狀態改為 `noError`，因為全部真的生效。
- 為什麼不用 ICU4X：`icu_datetime`／`icu_collator` 含全地區編譯資料會讓 wasm 多 10 MB 以上，而且 icu_datetime 2.x 取不出樣式對應的 pattern 字串（`getDateTimePattern()` 需要）；改用自帶 22 地區的表。Cargo.lock 只多 `unicode-normalization 0.1.26`（約 200 KB 表）。

## (c) 已知與真 Flash 還不同的地方

| 項目 | 差異 |
|---|---|
| flash.globalization 地區資料 | 只帶 22 個地區；其他地區照文件退回（同語言 → `usingFallbackWarning`，未知語言 → 預設地區與 `usingDefaultWarning`），真 Flash 在 Windows 可能有該地區的資料。`getAvailableLocaleIDNames()` 回這 22 個。 |
| 地區表的細節 | 日期時間樣式、縮寫、貨幣版面是依 Windows／CLDR 慣例整理（例如 en-US 負數貨幣 `($1.50)`、zh-TW 長時間 `下午 01:43:01`），真 Flash 逐 OS 版本不同；`shortAbbreviation` 與 `longAbbreviation` 相同（文件註明部分 OS 如此）；`Q`×4、`G`×4 只有英文全名；`z`／`v` 一律是 GMT 格式。 |
| NumberFormatter／CurrencyFormatter 超範圍設定 | 依 LastOperationStatus 文件回 `invalidAttrValue` 不丟例外；NumberFormatter 文件另一處寫會丟 ArgumentError，兩處文件矛盾，待真 Flash 確認。 |
| CurrencyFormatter.parse() | 比文件寬鬆：不檢查貨幣／符號／數字的順序是否與 `positiveCurrencyFormat`／`negativeCurrencyFormat` 完全一致，只要文字在一側即可。 |
| Collator | 近似 UCA，沒有 DUCET 全表：非拉丁字母按碼位排序、法文的反向第二層沒有做、`@collation=pinyin/stroke` 等中文排序沒有專門資料（退回碼位順序）。`numericComparison` 真 Flash 在 Windows／Linux 回 `unsupportedError`，這裡真的生效並回 `noError`。`collator_compare_basic` 的 `output.txt` 是 Linux Flash 錄的（忽略變音符號無效），仍標 `known_failure`。 |

## (d) queue.json

```json
[
  {"class": "flash.globalization.LocaleID", "status": "done", "note": "BCP 47/UTS #35 解析、likely-subtags 猜 script/region、-u- 與 @ 鍵值、determinePreferredLocales；測試 globalization_members"},
  {"class": "flash.globalization.StringTools", "status": "done", "note": "完整 Unicode 大小寫 + tr/az/lt 規則；地區退回照文件"},
  {"class": "flash.globalization.NumberFormatter", "status": "done", "note": "所有屬性與 parse/parseNumber 照文件；22 地區資料表"},
  {"class": "flash.globalization.CurrencyFormatter", "status": "done", "note": "20 個成員；正負版面表、setCurrency 驗證、parse"},
  {"class": "flash.globalization.DateTimeFormatter", "status": "done", "note": "LDML 樣式字母全部、樣式表、月份/星期名、首日；z/v 用 GMT 格式"},
  {"class": "flash.globalization.Collator", "status": "done", "note": "仿 UCA 多層排序、六個選項全部生效、sv/da/de-phonebook 客製；DUCET 全表與中文排序未帶"}
]
```
