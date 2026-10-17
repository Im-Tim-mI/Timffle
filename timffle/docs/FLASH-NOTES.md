# 在真 Flash Player 32 上量到的行為

這裡記錄實作過程中，用[差異測試](TESTING.md)在 **Adobe Flash Player 32.0.0.465（standalone projector，Wine 下執行）** 量到的行為。許多地方與文件、與 OpenFL／Away3D 一類實作的猜測不同，所以全部以量測為準。每一條都對應 `difftest/` 裡的黃金答案或探針。

> 這些是「在我們量測的條件下」的觀察：Wine、standalone 播放器、特定測試輸入。沒有在原生 Windows 或瀏覽器外掛版驗證。若發現與你的觀察不同，請開 issue 並附上可重現的測試。

## 1. 3D 顯示物件

（`d13perspective`、`d16props3d`、`d19render3d`；實作在 `render/src/transform.rs`、`core/src/display_object.rs`）

- **對 `z`、`rotationX/Y/Z`、`scaleZ`、`transform.matrix3D` 的任何指派，即使指派的是預設值，都會讓物件變成 3D 物件。** 此時 `transform.matrix` 與 `transform.concatenatedMatrix` 變成 `null`，`matrix3D` 才是真相。
- **`matrix3D` 與物件即時連動**：改傳回的 `Matrix3D`，物件就跟著動；把已綁定到別的物件的 `Matrix3D` 指派過來丟 `#2189`；`matrix3D = null` 回到 2D 單位矩陣，但 Flash 仍保留快取的 `scaleX`。
- 屬性值來自矩陣各欄向量的 Gram-Schmidt 正交化；歐拉角：`ry = -asin(R20)`、`rx = atan2(R21, R22)`、`rz = atan2(R10, R00)`。**設定屬性時一律以 `T·Rz·Ry·Rx·S` 重新組成，設定的先後順序無關。**
- **透視**：深度 `z` 處的平面縮放為 `f / (f + z)`，`f = (stageWidth / 2) / tan(fov / 2)`（960 寬、`fov = 55` → `f = 922.1`）。投影中心在**擁有者自己的座標空間**（擁有者自己的矩陣之後才套用），預設是舞台中心。變換鏈 `F = V·P(stage)·L(root)·P(root)·L(a)…·L(obj)`，擁有者的 `P` 緊接在它自己的矩陣之後。
- **邊界與座標**：`getBounds` 把投影後的角四捨五入到 1/4 像素，再向外擴張到整數像素；投影物件上的 `localToGlobal` 先取 1/4 像素，再「四捨六入五成雙」到整數像素。

## 2. BitmapData.draw 與 3D

（`d38drawbitmap`、探針 `d39drawmatrix`）

- 被畫的子樹有 3D 內容時，內容依投影繪製；被畫物件**自己的變換被忽略**，但它的 `perspectiveProjection` 會用於它的子物件。
- **子樹含 3D 時，`matrix` 參數被整個忽略**（`colorTransform` 仍有效）。
- Flash 對 3D 的圖會做濾波，邊緣約軟 1 像素，所以黃金答案用「與解析投影相比，在容許範圍內」的自我檢查，而不是逐像素比對。
- 注意：`draw(stage)` 在 Ruffle 裡只畫到舞台子物件的 2D 邊界，畫 3D 內容的測試要放一張與舞台同大的底圖。

## 3. Matrix3D 與 Utils3D

（`d18matrix3d`、`d22pointat`、`d26steps`、`d28steps`、`d29steps`、`d31steps`、`d32steps`、`d33utils3d`、`d34utils3dw`、`d36pointtowards`、`d40utils3dnull`；實作在 `core/src/avm2/globals/flash/geom/{matrix_3d,utils_3d}.rs`）原始資料為欄主序，平移在元素 12～14。

- **`pointAt(pos, at=+Y, up=+Z)`**：對各欄做 Gram-Schmidt 得到 `Q`，`D = diag(sx, sy, sz)`，`U = Qᵀ·L`；剪切 `Sh = Q·(U·D⁻¹)·Qᵀ`。世界座標系：`d = pos − 平移`，`w2 = d × (0,-1,0)`，`w1 = w2 × d`；物件座標系：`a0 = at`，`a2 = at × up`，`a1 = a2 × a0`。結果 `= Sh · [d w1 w2] · diag(sz, sy, sx) · [a0 a1 a2]ᵀ`（縮放順序反過來），平移保留，投影欄清空。方向恰好垂直或為零（float32 判斷 `d.x == 0 && d.z == 0`）、`at`／`up` 為零或平行、或平方長度溢位時，矩陣不變。`pos`／`at`／`up` 含 NaN／Inf → 全部 NaN；矩陣有一欄為零 → 全部**零**；某欄平方後下溢（1e-30）→ NaN。`pointAt(null)` 中止腳本。
- **`Utils3D.pointTowards(p, mat, pos, at, up)`** ＝ `Matrix3D.interpolate(mat, 以 mat 的平移組成的純旋轉 W·Aᵀ, p)`；方向退化時回傳 `mat` 的複本；`pos` 為 NaN 時旋轉為 NaN、平移保留。
- **`interpolate`**：百分比夾在 0～1，NaN → 旋轉與平移都是 NaN；旋轉是由原始 3×3 讀出的四元數（縮放留在裡面；對角元素相等時取最小索引，所以零矩陣被讀成繞 x 轉 180°），做球面內插（點積超過 0.9995 改用 nlerp），縮放被丟掉。
- **`recompose`**：`axisAngle` 的軸會正規化，角度除以軸長（`(0,2,0,0.8)` 轉 0.4；零軸 → `cos(angle)·I`）；`quaternion` 只接受 `0.99999f ≤ x²+y²+z²+w² ≤ 1.00001f`，否則 `ArgumentError #2004`；縮放為 0 或負值都接受；少於 3 個分量或含 null → 回傳 `false` 且矩陣不變；`components` 的 w 被忽略；樣式錯誤 → `#2187`。
- **`decompose`**：歐拉角用一般的 `asin/atan2`；`axisAngle` 由四元數導出（`2·acos(w)`，最多一整圈，軸為向量部分正規化，單位矩陣為零軸）；有剪切的矩陣用 Gram-Schmidt；鏡射得到負的 `sz`；**奇異矩陣回傳未初始化的記憶體（每次不同）**，黃金答案裡那幾行標 `~`。
- **`appendRotation`**：軸在 float32 下正規化（太小的軸視為零軸 → `cos(angle)·I`），樞軸平移為 `pivot − R·pivot`。
- **數值**：儲存是 float32。`transformVector`：乘積與總和用 double 精確計算，最後只捨入 float32 一次（60/60 位元精確）；`deltaTransformVector` ＝ `transformVector` 減去平移（float32 減法）；`append`／`prepend` 是單純的 float32 乘法；`determinant`／`invert` 使用另一種 float32 運算順序（Ruffle 約 70% 差一個 ulp，**尚未對齊**）。`projectVector`：結果 `= (x,y,z)·float32(1/w)`，保留 w，`w == 0` → `(0,0,0,0)`；`projectVectors` 只處理完整頂點（其他長度只調整輸出大小）。

## 4. 命中測試是依像素量化的

（探針 `d15hit_edge`）

`DisplayObject.hitTestPoint(x, y, true)` 在真 Flash 上，對整數像素 ±0.5 像素內的任何點給出同一個答案（在一張每格 8×8 像素、共 8960 格的格狀地圖上，11 個偏移量測過：沒有任何變化；超過 ±0.55 才開始改變）。Ruffle 的 `shape_hit_test` 是在指定 twip 上做精確的 winding-number 測試，所以 0.05 像素就可能翻轉結果。

用合成的矩形校準：水平／垂直邊緣的行為像是在 `(x − 1/8, y + 1/8)` 取樣；斜邊的容許量依斜率在 −0.6～超過 1 像素之間。最接近的常數偏移仍會留下 8 格不同。看起來是 Flash 的掃描線光柵化器的行為，因此**刻意不修**（成本與對其他遊戲的風險太高）。如果在 Ruffle 裡窄通道被擋住而 Flash 是通的，先懷疑這個（格子靠近輪廓邊緣）。

## 5. 名稱解析：先找父網域

Flash（avmplus `DomainEnv::getNamedScript`）詢問名稱時**父網域優先**：祖先網域裡的定義一律勝過自己網域裡的。這不只是「同一個名稱定義兩次」的問題，也決定了一個 multiname 的命名空間集合裡兩個**不同**命名空間哪一個被找到：每個 `import flash.system.*` 的腳本呼叫 `trace(...)` 時，都必須找到根網域的內建公開 `trace`，而不是子網域函式庫裡同名的 `flash.system::trace`。見 [`RUFFLE-PATCHES.md`](RUFFLE-PATCHES.md) 的 0003。

## 6. LocalConnection

（`t2localconn`、`r1lc_cyclic_args`、`r2lc_client_primitive`、`r4lc_limit`、`t3lc_*`）

- 訊息大小上限不是單一字串門檻：`合格連線名稱(UTF-8) + 方法名稱(UTF-8) + AMF3 參數 ≤ 40943`，接收端存在再扣 32，超過丟 `ArgumentError #2084`。這是用二分搜尋（0～50000）量到的：例如同一組名稱下，有接收端時最多可傳 40890 個字元的字串、沒有接收端時 40922；名稱越長門檻越低；中文字串每字 3 位元組，所以只有 13630 個字。
- Flash 會回收區域變數，`LocalConnection` 物件要放在靜態欄位，連線才不會悄悄消失。
- 排程：Flash 在同一幀處理 `status`，之後分 1～3 幀送達 `receiver`，且重跑時有一行會差 1 幀（`[f+N]` 不是決定性的）。

## 7. URLStream

（`t1urlstream`、`r3stream_state`、`r5stream_api`）

- 事件順序 `open → progress* → httpStatus → complete`；`bytesAvailable` 在每次 `progress` 都要與「已載入 − 已消耗」一致；`complete` 時的 `bytesAvailable` 會隨 TCP 分塊而變，所以黃金答案驗證的是不變量，不是固定數字。
- 在 `httpStatus` 的監聽器裡呼叫 `close()`，Flash **仍然會**送 `complete`——「`close()` 之後絕對沒有事件」不適用於已排定的終止事件。
- FP 11.4 的 `stop`／`position`／`length`：HTTP／未開啟時 `stop` **不會**停止傳輸，`position`／`length` 為 0，寫入 `position = 5` 或 `-1` 不會改變它。（只量過 HTTP 與未開啟；不保證其他協定相同。）
- HTTP 404：內容照常送來，之後 `httpStatus` ＋ `ioError #2032`；`file://` 的 `status=0` 視為成功。

## 8. Socket 與計時器的事件順序

腳本執行被占住（例如建構大量介面）時，真 Flash 的順序是：`enterFrame` < 到期的 `setTimeout`／`Timer` < `frameConstructed` < `exitFrame` < `socketData`。Ruffle 桌面版是「所有幀事件 < `socketData` < 計時器」，因此桌面版在這種情境下**會把某些遊戲的競態條件藏起來**；網頁版則因為資料經過多層非同步才到頁面，剛好與 Flash 一致。這個順序對「一個 1 秒計時器」與「到達中的封包」之間的競態很重要。（Wine 下的 standalone 量測；未在原生 Windows 驗證。）

## 9. 其他小差異

- `ByteArray.writeBytes(src, offset, length)` 的 `offset`／`length` 越界：Flash 丟 `RangeError #2006`，Ruffle 丟 `EOFError #2030`。
- `ba.readBytes(ba, 0, n)`（自己讀自己）：Flash 會推進 `position`，Ruffle 不會。
- 到期的重複 `Timer` 在腳本卡住之後：Ruffle 一次補跑全部 tick，Flash 只跑一次再等一個週期。
- `readBytes(dst, 0, 0)`＝讀剩下全部；`readBytes` 要求太長丟 `#2030` 且不消耗位元組；`readUnsignedInt` 剩 3 位元組丟 `#2030` 且 `position` 不動（兩邊相同）。

## 10. 讓黃金答案不穩定的 Flash 事實

- `Matrix3D.decompose` 對奇異矩陣回傳未初始化的記憶體：標 `~`。除此之外目前沒有需要標 `~` 的行（計時與版本字串除外）。
- 以真 Flash 為標準時，每個黃金答案至少跑兩次確認一致。
- 用 Wine 下的 standalone projector 當參考，與瀏覽器外掛或原生 Windows 可能有細微差異；事件順序的結論要保守。
