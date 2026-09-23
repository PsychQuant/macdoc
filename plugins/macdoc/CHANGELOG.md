# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

> ⚠ This file was bootstrapped by `changelog-tools:changelog-init` from the
> `plugin.json` description field. Section categorization is best-effort —
> review and refine `Added` / `Changed` / `Fixed` etc. as needed.

## [1.5.4] - 2026-09-23

### Fixed

- **版本下限補進讀者實際會照抄的地方**（PsychQuant/macdoc#198 verify 的 in-scope fix）。1.5.3 只在第 3 步加了警告框，
  但 issue 自己點名的受影響路徑是 swiftify 的「典型情境：以官方範本定點填寫」——那段 bash 正好就是出事的重現路徑。
  現在它多了第 0 步 `macdoc --version`，第 4 步也註明「已寫入」不代表值有填進去。macdoc skill 的 `--slot` 選項列
  同樣補上 raw-channel slot 需要 0.8.0+。
- **警告框不再把沒實測過的 MCP 行為說成已知**。「兩端的舊版表現不一樣」改寫成明確只講 CLI 0.7.0（兩個 release binary
  實測）；che-word-mcp 4.0.6 以前的 `execute_script` 標明未經驗證。`binary_version` 不變（0.8.0）。

## [1.5.3] - 2026-09-23

### Fixed

- **`swiftify` skill 寫明 raw-channel slot 的版本下限**（PsychQuant/macdoc#198）。先前版本列只寫「CLI 0.7.0+」，
  第 3 步又說 raw-channel slot 可用，讀者會推論 0.7.0 已經支援。實際上 0.7.0 的 ooxml-swift 比 raw slot 那一版還早：
  `reverse --slot` 對這類段落會報錯，但 **render 不會**——它把 `// @slot-raw` 當成註解，印「已寫入」、exit 0，
  輸出沒填值的模板。現在寫明需要 CLI **0.8.0+** 或 che-word-mcp **4.0.6+**，也說清楚舊版 render 的沉默行為和核對方式。
  順手修正同一段「三個行為細節」其實列了四點。`binary_version` 不變（0.8.0）。

## [1.5.2] - 2026-09-23

### Changed

- `binary_version` 0.7.0 → **0.8.0**，`binary_sha256` 換成 v0.8.0 的值；shell 1.5.1 → 1.5.2。CLI 0.8.0（Developer ID 簽章、
  Apple 公證，arm64）自 0.7.0 以來的使用者可見變化：
  - **Markdown 數學轉成 Word 原生 OMath**（`convert --to docx`，#154）。
  - **確定性的 token 計數路由**（#170）。
  - 偵測不支援的 Notability 容器並明確回報（#148）。
  - 依賴 **ooxml-swift 3.8.0**：讀進來的 `<w:b w:val="0"/>` 等明確關不再被當成開、存檔不再把沒動過的 run 改成粗體（#173）；
    `word reverse --slot` 可以指定多 run 的格式化段落（新文字放進第一個非空白的 carrier run，#131）；匯出腳本正確跳脫 CRLF。
  - `word render --verify-against` 的成功訊息說出比對範圍（#178）；`--coverage` 可單獨執行，降 raw 時說出可行的替代做法（#177、#176）。
  - 第一方依賴全面改用版本範圍，不再有 `branch:` 釘選（#184）。

### Fixed

- SessionStart 首次安裝時不再印出 `.macdoc.installed_version: No such file or directory`。讀 sidecar 那行的
  `2>/dev/null` 寫在 `<` 之後，而 redirection 由左到右生效，所以檔案不存在時的錯誤在被導走之前就印出來了。行為不變。

### 驗證

對**下載回來的 release binary**：發布的 `.sha256` 與下載檔一致、簽章需求（Team `6W377FS7BS`）通過、公證 ticket 的 cdhash
與 binary 相同、`--version` 回報 0.8.0；tag 指向 `0f9547e`。

## [1.5.1] - 2026-09-01

### Fixed

- SessionStart 不再執行常駐 `~/bin/macdoc --version`（PsychQuant/macdoc#161）。它先固定 system PATH，再以 `/usr/bin/codesign` 與 plugin-pinned `binary_sha256` 重驗 exact release bytes，只讀 installer sidecar 判斷版本；簽章／digest 不符、sidecar 缺失或版本不同時改嘗試一次 verified download。下載的 `.sha256` asset 也必須等於 plugin pin。這消除驗簽後從可替換路徑執行的 swap window，也避免 user-writable `~/bin` 劫持 trust-chain 工具；下載失敗仍維持 session fail-soft。

### Tests

- 新增共用驗證 library 與 resident binary 對抗測試：簽章不符的 binary 不得被執行；合法且 digest／sidecar 相符的 binary 只驗簽、不執行、不連網；release-pin、下載 bytes 與 codesign 三個 candidate gate 各有獨立負向測試，並以實際 signed v0.7.0 fixture 驗證正向路徑。

## [1.4.0] - 2026-08-19

### Changed

- **`binary_version` 0.6.0 → 0.7.0**。macdoc CLI v0.7.0 已發布（Developer ID 簽章 + Apple notarized，`spctl` 回 `Notarized Developer ID`），wrapper 會自動換裝。這個 bump 才是使用者真正拿到修正的那一步——**只動 `binary_version` 不會觸發 `plugin update`**，shell 版號不跟著走，修正就停在一個沒人拉取的 release 裡。
- **兩份 skill 的「0.7.0 尚未發布」警語改為已發布**。`skills/macdoc/SKILL.md` 與 `skills/swiftify/SKILL.md` 先前明寫「最新 release 是 0.6.0」，那在 0.7.0 出貨的當下就變成錯的敘述。

### Fixed（由 0.7.0 binary 帶來，非本 shell 的改動）

- **`word render --to-docx <既有目錄> --force` 不再把整個目錄換成一個檔案**（PsychQuant/ooxml-swift#109）。0.6.0 的行為是：拒絕訊息把目錄稱作「檔案」，操作者照著加 `--force`，`replaceItemAt` 對目錄目標會成功，整棵樹被替換成重建出的 docx，然後印「已寫入」、exit 0。實測 0.7.0 release binary：exit 64、訊息明寫「輸出路徑是一個目錄，不是檔案」、目錄與其內容原封不動。
- **輸出檔已存在時預設拒絕覆寫**，要 `--force`；**驗證失敗什麼都不寫出**（PsychQuant/che-word-mcp#180 / #181）。重建結果先落在同目錄暫存路徑，驗過才搬進位。

## [1.3.0] - 2026-08-19

### Added

- **`swiftify` skill**：docx → `.mdocx.swift` 腳本 → docx 的完整工作流。涵蓋 export / coverage 判讀 / slot 填寫 / render / byte-equal 驗證，CLI 與 MCP 兩個入口都列。明寫非目標：**不承諾產出可讀、可手改的 Swift**。
- **macdoc skill 補 `word` 子命令群**：先前「子命令總覽」表格完全沒有 `word` 這一列——`word reverse` 出貨已久卻在 skill 表面隱形。現含 `reverse` / `render` 的選項表與 fidelity 邊界。

### Changed

- **`binary_version` 0.5.0 → 0.6.0**：v0.5.0（2026-07-02）落後 71 個 commits，其中包含新的 `macdoc word render`。不 bump 的話，plugin 使用者下載到的 binary 沒有 skill 文件裡寫的命令。
- **fidelity 邊界改用實測數字陳述**：DSL 升級是 per-part 全有全無；含表格的文件整個 `document.xml` 落 raw channel。實測真實 NTU-REC 表單 **0.0% DSL（0 / 190479 bytes across 16 parts）**，產物是 byte-equal 封存而非可讀腳本。以「規則」而非「例外」的方式寫。

## [1.2.0] - 2026-07-02

### Added

- **CLI binary 自動安裝（PsychQuant/macdoc#114）**：`hooks/session-start.sh` 於 session 啟動比對 `~/bin/macdoc --version` 與 `binary_version`（=0.5.0，首次 CLI release），缺/不符即下載並以強制 sha256 + Developer ID requirement 驗證後安裝（與 MCP wrappers / release gate 同一把尺）。Session fail-soft（任何失敗警告即止、絕不擋 session）、artifact fail-closed（未驗過不裝）。arm64-only（CLI 依賴 MLX）。

## [Unreleased]

## [1.1.0] - (date unknown — please fill in)

### Changed
- macOS 原生文件處理 CLI — 格式轉換、VLM OCR（含 host profile 設定）、SRT 處理
