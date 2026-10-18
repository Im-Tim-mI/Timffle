# 跟進上游 Ruffle、授權與貢獻規則

Timffle 是 Ruffle 的長期分支：`main` 分支包含 Ruffle 到 `nightly-2026-10-13` 為止的**完整歷史**，Timffle 的改動是之後的 commit。這份文件說明怎麼持續跟進上游，以及開發時要注意的授權與程式碼問題。

## 分支與歷史

- **只用 merge 跟進上游，不要 rebase 已經推上 GitHub 的歷史。** Merge 會保留 Ruffle 每個 commit 的原作者，也讓別人的 clone 不會壞掉。
- 上游基準記在 [`../UPSTREAM.env`](../UPSTREAM.env)（`RUFFLE_BASE`、`FLASH_LSO_BASE`），合併新版後更新它。
- `vendor/rust-flash-lso/` 是 rust-flash-lso 的 **git subtree**（含它自己的歷史），Timffle 對它的修改是之後的 commit。
- Timffle 自己的東西集中在 `timffle/`；對 Ruffle 原有檔案的修改盡量小而集中，減少合併衝突。

## 合併新的 Ruffle 版本

```sh
git remote add upstream https://github.com/ruffle-rs/ruffle.git    # 第一次
git fetch upstream tag nightly-YYYY-MM-DD --no-tags                 # 只抓要的那個 nightly
git switch -c merge-nightly-YYYY-MM-DD
git merge nightly-YYYY-MM-DD
```

常見衝突與處理：

| 衝突 | 處理 |
|---|---|
| `.github/workflows/*`、`.github/dependabot.yml`、`.github/FUNDING.yml`、`.github/ISSUE_TEMPLATE/*`（上游有改、我們已刪除或替換） | 保持 Timffle 的版本：`git rm` 上游的 workflow／dependabot／FUNDING；issue 範本用我們的。Ruffle 的 CI 會發布到 Ruffle 的商店帳號、需要 Ruffle 的密鑰，不能在 Timffle 跑 |
| `README.ruffle.md`（上游改了 `README.md`） | Git 通常會跟著改名合併；若變成衝突，把上游的新 `README.md` 內容放進 `README.ruffle.md`，`README.md`（英文）與 `README.zh-TW.md`、`README.zh-CN.md` 保持 Timffle 的 |
| 語系文字 `*.ftl`、`messages.json`（上游 Crowdin 翻譯更新 vs 我們換過名） | 先接受上游版本（`git checkout --theirs <檔案>`），合併完成後跑 `python3 timffle/scripts/rebrand.py` 一次換回來，再跑 `python3 timffle/scripts/sync_locales.py`：Timffle 自己的介面文字（`timffle_` 開頭的鍵，來源在 [`../locales/`](../locales/)）會放回各語言的 `messages.json`。**不要把 Timffle 的文字只寫在 `messages.json` 裡**，下次取上游版本時會消失 |
| 上游新增了語言（`_locales/` 多一個資料夾） | `sync_locales.py` 會報錯，要求補上 `timffle/locales/<語言>.json`；照 [`../locales/README.md`](../locales/README.md) 補翻譯，機器翻譯要在 README 的「語言」段落照實說明。反過來，上游拿掉的語言要刪掉對應的檔案 |
| `Cargo.lock`（上游升級相依） | 接受上游版本後跑 `cargo metadata --format-version 1 > /dev/null` 讓 Cargo 補上 flash-lso 的 `[patch]`；確認 `Cargo.lock` 裡 `flash-lso` 沒有 `source`（表示用的是 `vendor/` 的版本） |
| 上游升級了 rust-flash-lso 的版本 | 用 `git subtree pull --prefix=vendor/rust-flash-lso https://github.com/ruffle-rs/rust-flash-lso.git <新 commit>`（或 `git merge -s subtree`）跟進，再確認我們的 AMF3 修正還在／上游是否已修好，最後更新 `UPSTREAM.env` 的 `FLASH_LSO_BASE` |
| 我們修改過的程式碼（AVM2、3D、網頁 Socket） | 一般的程式衝突；以真 Flash 的差異測試為準（[`TESTING.md`](TESTING.md)） |

合併後的檢查清單：

```sh
python3 timffle/scripts/rebrand.py && python3 timffle/scripts/rebrand.py --check   # 品牌
python3 timffle/scripts/sync_locales.py && python3 timffle/scripts/sync_locales.py --check   # Timffle 自己的介面文字
python3 timffle/branding/make_branding.py --check
cargo test -p tests --test tests                                                  # Ruffle 回歸測試（含我們新增的）
(cd web && npm ci && npm test --workspace=ruffle-extension)                        # 擴充功能單元測試
VERSION4=… timffle/scripts/build-extension.sh                                      # 完整建置
# 差異測試（真 Flash 標準答案），見 TESTING.md
git commit                                                                         # 合併 commit
timffle/scripts/list-modified-files.sh > timffle/MODIFIED-FILES.md                # 修改清單（看已 commit 的 HEAD）
# 更新 timffle/UPSTREAM.env、NOTICE.md（若上游授權或第三方清單有變）、timffle/CHANGELOG.md，再 commit
```

## 授權注意事項

- **保留所有授權與著作權聲明**：根目錄 `LICENSE.md`、`web/LICENSE.md`、各套件的 `LICENSE_MIT`／`LICENSE_APACHE`、`vendor/rust-flash-lso/LICENSE`、`timffle/relay/vendor/ws/LICENSE`。上游更新這些檔案時照單全收，不要改寫。
- **Apache-2.0 第 4(b) 條**：散布修改過的檔案時要有「已修改」的聲明。Timffle 用 [`../MODIFIED-FILES.md`](../MODIFIED-FILES.md)（腳本產生）＋ git 歷史滿足；每次改到上游檔案後重新產生。
- **Apache-2.0 第 4(d) 條**：上游若加了 `NOTICE` 檔，散布時要一併保留（目前 Ruffle 沒有）。
- **新增相依**：加入任何新的 Rust crate、npm 套件或 Go 模組之前，確認它的授權與 MIT／Apache-2.0 相容（Ruffle 用 `cargo deny`，設定在根目錄 `deny.toml`：`cargo deny check licenses`），並更新 `NOTICE.md` 與發行包的授權檔（`timffle/helper/package.py` 的 `LICENSE_FILES`）。**不要引入 GPL 等 copyleft 授權的程式碼**，否則整個專案就不能維持 MIT／Apache-2.0。
- **Timffle 原創的程式碼**以 MIT 或 Apache-2.0 雙授權提供；外部貢獻依 README 的條款，自動以同樣的雙授權提供。
- 發行 ZIP 一定要帶 `LICENSES/` 與 `NOTICE.md`（`package-release.sh` 會自動放進去，缺了會拒絕封裝）。

## 貢獻規則（Timffle 專屬）

- **來源要清楚**：遵守 Ruffle 的 [`CONTRIBUTING.md`](../../CONTRIBUTING.md)。Flash 行為一律用**自己寫的測試 SWF 在真 Flash Player 上量測**（差異測試）。
- **不得放入遊戲素材**：遊戲的 SWF、DLL、圖片、聲音、程式碼、伺服器位址、封包格式、加解密都不能進 repo，測試也不能依賴它們。
- **不得放入私人資料**：擴充功能私鑰（只放在 repo 外）、帳號密碼、token、個人路徑。`timffle/helper/package.py` 會掃描並拒絕封裝含 PEM 私鑰的檔案，但 repo 本身要靠自己注意。
- 品牌規則見 [`BRANDING.md`](BRANDING.md)：新增使用者看得到的文字時寫 Timffle（或跑 `rebrand.py`）。
- Commit 訊息沿用 Ruffle 的風格（`area: Summary`），一個 commit 一件事，方便日後挑出來回饋上游。

## 回饋給 Ruffle

Timffle 的 Flash 相容性修正（AVM2 網路、LocalConnection、3D／`Matrix3D` 等）對上游也有價值。送 PR 給 Ruffle 前：

1. 從 Ruffle 的最新 `master` 開分支（在另一個 clone，例如 tim 的 fork `Im-Tim-mI/ruffle`），只挑相關的改動，不要帶到 `timffle/`、品牌或擴充功能 Socket 橋接的改動。Ruffle 要求 PR 以最新 master 為基底、rebase、不含 merge，而且**不接受一次幾百上千行的大 PR**——一個 PR 一個小修正。
2. 註解與測試裡不要出現遊戲專屬名稱（遊戲內部的類別名稱、遊戲的英文名稱），改用中性描述；本 repo 已照這個規則整理過，新加的註解也要遵守。
3. 依 Ruffle 的 [CONTRIBUTING](../../CONTRIBUTING.md) 補 SWF 回歸測試（`tests/swfs/`），預期輸出要從真 Flash 錄製；`cargo fmt`、`cargo clippy` 要乾淨。
4. **Ruffle 的 AI 工具規定**：有 LLM 參與撰寫的程式碼必須標示（PR 範本的勾選項＋commit 的 `Assisted-by:` trailer），提交者本人必須審閱並完全理解改動，而且**不可以由 LLM 與維護者溝通**（PR 說明、留言、Discord 都要由本人處理）。
5. 先查上游是否已有相同工作（例如串流 `URLStream`、3D 屬性、`Matrix3D` 都有進行中的 PR），不要重複。

## 已知待辦（程式碼）

- **網域名稱解析**：`avm2: Network, …` commit 裡「一律先問父網域」的做法，會讓上游經真 Flash 驗證的回歸測試 `avm2/loader_duplicate_class` 失敗（Flash 會依網域快取綁定）。準備送上游的版本改成混合規則——**有多個命名空間的 multiname 從根網域先找，單一命名空間的名稱維持就近優先**——它通過上游完整測試套件。Timffle 還沒有換成混合規則；換之前要用遊戲的實際檔案重跑賽車座位相關的差異測試（那些測試因含遊戲檔案而不在 repo 內）。
- 完整的上游 `cargo test -p tests --test tests` 還沒有在 Timffle 的樹上跑過。
