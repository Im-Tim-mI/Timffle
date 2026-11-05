# s3dctx 批次：Context3D 剩餘空殼（configureBackBuffer wantsBestResolution*、setRenderToTexture colorOutputIndex、drawToBitmapData）

## (a) CHANGELOG 條目

- Context3D 最後三個空殼做成真的：`configureBackBuffer()` 的 `wantsBestResolution`／`wantsBestResolutionOnBrowserZoom` 依視埠的縮放係數（`Stage.contentsScaleFactor`，即裝置像素比×瀏覽器縮放）配置較大的後緩衝區並縮回原本的邏輯區域顯示，瀏覽器縮放改變時每幀重新配置；`setRenderToTexture()` 的 `colorOutputIndex` 1～3 做成多重繪製目標（wgpu 一個 render pass 最多四個色彩附件，AGAL 片段程式的 `oc0`～`oc3` 各對應一個輸出，`oc4` 以上照 Flash 丟 #3760），範圍外 #3770、baseline 系列 profile #3779、大小或位元深度不同 #3761；`drawToBitmapData(destination, srcRect, destPoint)` 用 GPU 紋理複製把後緩衝區（不是正在顯示的前緩衝區）搬進 BitmapData，走 `BitmapData.draw()` 同一條 GPU→CPU 同步路徑，不縮放、超出部分裁掉，`srcRect`／`destPoint` 超界或 NaN 丟 #3802，context 已 dispose #3694、BitmapData 已 dispose #2015；順便讓只呼叫 `clear()` 沒畫三角形的幀在 `present()`／`drawToBitmapData()` 前真的清掉（原本的 clear 是延遲到下一個 render pass）。驗證：`cargo check -p ruffle_core -p ruffle_render -p ruffle_render_wgpu -p naga-agal`、`cargo check -p ruffle_web --target wasm32-unknown-unknown`、`cargo test -p naga-agal`（新增 `test_multiple_color_outputs` 快照：三個輸出、補零到四個、裁到一個、`oc4` 錯誤）、clippy；SWF 測試 `stage3d_context_leftovers` 需要 GPU，在這台沒有 GPU 的機器上被跳過，預期輸出依 Adobe 文件語意寫成。

## (b) CHANGES-FROM-RUFFLE 段落

### 第 N 組：Context3D 剩餘項目（s3dctx）

**flash.display3D.Context3D**

- `configureBackBuffer(width, height, antiAlias, enableDepthAndStencil, wantsBestResolution, wantsBestResolutionOnBrowserZoom)`：
  - `wantsBestResolution = true`：後緩衝區以「要求的大小 × 視埠縮放係數」的裝置像素配置（Adobe：「if the device supports HiDPI screens it will attempt to allocate a larger back buffer than indicated by the width and height」），顯示時以 1/縮放係數畫回同一塊邏輯區域（`Context3DObject::render` 乘上反向縮放），所以 Stage3D 在 HiDPI 螢幕或瀏覽器放大時不再模糊；`Stage.contentsScaleFactor` 就是這個係數。
  - `wantsBestResolutionOnBrowserZoom = true`：後緩衝區「隨瀏覽器縮放比例成長」。這個播放器把裝置像素比和瀏覽器縮放合在一個視埠縮放係數裡，所以記下呼叫當時的係數當基準，之後每幀（`Stage::check_requested_context3ds`）比對：係數變了就用新的比例重新配置（`Context3DObject::refresh_best_resolution`）；兩個旗標都開時直接用完整係數。
  - 縮放後的大小仍受 `maxBackBufferWidth`／`maxBackBufferHeight`（與 16384）限制（Adobe：「maxBackBufferWidth and maxBackBufferHeight cap the growth」），`backBufferWidth`／`backBufferHeight` 回報實際配置的裝置像素大小（Adobe：這兩個屬性「may be modified when the browser zoom factor changes」，即反映真正的緩衝區）。
  - 先前批次的大小檢查（32～16384、#3669／#3780／#3781、maxBackBuffer*）保留，仍以要求的邏輯大小檢查。
- `setRenderToTexture(texture, enableDepthAndStencil, antiAlias, surfaceSelector, colorOutputIndex)`：
  - `colorOutputIndex` 0～3 為多重繪製目標：輸出 0 照舊，1～3 綁成同一個 render pass 的額外色彩附件（`WgpuContext3D::extra_color_targets`），深度／模板緩衝、取樣數、`clear()` 與混合、色彩遮罩都跟著輸出 0；`setRenderToBackBuffer()`、`present()`、`configureBackBuffer()` 解除全部，重新設定輸出 0 時只保留大小相同的額外輸出。
  - AGAL（render/naga-agal）：片段程式的 `oc`／`oc0`～`oc3` 各自成為回傳結構的 `@location(0..3)` 成員，`agal_to_naga_with_color_outputs()` 依管線實際綁定的目標數產生對應數量的輸出（沒寫到的補零、超過的丟掉，對應 Flash 的 #3774「All the assigned render targets should match the outputs in the fragment program」——這裡不丟錯，只照綁定數輸出）；`oc4` 以上在上傳時丟 Error #3760（「The color output index is out of range.」）。
  - 錯誤：`colorOutputIndex` 不在 0～3 → ArgumentError #3770（「ColorOutputIndex must be in the range [0..3].」）；非 0 且 profile 是 baseline／baselineConstrained／baselineExtended → ArgumentError #3779（「requires a Context3D that is created with the standard profile or above」，Adobe：「must be 0 in constrained or baseline mode」）；位元深度（RGBA_HALF_FLOAT 對 8 位元）與輸出 0 不同 → ArgumentError #3761（「The bit depth of all textures used for render to texture must be exactly the same.」）；大小與輸出 0 不同也丟 #3761（Adobe 沒寫明，見 (c)）。
  - `surfaceSelector` 的立方體面選擇本來就有效（view 的 `base_array_layer`），額外輸出同樣支援。
- `drawToBitmapData(destination, srcRect = null, destPoint = null)`：AIR 25 簽名。讀的是**後緩衝區**（Adobe：「the back render buffer, not the front buffer shown on stage」，要擷取畫面請在 `present()` 前呼叫）。實作是 `RenderBackend::copy_stage3d_to_bitmap`（wgpu：`copy_texture_to_texture` 進 BitmapData 的紋理，再用和 `BitmapData.draw()` 相同的 `QueueSyncHandle` 在下次讀取像素時同步回 CPU），所以不縮放、不混色、顏色視為預乘（Adobe：「the rendering context does not check the format」）。`srcRect` 預設整個後緩衝區、`destPoint` 預設 (0,0)；超出 BitmapData 的部分裁掉（Adobe：「it is not scaled to fit the bitmap」）。錯誤：`srcRect` 超出後緩衝區、`destPoint` 超出 BitmapData 或任一值 NaN → Error #3802（「Offset outside stage coordinate bound.」）；context 已 dispose → #3694；BitmapData 已 dispose → #2015。還沒 `configureBackBuffer()` 時什麼都不做。
- 附帶：`clear()` 在 Ruffle 裡延遲到下一個 render pass 才執行，只 `clear()` 不畫三角形的幀原本不會顯示；現在 `present()` 與 `drawToBitmapData()` 前會用空 render pass 把待處理的 clear 套用（Flash 的 clear 是立即的）。

## (c) 「已知與真 Flash 還不同的地方」

| 項目 | 差異 |
| --- | --- |
| `Context3D.configureBackBuffer` wantsBestResolution | 裝置像素比與瀏覽器縮放在這個播放器是同一個視埠縮放係數，`wantsBestResolutionOnBrowserZoom` 單獨開時以呼叫當時的係數為基準算比例；Flash 另外會對 Stage 送 `Event.BROWSER_ZOOM_CHANGE`，這裡沒有送。`backBufferWidth/Height` 回報裝置像素大小，是依 Adobe 對瀏覽器縮放的描述推論，未用真 Flash 量過。 |
| `Context3D.setRenderToTexture` colorOutputIndex | 大小與輸出 0 不同時丟 #3761（Adobe 文件沒有列這個情況；wgpu 的附件必須同大小）；片段程式輸出數與綁定目標數不符時 Flash（enableErrorChecking）丟 #3774，這裡照綁定數補零／丟棄不丟錯；重新設定輸出 0 時只保留同大小的額外輸出，Flash 是否保留未驗證。 |
| `Context3D.drawToBitmapData` | 寬或高為 0 的 `srcRect` 不複製也不丟錯（Flash 行為未驗證）；WebGL／canvas 後端沒有 Context3D，所以沒有此路徑。 |

## (d) queue.json

```json
[
  {
    "class": "flash.display3D.Context3D",
    "status": "done",
    "note": "s3dctx: configureBackBuffer wantsBestResolution/OnBrowserZoom real (DPR-scaled back buffer, 1/scale draw, per-frame re-apply on zoom change, maxBackBuffer cap), setRenderToTexture colorOutputIndex 0..3 = MRT (wgpu extra colour attachments, naga-agal oc0..oc3 outputs, #3770/#3779/#3761, oc4 #3760), drawToBitmapData(destination, srcRect, destPoint) real GPU copy + BitmapData sync path (#3802, #3694, #2015). createTexture BgrPacked/Compressed belong to the texture-format batch. SWF test stage3d_context_leftovers needs a GPU (skipped here)."
  }
]
```
