# render2 批次（DisplayObject.scale9Grid、Stage3D 剩餘項目）

分支 `worktree-agent-a97c691017c21dbbd`（自 PRO_bata 833e6095 切出）。此容器沒有 GPU：`scale9grid_render` 與 `stage3d_leftovers` 兩支測試在這裡是 `ignored`，必須在有 GPU 的機器上執行 `cargo test -p tests --test tests --features imgtests -- scale9grid_render`／`-- stage3d_leftovers`。

## (a) CHANGELOG 條目

- **DisplayObject.scale9Grid 真的做 9 格縮放；Stage3D 貼圖有完整 mip 鏈**：`scale9Grid` 不再只是存起來——物件被自己的矩陣縮放時，內容依九宮格分區各畫一次（每區一個仿射變換加上一個矩形 stencil 遮罩，沿用 scrollRect 的裁切機制），四角不縮、上下邊只橫向拉、左右邊只縱向拉、中央雙向拉；旋轉／斜切／3D 的物件、文字、點陣圖、影片、旋轉過或自帶格線的子物件照常縮放（Adobe 參考的規則）。setter 依 Adobe 參考驗證：矩形不在物件 bounds 內（含負尺寸、物件沒有內容）丟 ArgumentError #2004，null 清除。Stage3D：2 的冪次貼圖（Texture／CubeTexture）在 wgpu 建立完整 mip 鏈，`uploadFromBitmapData`／`uploadFromByteArray` 的 `miplevel` 寫入對應層（不存在的層丟 #3669），`createTexture`／`createCubeTexture` 接受 `streamingLevels`，ATF 檔案的每個面、每一層都上傳，`setSamplerStateAt` 的 mipfilter 真的生效（mipnone 綁定只含第 0 層的 view，避免沒上傳的層滲入；無效值 #2008）；`setRenderToTexture` 的 antiAlias 早已由 wgpu 的多重取樣貼圖＋resolve 實作，移除空殼標記。驗證：新測試 `scale9grid_members`（trace，通過）、`scale9grid_render`（BitmapData.draw + getPixel，需要 GPU）、`stage3d_leftovers`（需要 Context3D）；`-- stage3d` 的 38 支測試中 5 支非 GPU 通過、33 支 ignored；`cargo check -p ruffle_core -p ruffle_render -p ruffle_render_wgpu`（含 `--features ruffle_core/jpegxr`）通過。

## (b) CHANGES-FROM-RUFFLE 段落

### 第 N 組：9 格縮放與 Stage3D mip 鏈（render2）

**flash.display.DisplayObject.scale9Grid**（`core/src/display_object.rs` 的 `render_self_with_scaling_grid`、`core/src/avm2/globals/flash/display/display_object.rs`）：

- 行為：格線只看物件自己的矩陣（`scaleX`／`scaleY`／`width`／`height` 改的那個）；有旋轉或斜切（b、c ≠ 0）或 matrix3d 時整個物件照常縮放。分區以物件未變換的 bounds（含子物件、含筆畫）為準，縮放後整體仍恰好覆蓋 `bounds × scale`；中央區在縮到比四角總和還小時收縮到 0（不反向）。
- 參與對象：物件自己的向量圖（MovieClip／Sprite 的 drawing）、直接子物件中的 Graphic／MorphShape／MovieClip／Avm2Button／LoaderDisplay，且子物件沒有旋轉／斜切／3D、沒有自己的 scale9Grid；Bitmap／EditText／Text／TextLine／Video 子物件照常縮放（Adobe：「all text and gradients are scaled normally」「bitmaps… stretched to fit their shapes」）。子物件依顯示順序分成「參與」連續段，每段畫 9 次。
- 有 timeline 遮罩（clip depth）的容器走原本的路徑（不切）。cacheAsBitmap 的離屏繪製也會切。
- setter：矩形須在 `getBounds(this)` 內，否則 ArgumentError #2004（Adobe：「Throws ArgumentError — If you pass an invalid argument」；社群普遍記錄為 #2004）。沒有內容的物件任何矩形都超出 bounds → #2004。null 清除。Stage 仍是 #2071（原有）。
- 矩形的座標沿用上游 `object_to_rectangle` 的整數像素四捨五入（10.123 → 10）；真 Flash 可能保留 twips 精度——未驗證，列在 (c)。

**flash.display3D（Context3D、Texture、CubeTexture）**（`render/src/backend.rs`、`render/wgpu/src/context3d/mod.rs`、`current_pipeline.rs`、`core/src/avm2/object/context3d_object.rs`、`core/src/avm2/globals/flash/display3D/**`）：

- `createTexture`／`createCubeTexture`：寬高都是 2 的冪次時建立完整 mip 鏈（到 1×1），`streamingLevels` 不再拒絕（Flash 的 streamingLevels 只是告訴播放器哪些層會晚點到，不需要另外的儲存）；RectangleTexture 仍是單層（Flash 也沒有 mipmap）。新的 `Texture::mip_level_count()`。
- `uploadFromBitmapData(source, miplevel)`／`uploadFromByteArray(data, offset, miplevel)`（Texture 與 CubeTexture 的 side 版本）：寫入第 n 層（`CopyBitmapToTexture` 多了 `mip_level`），來源要能放進該層（允許較小的部分上傳，如上游）；miplevel ≥ 層數丟 ArgumentError #3669（「Bad input size」——Flash 對尺寸不符用這個碼；精確碼未以真 Flash 驗證）。
- ATF（`uploadCompressedTextureFromByteArray`）：檔案裡每個面、每一層都解碼上傳（之前只上傳第 0 層）。
- `setSamplerStateAt(…, mipfilter)`：`mipnone`／`mipnearest`／`miplinear` 傳到 wgpu（naga_agal 的 Mipmap），無效字串 #2008；mipnone 時綁定只含第 0 層的 texture view，避免從未上傳的 mip 層被取樣成黑色。
- `setRenderToTexture(…, antiAlias)`：wgpu 後端本來就以 antiAlias 的取樣數建立多重取樣貼圖並 resolve 到目標，只是留著空殼標記——移除；WebGL 上仍會退回 1（上游警告）。
- 還是空殼（見 (d)）：`createTexture` 的 BGR_PACKED／COMPRESSED 格式（存成 RGBA8，上傳自 BitmapData 可用，但沒有 565 量化、DXT1 需要 BC 功能或 CPU 解碼器）、`setRenderToTexture` 的 colorOutputIndex > 0（多重渲染目標；Flash 只在 standard profile 支援，錯誤碼未查到）、`configureBackBuffer` 的 wantsBestResolution／wantsBestResolutionOnBrowserZoom（需要把 back buffer 乘上裝置像素比並在 Stage3D 繪製時縮回——設計：Context3DObject 記住比例、`render()` 乘 1/比例、backBufferWidth 回報放大後的值）、`drawToBitmapData`（需要把 front buffer 經 `render_offscreen` + sync 讀回 BitmapData：可用 `commands.render_stage3d(handle, transform)` 配合 BitmapData.draw 的 readback 路徑）、Texture／CubeTexture 的非 BGRA `uploadFromByteArray` 與不支援的 ATF 格式（RawCompressed DXT1／ETC1／ETC2／PVRTC：Cargo.lock 沒有解碼器 crate，wgpu 的 BC／ETC2 功能要看 adapter）。

## (c) 「已知與真 Flash 還不同的地方」

| 項目 | 狀況 |
|---|---|
| `DisplayObject.scale9Grid` 的矩形精度 | 沿用上游整數像素四捨五入；真 Flash 可能保留 twips（0.05 px）精度，未驗證。 |
| `scale9Grid` 中央區縮到負寬度時 | 這裡收縮到 0（四角相接）；真 Flash 的行為未驗證。 |
| `scale9Grid` 容器含 timeline 遮罩（clip depth） | 不切，整體照常縮放。 |
| `Texture.uploadFromBitmapData` miplevel 超出層數 | 丟 #3669；真 Flash 的錯誤碼未驗證。 |
| 9 格縮放／mip 鏈的像素結果 | 此容器沒有 GPU，`scale9grid_render`、`stage3d_leftovers` 與 33 支 stage3d 測試未執行。 |

## (d) queue.json

```json
[
  {"class": "flash.display.DisplayObject", "status": "done", "note": "render2: scale9Grid real 9-slice rendering (per-region transform + stencil clip in render_base, own matrix only, rotated/3D/text/bitmap/video excluded per reference), setter #2004 when the rect is outside getBounds(this) or the object is empty, null clears. Tests scale9grid_members (pass) + scale9grid_render (needs GPU, not run here)."},
  {"class": "flash.display3D.Context3D", "status": "partial", "note": "render2: setSamplerStateAt mipfilter real (mip chains), setRenderToTexture antiAlias marker removed (wgpu MSAA resolve already real), createTexture streamingLevels accepted. Left: createTexture BgrPacked/Compressed (RGBA8 storage, no 565/DXT1), setRenderToTexture colorOutputIndex>0 (MRT), configureBackBuffer wantsBestResolution* (needs DPR-scaled back buffer + 1/scale draw), drawToBitmapData (front-buffer readback via render_offscreen)."},
  {"class": "flash.display3D.textures.Texture", "status": "partial", "note": "render2: uploadFromBitmapData/uploadFromByteArray at any miplevel (#3669 beyond the chain), ATF uploads fill all levels. Left: uploadFromByteArray for non-BGRA formats, uploadCompressedTextureFromByteArray for unsupported ATF formats (raw DXT1/ETC/PVRTC: no decoder crate)."},
  {"class": "flash.display3D.textures.CubeTexture", "status": "partial", "note": "render2: untested markers removed, per-side mip uploads real (#3669 beyond the chain). Left: uploadCompressedTextureFromByteArray for non-BGRA formats."}
]
```
