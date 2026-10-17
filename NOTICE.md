# NOTICE／聲明

Timffle — an unofficial fork of Ruffle, the Flash Player emulator.
Copyright (c) 2018-2022 Ruffle LLC and Ruffle contributors (https://github.com/ruffle-rs/ruffle/graphs/contributors).
Copyright (c) 2020 Callum Thomson (rust-flash-lso).
Modifications and additions Copyright (c) 2026 Im-Tim-mI and Timffle contributors.

## 這是什麼，不是什麼

- Timffle 是 [Ruffle](https://github.com/ruffle-rs/ruffle) 的**非官方**分支（fork），與 Ruffle 專案、Ruffle LLC、淘米網絡（Taomee）及其台灣營運方、Adobe 都**沒有隸屬或合作關係**，也沒有得到它們的認可。
- Timffle 的 Flash 模擬核心來自 Ruffle 與其貢獻者。本 repo 保留 Ruffle 完整的 git 歷史（每一個 commit 的作者）與 Ruffle 的授權檔 [`LICENSE.md`](LICENSE.md)，**不得移除**。
- **Timffle 的問題請回報到 https://github.com/Im-Tim-mI/Timffle/issues ，不要回報給 Ruffle。** 擴充功能錯誤畫面的「回報錯誤」、「關於」選單與「更新」連結都指向 Timffle。
- **本 repo 不包含任何遊戲素材**：沒有遊戲的 SWF、DLL、圖片、聲音、程式碼，也沒有遊戲的伺服器位址、封包格式或加解密。`timffle/difftest/` 內的 SWF 都是我們自己用 Haxe 寫的測試程式；需要遊戲檔案才能執行的測試沒有放進來。
- 本專案**不修改遊戲檔案**；遊戲仍由使用者透過瀏覽器從官方網站載入。
- **Adobe Flash Player 不在本 repo，也不隨發行包散布。** 差異測試只在本機用它產生「標準答案」。
- 請遵守各遊戲的服務條款，只使用自己的帳號。使用本軟體的風險由使用者自行承擔。

## 授權

| 範圍 | 著作權 | 授權 | 授權檔 |
|---|---|---|---|
| Ruffle 的原始碼（本 repo 中來自上游的一切） | Ruffle LLC 與 Ruffle 貢獻者 | MIT 或 Apache-2.0，任選其一 | [`LICENSE.md`](LICENSE.md)（含 Ruffle 所依賴的第三方 Rust crate 授權清單）、[`web/LICENSE.md`](web/LICENSE.md)（網頁端相依套件） |
| rust-flash-lso（`vendor/rust-flash-lso/`） | Callum Thomson | MIT | [`vendor/rust-flash-lso/LICENSE`](vendor/rust-flash-lso/LICENSE) |
| Timffle 對 Ruffle 與 rust-flash-lso 的修改、`timffle/` 下的原創部分（連線小幫手、本機代理、差異測試、工具、腳本、文件、Timffle 標誌與圖示） | Im-Tim-mI 與 Timffle 貢獻者 | MIT 或 Apache-2.0，任選其一 | [`timffle/LICENSE-MIT`](timffle/LICENSE-MIT)、[`timffle/LICENSE-APACHE`](timffle/LICENSE-APACHE) |
| ws（`timffle/relay/vendor/ws/`） | ws 的作者 | MIT | `timffle/relay/vendor/ws/LICENSE` |

- 授權以目錄為單位，沒有逐檔的授權標頭。
- **修改聲明（Apache-2.0 第 4(b) 條）**：Timffle 修改過的上游檔案列在 [`timffle/MODIFIED-FILES.md`](timffle/MODIFIED-FILES.md)（由 `timffle/scripts/list-modified-files.sh` 產生），每一項修改的內容與作者都在 git 歷史中（`git log 46fec3f..HEAD -- <檔案>`）。
- 散布 Timffle（原始碼或建置）時，請保留上述所有授權檔與本 NOTICE。發行 ZIP 會在 `LICENSES/` 附上：Ruffle 的 `LICENSE.md` 與 `web/LICENSE.md`、Timffle 的 MIT／Apache-2.0、rust-flash-lso 的 MIT，以及靜態連結進小幫手的 Go 標準函式庫授權（BSD-3-Clause）。
- Timffle 沒有新增任何 Rust crate 或 npm 套件相依（只把 `flash-lso` 指向 `vendor/` 內的修補版），所以第三方相依的授權清單就是上游的 `LICENSE.md` 與 `web/LICENSE.md`；跟進上游時一併更新。

## 商標

- 「Ruffle」名稱與 Ruffle 標誌屬於 Ruffle 專案。MIT 與 Apache-2.0（第 6 條）都**不授予商標權**，所以 Timffle 的產品名稱、圖示、標題與連結都不使用 Ruffle 的名稱或標誌，只以描述方式提及 Ruffle（「Ruffle 的分支」「基於 Ruffle」「Ruffle wiki」）。哪些地方改了、哪些刻意保留，見 [`timffle/docs/BRANDING.md`](timffle/docs/BRANDING.md)。
- 程式碼內的識別名稱（例如 `ruffle_core`、`window.RufflePlayer`、`<ruffle-player>`）是 Ruffle 的公開 API 與內部名稱，為了相容性與方便跟進上游而保留，不是產品名稱。
- 「摩爾莊園」「賽爾號」「小花仙」「彈彈堂」「淘米」「Flash」「Adobe」「Chrome」「Windows」「macOS」等名稱與商標屬於各自的權利人，本專案只用來指稱相容的對象。

## 沒有保證

本軟體依授權條款「依現狀」提供，不附任何明示或默示的保證。連線小幫手允許被授權的網站連到公開網路上的任何 TCP 位址，請只授權你信任的網站（見 [`timffle/docs/ARCHITECTURE.md`](timffle/docs/ARCHITECTURE.md)）。

---

# NOTICE (English)

- Timffle is an **unofficial fork** of [Ruffle](https://github.com/ruffle-rs/ruffle). It is not affiliated with or endorsed by the Ruffle project or Ruffle LLC, Taomee or its Taiwan operator, or Adobe. Its Flash emulation comes from Ruffle and its contributors; this repository keeps Ruffle's complete git history and Ruffle's licence file [`LICENSE.md`](LICENSE.md), which must not be removed.
- **Report Timffle problems to https://github.com/Im-Tim-mI/Timffle/issues, not to Ruffle.**
- **Licences:** Ruffle's code — MIT OR Apache-2.0 (Ruffle LLC and Ruffle contributors; `LICENSE.md`, `web/LICENSE.md`, which also list the third-party dependencies). rust-flash-lso in `vendor/rust-flash-lso/` — MIT (Callum Thomson). Timffle's modifications and the original parts under `timffle/` — MIT OR Apache-2.0 at your option (Im-Tim-mI and Timffle contributors; `timffle/LICENSE-MIT`, `timffle/LICENSE-APACHE`). ws in `timffle/relay/vendor/ws/` — MIT. Timffle adds no Rust or npm dependencies.
- **Modification notice (Apache-2.0 §4(b)):** the upstream files changed by Timffle are listed in [`timffle/MODIFIED-FILES.md`](timffle/MODIFIED-FILES.md); each change and its author are in the git history.
- **Trademarks:** neither licence grants trademark rights. Timffle does not use the Ruffle name or logo as its product name, icon, title or link target, and mentions Ruffle only descriptively. Code identifiers such as `ruffle_core`, `window.RufflePlayer` and `<ruffle-player>` are kept for API compatibility. Game names, "Taomee", "Flash", "Adobe", "Chrome" etc. belong to their owners. See [`timffle/docs/BRANDING.md`](timffle/docs/BRANDING.md).
- **No game assets** are included and game files are not modified. Adobe Flash Player is neither included nor distributed.
- Provided "as is", without warranty of any kind.
