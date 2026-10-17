# 品牌：Timffle 與 Ruffle 的名稱

## 原則

- **Ruffle 的程式碼可以用，Ruffle 的名字與標誌不能當我們的產品名稱用。** Ruffle 以 MIT 或 Apache-2.0 授權，兩者都允許修改與散布程式碼，但都**不授予商標權**（Apache-2.0 第 6 條明文排除；MIT 根本不涉及）。「Ruffle」名稱與標誌屬於 Ruffle 專案（Ruffle LLC）。
- 所以：使用者**看得到的產品名稱、圖示、標題、「關於」、錯誤回報與更新連結**都必須是 Timffle；提到 Ruffle 時只能是**描述性**的（「Ruffle 的非官方分支」「基於 Ruffle」「Ruffle wiki」），而且不能讓人以為 Timffle 是 Ruffle 官方或得到 Ruffle 認可。
- **致謝不能拿掉**：Ruffle 的授權檔、著作權聲明、git 歷史與作者紀錄全部保留；README、NOTICE、選項頁、發行包的 README.txt 都明寫 Timffle 來自 Ruffle 與其貢獻者。
- 新名字同時也避開了遊戲名稱（淘米的商標）。

## 已改成 Timffle 的地方（網頁版）

| 位置 | 內容 | 怎麼維護 |
|---|---|---|
| `web/packages/extension/manifest.json5` | `name`「Timffle - Flash Emulator」、`short_name`、`homepage_url` → Timffle repo | 手改；`rebrand.py --check` 會檢查 |
| `web/packages/extension/build.ts` | Firefox 附加元件 ID 改成 Timffle 自己的 `{4244f375-9038-4a8d-bc77-e47e6cc7a426}`（`ruffle@ruffle.rs` 屬於官方 Ruffle 附加元件） | 手改；有檢查 |
| `web/packages/extension/assets/*.html` | 頁面標題、文字、`alt`、標誌連結 | `rebrand.py` 自動 |
| `web/packages/extension/assets/options.html` | 頁尾的非官方分支聲明與致謝（`class="timffle-attribution"`，雙語、`translate="no"`，刻意提到 Ruffle 並連到 ruffle.rs） | 手改；`rebrand.py` 跳過這一段；有檢查 |
| `web/packages/extension/assets/_locales/*/messages.json` | 擴充功能的所有語系文字 | `rebrand.py` 自動 |
| `web/packages/core/texts/*/*.ftl` | 播放器的右鍵選單（「關於 Timffle」）、錯誤畫面、提示等所有語系文字 | `rebrand.py` 自動 |
| `web/packages/core/src/internal/constants.tsx` | 新增 `TIMFFLE_REPOSITORY` | 手改 |
| `web/packages/core/src/internal/ui/panic.tsx` | 錯誤畫面的「回報錯誤」開 **Timffle** 的 issue（`.github/ISSUE_TEMPLATE/error_report.md`）；「更新」連到 Timffle Releases | 手改；有檢查 |
| `web/packages/core/src/internal/player/inner.tsx` | 右鍵「關於 Timffle」開 Timffle repo | 手改；有檢查 |
| `web/packages/core/src/internal/ui/splash-screen.tsx` | 載入畫面的字標（原本是 RUFFLE 字標） | `timffle/branding/make_branding.py` 產生；有檢查 |
| 擴充功能與 Demo 的圖示、`logo.svg` | Timffle 自己的圖示與字標 | `timffle/branding/make_branding.py` 產生 |
| `web/packages/demo/index.html`、`navbar.tsx` | 網頁 Demo 的標題、標誌與連結 | `rebrand.py` 自動＋手改 |
| 連線小幫手 | `timffle-socket-helper`、Native Messaging `timffle_socket_helper`、資料夾 `TimffleSocketHelper`、發行包 `timffle-chrome-<版本>.zip` | 本來就是 Timffle 的程式碼 |

**錯誤回報導向 Timffle 特別重要**：Timffle 的錯誤不應該變成 Ruffle 維護者的負擔。

## 刻意保留「Ruffle」的地方

| 項目 | 為什麼保留 |
|---|---|
| 「Ruffle wiki」的文字與連結 | 連結真的指向 Ruffle 的 wiki（自架設定、CORS、MIME 類型等說明對 Timffle 一樣適用）；說成「Timffle wiki」反而不實。`rebrand.py` 以「Ruffle 旁邊 16 個字元內、同一句子裡有 wiki／ウィキ／위키／вики…」辨認 |
| 錯誤畫面的「網頁 Demo」「桌面應用程式」連結到 ruffle.rs | 那些是 Ruffle 的產品，標籤本身不寫 Ruffle；Timffle 沒有桌面版 |
| 程式碼識別名稱與公開 API：`ruffle_core`、`ruffle_web` 等 crate、`window.RufflePlayer`、`<ruffle-player>`／`<ruffle-embed>`、`RufflePlayer.config`、npm workspace 名稱（`ruffle-core`、`ruffle-extension`）、CSS 變數 `--ruffle-*`、`ruffle_extension.zip` | 網站是照 Ruffle 的 API 寫設定的，改名會破壞相容性；也會讓每次跟進上游都產生大量衝突。這些是程式內部名稱，不是產品名稱 |
| 原始碼註解、開發者記錄（`console.log`）、Rust 核心的警告文字 | 給開發者看，描述性提及 |
| `Cargo.toml` 的 `authors`、`homepage`、`repository` | 那是 Ruffle crate 的作者與來源資訊（我們不發布 crate）；保留作者是致謝 |
| `LICENSE.md`、`web/LICENSE.md`、擴充功能 `LICENSE_MIT`／`LICENSE_APACHE` | 授權檔與著作權聲明**必須**原樣保留 |
| `README.ruffle.md`、`CONTRIBUTING.md`、`CODE_OF_CONDUCT.md` | 上游文件原樣保留（後兩者在開頭加了 Timffle 的說明） |

## 還沒改、因此**不能**以 Timffle 名義散布的部分

Timffle 目前只發行 Chrome 擴充功能。下列部分仍是上游 Ruffle 的名稱、圖示與識別碼，**散布它們的建置前必須先完成改名**：

- **桌面版**（`desktop/`）：視窗標題、關於對話框與 `about_logo.png`、`desktop/assets/texts/*.ftl`、各平台打包（`desktop/packages/`：Windows MSI、macOS bundle、Linux desktop 檔、Flatpak 的 `rs.ruffle.Ruffle` ID）、設定資料夾名稱。
- **Safari 擴充功能**（`web/packages/extension/safari/`）：bundle ID `rs.ruffle.*`。
- **npm 套件**（`web/packages/selfhosted/npm-package.json5`、`web/packages/core/package.json`）：套件名稱是 Ruffle 的（例如 `@ruffle-rs/ruffle`），不要發布；自架播放器的畫面文字已經是 Timffle（共用 core 的文字）。
- **Firefox**：附加元件 ID 已換成 Timffle 的，但沒有在 Firefox 上測試過。

做法：擴充 `timffle/scripts/rebrand.py`（例如加入 `desktop/assets/texts/**`），並把圖示加進 `timffle/branding/make_branding.py`；同時在本檔更新表格。

## 每次跟進上游後

```sh
python3 timffle/scripts/rebrand.py           # 上游新增或 Crowdin 翻譯更新的文字重新換名
python3 timffle/scripts/rebrand.py --check   # 也會檢查上面「手改」的地方有沒有在合併時被蓋掉
python3 timffle/branding/make_branding.py --check
```

`timffle/scripts/build-extension.sh` 建置前會自動跑這兩個檢查。看一下 `git diff` 確認換名的結果自然（例如韓文助詞、芬蘭文的所有格會跟著名稱變化，`rebrand.py` 只換字，不調整文法）。

## 標誌與圖示

`timffle/branding/make_branding.py` 用純幾何圖形（矩形與多邊形，不依賴字型）產生 Timffle 的字標與圖示，刻意與 Ruffle 的標誌不同（藍色、直立方塊字、「T」圖示）。這是 Timffle 的原創作品，以本 repo 的授權（MIT 或 Apache-2.0）提供。要換設計：改這支程式後執行它，產生的檔案（`timffle/branding/*.svg`、擴充功能與 Demo 的 `logo.svg`／`icon*.png`、載入畫面的 `splash-logo.tsx.txt`）一起 commit，並把 `splash-logo.tsx.txt` 的內容貼回 `splash-screen.tsx`。

## 尚未確認的事

- 沒有找到 Ruffle 公開的商標政策，也沒有查過商標註冊資料；以上做法是保守的一般做法（不把別人的名稱與標誌當成自己產品的名稱），不是法律意見。
- 「Timffle」這個名字本身是否與既有商標衝突，沒有查過。
