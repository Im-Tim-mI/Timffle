# 批次 graphics2：Graphics.readGraphicsData、beginShaderFill／lineShaderStyle、BitmapData.applyFilter(ShaderFilter 子矩形)

分支 `graphics2`（自 PRO_bata `833e6095` 切出）。本機沒有 GPU：`graphics_shader_fill` 與 `bitmapdata_applyfilter_shader` 兩個測試（`with_renderer = { optional = false }`）在這裡被跳過，**它們的 output.txt 是依著色器語意推算的預期值，尚未在任何機器上執行過**；readGraphicsData 的測試在這裡通過。

另外注意：STATUS 第 8 批說「results in difftest/results/flash/d55graphics.txt、d56graphics2.txt、d57winding.txt — keep them」，但這三個檔案**沒有進 git**（results/flash 裡只有 d60、d61），整個檔案系統也找不到。本批 readGraphicsData 的結構只能依 STATUS 2026-11-04 21:57 那行寫下的「readGraphicsData facts measured」與三支探針原始碼（D55Graphics.hx、D56Graphics2.hx、D57Winding.hx）重建；哪些輸出行有 Flash 事實支撐、哪些是推論，見下面的清單。

## (a) CHANGELOG 一行

- **第 2 組（繪圖：Graphics 剩餘 3 個空殼 + BitmapData.applyFilter）**：`Graphics.readGraphicsData(recurse)` 真的回傳繪圖紀錄（依真 Flash 32 量到的結構：每個填色群組 `[填色, GraphicsPath, GraphicsEndFill]`、該群組內的筆畫接在後面 `[GraphicsStroke, GraphicsPath(nonZero), GraphicsStroke(0)]`、每次 lineStyle 切一段、封閉迴圈從第二段起算並把第一段接到最後、lineTo 填色的筆畫含隱含封閉段而 drawPath 的不含、最後一項是筆畫時補一個 GraphicsEndFill、實心色經 8 位元預乘來回、漸層色 ARGB、點陣圖矩陣 ×4095/4096 且 repeat=true/smooth=false、`bitmapData` 是同一個物件、三次曲線拆成 4 條二次曲線、圓／橢圓／圓角矩形從 (x+w, y+h-ry) 順時針兩段曲線一角，`recurse` 把可見子物件的資料轉進被查詢物件的座標）；`beginShaderFill`／`lineShaderStyle`／`GraphicsShaderFill` 真的執行 Pixel Bender 著色器（第一次繪製時在填色範圍上算一次，結果當成不重複的點陣圖填色；null 著色器 TypeError #2007、沒有位元碼的 Shader ArgumentError #2004；渲染器跑不了著色器時填色登記但畫成透明，不會當掉）；`BitmapData.applyFilter` 的 ShaderFilter 不再限制 sourceRect 必須是整張來源（子矩形先複製到暫存點陣圖再跑著色器，寫到 destPoint）。驗證：新測試 `graphics_read_graphics_data`（254 行，結構行依 Flash 事實）、`graphics_shader_fill`、`bitmapdata_applyfilter_shader`（後兩者需要 GPU，本機未執行），既有 `graphics_*`／`bitmapdata_*`／`shape*`／`drawing*` 測試維持綠燈。

## (b) CHANGES-FROM-RUFFLE 段落

### 第 2 組：Graphics 剩餘成員（readGraphicsData、著色器填色）與 BitmapData.applyFilter(ShaderFilter)

Ruffle 上游：`readGraphicsData` 永遠回空 Vector；`beginShaderFill`／`lineShaderStyle` 是空殼、`drawGraphicsData` 遇到 `GraphicsShaderFill` 只印警告；`applyFilter` 的 ShaderFilter 把任何不是整張來源的 sourceRect 改成整張。Timffle：

- **`Graphics.readGraphicsData(recurse)`**（`graphics.rs`、`drawing.rs`）：`Drawing` 新增 `read_graphics_data()`，把已記錄的填色群組（第 8 批的 `FillOrigin`）與筆畫依 Flash 32 的順序吐出來（結構來自 STATUS 第 8 批「readGraphicsData facts measured」，探針 D55Graphics.hx／D56Graphics2.hx／D57Winding.hx）：
  - 每個填色群組 → `[GraphicsSolidFill|GraphicsGradientFill|GraphicsBitmapFill|GraphicsShaderFill, GraphicsPath(commands, data, winding), GraphicsEndFill]`；一般指令與 drawTriangles 群組回 `evenOdd`，drawPath 群組回它自己的 winding；drawTriangles 的三角形變成路徑（沒有 GraphicsTrianglePath）。填色路徑不含 `close_path` 加的隱含封閉段（`DrawingFill.implicit_closes` 記下索引），連續 MoveTo 只留最後一個。
  - 筆畫接在包含它的填色群組後面：`[GraphicsStroke(thickness, pixelHinting=false, scaleMode=normal, caps=none, joints=round, miterLimit=3, fill), GraphicsPath(nonZero), GraphicsStroke(thickness=0, fill=null)]`，每次 lineStyle 變更切一段；封閉迴圈 `M p0, s1→p1, s2, …, sk→p0` 回報成 `M p1, s2, …, sk, s1`（從第一段之後開始，第一段接到最後），封閉點之後的指令另起一個 MoveTo 子路徑；lineTo 畫的填色筆畫含隱含封閉段，drawPath 的不含；只有 MoveTo 沒有線段的筆畫不回報；整份資料最後一項是 GraphicsStroke(0) 時補一個 GraphicsEndFill。
  - 數值：實心色經 Flash 的 8 位元預乘來回 `p = round(c·a/255)`、`c' = floor(p·255/a)`（STATUS：7 個樣本中符合 5 個，精確公式未知；alpha 0 回 0x000000）、alpha = floor(a·255)/255；漸層 colors 為含 alpha 位元組的 ARGB uint、alphas = a/255、ratios 原值、matrix 如給定（f32）、focalPointRatio 經 Fixed8；點陣圖填色 matrix = 給定值 ×4095/4096、repeat 永遠 true、smooth 永遠 false、`bitmapData` 是同一個物件（`Drawing::bitmap_objects` 用 `DynamicRoot` 抓住 AVM2 物件，`ObjectRoot`）；lineGradientStyle／lineBitmapStyle 的填色出現在 `GraphicsStroke.fill`；空的或 clear() 過的 → 空 Vector。
  - 幾何：`cubicCurveTo` 回報成 4 條二次曲線（在 t = ¼、½、¾ 切開，控制點 = (3(Q1+Q2)−Q0−Q3)/4，座標取整到 twips）；`draw_round_rect_internal` 改成從 (x+w, y+h−ry) 出發順時針、每個角兩段二次曲線、直邊長度為 0 時仍有一個零長 LineTo（Flash 的順序；只是同一迴圈換起點，渲染不變）。
  - `recurse=true`：自己的 transform **不**套用，可見的子物件（`iter_render_list` 順序，`visible=false` 跳過）遞迴附加，路徑座標與漸層／點陣圖矩陣乘上子物件相對於被查詢物件的矩陣。
- **`beginShaderFill(shader, matrix)`／`lineShaderStyle(shader, matrix)`／`GraphicsShaderFill`**（`graphics.rs`、`drawing.rs`）：`Drawing::add_shader_fill` 記下 Pixel Bender handle、參數（用 ShaderJob 的 `get_shader_args` 在呼叫當下複製）與矩陣，回一個點陣圖填色樣式，id ≥ 0x8000 代表著色器填色；`BitmapSource::bitmap_size`／`bitmap_handle` 在圖形第一次向渲染器登記時才算：填色（與筆畫）的邊界經矩陣反矩陣映回著色器座標，從原點起取一張 `ceil(max)`（1～4096）大小的空材質，用 `run_pixelbender_shader(PixelBenderTarget::Bitmap)` 算一次，之後當成不重複、不平滑的點陣圖填色（矩陣 = 給定矩陣 × 20）。**近似**：著色器只在提交後第一次繪製時靜態算一次，之後改 `shader.data.*` 不會重算（直到繪圖內容改變）；`outCoord()` 從 0 起算，所以只有落在正象限的填色座標與 Flash 相同；渲染器跑不了（本機沒有 GPU 的 null renderer）時填色仍登記、畫成透明並印一次 warn，不會 panic。錯誤：`shader` 為 null → TypeError #2007；Shader 沒有位元碼 → ArgumentError #2004（Adobe 文件只說 ArgumentError，代碼是推論）。`readGraphicsData` 回 `GraphicsShaderFill(shader 同一物件, matrix)`（Flash 對著色器填色的回報未量測）。
- **`BitmapData.applyFilter(src, sourceRect, destPoint, ShaderFilter)`**（`bitmap_data.rs`）：sourceRect 不是整張來源時，把該區域（夾在來源範圍內）用 `operations::copy_pixels` 複製到一張同透明度的暫存 BitmapData，著色器在暫存圖上跑（`outCoord()` 從矩形左上角起算，與其他濾鏡的子矩形一致），結果寫到 destPoint；寬或高夾成 0 時不做事。

## (c) 「已知與真 Flash 還不同的地方」新列

| 區域 | 差異 |
|---|---|
| `Graphics.readGraphicsData` | 結構依 STATUS 第 8 批整理的 Flash 32 事實重建（原始結果檔沒有進 git）。未經 Flash 驗證的推論：三角形群組與空填色的回報、lineTo 未 moveTo 時以目前筆位置當起點（`M(0,0)`）、填色路徑不含隱含封閉段、`GraphicsStroke` 的 pixelHinting／scaleMode／caps／joints／miterLimit 一律回 `false/normal/none/round/3`（照 STATUS 的字面）、drawPath+endFill 後多出的一段封閉筆畫（Ruffle 第 8 批的渲染就是這樣）、著色器填色的回報、`recurse` 時子物件的筆畫粗細不乘比例。座標：Ruffle 把像素截斷成 twips（`Twips::from_pixels`），Flash 四捨五入，圓的控制點等非整數座標可差 0.05 px。`beginGradientFill(matrix=null)`：Flash 回報 a=d=1/8.192（0.12207），Ruffle 存的是單位矩陣所以回 1（Ruffle 以單位矩陣渲染 null 矩陣漸層，是否與 Flash 的 200 px 漸層框一致未驗證）。實心色的預乘來回公式只符合 7 個樣本中的 5 個。 |
| `Graphics.beginShaderFill`／`lineShaderStyle` | 著色器在第一次繪製時靜態算一次（Flash 每次繪製都算）；`outCoord()` 從 0 起算，負座標的填色會被夾掉；渲染器不支援 Pixel Bender（canvas／無 GPU）時畫成透明。像素結果未在 GPU 機器上驗證。 |
| `BitmapData.applyFilter(ShaderFilter, 子矩形)` | Flash 在 x/y 非 0 時有奇怪的平移／裁切、x=y=0 時忽略 width/height（上游註解）；Timffle 把子矩形當成一張獨立的來源圖處理，邊緣行為未以真 Flash 驗證。 |

## (d) queue.json

```json
[
  {"class": "flash.display.Graphics", "status": "done", "note": "batch graphics2: readGraphicsData real (Flash 32 structure per STATUS batch-8 facts; raw d55/d56/d57 result files are not in git), beginShaderFill/lineShaderStyle/GraphicsShaderFill real (shader evaluated once at first render over the fill bounds -> bitmap fill; #2007 null, #2004 no bytecode). 0 stubs left. GPU tests graphics_shader_fill not executed here."},
  {"class": "flash.display.BitmapData", "status": "partial", "note": "batch graphics2: applyFilter ShaderFilter with a sub-rect real (copy region to a temp bitmap, run, write at destPoint; edges not Flash-verified; GPU test bitmapdata_applyfilter_shader not executed here). Remaining stub: encode JPEGXR (needs a jxrlib encoder FFI)."}
]
```

## 測試 `graphics_read_graphics_data` 各行的來源

- Flash 事實（STATUS 第 8 批）直接支撐：r2（筆畫三件組 + 結尾 EndFill）、r3／s1／s2／s4／s5（填色群組順序、筆畫在群組後、封閉迴圈旋轉、每個群組重覆填色樣式）、r4／s8／s9（圓從 (x+w, y+h−ry) 順時針、兩段曲線一角、零長 LineTo）、r5／r5b／g1／g2（ARGB 色、a/255、矩陣如給定、Fixed8 焦點、線漸層／線點陣圖在 Stroke.fill）、r6／g1（點陣圖矩陣 ×4095/4096、repeat/smooth、同一個 bitmapData）、r7（三次曲線拆四段、twips 取整、drawPath 群組 winding）、r8（自身 transform 不套、子物件轉進父座標、不可見子物件跳過）、r10/s3/s6（lineTo 填色含隱含封閉段）、s7（lineStyle() 切段）、r11（空 Vector）、c1（預乘來回：10CDAB→10CCAB、7F7F7F→7A7A7A，0 alpha 行是推論）、w1（第 8 批的群組規則）。
- 推論（未有 Flash 結果檔）：r9（三角形群組的封閉 LineTo）、r12（無 moveTo 從 (0,0) 起）、r13 第二段封閉筆畫、r14、r1 的 alpha 0.498 捨入、s8 筆畫結尾的 `M(70,50) L(70,50)`（照「封閉點之後另起 MoveTo」與「零長 LineTo」兩條規則推得）。
