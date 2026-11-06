# api100 — Flash Player API 補齊到 100%（PRO_bata 分支）

目標：README「Timffle 對 Ruffle 的修補」圖表用 Ruffle 自己的 `tools/stub-report` 量 Flash Player API：每個 API 一項，空殼（`avm2_stub_*!` 巨集）扣回一項。目標是 **0 個缺少、0 個空殼**。基準（2026-11-04，main `c181461b6`）：4,560 項，354 缺少、421 空殼，82.59%。

這個資料夾是交接用的工作紀錄，放在 `timffle/docs/api100/`：

- `README.md`（本檔）：規則與做法。
- `queue.json`：每個還有缺口的類別，`group` 1…5（依序做），`missing`／`stubbed` 成員清單，`status`（`todo`／`done`／`partial`／`blocked`）與 `note`。做完要更新。
- `STATUS.md`：每一批一行（UTC 時間、做了什麼、量到的 %、下一批）。開工先讀最後幾行。
- `measure.sh`：在 repo 根目錄執行（`sh timffle/docs/api100/measure.sh`），跑 stub-report 並印出一行摘要（需要 Rust、Java；第一次約 5～10 分鐘）。

## 怎麼量

```sh
sh timffle/docs/api100/measure.sh          # 寫到 timffle/docs/api100/reports/<日期>-<sha>.json 並印出 %
```

Ruffle 的基底報告（nightly-2026-10-13，`46fec3f`）：`timffle/docs/data/ruffle-patches.json` 裡的數字；圖表由 `timffle/scripts/ruffle_patches.py` 產生。

## 程式碼在哪

- playerglobal：`core/src/avm2/globals/**/*.as`（AS3 宣告）＋ Rust 原生實作 `core/src/avm2/globals/**/*.rs`。
- 空殼巨集：`avm2_stub_method!`、`avm2_stub_getter!`、`avm2_stub_setter!`、`avm2_stub_constructor!`（`core/src/stub.rs`，`known_stubs` feature 用 `linkme` 收集成 `KNOWN_STUBS`）。缺少的項目 = 編譯出的 playerglobal 與 Adobe API 清單比對（`tools/stub-report`、`ruffle_api_report`）。
- 參考：Adobe AS3 Reference（https://airsdk.dev/reference/actionscript/3.0/）；行為有疑問時用真 Flash Player 32（Wine，`timffle/difftest/`，見 `timffle/docs/TESTING.md`）。
- 測試：`tests/tests/swfs/avm2/<name>/`（`test.toml` + `output.txt`，照既有範例），執行 `cargo test -p tests --test tests -- <name>`。

## 規則

1. **只做真實作。** 不可以只刪掉空殼巨集、回假值或假裝成功。瀏覽器沒有的功能（攝影機、麥克風、DRM、RTMFP 群組、Worker、列印、自動化、取樣器、感測器、StageVideo、AVStream）照 **Flash Player 在沒有該功能的機器上的行為**實作：`isSupported` false、取裝置回 null、丟 Flash 會丟的錯誤與事件，絕不假裝成功；在類別的文件註解與 `timffle/docs/CHANGES-FROM-RUFFLE.md` 說明。
2. **通用，不針對特定網站**（不可有主機名判斷）。
3. **測試適量**：每個類別或相關成員一組一個 SWF 回歸測試；只跑你碰到的測試；每次 commit 前 `cargo check -p ruffle_core`；每批跑一次 `cargo clippy -p ruffle_core`。不要重建 wasm／擴充功能，不要跑 242 支 SWF 的瀏覽器比對；出 ZIP 由 tim 決定。
4. **每個類別（或小組）一個 commit**，Ruffle 風格標題（`avm2: Implement Capabilities.hasAccessibility …`），作者 Im-Tim-mI。每批成功後 `git push origin PRO_bata`。**絕不推 main**、不 rebase、不 force-push。
5. **CHANGELOG**：`timffle/CHANGELOG.md` 最上面維持一節 `## 未發布（PRO_bata：API 補齊）`，每批加一行（繁體中文：做了什麼、為什麼、怎麼驗證）。不改版本號、不出 ZIP、不發布、README 與圖表最後才改。
6. 上游程式碼的改動加 `// Timffle:` 註解；每批結束重新產生 `timffle/MODIFIED-FILES.md`（`sh timffle/scripts/list-modified-files.sh > timffle/MODIFIED-FILES.md`）並提交。
7. **一次一批**：第 2 組一批約 10～30 項，或一個大類別（NetStream、TextLine…）；做完量測、更新 queue 與 STATUS、推送。編譯或測試連續兩次失敗就還原、把該類別標 `blocked` 寫原因，做下一個。
8. **完成條件**：`measure.sh` 印出 `0 missing, 0 stubs`。然後重新產生圖表（`python3 -I timffle/scripts/ruffle_patches.py summarize --ruffle <Ruffle 基底報告> --timffle <最新報告> && python3 -I timffle/scripts/ruffle_patches.py svg`），更新三個 README 的修補段落（數字、commit、日期；zh-CN 由 zh-TW 轉換），提交、推送，並寫最後一行 STATUS。
9. 需要 tim 決定的事（行為查不到、會改變使用者看得到的行為）：標 `blocked`、繼續下一個，問題列在 STATUS.md。

## 每次開工的順序

1. 讀 `STATUS.md` 最後幾行；`git status` 必須乾淨；`git pull --ff-only origin PRO_bata`。
2. 依 queue 順序取下一個 `todo` 類別：查 Adobe 文件、讀 Ruffle 現有程式、實作、加／改回歸測試、`cargo check`、跑該測試、clippy、commit。
3. `measure.sh`；更新 `queue.json`（status／note）與 `STATUS.md`；重新產生 MODIFIED-FILES.md；commit；push。
