# Timffle 的介面文字（多語言）

Chrome 擴充功能的介面文字，和 Ruffle 一樣用 Chrome 的訊息目錄（`web/packages/extension/assets/_locales/<語言>/messages.json`），語言跟著瀏覽器的介面語言，支援 Ruffle 擴充功能的同樣 36 種語言：

`ar bs ca cs de en eo es fi fr gl he hr hu id it ja ko nb nl pl pt_BR pt_PT ro ru sk sl sr sv th tr tt uk vi zh_CN zh_TW`

Ruffle 原有的文字（一般選項、播放器訊息）由上游的 Crowdin 翻譯，跟進上游時整份取用上游版本。**Timffle 自己新增的文字**（Socket 設定、彈出視窗的 Socket 區塊、詢問視窗、頁尾聲明）放在這個資料夾，每種語言一個檔案：

| 檔案 | 內容 |
|---|---|
| `en.json` | **完整來源**：每個鍵的英文、給翻譯者的說明（`description`）、佔位符（`placeholders`） |
| `<語言>.json` | 那種語言的翻譯，格式是 `{"鍵": "文字"}`；說明與佔位符從 `en.json` 帶過去 |

鍵一律以 `timffle_` 開頭：`rebrand.py` 不改這些訊息（它們刻意提到 Ruffle），`sync_locales.py` 只動這些鍵，不碰上游的鍵。

## 怎麼用

```sh
python3 timffle/scripts/sync_locales.py           # 把這裡的文字複製進每種語言的 messages.json
python3 timffle/scripts/sync_locales.py --check   # 確認複製結果是最新的、文字沒有壞掉（建置前會自動跑）
```

**為什麼不直接改 `messages.json`**：跟進上游時，這些檔案一律取上游版本（見 [`../docs/UPSTREAM.md`](../docs/UPSTREAM.md)），寫在裡面的 Timffle 文字會消失。取用上游版本之後再跑一次 `sync_locales.py` 就會放回來。

## 加一句新的文字

1. 在 `en.json` 加鍵（`timffle_` 開頭）、英文、必要的 `description`（語氣、是哪個按鈕、哪些字不能翻）與 `placeholders`。
2. 在**每一個**語言檔加上翻譯（缺的鍵、多的鍵、佔位符不一致都會讓 `--check` 失敗）。
3. 頁面上的靜態文字：元素加 `data-i18n="鍵"`（含連結或粗體的句子用 `data-i18n-rich="鍵"`，句子裡的 `<1>…</1>` 對應元素的第 1 個子元素）；程式組出來的文字用 `text("鍵")`（`src/i18n.ts`）。HTML 裡不要放文字。
4. `python3 timffle/scripts/sync_locales.py`，再跑 `cd web && npm test --workspace=ruffle-extension`。

## 翻譯時要守的規則（測試會檢查大部分）

- `{host}`、`{port}`（使用者要照打的樣板）、`$VERSION$`（佔位符）、`<1>…</1>`／`<2>…</2>`（連結與粗體的範圍）原樣保留。
- 名稱與技術用詞保留拉丁字母：`Timffle`、`Ruffle`（頁尾聲明裡兩個連結的文字就是這兩個名字）、`TCP`、`WebSocket`、`token`、`URL`、`HTTP/HTTPS`、`SWF`、`Chrome`，以及資料夾名稱 `helper`（使用者要在下載的檔案裡找到它）。`ws://` 與 `wss://` 照寫；阿拉伯文與希伯來文要在它們後面放 U+200E（由左到右標記），否則 `://` 會被排反。
- 四個遊戲名稱 `摩爾莊園`、`賽爾號`、`小花仙`、`彈彈堂` 一律用中文原名（簡體中文用 `摩尔庄园`、`赛尔号`、`小花仙`、`弹弹堂`），主機名稱（`mole.61.com.tw` 等）原樣保留。
- 說明文字裡引用的按鈕與選項要和它們的文字**完全一致**（例如 `timffle_note_ask` 引用「允許」「一律允許」「拒絕」「一律拒絕」「每次造訪時詢問」）。
- 文字是給一般人看的：不要把英文原文整句留著，也不要把技術名詞硬翻成使用者找不到的詞。

## 品質與誠實說明

- **英文與繁體中文由作者撰寫**；`zh_CN`（簡體）由繁體轉換後逐句改成大陸慣用說法。
- **其他語言是機器翻譯**（以 AI 模型產生），沒有請母語人士審閱，措辭可能不自然或有誤，尤其是使用人數較少的語言（例如韃靼文 `tt`）。測試只能檢查結構、用字與技術用詞，檢查不出語意是否通順。
- 歡迎用 issue 或 pull request 指正；母語人士的修正請直接改該語言的 `.json`，跑 `sync_locales.py` 與單元測試後送出。
- 新增或修改一句英文時，若沒有能力為所有語言翻譯，**不要**把英文塞進別的語言檔假裝翻過；請用機器翻譯並在 README 的「語言」段落維持這個說明。
- Chrome 沒有波士尼亞文（`bs`）、世界語（`eo`）、加利西亞文（`gl`）與韃靼文（`tt`）的介面語言，這四種在 Chrome 上顯示英文；翻譯仍然附上，和 Ruffle 一樣。
- 沒涵蓋：連線小幫手安裝程式的訊息（繁體中文＋英文雙語）、獨立播放器頁（`player.html`，Ruffle 原本就沒有翻譯）。
