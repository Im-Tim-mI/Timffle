# 裝置字型的字寬：讓 Timffle 在每個平台都排得和 Windows 版 Flash 一樣

Flash 內容用「裝置字型」（沒有內嵌字型檔、只寫字型名稱的文字欄）排版時，每個字佔多寬是由播放器所在的作業系統決定的。同一段文字在 Windows 的 Flash Player 裡能排在一行，在 Mac、Linux、Android 的瀏覽器裡可能就會多出一個字或換行——摩爾莊園許願池對話框多出來的「摩」字就是這樣來的。

從 0.8.0.26357 起，**Timffle 不再用瀏覽器量出來的字寬排裝置字型，而是用一張內建的「Windows Flash 字寬表」**（0.8.0.26358 起連行高也來自這張表；0.8.0.26359 起涵蓋斜體與 Windows 合成的粗體／斜體；0.8.0.26360 起涵蓋 6～255 px 每個字級、點陣字型 Courier、FontLink 字型的韓文，全部實測；0.8.0.26361 起 Courier 的整段補字規則；0.8.0.26363 起斜體與粗斜體的非拉丁字與符號也全部實測）：不論在 Windows、Linux、macOS、Android 還是 ChromeOS，不論電腦上裝了哪些字型，每個字的前進寬度都和 Windows 11 上的 Flash Player 32 相同。畫出來的字形仍由瀏覽器手上的字型負責（所以逐像素不會一樣，但字的位置、換行、欄寬計算一樣）。

本文記錄量到的 Windows Flash 規則、表格涵蓋的字型清單、各平台的驗證結果與已知差異。量測工具在 `timffle-work/fontsurvey/`（見文末）。

## 1. 量測方法

- **基準**：Adobe Flash Player 32.0.0.465（standalone debug projector），Windows 11 繁體中文版。26357 的普查用預設字型（未另裝 Office 字型；有 msgothic、YuGothic、malgun、Noto Sans CJK 可變字型）；26358 的全尺寸普查前裝上了 Windows 的**日文與韓文補充字型**（`Language.Fonts.Jpan`／`Kore`：Meiryo、MS Mincho、Yu Mincho、Gulim、Batang、Dotum、Gungsuh），所以基準是「裝了日韓字型的繁中 Windows 11」。
- **探針** `Survey.hx`：一個 `TextField`（不內嵌字型、不自動換行），對 **53 個字型名稱 × 5 個字級（12/14/16/20/24 px）× 12 組字串**（ASCII 全部可印字元、Latin-1 重音字母、`&nbsp;`、希臘、西里爾、繁中、簡中、日文假名與漢字、韓文、泰文、全形字元、常見標點符號），記下整串的 `textWidth` 和每個字單獨的 `textWidth`。第二份探針 `Survey2.hx` 量**粗體**字寬和每個字型每個字級的 `getLineMetrics`（ascent／descent／height）。
- **對照**：同一個 SWF 用 Timffle 在 Windows（真 SimSun 等字型）與 Linux（Liberation、Noto 字型）無頭 Chrome 裡跑，再用 `compare.py`／`analyze.py` 逐字比對。
- **第七份探針** `Survey7.hx`（26363）：每個字型在**斜體**（有粗體檔的字型加量**粗斜體**）6～255 px 每個字級的 `&nbsp;`／標點／日文／韓文／全形／泰文字串，與每種樣式每個字級的 `getLineMetrics`：147,003 行（Flash 約 45 分鐘）。這是表裡最後一塊沒有實測、靠 FreeType 推算的範圍。
- **第六份探針** `Survey6.hx`（26361）：每個字型在 survey3 沒量的字級（6～255 px）一般與粗體的 `&nbsp;`／標點／日文／韓文／全形／泰文字串、每個字型每個字級每種樣式其餘的大寫希臘／西里爾字母（`greek2`／`cyrillic2`）、Courier 粗體與粗斜體的全部字串與行高：268,643 行。
- **第五份探針** `Survey5.hx`（26360）：每個字型 6～255 px 一般與粗體的單一諺文寬度（`K=` 行）、131～255 px 的 ASCII／Latin-1、49～255 px 的希臘／西里爾、斜體（含粗斜體）49～255 px 的 ASCII／Latin-1 與 6～255 px 的希臘／西里爾、對應字級各樣式的行高：183,765 行。
- **第四份探針** `Survey4.hx`（26359）：57 個字型 × 斜體 6～48 px × ASCII／Latin-1（有粗體檔的加量粗斜體）、49～130 px 每個字級的一般與粗體 ASCII／Latin-1、每個字級每種樣式的 `getLineMetrics`，加上 `text` 設相同字串的語意探針：32,501 行。`TextFormat.size` 到 130 都正常。
- **第三份探針** `Survey3.hx`（26358）：57 個字型名稱 × **每個字級 6～48 px** × ASCII／Latin-1／希臘／西里爾（粗體另量 ASCII／Latin-1），加上每個字型在 12～24 px 的 `&nbsp;`／標點／日／韓／全形／泰文，以及每個字型每個字級一般與粗體的 `getLineMetrics`：18,310 行。

## 2. 量到的 Windows Flash 規則

1. **字寬是整數像素，而且是「hinted」字寬。** Flash 用 GDI 排裝置字型：每個字的前進寬度 = 字型檔裡 `hdmx`（device metrics）表在那個像素大小的紀錄；沒有紀錄的大小則是字型 hinting 程式算出來的整數寬度。這和瀏覽器 canvas 量到的線性字寬（`hmtx` × 字級，不取整）不同：例如 Arial 14 px 的 `I` 是 **3** px（線性 3.89→4）、`H` 是 9（線性 10.1）、`M` 是 11（線性 11.66），一行 95 個 ASCII 字差了 14 px（2%）。FreeType 的 v35 直譯器（單色模式）能精確重現 GDI 的 hinted 字寬；只有複合字形（重音字母）在沒有 `hdmx` 紀錄的字級用線性取整。
2. **裝置字型沒有字距調整（kerning）**：整串寬度永遠等於各字寬度之和。
3. **字型只以英文家族名稱尋找。** 中文名稱（宋体、新宋体、黑体、微软雅黑、楷体、仿宋、微軟正黑體、新細明體、細明體、標楷體、宋體）**在 Windows Flash 裡一律找不到**，即使是繁體中文 Windows、即使系統有那個字型：它們和亂取的名字畫得一模一樣。`Helvetica`＝Arial、`Times`＝Times New Roman、`Courier`≈Courier New（Windows 的 Courier 其實是點陣字型，見第 5 節）、`NSimSun`＝SimSun；`_sans`＝Arial、`_serif`＝Times New Roman、`_typewriter`＝Courier New。
4. **找不到的字型用 Times New Roman**（`_serif` 預設）畫英文、希臘、西里爾字母和標點；行高也是 Times New Roman 的（14 px：ascent 13、descent 3、height 16；SimSun 本尊是 12/2/14）。
5. **漢字一律 1 em**（任何字型，連 Arial 也是：由系統中文字型補字）。
6. **行高也是 GDI 的整數值**（`getLineMetrics` 的 ascent／descent）：字型有 `VDMX` 表、且其中有為「Windows ANSI 字集」（bCharSet=1）算的 1:1 群組時，取該字級的 yMax／yMin（Arial 12 px 12/3、24 px 21/6）；否則是 OS/2 `usWinAscent`／`usWinDescent` 四捨五入（Tahoma 的 VDMX 是為全部字形算的，GDI 不用它，12 px 是 12/2；SimSun 14 px 12/2）。粗體用粗體字面的值（Arial 粗體 16 px 15/4，一般 15/3）；沒有粗體檔的字型合成粗體時行高不變。全部 57 個字型 × 43 個字級 × 粗細 4,472 筆與這條規則完全相同。
7. **字型沒有的文字由 Windows 的字型連結補**：一般字型（Arial、Times New Roman、Verdana、Segoe UI、Calibri、Georgia……）的日文假名與全形字元來自 **MS PGothic**（比例寬，不是 1 em：14 px 的「あ」13 px、「１」10 px）；有 FontLink 設定的 **Tahoma、Microsoft Sans Serif、Lucida Sans Unicode** 則連到 MingLiU，假名與全形都是 1 em。泰文來自 **Leelawadee UI**（Tahoma、Microsoft Sans Serif 自己有泰文）。沒有希臘、西里爾字母的字型（DFKai-SB、微軟正黑體；PMingLiU／MingLiU 雖然有，Flash 也不用）由 **Arial** 補，Leelawadee UI 的則是 1 em。GB2312 字型（SimHei、KaiTi、FangSong）沒有的 Latin-1 重音字母、`&nbsp;`、`•©®™£¥` 等符號畫成 **1 em** 的全形字。**韓文**：裝了韓文字型的 Windows 上，任何字型裡的諺文都是 **1 em**（26357 的「14 px 每字 11 px」是沒裝韓文字型時的替代字形，不是正常狀態）；有 FontLink 的 Tahoma／Microsoft Sans Serif／Lucida Sans Unicode／MS Gothic 系列／NSimSun 例外，見第 5 節。**裝了日文字型後**，繁中字型（微軟正黑體、PMingLiU、MingLiU、MingLiU_HKSCS、標楷體）的假名也改由 MS PGothic 補（雖然它們自己有假名）。
8. **粗體**：有粗體檔的字型（Arial、Times New Roman、Verdana、Tahoma、Georgia、Segoe UI、Calibri、Trebuchet MS、Comic Sans MS、Courier New、微軟正黑體、微軟雅黑、Yu Gothic、Malgun Gothic）用粗體檔的字寬；**沒有粗體檔的字型（SimSun、SimHei、KaiTi、FangSong、MingLiU、PMingLiU、DFKai-SB、MS Gothic、MS PGothic、Impact、Lucida Console）由 GDI 合成粗體，每個字一律加寬 1 px**，漢字也加（15 px）；補字的中文字型沒有粗體，所以 Arial 粗體裡的漢字也是 15 px；Arial Black 本身已經比粗體更粗，粗體不再加寬。
9. **斜體**：有斜體檔的字型（Arial、Times New Roman、Courier New、Verdana、Georgia、Trebuchet MS、Comic Sans MS、Segoe UI、Calibri、Meiryo／Meiryo UI）用斜體字面的 hinted 字寬；沒有的由 GDI 合成斜體，**合成斜體在部分字級也會改變字寬**（Gulim、Dotum、Batang、Gungsuh 在 43 個字級裡有 15 個不同，MingLiU 也有），不是單純歪斜。同理合成粗體也不一定是「加 1 px」：MingLiU 的重音字母多半比加 1 窄（12 px 的 Ç 是 8 不是 10），Yu Mincho、Gulim、Batang 的粗體幾乎每個字都不同。這些全部用實測值記在「合成字面」裡（第 3 節）。
10. **49～255 px**：hinting 仍然影響字寬——Arial 49～130 px 的 ASCII 有 12% 的字與線性取整不同、Times New Roman 17%、Verdana 3%、中文字型 0%；行高規則（VDMX／`usWin`）到 255 px 都成立。`TextFormat.size` 到 255 仍正常。
10a. **Courier**：Windows 的 Courier 是點陣字型（`coure.fon` 等），字寬與行高只能實測，不能從字型檔算。它只有 ASCII（U+0020～007F）的字形，字級 6～15 px 用 13 px 的點陣（每字 8 px）、16～19 用 16 px、20～24 用 20 px、25～91 用 25 px（每字 15 px）、92 px 起 GDI 換成可縮放的替代字型（比例字寬）；行高同樣跟著點陣（13／16／20／25 px）。**補字不是逐字而是整段**（26361，`fontsurvey/probe-courier/`）：GDI 不能把別的字型的字形混進點陣字型，所以同一段（同字型、同字級、同粗體、同斜體、同一行；顏色不同不算分段，`setTextFormat` 改字級或粗體、`<font face>` 才算）只要有一個 ASCII 以外的字，**整段連 ASCII 一起改用補字字型**，字級為 `max(字級, 13)`（Courier 12 px 的「abc안」是 Gulim 13 px 的 8+8+8+13＝37，不是 Courier 的 24＋13）。補字字型由該段第一個 ASCII 以外的字決定：諺文 → Gulim；泰文 → Leelawadee UI；注音 → SimSun；漢字、假名、CJK 符號、全形／半形形式、箭頭、數學運算子、幾何圖形 → MS PGothic；其他（Latin-1、拉丁擴充、希臘、西里爾、希伯來、阿拉伯、一般標點、貨幣、字母式符號）→ Arial。行高仍是 Courier 自己的。**Flash 這個選擇有歷史相依性**：同一個播放器程序裡，之後的段落會優先沿用已經載入過的補字字型（量過假名之後再量希臘字母，希臘字母就變成 MS PGothic 而不是 Arial；而且每個字級各記一次），任何固定的表都無法重現；Timffle 一律用「剛啟動的播放器」的選擇（以上清單，每類各用一個新程序實測）。混合類別的段落以第一個字決定，實測一致，只有「€ 與泰文同段」兩種順序都是 Leelawadee UI，原因不明、未模仿。
10b. **FontLink 字型裡的韓文**：Tahoma、Microsoft Sans Serif、Lucida Sans Unicode、MS Gothic／PGothic／Mincho／PMincho、NSimSun 自己沒有諺文，Windows 依登錄檔 `FontLink\SystemLink` 的清單（PMingLiU、SimSun、MS PMincho、Batang、微軟正黑體 UI……）補字並縮放，寬度隨字級不規則，但同一字級內每個諺文寬度相同；其他字型的諺文都是 1 em。
11. **`text` 設成相同字串**（`fontsurvey/probe-sametext/`，16 步）：相同字串本身不重排、保留逐段格式；但只要中間指派過 `defaultTextFormat`（即使值相同），下一次設相同字串就整段套用預設格式。`htmlText` 設相同字串不重排。
12. **SimSun／NSimSun／MS Gothic**：ASCII 與 Latin-1 字母半形（0.5 em），`&nbsp;`、希臘、西里爾、全形、大多數標點 1 em（例外：`•©®™£¥` 半形）。所以許願池那 20 個 `&nbsp;` 在 SimSun 14 px 是 280 px，超過 275 px 的欄寬而換行，「個摩」到下一行——這就是 Windows Flash 看不到「摩」的真正原因（Mac 版 Flash 則是因為用 Times 把整行縮短）。
13. **等寬中日韓字型的漢字在奇數字級是「半形的兩倍」**（26361）：MingLiU、DFKai-SB、MS Gothic、MS Mincho、NSimSun、SimHei、KaiTi、FangSong、GulimChe、DotumChe、BatangChe 的漢字與全形字元是半形字寬的兩倍，奇數字級無條件進位（7 px 是 8、15 px 是 16、101 px 是 102）；偶數字級、以及其他字型（SimSun、PMingLiU、微軟正黑體、Meiryo、Gulim……）都是 1 em。MingLiU／PMingLiU／DFKai-SB 裡 Big5 以外的漢字（例如「仮」）在奇數字級仍是 1 em（這類字由 hinting 程式決定寬度，FreeType 算不出，只能實測）。
14. **FontLink 字型裡的假名、全形字元與漢字會被縮放**（26361）：Tahoma、Microsoft Sans Serif、Lucida Sans Unicode 連結的 MingLiU 以 GDI 自己算的字級補字——11 px 的文字補成 12 px 的字、13 px 補成 15 px（7、9、25、33 px 等則等於字級），同一字級內每個字相同；韓文同理（第 10b 條）。
15. **合成粗體的漢字不一定加 1 px**（26361）：Gulim、Dotum、Batang、Gungsuh、Yu Mincho 沒有粗體檔，GDI 合成的粗體漢字在 6～50 px 比一般寬 1 px、51～100 px 相同、101～150 px 窄 1 px、151～200 px 窄 2 px、201～250 px 窄 3 px、251～255 px 窄 4 px。
16. **Arial Black 的粗體**（26361）：本身的字（拉丁、希臘、西里爾）不加寬，補字的假名、全形、漢字、韓文仍照補字字型（沒有粗體檔）加 1 px。**泰文的粗體**：補字用 Leelawadee UI 真正的粗體字面，不是一般字面加 1 px。
17. **斜體裡補字的假名也被合成斜體**（26363）：MS PGothic 沒有斜體檔，任何字型的斜體（與粗斜體）文字裡由它補的假名由 GDI 合成斜體，在 7、8、9、13、17、19、21、22 px 這 8 個字級「イ」「カ」的寬度改變（7～9 px 窄 1 px，13～22 px 寬 1～2 px），「キ」在 9 與 13 px 寬 1 px；其餘假名、全形字、漢字、泰文、諺文不變。有斜體檔的字型（Arial、Times New Roman、Georgia……）的斜體假名同樣如此（補字字型是 MS PGothic，不是該字型的斜體檔）。MS PMincho 自己的假名合成斜體時「あ」「う」「く」「ケ」在 7～22 px 的 9 個字級也不同。
18. **韓文字型的合成斜體**（26363）：Gulim、Dotum、Batang、Gungsuh 的斜體（與粗斜體）在 11～25 px 這 15 個字級改變 ASCII 字母、標點與全形字（含全形空白、全形英數）的寬度，諺文與漢字不變；等寬的 GulimChe、DotumChe、BatangChe 只有全形空白在 13、15、17、21、25 px 窄 1 px。MingLiU 的合成斜體則在 6～198 px 的 85 個字級改變 `•©®™` 的寬度。SimSun、NSimSun、SimHei、KaiTi、FangSong、Microsoft YaHei、Tahoma、Microsoft Sans Serif、Lucida Sans Unicode、MS Gothic、MS UI Gothic、MS Mincho、Yu Gothic、Yu Mincho、Malgun Gothic 的合成斜體在這些字串上與直立體完全相同。
19. **斜體的行高**與同粗細的直立體相同（合成與真斜體檔皆然；21,000 筆）。
20. **沒有實測粗斜體、斜體又是合成的字型的粗斜體**（26363）：GDI 把合成粗體與合成斜體都套上，字寬 = 粗體字寬 +（合成斜體字寬 − 直立體字寬）；MS PGothic 的粗體是 +1 px，所以 Courier 粗斜體段落裡 MS PGothic 的假名 = 合成斜體字寬 + 1（250 列全部吻合）。有普查到粗斜體的字型（SimSun、MingLiU、PMingLiU、Gulim、Batang、Yu Mincho、Tahoma、微軟正黑體……）仍逐字用實測值。


## 3. Timffle 的做法（26357）

- `core/src/font/windows_metrics.rs` 內建字寬表 `windows_metrics.bin.z`（26363：格式仍是第 5 版，zlib 5.99 MB（解開 13.99 MB），161 個字體——斜體字面（真斜體檔與 Windows 合成的斜體，含新建的 9 個合成斜體字面）也記每個字級的漢字、假名／全形與諺文寬度，第七份普查量到的每個字逐字以實測值寫入；26361：格式第 5 版，zlib 5.11 MB，152 個字體——每個字體另記 6～255 px 每個字級的漢字寬度與假名／全形寬度（一般與合成粗體各一；第 2 節第 13～16 條的規則就是靠這些值），普查量到的每個字（含補字的假名、泰文、希臘、西里爾）逐字以實測值寫入；26360：格式第 4 版，zlib 1.96 MB，121 個字體——含斜體、粗斜體、「合成字面」（Windows 自己合成的樣式以底字面的 hinted 字寬（粗體加 1 px）為預設，實測不同的字逐一記下）、純實測字面（Courier）、每個字級的諺文寬度；由 `fontsurvey/gen_metrics.py` 從字型檔的 `hdmx` 表、FreeType v35 和上述實測產生，**只含字寬數字，沒有字形**）。每個字體（family × 粗體 × 斜體）存每個字的線性寬度（字型單位）、**6～255 px** 每個字級裡與線性取整不同的 hinted 寬度（ASCII／Latin-1／希臘／西里爾在所有字級、所有樣式都以 Flash 實測值寫入；其他符號以 FreeType v35 推算），每個字級的 ascent／descent 與諺文寬度；255 px 以上寬度用線性取整、行高用 `usWin` 值取整。
- 行高（`core/src/font.rs` `FontMetrics::ascent`／`descent`）：裝置字型的 `FontMetrics` 帶著表裡的字面，每次依字級查 GDI 的整數 ascent／descent，`getLineMetrics`、行距、基線位置都用它；字形改成相對基線擺放（`Glyph::rendered_at_baseline`），所以表的 ascent 直接決定字形的位置。
- 排版（`core/src/font/font_like.rs`）：裝置字型的每個字先查表（名稱先依第 2 節第 3 條解析，找不到的用 Times New Roman；漢字 1 em；假名／全形／泰文依第 6 條補字；粗體依第 7 條），查到就用它、不做 kerning；表裡沒有的字（韓文、少見符號）才退回瀏覽器量的寬度取整。只有網頁版（擴充功能、Timffle Browser）開啟這張表；桌面版與測試不受影響。
- 字形（`web/src/ui/canvas_font_renderer.rs`）：名稱解析後，瀏覽器有那個字型就用它畫；是 Windows 字型但瀏覽器沒有（Linux 的 Verdana、Mac 的 SimSun）就用同類字型畫（sans→Arial/Helvetica，serif→Times，等寬→Courier New，中文字型保留名稱讓瀏覽器以 CJK 後備字型畫）；Windows 沒有的名稱（含中文名稱）一律用 Times New Roman 畫，和 Windows Flash 相同。行高也照解析後的名稱查既有的 Windows 行高表。

## 4. 字型清單與各平台結果

表中「Windows Flash」是基準行為；「Timffle 26356」是改版前在 Windows／Linux 上與基準不同的地方；「Timffle 26357」是改版後（字寬表）在所有平台的狀態。「✓」＝所有量到的字級、字串都與 Windows Flash 相同。

| 名稱 | Windows Flash 的行為 | Timffle 26356（改版前） | Timffle 26357 |
| --- | --- | --- | --- |
| `_sans`、Arial、Helvetica | Arial（hinted） | Windows/Linux 英文每行差 1～3%（線性字寬），假名用 1 em | ✓（Liberation Sans／Helvetica 只畫字形） |
| `_serif`、Times New Roman、Times、找不到的字型 | Times New Roman | 同上 | ✓ |
| `_typewriter`、Courier New | Courier New（0.6 em） | ✓ | ✓ |
| Courier | Windows 點陣字型 Courier | 當成 Courier New | ✓（26360：6～255 px 全部實測的純實測字面；26361：非 ASCII 整段換補字字型） |
| SimSun、NSimSun | 半形／全形規則（第 2 節第 8 條） | Windows ✓；Linux 被 fontconfig 換成 Noto Serif CJK，英文比例寬、希臘西里爾半形；Mac 用 Times | ✓ |
| 宋体、新宋体、宋體、黑体、微软雅黑、楷体、仿宋、微軟正黑體、新細明體、細明體、標楷體 | 找不到 → Times New Roman | Windows 的 Chrome 認得中文名稱，畫成本尊（寬度不同）；Linux/Mac 用 Times | ✓（一律 Times New Roman） |
| SimHei、KaiTi、FangSong | 半形英文、1 em 其他（含 Latin-1 重音字母） | Windows ✓（重音字母除外）；Linux/Mac 用 Times | ✓ |
| Microsoft YaHei、Microsoft JhengHei | 比例寬英文（hinted） | Windows ±1 px；Linux/Mac 用 Times | ✓ |
| PMingLiU、MingLiU、DFKai-SB | 比例寬／半形英文；西里爾在 PMingLiU 約半形 | Windows ✓（Latin-1、西里爾除外）；Linux/Mac 用 Times | ✓（26358：6～48 px 全部實測；26359：MingLiU 粗體、斜體也實測） |
| MS Gothic、MS PGothic、Yu Gothic | 半形／比例寬（hinted） | Windows ✓；Linux/Mac 用 Times | ✓ |
| Malgun Gothic | 比例寬（hinted） | Windows ✓；Linux/Mac 用 Times | ✓（韓文也在表內） |
| Tahoma、Verdana、Georgia、Segoe UI、Calibri、Trebuchet MS、Comic Sans MS、Impact、Arial Black、Microsoft Sans Serif、Lucida Console、Lucida Sans Unicode | 各自的 hinted 字寬 | Windows 每行差 0～4%；Linux/Mac 沒有這些字型，用 Times（Verdana 一行差 232 px） | ✓ |
| Meiryo、Meiryo UI、MS Mincho、MS PMincho、Yu Mincho、Gulim、GulimChe、Dotum、DotumChe、Batang、BatangChe、Gungsuh、GungsuhChe、MS UI Gothic、Microsoft YaHei UI、Microsoft JhengHei UI、MingLiU_HKSCS、Leelawadee UI | 各自的 hinted 字寬（日韓字型需裝補充字型） | 26357 以前視為找不到（Times New Roman） | ✓（26358 起在表內） |
| Arial Narrow | 隨 Office 安裝，這台沒有，Flash 畫 Times New Roman | 用 Times | 近似（26360：Liberation Sans Narrow 的線性字寬＝Arial Narrow，hinting 不同；對應裝了 Office 的 Windows） |
| 韓文（任何字型） | 1 em；FontLink 字型裡隨字級縮放 | 瀏覽器後備字型 | ✓（26358 一般字型；26360 FontLink 字型每個字級實測） |
| 泰文（非 Tahoma 等） | Leelawadee UI | 瀏覽器後備字型 | ✓（單獨量的組合符號除外） |

各平台驗證（Survey.hx，3180 筆，與 Windows Flash 逐字比對）：

| 平台 | 字形字型 | 26356 | 26357 |
| --- | --- | --- | --- |
| Windows 11（真字型） | 系統字型 | 53 個字型中 10 個全對 | 52 個全對（Courier 除外）；韓文只有 Arial Black、Segoe UI、Malgun Gothic 相同 |
| Linux（Liberation／Noto） | fontconfig 別名與後備 | 2 個全對（Courier New、`_typewriter`） | 52 個全對（Courier 除外）；韓文全部不同 |
| macOS 26（MacBook Pro） | Helvetica／Times／Songti 等 | 同 Linux 的情形 | 52 個全對（Courier 除外）；韓文全部不同 |

26363（斜體與粗斜體的非拉丁字全部實測）：產表時以六份普查共 1,739 萬筆（survey2～7）逐字驗證 0 筆不同、行高 66,060 筆與諺文 26,500 筆 0 筆不同；Timffle 26363 在 Linux 跑 survey7（147,003 行）、survey6（268,643 行）與 survey3（18,310 行）逐字比對 Windows Flash：survey7 除 Arial Narrow（刻意近似）外 125 個字型樣式 124,500 行字寬與 20,756 筆行高全部相同；survey6 只剩 Arial Narrow 與 Courier 粗體／粗斜體段落各 486 行（全是 Flash 程序內歷史相依的希臘／西里爾補字字型，文件第 5 節；26361 的 Courier 粗斜體還有 59 行假名與 `€£¥` 不同，現在相同）；survey3 與 26361 相同（Arial Narrow 與 Courier 的歷史相依補字 86 行）。改版前（26362）survey7 有 69 個字型樣式、7,816 行不同（Times New Roman 斜體的標點、各字型斜體裡補字的假名、Gulim 等的合成斜體……）。核心單元測試 158 個通過。

26361（表格式第 5 版）：產表時以五份普查共 1,490 萬筆（survey2～6）逐字驗證 0 筆不同、行高與諺文 0 筆不同；Timffle 26361 在 Linux 跑 survey6（268,643 行）與 survey3（18,310 行）逐字比對 Windows Flash：survey6 的 500 筆行高全部相同，字寬除 Arial Narrow（刻意近似）與 Courier 粗體／粗斜體段落（第 5 節：Flash 程序內歷史相依的補字字型、未實測的合成斜體補字）外全部相同（改版前 survey6 有 191 個字型樣式、79,713 行不同）；survey3 與 26360 相同（只有 Arial Narrow 與 Courier 的歷史相依補字行）。

26360（表格式第 4 版）：Windows 與 Linux 各跑 survey3／4／5（23.4 萬行）與 `text` 語意探針，除 Arial Narrow（刻意近似）外與 Windows Flash 全部相同。

26358 的全尺寸普查（`Survey3.hx`，18,310 行，含行高）：Windows、Linux、macOS 三個平台的 Timffle 輸出逐位元組相同；與 Windows Flash 比對，11,514 行一般字寬只有 Courier 與第 5 節列的韓文例外不同，4,472 筆行高全部相同（粗體行高見第 5 節探針限制），粗體字寬只有 MingLiU 的重音字母不同。
| Android／ChromeOS | Roboto／Noto | 無 Arial、Times、SimSun，全部用後備字型 | 字寬由表決定，與平台無關；字形為 Noto／Roboto |

## 5. 已知差異與限制

- **韓文**：26360 起 FontLink 字型的諺文寬度也實測（每個字級一個值）。沒裝韓文字型的 Windows 上 Flash 畫的是替代字形（14 px 每字 11 px），Timffle 不模仿。
- **MingLiU／PMingLiU**：這兩個是靠 hinting 程式產生字形的「tricky」字型，FreeType 算不出 GDI 的字寬；6～130 px 的 ASCII／Latin-1 已全部用實測值寫入（26359 起粗體、斜體也是）。
- **Courier**：26360 起 ASCII 與行高用實測值（6～255 px）；26361 起 ASCII 以外的字照第 2 節第 10a 條**整段換補字字型**（新程序的選擇）。Flash 自己的補字字型選擇有歷史相依性（同一程序裡沿用先前載入過的補字字型），Timffle 不可能重現，只模仿剛啟動的播放器；「€ 與泰文同段」的例外未模仿；字形仍由瀏覽器的 Courier New 畫，只有寬度換成補字字型的。
- **泰文組合符號**單獨量時 Flash 給它一個寬度，表裡是 0（放在字母後面時 Flash 也是 0）。
- **MingLiU／PMingLiU／DFKai-SB 裡 Big5 以外的漢字**在奇數字級比 Big5 的漢字窄 1 px（第 2 節第 13 條）；表只記了普查量到的那幾個字（「仮」），其他 Big5 以外的字在奇數字級用 Big5 的寬度（多 1 px）。
- **Courier 粗斜體的整段補字**：補字字型（MS PGothic、Arial……）在 Flash 裡也被合成斜體；26363 起這些字型斜體下的假名、標點、全形、泰文都有實測值（第七份探針），Courier 粗斜體段落的字寬跟著正確。survey6 裡仍不同的只剩 Flash 程序內歷史相依的補字字型選擇（下一條）。
- **Courier 的希臘／西里爾段**：survey6 在同一個 Flash 程序裡先量了假名，之後 Courier 的希臘／西里爾段落被 Flash 以 MS PGothic（1 em）補字——這是第 10a 條說的歷史相依，Timffle 照剛啟動的播放器用 Arial。
- **有粗體檔的中日韓字型裡沒有的漢字**（例如微軟正黑體粗體裡的「仮」）：Flash 由連結字型補字並合成粗體（多 1 px），Timffle 沒有各字型的字集表，把每個漢字都當成字型自己的（1 em），只有普查量到的字例外。
- **Arial Narrow**（隨 Office 安裝，基準電腦沒有）無法實測：表裡用線性字寬相同的 Liberation Sans Narrow 近似（hinting 不是 Arial Narrow 的，差 1 px 的字會有），對應裝了 Office 的 Windows；沒裝 Office 的 Windows 上 Flash 畫的是 Times New Roman。**使用者自己安裝、但不在表裡的字型**（例如 Noto Sans TC）在 Timffle 裡一律是 Times New Roman。沒裝日韓補充字型的 Windows 上，Flash 把 Meiryo、Gulim 等當成找不到；Timffle 一律當成有裝。
- **255 px 以上**用線性字寬取整、行高用 `usWin` 取整；**非整數字級**四捨五入到整數 px 查表。26363 起七份普查的每個樣本字（ASCII、Latin-1、希臘、西里爾、`&nbsp;`、常用標點、假名與樣本漢字、全形字、泰文、諺文）在每種樣式、6～255 px 每個字級都是實測值；**沒有普查到的字**（箭頭、數學符號、幾何圖形、方塊元素、少見標點、樣本以外的假名與全形字）仍是字型檔 `hdmx`／FreeType v35 的推算值，斜體時沿用直立體的推算值加實測例外，漢字與全形字則用該字體在該字級的均一寬度。
- **`text` 設相同字串**：26359 起照第 2 節第 11 條（之前 Timffle 一律不重排；上游 Ruffle 仍是如此）。
- 字形仍由瀏覽器的字型畫，所以筆畫形狀、粗細與 Windows 不同，只有位置相同。

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
