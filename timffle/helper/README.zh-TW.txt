Timffle Chrome 插件（附連線小幫手 1.4.1）
=========================================

Timffle 是 Ruffle（https://ruffle.rs/）的非官方分支，與 Ruffle 專案沒有隸屬關係；
Flash 模擬核心來自 Ruffle 與其貢獻者。問題請回報到 https://github.com/Im-Tim-mI/Timffle/issues 。

Chrome 插件本身不能直接連到遊戲伺服器（Chrome 的限制），所以附了一個「連線小幫手」。
小幫手只要安裝一次。之後 Chrome 會在遊戲需要連線時自動啟動它、用完自動關閉；
不用另外開任何程式或視窗、不用填代理網址，也不會常駐在背景。

壓縮檔內容：
  extension\  Chrome 插件
  helper\     連線小幫手與安裝／移除程式
  README.txt  本說明


一、安裝連線小幫手（只要一次，不需要系統管理員權限）
--------------------------------------------------

Windows（10／11）：
  開啟 helper 資料夾，雙擊 install-windows.cmd。
  若出現「開啟檔案 - 安全性警告」或「Windows 已保護您的電腦」，確認是這個檔案後按
  「執行」或「其他資訊」→「仍要執行」。看到「已安裝連線小幫手」就完成了，按任意鍵關閉。

macOS：
  開啟 helper 資料夾，雙擊 install-macos.command。
  小幫手沒有 Apple 簽署，macOS 可能會擋下 install-macos.command 或小幫手本身。
  被擋時到「系統設定」→「隱私權與安全性」，往下找到被擋的項目按「仍要打開」，
  再雙擊 install-macos.command 一次。看到「已安裝連線小幫手」就完成了。

Linux：
  在 helper 資料夾開終端機，執行  sh install-linux.sh

請保留 helper 資料夾（或保留這個壓縮檔），日後移除時會用到。

不想用這個資料夾也可以：插件還沒找到小幫手時，遊戲一需要連線就會跳出「請先安裝連線小幫手」的視窗（寫了怎麼執行安裝程式，並自己偵測安裝完成，「繼續」亮起後按下去遊戲頁面會重新載入），工具列彈出視窗（與選項頁）也有「直接下載安裝程式」按鈕，
它會判斷你的系統並直接下載對應的安裝檔（Windows 是單一 .exe，雙擊即可；macOS 是 zip，Linux 是 tar.gz）。
小幫手 1.3.0 起，不帶引數直接執行小幫手本身（例如雙擊 bin 資料夾裡的小幫手）也會安裝，效果和 --install 相同。


二、安裝 Chrome 插件
--------------------

1. 把 extension 資料夾放到固定位置。之後不要刪除或搬移，Chrome 每次都從這裡讀取。
2. 開啟 chrome://extensions，打開右上角的「開發人員模式」。
3. 按「載入未封裝項目」，選擇 extension 資料夾。
4. 如果裝過官方的 Ruffle 擴充功能，請先移除或停用，避免互相搶著接管。


三、開始玩
----------

打開 https://mole.61.com.tw/，按播放器的播放鍵後照常登入，不用設定代理。
賽爾號（http://seer.61.com.tw/）、小花仙（http://hua.61.com.tw/）、彈彈堂（http://ddt.61.com.tw/main_index.php）同樣預設可使用連線，打開各自的網站即可。
首次載入插件後，請重新整理已開啟的遊戲頁；若仍顯示下載 Flash 的提示，等幾秒再重新整理一次。

想確認小幫手有沒有裝好：在插件的「選項」頁找到「Socket 連線」，
「連線小幫手」旁邊應該顯示「已安裝（版本 1.4.1）」。
如果顯示找不到小幫手：重新執行安裝程式，然後完全關閉 Chrome 再開。


移除
----

1. 執行 helper 資料夾裡的 uninstall-windows.cmd、uninstall-macos.command 或 uninstall-linux.sh。
   只會刪除安裝程式自己建立的檔案和設定。
2. 到 chrome://extensions 移除插件。


說明
----

- 小幫手只會連往公開網路位址，不會連往你的區域網路或這台電腦，也不記錄連線內容。
  唯一的例外：你允許的網站如果本身就放在區域網路位址上（例如 http://192.168.0.5/），
  它可以連回那一個位址（任何連接埠）；區域網路上的其他裝置與 localhost／127.0.0.1 仍然連不到。
- 區網架站（遊戲伺服器架在自己的區域網路上，例如 192.168.0.163）：
  每一台要玩的電腦上的小幫手都要是 1.4.0 以上（在那台電腦重新執行安裝程式，只更新插件不夠）；
  網頁要用 IP 位址打開（http://192.168.0.163/，不能用電腦名稱或網域名稱）；遊戲要連的也必須是同一個 IP。
  伺服器的其他部分若在區域網路上的另一台電腦，或遊戲連 localhost／127.0.0.1，仍然連不到。
- 預設可以使用連線的網站（各含 http 與 https）：摩爾莊園（mole.61.com.tw）、賽爾號（seer.61.com.tw）、小花仙（hua.61.com.tw）、彈彈堂（ddt.61.com.tw）。
  要加其他網站，到插件選項的「Socket 連線」新增。舊版沒改過的預設清單（只有摩爾莊園）更新後會自動換成上面四個；你自己編輯過並儲存的清單不會被動。
- 小幫手安裝在：
    Windows：%LOCALAPPDATA%\TimffleSocketHelper
    macOS：  ~/Library/Application Support/TimffleSocketHelper
    Linux：  ~/.local/share/timffle-socket-helper
- 此包提供 Windows x86／x64／ARM64、macOS Intel／Apple Silicon、Linux x64，另附 Linux ARM64 建置。
  請使用你的作業系統與處理器實際支援的 Chrome／Chromium；有建置產物不代表已在該平台實機驗證。
- 小幫手尚未取得 Microsoft 發行者簽章或 Apple Developer ID 簽章／公證。
  Windows 11 的「智慧型應用程式控制」(Smart App Control) 等政策可能直接阻擋；不要為此停用安全保護。
  安裝程式不會自動解除下載標記、停用 Gatekeeper 或修改這些安全設定。
- 測試狀況：Linux x64 已用 Chrome 驗證安裝／移除、自動啟停、二進位傳輸及連線失敗處理。
  Windows 版以 Wine 模擬環境測試安裝與連線程式，並非 Windows 實機；macOS 與其他 ARM64 平台未實機測試。
  摩爾莊園已在 Linux x64 的 Chrome 155 用真實帳號驗證過登入、進入世界、走路、換地圖與賽車座位；
  賽爾號、小花仙、彈彈堂只確認預設放行連線，沒有實測遊玩。TCP 接通不等於遊戲能登入。
- 安裝程式會拒絕覆寫內容已變更的原生元件、外來同名檔案、受操作目錄中的符號連結／reparse point。
  Windows 移除時只清除屬於本元件的登錄預設值，保留同 key 的其他值／子 key（可能留下空 key）。
- 原生程式最多同時處理受限數量的連線，傳輸佇列有上限；允許的網站仍可存取公網 TCP（本身放在區域網路 IP 上的網站，還能連到它自己那台電腦的任何連接埠），請只加入你信任的網站。
