# s3dtex 批次：Stage3D 貼圖格式（Context3D.createTexture 的壓縮／打包格式、ATF 上傳）

## (a) CHANGELOG 條目

- **第 4 組（Stage3D）：貼圖格式**：`Context3D.createTexture`／`createCubeTexture` 的 `bgrPacked565`、`bgraPacked4444`、`compressed`、`compressedAlpha` 不再是空殼。打包格式存成 RGBA8，但每次上傳都量化成 5-6-5／4-4-4-4 再展開，取樣精度與 Flash 相同；`uploadFromByteArray` 照格式讀每像素 2（打包，小端 u16）、4（BGRA；壓縮格式亦同，執行期壓縮）或 8（半精度浮點，原樣送 GPU）位元組。壓縮格式在轉接器有 `TEXTURE_COMPRESSION_BC` 時真的存成 BC1／BC3（DXT1／DXT5），有 `TEXTURE_COMPRESSION_ETC2` 時存成 ETC2 RGB／RGBA，否則存 RGBA8；`uploadFromBitmapData`／`uploadFromByteArray` 對壓縮貼圖照桌面版 Flash 做執行期 DXT 壓縮（BC 儲存：以新寫的 BC1／BC3 編碼器壓；RGBA8 儲存：編碼再解碼，精度損失一樣），ETC2 儲存（Adobe 文件的「行動平台不支援執行期壓縮」）丟 `ArgumentError #3675`。`Texture`／`CubeTexture.uploadCompressedTextureFromByteArray` 的 ATF 容器完整解析：格式 3／5（RAW_COMPRESSED／RAW_COMPRESSED_ALPHA：DXT、PVRTC、ETC1、ETC2 四筆原始資料，版本 < 3 三筆）、格式 2（COMPRESSED：LZMA 查表 + JPEG-XR 端點重組成 DXT1，與既有 COMPRESSED_ALPHA 的 RGB 半邊相同作法）、格式 0／1／4 沿用；貼圖原生儲存 DXT 時直接上傳 DXT 資料、ETC2 時上傳 ETC2（沒有則 ETC1，RGBA 貼圖用不透明 EAC 區塊包起來），RGBA8 儲存時由新模組 `render/src/compressed.rs` 的 CPU 解碼器（DXT1 含 1 位元 alpha、DXT5、ETC1、ETC2 RGB／RGBA 含 T／H／平面模式與 EAC alpha、PVRTC 4bpp 含 Morton 排序、雙線性放大與 punch-through）解成 RGBA8；錯誤碼照 Adobe 文件：資料太短 `RangeError #3669`、解碼失敗或 ATF 版本高於 SWF 允許（v2 需 SWF ≥ 21、v3 需 ≥ 29）`#3677`、尺寸不符 `#3679`、格式不符（cube／非 cube、檔案沒有該貼圖能收的資料）`#3675`、`miplevel` 超出 `#3674`（之前用 #3669）。wgpu 的貼圖上傳對小於 4×4 的 mip 層與每列未對齊 256 的區塊資料也修正（之前 DXT5 小 mip 會觸發 wgpu 驗證錯誤）。驗證：`cargo test -p ruffle_render --lib compressed`（9 個手算向量的單元測試：565／4444 量化與位元組佈局、DXT1 四色／三色、DXT5 八階／六階 alpha、DXT 編碼往返、ETC1 個別／差分、ETC2 T／H／平面、EAC、PVRTC 單區塊與插值／Morton）、`cargo check` 三個 crate 與 wasm、clippy；新 SWF 測試 `stage3d_texture_formats`（需要 Context3D，本容器無 GPU 未執行）。

## (b) CHANGES-FROM-RUFFLE 段落

### 第 N 組：Stage3D 貼圖格式（s3dtex）

**flash.display3D.Context3D.createTexture／createCubeTexture 的格式**（`render/wgpu/src/context3d/mod.rs` `convert_texture_format`、`render/wgpu/src/backend.rs` 的可選功能、`render/src/backend.rs` `Texture::compressed_format`）：

- `bgrPacked565`／`bgraPacked4444`：wgpu 並非每個後端都有可取樣的 565／4444 格式，所以存 RGBA8；上傳時量化（`compressed::quantize_rgb565`／`quantize_rgba4444`：捨去低位、再以 Flash／GPU 的位元複製法展開，例如 128 → 130、7 → 0，565 的 alpha 固定 255），取樣結果與真的 16 位元貼圖一樣。
- `compressed`（DXT1）／`compressedAlpha`（DXT5）：裝置功能有 `TEXTURE_COMPRESSION_BC` 時建 `Bc1RgbaUnorm`／`Bc3RgbaUnorm`，有 `TEXTURE_COMPRESSION_ETC2`（現在列為可選功能）時建 `Etc2Rgb8Unorm`／`Etc2Rgba8Unorm`，都沒有時 RGBA8。壓縮貼圖不能當 render attachment（之前 Bc3 已如此）。`Texture::compressed_format()` 告訴 core 貼圖實際存什麼。`totalGPUMemory` 的計算不變（0.5／1 位元組每像素）。
- 空殼 `check_texture_stub` 整個移除。`rgbaHalfFloat` 維持 `Rgba16Float`。

**Texture／CubeTexture.uploadFromBitmapData／uploadFromByteArray**（`core/src/avm2/globals/flash/display3D/textures/texture.rs` `upload_rgba`／`do_copy`／`do_copy_bitmap_data`，CubeTexture 共用）：

- 每種格式都真的上傳：BGRA 照舊；打包格式量化；`compressed`／`compressedAlpha` 照 Adobe 文件只在「行動平台不支援執行期貼圖壓縮」時丟 `ArgumentError #3675`，桌面版會執行期壓縮——BC 儲存時用新的 BC1／BC3 編碼器（端點取最亮／最暗像素、每像素取最近的調色盤項；alpha 取最大／最小的 8 階），RGBA8 儲存時編碼後再解碼（精度損失與真的壓縮一致），ETC2 儲存（行動 GPU）丟 #3675；`rgbaHalfFloat` 的 BitmapData 轉半精度（自寫 f32→f16 捨入到偶數）。
- `uploadFromByteArray` 每像素位元組數依格式：BGRA／壓縮 4、打包 2（小端 u16：565 為 r 15..11、g 10..5、b 4..0；4444 為 a 15..12、r 11..8、g 7..4、b 3..0——Adobe 參考沒有寫佈局，採 Starling／OpenFL 的解讀，見 (c)）、半精度 8（原樣）；`byteArrayOffset` 起不足該層所需位元組 → `RangeError #3669`「Bad input size」（之前是 panic）。
- `miplevel` 超出層數 → `ArgumentError #3674`「Miplevel too large」（Adobe 文件的錯誤名稱；上一批用 #3669）。來源比該層大 → #3675（Adobe「Invalid BitmapData Error」，碼未查到，見 (c)）。
- `Context3DObject::copy_pixels_to_texture` 改為接「貼圖自己儲存佈局的位元組 + 來源寬高」，RGBA8 像素或 DXT／ETC2 區塊都走同一條 `CopyBitmapToTexture`；wgpu 端的複製改用區塊數向上取整計算每列位元組、複製範圍進位到區塊大小、每列一律補到 256 對齊（之前 DXT5 的 4×4 以下 mip 層與 16 像素寬的列會違反 wgpu 的對齊規則）。

**Texture／CubeTexture.uploadCompressedTextureFromByteArray（ATF）**（`render/src/atf.rs`、`core/.../textures/atf_upload.rs`（新）、`atf_jpegxr.rs`（只剩 JPEG-XR 解碼，錯誤改為回傳而非 panic）、`atf_jpegxr_stub.rs`）：

- 容器：格式 3／5 解析成 `ATFTextureData::Raw { alpha, dxt, pvrtc, etc1, etc2 }`（版本 ≥ 3 四筆紀錄，否則三筆，與 OpenFL 的 ATFReader 相同；用 `tests/.../stage3d_texture_bytearray_compressed_raw_alpha/circle.atf`（v3、512×512、10 層、只有 DXT5）核對過紀錄長度），格式 2 解析成 `CompressedDxt1 { LZMA 查表, JPEG-XR 端點 }` 並略過其後 9 筆 PVRTC／ETC1 紀錄；格式 0／1（JPEG-XR）、4（COMPRESSED_ALPHA）沿用；0xc／0xd（COMPRESSED_LOSSY）仍只合併成 `Unknown`，上傳時 #3677（佈局沒有可靠來源）。新增 `ATFTexture.version`。
- 上傳：先查 `byteArrayOffset + 6 > length` → `RangeError #3669`；解析失敗 → `#3677`；ATF v3 配 SWF < 29 或 v2 配 SWF < 21 → `#3677`（Adobe 文件明文）；尺寸不符 `#3679`、cube／非 cube 不符 `#3675`（原有）。每個面、每一層依貼圖儲存格式挑資料：BC 儲存要 DXT（alpha 格式對 `compressedAlpha`、非 alpha 對 `compressed`，否則 #3675）；ETC2 儲存要 ETC2，沒有則 ETC1（RGBA 貼圖把每個 ETC1 區塊前面加一個不透明 EAC 區塊：base 255、乘數 0）；RGBA8 儲存（含 `bgra` 貼圖，維持上游行為）依序用 DXT → ETC2 → ETC1 → PVRTC 的 CPU 解碼器；JPEG-XR 類資料（格式 0／1／2／4）解出 RGBA8 或 DXT 區塊後同樣處理（ETC2 儲存收不到 → #3675）。`async=true` 仍是 AS 端 `setTimeout` 後上傳並派送 `textureReady`。
- `render/src/compressed.rs`（新，純 Rust、無新依賴）：`decode_dxt1`（c0 ≤ c1 時第 4 色是透明黑）、`decode_dxt5`（8 階／6 階 alpha）、`encode_dxt1`／`encode_dxt5`、`decode_etc2_rgb`（ETC1 個別／差分 + ETC2 的 T、H、平面模式，位元佈局依 Khronos Data Format Specification）、`decode_etc2_rgba`（EAC alpha 16×8 修正表）、`etc2_rgb_to_rgba_opaque`、`decode_pvrtc_4bpp`（Imagination 參考解壓器的作法：區塊 Morton 排序 `TwiddleUV`、A／B 兩個顏色面以 4×4 視窗雙線性放大（權重 (4-i)(4-j) 等）、5 位元 ×16 後以 `(v>>6)+(v>>1)` 展開、2 位元調變值 0/3/5/8 或 punch-through 0/4/4+alpha0/8），以及 565／4444 的量化與位元組轉換。9 個單元測試全部以手算的區塊為準。
- 仍是空殼：無。ASTC 不在 ATF 規格裡，沒有做。

## (c) 「已知與真 Flash 還不同的地方」表格列

| 項目 | 說明 |
|---|---|
| Stage3D 打包格式的 `uploadFromByteArray` 位元組佈局 | Adobe 參考沒有寫 565／4444 的 ByteArray 佈局；採小端 u16（565：r 15..11／g 10..5／b 4..0；4444：a 15..12／r 11..8／g 7..4／b 3..0，Starling／OpenFL 的解讀），未以真 Flash 驗證。 |
| Stage3D 壓縮貼圖的執行期壓縮 | 桌面 Flash 把 BitmapData 上傳到 `compressed`／`compressedAlpha` 貼圖時做 DXT 壓縮；Timffle 的 BC1／BC3 編碼器（最亮／最暗端點、最近調色盤項）比 Flash 的編碼器簡單，壓縮後的顏色可能略有不同（量化等級相同）。 |
| Stage3D 貼圖上傳的錯誤碼 | `#3674`（miplevel）、`#3677`（解碼失敗／ATF 版本）、`RangeError #3669`（資料太短）、`#3675`（格式不符）依 Adobe 文件的錯誤名稱對應 `error_messages.rs`；來源比 mip 層大的「Invalid BitmapData Error」碼查不到，用 #3675。ATF 上傳到 `bgra` 貼圖維持上游的「接受並解碼」，真 Flash 是否接受未驗證。 |
| Stage3D 在 ETC2-only 的 GPU | 壓縮貼圖存成 ETC2 時，`uploadFromBitmapData` 丟 #3675、只含 DXT 的 ATF 丟 #3675——與 Flash 在行動平台相同，但 `stage3d_texture_formats` 的黃金輸出是桌面行為（BC 或 RGBA8 儲存）。 |
| Stage3D 測試 | 本容器沒有 GPU：`stage3d_texture_formats`（以及既有的 `stage3d_*` ATF 影像測試）無法執行，黃金輸出依 Adobe 文件與實作語意手寫；`cargo test -p ruffle_render --lib compressed` 的 9 個解碼器單元測試有跑。合併後請在有 GPU 的機器跑 `cargo test -p tests --test tests -- stage3d`。 |

## (d) queue.json

```json
[
  {"class": "flash.display3D.Context3D", "status": "partial", "note": "s3dtex: createTexture BgrPacked/BgraPacked (quantised RGBA8), Compressed/CompressedAlpha (BC1/BC3 native when TEXTURE_COMPRESSION_BC, ETC2 when TEXTURE_COMPRESSION_ETC2, else RGBA8 + CPU codecs); check_texture_stub removed. Left: configureBackBuffer wantsBestResolution*, drawToBitmapData, setRenderToTexture colorOutputIndex>0."},
  {"class": "flash.display3D.textures.Texture", "status": "done", "note": "s3dtex: uploadFromBitmapData/uploadFromByteArray for every format (packed quantised, compressed runtime-DXT or #3675 on ETC2 storage, half float), RangeError #3669 short data, #3674 miplevel; uploadCompressedTextureFromByteArray parses ATF 0/1/2/3/4/5 fully, GPU-native DXT/ETC2 upload or CPU decode (DXT1/DXT5/ETC1/ETC2/PVRTC in render/src/compressed.rs), #3677/#3679/#3675 per Adobe; COMPRESSED_LOSSY (0xc/0xd) -> #3677 (layout unknown)."},
  {"class": "flash.display3D.textures.CubeTexture", "status": "done", "note": "s3dtex: same paths as Texture for all six faces."}
]
```
