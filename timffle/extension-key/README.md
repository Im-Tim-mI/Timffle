# extension-key

Chrome 擴充功能的 ID 是由一把公鑰算出來的。把這把公鑰放進 `manifest.json` 的 `key` 欄位，載入未封裝的擴充功能時 ID 就固定不變，連線小幫手才能用固定的 ID 驗證「是誰在叫用我」。

| 檔案 | 內容 |
|---|---|
| `chrome-extension-public.b64` | 公鑰（DER 的 base64）。建置時以環境變數 `EXTENSION_PUBLIC_KEY` 傳入。 |
| `extension-id.txt` | 由公鑰算出的擴充功能 ID：`eandddnbchclalbjkhfelhjhpijifcog` |

**私鑰不在這個 repo 裡，也不應該放進來。** 只有要把擴充功能上架 Chrome 線上應用程式商店或簽署 `.crx` 時才需要私鑰；載入未封裝的擴充功能不需要。`.gitignore` 已排除 `*.pem`／`*.key`，`helper/package.py` 也會拒絕任何含 PEM 私鑰標記的檔案進入發行 ZIP。

## ID 怎麼算

```sh
python3 -I scripts/extension-id.py                       # 讀 extension-key/chrome-extension-public.b64
python3 -I scripts/extension-id.py 別的公鑰.b64            # 或指定檔案
```

ID 是公鑰 DER 的 SHA-256 取前 32 個十六進位數字，再把 `0`～`f` 寫成字母 `a`～`p`。腳本只讀公鑰，遇到含 `PRIVATE KEY` 的檔案會拒絕。

## 信任模型的提醒

這把公鑰是公開的。任何人只要在自己擴充功能的 `manifest.json` 放同一個 `key`，載入後就會得到同一個 ID，也就能叫用你電腦上的連線小幫手。所以：

- 只載入來自你信任的來源的擴充功能；小幫手的第二道防線是它只連公開網路位址、不監聽任何連接埠。
- 如果你要自行散布，請產生自己的金鑰組，並把新的 ID 換進小幫手與封裝腳本（清單見 [`../docs/BUILD.md`](../docs/BUILD.md#4-使用自己的擴充功能金鑰)）。
