# 待合併：stage3d 批（第 4 組 flash.display3D）

## (a) CHANGELOG 條目

- **Stage3D API 補齊（第 4 組，部分）**：`Context3D` 新增 `totalGPUMemory`（真的統計此 context 持有的索引緩衝、頂點緩衝、貼圖、程式的位元組數；建立時加、`dispose()` 時減），`backBufferWidth`／`backBufferHeight`（最後一次成功 `configureBackBuffer()` 的大小，未設定前 0）、`maxBackBufferWidth`／`maxBackBufferHeight`（預設 16384 = 平台上限；設定值夾在「32 或最後一次成功設定的大小」與 16384 之間，`configureBackBuffer()` 超過上限會丟 #3780／#3781，SWF 30 以前 #3669）、`driverInfo`（由 wgpu 轉接器資訊組成 `"<API> (<模式>) Vendor=… Version=… Renderer=…"`，`dispose()` 後回 `"Disposed"`）、`createVideoTexture()`（本播放器沒有硬體影片轉貼圖，`supportsVideoTexture` 為 false，依文件回 `null`）、`dispose(recreate)`（真的釋放 wgpu 端 context 與所有資源，`Stage3D.context3D` 變 null，之後呼叫任何方法丟 Error #3694「The object was disposed by an earlier call of dispose() on it」；`recreate=true` 時以同一 profile 重新請求並在該幀結束時再次派送 `context3DCreate`）；`setSamplerStateAt` 的 anisotropic 過濾器 wgpu 早已套用（`anisotropy_clamp`），移除過時的空殼標記。`IndexBuffer3D`／`VertexBuffer3D`／`Program3D`／`TextureBase.dispose()` 真的丟掉 GPU 緩衝／著色器模組／貼圖（Rc／Box 釋放），之後上傳或綁定丟 #3694。`VideoTexture` 補齊 `attachCamera`／`attachNetStream`／`videoWidth`／`videoHeight`（永遠拿不到實例，見下）。`CubeTexture.uploadCompressedTextureFromByteArray` 的 `async` 參數改成和 `Texture` 一樣（複製資料、setTimeout 上傳、派送 `textureReady`）。驗證：`cargo check -p ruffle_core -p ruffle_render_wgpu` 通過；新增測試 `stage3d_members`（本機容器沒有 GPU，需要 Context3D 的路徑未能在此執行，見 (c)）。

## (b) CHANGES-FROM-RUFFLE 段落

### 第 4 組：Stage3D（flash.display3D）

- **Context3D**
  - `dispose(recreate:Boolean = true)`：`Context3DObject::dispose()` 把 `render_context` 丟掉（wgpu 的 `WgpuContext3D` 連同所有緩衝、貼圖、pipeline 一起釋放），設 `disposed`，`Stage3D` 狀態清成 None；`recreate` 為 true 時重新設成 `Requested{profile}`，由既有的幀末流程重建並派送 `context3DCreate`（Flash 文件：若不想要，先移除監聽或傳 false）。所有 native 方法開頭 `check_disposed()` → `Error #3694`。再次 `dispose()` 不做事。
  - `backBufferWidth`／`backBufferHeight`：`configureBackBuffer()` 成功後記下的大小；未設定前 0。
  - `maxBackBufferWidth`／`maxBackBufferHeight`：預設 16384；setter 夾到 `[max(32, 最後成功設定的寬/高), 16384]`；`configureBackBuffer()` 超過時丟 #3780／#3781（SWF < 30 丟 #3669，與既有 32…16384 檢查一致）。
  - `totalGPUMemory`：索引緩衝 = `numIndices × 2`；頂點緩衝 = `numVertices × data32PerVertex × 4`；貼圖 = 寬 × 高 × 每像素位元組（BGRA 4、BGRA_PACKED／BGR_PACKED 2、COMPRESSED ½、COMPRESSED_ALPHA 1、RGBA_HALF_FLOAT 8；`streamingLevels > 0` 算整條 mip 鏈；CubeTexture × 6）；程式 = 上傳的 AGAL 位元組數（編譯後大小無法得知）。`dispose()` 減回，context 本身 `dispose()` 歸 0。只算 Flash 文件列的四類，不含後緩衝。
  - `driverInfo`：新增 `Context3D::driver_info()` trait 方法（`render/src/backend.rs`），wgpu 實作用 `adapter.get_info()`：API 名（Vulkan／Metal／Direct3D12／OpenGL／WebGPU）、`DeviceType::Cpu` 時標 `Software` 否則 `Direct Mode`、`Vendor=driver`、`Version=driver_info`、`Renderer=name`。
  - `createVideoTexture()`：先做 #3694 檢查，再回 `null`（文件：「returns null if the system doesn't support this feature」）。
  - `setSamplerStateAt`：anisotropic 的空殼標記移除（wgpu `current_pipeline.rs` 早已把 `Anisotropic2x…16x` 變成 `anisotropy_clamp`）；`mipfilter != "mipnone"` 仍是空殼（wgpu 端所有貼圖 `mip_level_count = 1`，需要 mip 鏈與 `miplevel` 上傳才能做）。
- **IndexBuffer3D / VertexBuffer3D / Program3D / TextureBase**：`dispose()` 改成 native；物件的 handle 改成 `RefCell<Option<…>>`，`dispose()` 取走（Box／Rc 釋放 → wgpu 資源釋放；被 pipeline 綁定中的貼圖在解除綁定後釋放），並從 `totalGPUMemory` 扣除；`uploadFrom*`、`upload()`、`setVertexBufferAt`、`setProgram`、`drawTriangles`、`setTextureAt`、`setRenderToTexture` 對已 dispose 的物件丟 #3694。`new TextureBase()` 沒有 GPU 貼圖，`dispose()` 不做事。
- **VideoTexture**：補 `attachCamera`／`attachNetStream`／`videoWidth`／`videoHeight`。沒有硬體影片轉貼圖 → `supportsVideoTexture` false、`createVideoTexture()` null，類別仍是 abstract（`new` 丟 #2012），所以永遠拿不到實例；成員以「未附加來源」行為實作（記錄來源、null 解除、寬高 0）。
- **CubeTexture.uploadCompressedTextureFromByteArray(async)**：AS 端和 `Texture` 相同；native 改名 `…Internal`。

## (c) 「已知與真 Flash 還不同的地方」

| 項目 | 說明 |
|---|---|
| `Context3D.driverInfo` 字串 | 格式仿 Flash 的 `OpenGL Vendor=… Version=… Renderer=…`，但內容來自 wgpu 轉接器；`dispose()` 後回 `"Disposed"` 是依 OpenFL／常見實作，沒有用真 Flash 驗證。 |
| `maxBackBufferWidth/Height` 超出範圍 | 文件只說「不能大於系統上限、不能小於 32／最後設定值」，沒說丟什麼錯；這裡夾值不丟錯。 |
| `totalGPUMemory` 的程式大小 | 用 AGAL 位元組數代替驅動程式實際配置量。 |
| Stage3D 測試 | 本容器沒有 Vulkan ICD／EGL，wgpu 找不到轉接器：`stage3d_members` 只涵蓋不需要 context 的部分（`supportsVideoTexture`、`new VideoTexture()` #2012、`TextureBase.dispose()`、`stage3Ds`）；`dispose()`→#3694、`totalGPUMemory`、`backBuffer*`、`maxBackBuffer*` 的程式碼只經 `cargo check` 與人工閱讀，未在此機器執行。合併後請在有 GPU 的機器跑 `cargo test -p tests --test tests -- stage3d`。 |

## 未完成（這批沒做）

- `Context3D.configureBackBuffer` 的 `wantsBestResolution`／`wantsBestResolutionOnBrowserZoom`（需要以 `contentsScaleFactor` 放大後緩衝；未做）。
- `Context3D.createTexture` 的 `BgrPacked`／`Compressed` 格式（wgpu 端的格式轉換未驗證，標記保留）。
- `Context3D.drawToBitmapData`（需要在 `WgpuContext3D` 加後緩衝讀回：把 back buffer 貼圖 copy 到 buffer、map、寫進 BitmapData；未做）。
- `Context3D.setRenderToTexture` 的 `antiAlias != 0`（wgpu 已用 sample_count，但標記未移除因為未驗證）與 `colorOutputIndex != 0`（需要 MRT）。
- `Context3D.setSamplerStateAt` 的 `mipfilter`（見上）。
- `Texture`／`CubeTexture`／`RectangleTexture` 的 `miplevel != 0` 上傳與 ATF 不支援格式（需要 mip 鏈貼圖與 ETC1／PVRTC／DXT 解碼器）；`CubeTexture.uploadFromByteArray`／`uploadCompressedTextureFromByteArray` 的「未測試」標記保留。
- 停放的 display 項目（`Graphics.readGraphicsData`、`beginShaderFill`／`lineShaderStyle`、`DisplayObject.scale9Grid`、`BitmapData.applyFilter` ShaderFilter）：時間不足，未動。

## (d) queue.json

```json
[
  {"class": "flash.display3D.Context3D", "status": "partial", "note": "stage3d batch: totalGPUMemory, backBufferWidth/Height, maxBackBufferWidth/Height, driverInfo, createVideoTexture (null, supportsVideoTexture false), dispose (#3694 + wgpu release + recreate), setSamplerStateAt anisotropic real. Left: configureBackBuffer wantsBestResolution*, createTexture BgrPacked/Compressed, drawToBitmapData (needs wgpu readback), setRenderToTexture antiAlias/colorOutputIndex markers, setSamplerStateAt mipfilter (textures have 1 mip level)."},
  {"class": "flash.display3D.IndexBuffer3D", "status": "done", "note": "dispose real (buffer dropped, #3694 afterwards)."},
  {"class": "flash.display3D.Program3D", "status": "done", "note": "dispose real (shader module dropped, #3694 afterwards)."},
  {"class": "flash.display3D.VertexBuffer3D", "status": "done", "note": "dispose real (buffer dropped, #3694 afterwards)."},
  {"class": "flash.display3D.textures.TextureBase", "status": "done", "note": "dispose real (texture dropped, #3694 afterwards)."},
  {"class": "flash.display3D.textures.VideoTexture", "status": "done", "note": "attachCamera/attachNetStream/videoWidth/videoHeight; instances never obtainable (createVideoTexture returns null, supportsVideoTexture false)."},
  {"class": "flash.display3D.textures.CubeTexture", "status": "partial", "note": "async upload real (textureReady). Left: 'untested' markers on uploadFromByteArray/uploadCompressedTextureFromByteArray, miplevel != 0, unsupported ATF formats."},
  {"class": "flash.display3D.textures.Texture", "status": "todo", "note": "miplevel != 0 uploads need mip-chain textures in wgpu; ATF formats beyond BGRA/DXT5 need decoders."}
]
```
