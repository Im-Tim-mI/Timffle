# 裝置字型的字寬：讓 Timffle 在每個平台都排得和 Windows 版 Flash 一樣

Flash 內容用「裝置字型」（沒有內嵌字型檔、只寫字型名稱的文字欄）排版時，每個字佔多寬是由播放器所在的作業系統決定的。同一段文字在 Windows 的 Flash Player 裡能排在一行，在 Mac、Linux、Android 的瀏覽器裡可能就會多出一個字或換行——摩爾莊園許願池對話框多出來的「摩」字就是這樣來的。

從 0.8.0.26357 起，**Timffle 不再用瀏覽器量出來的字寬排裝置字型，而是用一張內建的「Windows Flash 字寬表」**：不論在 Windows、Linux、macOS、Android 還是 ChromeOS，不論電腦上裝了哪些字型，每個字的前進寬度都和 Windows 11 上的 Flash Player 32 相同。畫出來的字形仍由瀏覽器手上的字型負責（所以逐像素不會一樣，但字的位置、換行、欄寬計算一樣）。

本文記錄量到的 Windows Flash 規則、表格涵蓋的字型清單、各平台的驗證結果與已知差異。量測工具在 `timffle-work/fontsurvey/`（見文末）。

## 1. 量測方法

- **基準**：Adobe Flash Player 32.0.0.465（standalone debug projector），Windows 11 繁體中文版，預設字型（未另裝 Office 字型；有 msgothic、YuGothic、malgun、Noto Sans CJK 可變字型）。
- **探針** `Survey.hx`：一個 `TextField`（不內嵌字型、不自動換行），對 **53 個字型名稱 × 5 個字級（12/14/16/20/24 px）× 12 組字串**（ASCII 全部可印字元、Latin-1 重音字母、`&nbsp;`、希臘、西里爾、繁中、簡中、日文假名與漢字、韓文、泰文、全形字元、常見標點符號），記下整串的 `textWidth` 和每個字單獨的 `textWidth`。第二份探針 `Survey2.hx` 量**粗體**字寬和每個字型每個字級的 `getLineMetrics`（ascent／descent／height）。
- **對照**：同一個 SWF 用 Timffle 在 Windows（真 SimSun 等字型）與 Linux（Liberation、Noto 字型）無頭 Chrome 裡跑，再用 `compare.py`／`analyze.py` 逐字比對。

## 2. 量到的 Windows Flash 規則

1. **字寬是整數像素，而且是「hinted」字寬。** Flash 用 GDI 排裝置字型：每個字的前進寬度 = 字型檔裡 `hdmx`（device metrics）表在那個像素大小的紀錄；沒有紀錄的大小則是字型 hinting 程式算出來的整數寬度。這和瀏覽器 canvas 量到的線性字寬（`hmtx` × 字級，不取整）不同：例如 Arial 14 px 的 `I` 是 **3** px（線性 3.89→4）、`H` 是 9（線性 10.1）、`M` 是 11（線性 11.66），一行 95 個 ASCII 字差了 14 px（2%）。FreeType 的 v35 直譯器（單色模式）能精確重現 GDI 的 hinted 字寬；只有複合字形（重音字母）在沒有 `hdmx` 紀錄的字級用線性取整。
2. **裝置字型沒有字距調整（kerning）**：整串寬度永遠等於各字寬度之和。
3. **字型只以英文家族名稱尋找。** 中文名稱（宋体、新宋体、黑体、微软雅黑、楷体、仿宋、微軟正黑體、新細明體、細明體、標楷體、宋體）**在 Windows Flash 裡一律找不到**，即使是繁體中文 Windows、即使系統有那個字型：它們和亂取的名字畫得一模一樣。`Helvetica`＝Arial、`Times`＝Times New Roman、`Courier`≈Courier New（Windows 的 Courier 其實是點陣字型，見第 5 節）、`NSimSun`＝SimSun；`_sans`＝Arial、`_serif`＝Times New Roman、`_typewriter`＝Courier New。
4. **找不到的字型用 Times New Roman**（`_serif` 預設）畫英文、希臘、西里爾字母和標點；行高也是 Times New Roman 的（14 px：ascent 13、descent 3、height 16；SimSun 本尊是 12/2/14）。
5. **漢字一律 1 em**（任何字型，連 Arial 也是：由系統中文字型補字）。
6. **字型沒有的文字由 Windows 的字型連結補**：一般字型（Arial、Times New Roman、Verdana、Segoe UI、Calibri、Georgia……）的日文假名與全形字元來自 **MS PGothic**（比例寬，不是 1 em：14 px 的「あ」13 px、「１」10 px）；有 FontLink 設定的 **Tahoma、Microsoft Sans Serif、Lucida Sans Unicode** 則連到 MingLiU，假名與全形都是 1 em。泰文來自 **Leelawadee UI**（Tahoma、Microsoft Sans Serif 自己有泰文）。沒有希臘、西里爾字母的字型（DFKai-SB、微軟正黑體；PMingLiU／MingLiU 雖然有，Flash 也不用）由 **Arial** 補。GB2312 字型（SimHei、KaiTi、FangSong）沒有的 Latin-1 重音字母、`&nbsp;`、`•©®™£¥` 等符號畫成 **1 em** 的全形字。韓文的補字字型沒能辨認出來（14 px 每字 11 px，不是 Malgun Gothic 的 14），見第 5 節。
7. **粗體**：有粗體檔的字型（Arial、Times New Roman、Verdana、Tahoma、Georgia、Segoe UI、Calibri、Trebuchet MS、Comic Sans MS、Courier New、微軟正黑體、微軟雅黑、Yu Gothic、Malgun Gothic）用粗體檔的字寬；**沒有粗體檔的字型（SimSun、SimHei、KaiTi、FangSong、MingLiU、PMingLiU、DFKai-SB、MS Gothic、MS PGothic、Impact、Lucida Console）由 GDI 合成粗體，每個字一律加寬 1 px**，漢字也加（15 px）；補字的中文字型沒有粗體，所以 Arial 粗體裡的漢字也是 15 px；Arial Black 本身已經比粗體更粗，粗體不再加寬。
8. **SimSun／NSimSun／MS Gothic**：ASCII 與 Latin-1 字母半形（0.5 em），`&nbsp;`、希臘、西里爾、全形、大多數標點 1 em（例外：`•©®™£¥` 半形）。所以許願池那 20 個 `&nbsp;` 在 SimSun 14 px 是 280 px，超過 275 px 的欄寬而換行，「個摩」到下一行——這就是 Windows Flash 看不到「摩」的真正原因（Mac 版 Flash 則是因為用 Times 把整行縮短）。

## 3. Timffle 的做法（26357）

- `core/src/font/windows_metrics.rs` 內建字寬表 `windows_metrics.bin.z`（zlib，172 KB，62 個字體；由 `fontsurvey/gen_metrics.py` 從字型檔的 `hdmx` 表、FreeType v35 和上述實測產生，**只含字寬數字，沒有字形**）。每個字體（family × 粗體 × 斜體）存每個字的線性寬度（字型單位）和 **6～48 px** 每個字級裡與線性取整不同的 hinted 寬度；48 px 以上用線性取整。
- 排版（`core/src/font/font_like.rs`）：裝置字型的每個字先查表（名稱先依第 2 節第 3 條解析，找不到的用 Times New Roman；漢字 1 em；假名／全形／泰文依第 6 條補字；粗體依第 7 條），查到就用它、不做 kerning；表裡沒有的字（韓文、少見符號）才退回瀏覽器量的寬度取整。只有網頁版（擴充功能、Timffle Browser）開啟這張表；桌面版與測試不受影響。
- 字形（`web/src/ui/canvas_font_renderer.rs`）：名稱解析後，瀏覽器有那個字型就用它畫；是 Windows 字型但瀏覽器沒有（Linux 的 Verdana、Mac 的 SimSun）就用同類字型畫（sans→Arial/Helvetica，serif→Times，等寬→Courier New，中文字型保留名稱讓瀏覽器以 CJK 後備字型畫）；Windows 沒有的名稱（含中文名稱）一律用 Times New Roman 畫，和 Windows Flash 相同。行高也照解析後的名稱查既有的 Windows 行高表。

## 4. 字型清單與各平台結果

表中「Windows Flash」是基準行為；「Timffle 26356」是改版前在 Windows／Linux 上與基準不同的地方；「Timffle 26357」是改版後（字寬表）在所有平台的狀態。「✓」＝所有量到的字級、字串都與 Windows Flash 相同。

| 名稱 | Windows Flash 的行為 | Timffle 26356（改版前） | Timffle 26357 |
| --- | --- | --- | --- |
| `_sans`、Arial、Helvetica | Arial（hinted） | Windows/Linux 英文每行差 1～3%（線性字寬），假名用 1 em | ✓（Liberation Sans／Helvetica 只畫字形） |
| `_serif`、Times New Roman、Times、找不到的字型 | Times New Roman | 同上 | ✓ |
| `_typewriter`、Courier New | Courier New（0.6 em） | ✓ | ✓ |
| Courier | Windows 點陣字型 Courier（只有幾個大小） | 當成 Courier New | 當成 Courier New（已知差異） |
| SimSun、NSimSun | 半形／全形規則（第 2 節第 8 條） | Windows ✓；Linux 被 fontconfig 換成 Noto Serif CJK，英文比例寬、希臘西里爾半形；Mac 用 Times | ✓ |
| 宋体、新宋体、宋體、黑体、微软雅黑、楷体、仿宋、微軟正黑體、新細明體、細明體、標楷體 | 找不到 → Times New Roman | Windows 的 Chrome 認得中文名稱，畫成本尊（寬度不同）；Linux/Mac 用 Times | ✓（一律 Times New Roman） |
| SimHei、KaiTi、FangSong | 半形英文、1 em 其他（含 Latin-1 重音字母） | Windows ✓（重音字母除外）；Linux/Mac 用 Times | ✓ |
| Microsoft YaHei、Microsoft JhengHei | 比例寬英文（hinted） | Windows ±1 px；Linux/Mac 用 Times | ✓ |
| PMingLiU、MingLiU、DFKai-SB | 比例寬／半形英文；西里爾在 PMingLiU 約半形 | Windows ✓（Latin-1、西里爾除外）；Linux/Mac 用 Times | 量過的字級 ✓；其他字級的重音字母、西里爾可能差 1～2 px（第 5 節） |
| MS Gothic、MS PGothic、Yu Gothic | 半形／比例寬（hinted） | Windows ✓；Linux/Mac 用 Times | ✓ |
| Malgun Gothic | 比例寬（hinted） | Windows ✓；Linux/Mac 用 Times | ✓（韓文也在表內） |
| Tahoma、Verdana、Georgia、Segoe UI、Calibri、Trebuchet MS、Comic Sans MS、Impact、Arial Black、Microsoft Sans Serif、Lucida Console、Lucida Sans Unicode | 各自的 hinted 字寬 | Windows 每行差 0～4%；Linux/Mac 沒有這些字型，用 Times（Verdana 一行差 232 px） | ✓ |
| Arial Narrow、Meiryo、MS Mincho、Gulim、Batang、Dotum | 這台 Windows 沒有 → Times New Roman | 用 Times | ✓（當成找不到；裝了 Office／日韓字型的 Windows 會不同，見第 5 節） |
| 韓文（任何字型） | 補字字型未辨認（14 px 每字 11） | 瀏覽器後備字型（1 em 或 Malgun） | 未改（第 5 節） |
| 泰文（非 Tahoma 等） | Leelawadee UI | 瀏覽器後備字型 | ✓（單獨量的組合符號除外） |

各平台驗證（Survey.hx，3180 筆，與 Windows Flash 逐字比對）：

| 平台 | 字形字型 | 26356 | 26357 |
| --- | --- | --- | --- |
| Windows 11（真字型） | 系統字型 | 53 個字型中 10 個全對 | 52 個全對（Courier 除外）；韓文只有 Arial Black、Segoe UI、Malgun Gothic 相同 |
| Linux（Liberation／Noto） | fontconfig 別名與後備 | 2 個全對（Courier New、`_typewriter`） | 52 個全對（Courier 除外）；韓文全部不同 |
| macOS 26（MacBook Pro） | Helvetica／Times／Songti 等 | 同 Linux 的情形 | 52 個全對（Courier 除外）；韓文全部不同 |
| Android／ChromeOS | Roboto／Noto | 無 Arial、Times、SimSun，全部用後備字型 | 字寬由表決定，與平台無關；字形為 Noto／Roboto |

## 5. 已知差異與限制

- **韓文**：Windows Flash 補韓文的字型沒能從量到的寬度辨認出來（不是 Malgun Gothic、Gulim、Batang 之一的 1 em），Timffle 仍用瀏覽器量的寬度。摩爾莊園沒有韓文。
- **MingLiU／PMingLiU**：這兩個是靠 hinting 程式產生字形的「tricky」字型，FreeType 算不出 GDI 的字寬；表裡用實測值蓋掉 12/14/16/20/24 px，其他字級的 Latin-1 重音字母和西里爾字母可能差 1～2 px；粗體的重音字母也不同。
- **Courier**：Windows 的 Courier 是點陣字型（只有 10、12、15 px 幾種大小，其他大小由 GDI 縮放），Timffle 當成 Courier New。
- **泰文組合符號**單獨量時 Flash 給它一個寬度，表裡是 0（放在字母後面時 Flash 也是 0）。
- **基準電腦沒有的字型**（Arial Narrow 隨 Office 安裝；Meiryo、MS Mincho、Gulim、Batang、Dotum 是日韓語言包）在表裡視為找不到（Times New Roman），和沒裝它們的 Windows 相同；裝了的 Windows 會用本尊。同理，**使用者自己安裝、但不在表裡的字型**（例如 Noto Sans TC）在 Timffle 裡一律是 Times New Roman。
- **48 px 以上**用線性字寬取整（大字的 hinting 影響很小）；**非整數字級**四捨五入到整數 px 查表。
- 字形仍由瀏覽器的字型畫，所以筆畫形狀、粗細與 Windows 不同，只有位置相同。
- **行高尚未納入**：Windows Flash 的 `getLineMetrics` ascent／descent 也是 GDI 的整數值（來自字型的 `VDMX` 表或取整的 hhea 值：Arial 12 px 是 12/3/15，14 px 是 13/3/16；Arial 粗體 16 px 是 15/4/19 但一般是 15/3/18），Timffle 回報的是線性值（Arial 14 px 12.65/3.05/15.7）。`Survey2.hx` 已量到 34 個字型 × 5 個字級 × 粗細的行高（`win-flash2.txt` 的 `L=` 行），可作為下一步的依據；目前只有 SimSun 等幾個字型用既有的 Windows 行高表。

## 6. 重跑量測

```
# 1. 在 Windows 用 Flash 32 debug projector 跑 survey.swf（mm.cfg: TraceOutputFileEnable=1），
#    取 %APPDATA%\Macromedia\Flash Player\Logs\flashlog.txt → win-flash.txt；survey2.swf → win-flash2.txt
# 2. 用 Timffle 跑同一個 SWF（任何平台）：
CHROME_BIN=/usr/bin/google-chrome-stable CDP_WS=1 MAXSEC=1500 node survey-run.mjs <extension dir> /tmp/survey > linux-timffle.txt
# 3. 比對
python3 compare.py win-flash.txt linux-timffle.txt --quiet      # 每個字型的差異統計
python3 analyze.py win-flash.txt linux-timffle.txt matrix       # 字型 × 字串 矩陣
# 4. 重新產生字寬表（需要 Windows 字型檔的本機複本，不入庫）
FREETYPE_PROPERTIES="truetype:interpreter-version=35" python3 gen_metrics.py winfonts-local winmetrics.bin \
    --override win-flash.txt win-flash2.txt --check win-flash.txt win-flash2.txt
```

探針原始碼：`Survey.hx`、`Survey2.hx`（Haxe，`-swf-version 11`）。
