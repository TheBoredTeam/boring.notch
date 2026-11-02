# AI 狀態工具的開源事件來源研究

研究日期：2026-11-02。閱讀公開 repository 原始碼、測試與官方文件；沒有執行第三方程式或讀取使用者的對話、認證與設定。以下是來源設計的證據，不代表已在本機 App 版本實測成功。

## 結論

Claude Code 的 GUI 不必等同於只能觀察畫面：Claude Desktop Code 分頁的本機工作有 hooks 路線。官方 [Desktop shared configuration](https://code.claude.com/docs/en/desktop#shared-configuration) 說明 hooks 設定與 CLI 共用；CodeIsland 有專門處理 Code GUI 來源與 session ID 的程式碼和測試。

現有開源工具使用四種不同訊號：runtime hooks、本機結構化紀錄、AX 介面狀態、程序／修改時間推測。這四者的可信度與可監看範圍不同，不能一律轉成同樣可靠的紅黃綠燈。

## 1. CodeIsland：最直接相關的 GUI 與 mascot 參考

Repository：[wxtsky/CodeIsland](https://github.com/wxtsky/CodeIsland)。閱讀基準：`03c77e9457f0adc56fa036caf4925e4a576b453b`。

- [ClaudeDesktopSupportTests.swift](https://github.com/wxtsky/CodeIsland/blob/03c77e9457f0adc56fa036caf4925e4a576b453b/Tests/CodeIslandTests/ClaudeDesktopSupportTests.swift)：明確測試 Claude Desktop Code 分頁來源與終端機來源的區別。測試註解記錄 GUI 工作觸發相同的使用者 hooks，並繼承桌面 bundle identity；本機仍須驗證。
- [ClaudeDesktopCodeSession.swift](https://github.com/wxtsky/CodeIsland/blob/03c77e9457f0adc56fa036caf4925e4a576b453b/Sources/CodeIslandCore/ClaudeDesktopCodeSession.swift)：除了 hook 的 session ID，另外保存 `CLAUDE_CODE_HOST_SESSION_ID`，用於桌面工作回跳；產生 `claude://code/continue?session=…` 前先驗證 ID。這是第三方觀察的 App 行為，不是此研究已確認的官方穩定協定。
- [HookSocket.swift](https://github.com/wxtsky/CodeIsland/blob/03c77e9457f0adc56fa036caf4925e4a576b453b/Sources/CodeIsland/HookSocket.swift)：hooks 透過 Unix domain socket 傳送，包含 socket owner／peer、既有 listener 與資源限制處理。
- [CodexDiscovery.swift](https://github.com/wxtsky/CodeIsland/blob/03c77e9457f0adc56fa036caf4925e4a576b453b/Sources/CodeIsland/Discovery/CodexDiscovery.swift)：Codex desktop discovery 會查本機 state DB 與 rollout；另有 app-server adapter。不能僅看到其 app-server 功能就推論任意新連線可監看另一個已開啟的桌面 runtime。
- [MascotView.swift](https://github.com/wxtsky/CodeIsland/blob/03c77e9457f0adc56fa036caf4925e4a576b453b/Sources/CodeIsland/MascotView.swift)、[MascotTimeline.swift](https://github.com/wxtsky/CodeIsland/blob/03c77e9457f0adc56fa036caf4925e4a576b453b/Sources/CodeIsland/MascotTimeline.swift)：角色選擇與狀態分離，具備可見性 gate、速度控制與約 20 fps 的共用時鐘設計；避免快速動畫帶動整個 panel layout。

採用啟示：優先參考 GUI session 配對、hook bridge、動畫暫停與低幀率的設計；不需要把它的授權操作、跨裝置功能或整套 framework 搬進 Boring Notch。

## 2. Pip：hooks → bridge → Unix socket

Repository：[Kikatsu/pip-notch](https://github.com/Kikatsu/pip-notch)。閱讀基準：`810e26fef8de4a91c1b4b936b5dc5a120d5e7ae1`。

[Bridge/main.swift](https://github.com/Kikatsu/pip-notch/blob/810e26fef8de4a91c1b4b936b5dc5a120d5e7ae1/Sources/Bridge/main.swift) 讀取 hook JSON，正規化並送到 socket；[SocketServer.swift](https://github.com/Kikatsu/pip-notch/blob/810e26fef8de4a91c1b4b936b5dc5a120d5e7ae1/Sources/App/Core/SocketServer.swift) 在背景接收，再把事件交到主執行緒，並處理重複 instance 與 socket 被替換的情況。

採用啟示：小型轉送程式與 UI 解耦，App 沒開時快速結束；需要遵守各 provider 對 hook output 的要求。此研究沒有從 Pip 的 transport 程式證明它涵蓋所有桌面 GUI，不能把支援 agent 名稱等同於支援所有產品介面。

Pip 的 [entitlements](https://github.com/Kikatsu/pip-notch/blob/810e26fef8de4a91c1b4b936b5dc5a120d5e7ae1/Sources/App/Pip.entitlements) 未啟用本專案相同的 App Sandbox 設定，因此 socket 路徑與權限不能直接照搬；Boring Notch 應先測試既有 XPC helper 承載 transport 的方式。

## 3. Claude Status：自有狀態檔＋通知＋檔案事件

Repository：[gmr/claude-status](https://github.com/gmr/claude-status)。App 閱讀基準：`6a4ef500f75e55c86bbfd0d2a4670c1067fa8773`；另讀獨立 [plugin](https://github.com/gmr/claude-status-plugin) 的 `007e1820d691cc225e719bf9bd83a45cbfc9aaed`，不是宣稱兩者為同一個 release 的固定配對。

- [plugin hooks.json](https://github.com/gmr/claude-status-plugin/blob/007e1820d691cc225e719bf9bd83a45cbfc9aaed/plugins/claude-status/hooks/hooks.json) 設定狀態寫入程式，輸出每個 session 的 `.cstatus`。
- [SessionMonitor.swift](https://github.com/gmr/claude-status/blob/6a4ef500f75e55c86bbfd0d2a4670c1067fa8773/Claude%20Status/SessionDiscovery/SessionMonitor.swift) 記錄以 Darwin notifications、檔案系統事件與 5 秒備援輪詢更新。
- [StateResolver.swift](https://github.com/gmr/claude-status/blob/6a4ef500f75e55c86bbfd0d2a4670c1067fa8773/Claude%20Status/SessionDiscovery/StateResolver.swift) 沒有自有狀態檔時，會依 JSONL 最後訊息與修改時間推測；例如將部分安靜狀態歸為 waiting。這類 fallback 不能直接解讀為本方案的「需要使用者處理」。

採用啟示：自有小型狀態檔能補 App 重啟後的 snapshot；檔案通知只是叫讀取端重新查狀態，不是完成證據。若採檔案方案，應把自有 metadata 放獨立目錄，不必沿用逐字稿所在位置。

## 4. codex-notch：讀桌面本機紀錄，避免只看程序

Repository：[yazmorukyaz/codex-notch](https://github.com/yazmorukyaz/codex-notch)。閱讀基準：`290eba245d1c1e11b8603619cf599f1c8c912774`。

[CodexStateDatabase.swift](https://github.com/yazmorukyaz/codex-notch/blob/290eba245d1c1e11b8603619cf599f1c8c912774/Sources/Core/Services/CodexStateDatabase.swift) 以唯讀 SQLite 開啟 `state_5.sqlite`，取 thread 與 rollout 路徑；[CodexLocalRepository.swift](https://github.com/yazmorukyaz/codex-notch/blob/290eba245d1c1e11b8603619cf599f1c8c912774/Sources/Core/Services/CodexLocalRepository.swift) 合併 snapshot；[RolloutParser.swift](https://github.com/yazmorukyaz/codex-notch/blob/290eba245d1c1e11b8603619cf599f1c8c912774/Sources/Core/Services/RolloutParser.swift) 解析開始、完成、中斷與待回應事件。

採用啟示：即使不用 hooks，也可研究結構化 lifecycle evidence；但 schema、filter 與 marker 名稱都與產品版本綁定。這只是 Codex 的先例，不能泛化成 ChatGPT／Claude Chat 也有同樣紀錄。Boring Notch 若需此備援，應隔離 adapter 並明確顯示來源失效。

## 5. agent-notch：外觀相關，事件推測不適合 GUI 主路線

Repository：[realfishsam/agent-notch](https://github.com/realfishsam/agent-notch)。閱讀基準：`443c0f5b6e66cf2bb8d1dcfb2865906d2f2b2d75`。

[main.swift](https://github.com/realfishsam/agent-notch/blob/443c0f5b6e66cf2bb8d1dcfb2865906d2f2b2d75/main.swift) 用 `ps`／`lsof` 配對程序與 session，而且要求 TTY；busy 判斷包含最近 30 秒的逐字稿活動。[README](https://github.com/realfishsam/agent-notch/blob/443c0f5b6e66cf2bb8d1dcfb2865906d2f2b2d75/README.md) 也說明更新時間推測可能讓完成後動畫延續約 33 秒。

採用啟示：可參考瀏海旁的 mascot 呈現、sprite sheet 與 parent／child 分組；不採用 TTY 限制或「程序消失＝完成」來監看 GUI 工作。第三方 repo 的程式授權不自動代表其中外部品牌／sprite 資產可原樣再散布；實作選用資產時另確認來源。

## 6. chatgpt-cli：證明 AX 能觀察部分生成介面，但不是背景事件訂閱

Repository：[toby1991/chatgpt-cli](https://github.com/toby1991/chatgpt-cli)。閱讀基準：`785fa68c885b259876e581d104f22b1324deda65`。

[driver/chatgpt.go](https://github.com/toby1991/chatgpt-cli/blob/785fa68c885b259876e581d104f22b1324deda65/driver/chatgpt.go) 透過 AX 找生成中的按鈕，以出現／消失判斷一次生成；名稱依特定語言環境。該程式還會啟用 App、還原視窗及操作輸入，因此它的自動化成功不證明可以安靜監看背景所有聊天。它的 `GetStatus()` 只判斷 App 是否能啟用，不是工作中的狀態。

採用啟示：研究 AX role／identifier 與生成狀態的關係，測試多語系與背景視窗；不複製自動切換視窗、不以按鈕消失推定成功、不將 App 已開啟當作紅燈。

## 套用到 Boring Notch 的決策

1. 首要驗證 Claude Code GUI 的本機 hooks；GUI session 與 engine session 雙 ID 保存，與一般 Claude Chat 分開。
2. Codex desktop 先驗證 hooks；必要時以限定範圍、可停用的唯讀 lifecycle adapter 補足。
3. ChatGPT／Claude 一般聊天保留 AX 探索，尚無本研究可證明的四工具通用事件協定。
4. transport 優先驗證 helper Unix socket，再選擇是否改採 loopback HTTP；只交付一套主要 bridge。
5. mascot renderer 與事件來源解耦，同一狀態同時驅動角色動作及右側三燈，避免顯示互相矛盾。
6. 第一版只觀察狀態與回到原 App，不需接入其他工具的授權代答機制。
