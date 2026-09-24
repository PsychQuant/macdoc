# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

> ⚠ This file was bootstrapped by `changelog-tools:changelog-init` from the
> `plugin.json` description field. Section categorization is best-effort —
> review and refine `Added` / `Changed` / `Fixed` etc. as needed.

## [1.8.0] - 2026-09-24

### Changed

- CLI binary **0.10.0 → 0.11.0**：
  - `convert --to html` 的 `.srt`／`.note` 不帶 `--css` 時預設 `dark`，不再以 exit 64 失敗（PsychQuant/macdoc#216）。
  - `pdf ocr --mode ollama` 沒給 `--host`／`--model` 時改讀 `config ocr` 的預設值，並修正 model 被寫死成 `glm-ocr` 的既有 bug（#218）。
  - 依 `cli-spec.yaml` 更正文件與規格不一致處（#217）；測試 helper 的 pipe 讀取不再在大量輸出或平行測試下死結（#219）。
  - 依賴 ooxml-swift 3.11.0（格式 profile 依 relationship 解析 part、匯入只收 UTF-8、缺欄位錯誤指名欄位；#212–#214）與 pdf-to-latex-swift 0.4.0（page label 頁碼、偶數頁章節加 `openany`、圖寬改為原書絕對尺寸、裁切檔名帶頁碼、去重不動 verbatim；#207–#211、#215）。`pdf scan`／`pdf render` 會把 page label 寫進 manifest，`pdf normalize` 的摘要涵蓋這些新紀錄。
- skill：`--css` 的預設、`config ocr` 由誰讀取、1.8.0 版本紀錄；swiftify 補上 che-word-mcp 4.3.0 的 `raw_reason` 與 `paragraphs_only`。

## [1.7.0] - 2026-09-24

### Added

- **`macdoc config document gc`**（PsychQuant/macdoc#194）：列出 `profiles/` 裡未被 `officialSnapshot` 引用的舊格式快照。
  預設只預覽，`--force` 才刪除；被引用的快照與其他檔案永遠不碰，設定檔損毀時先失敗。
- **`macdoc pdf normalize` 還原原書頁碼與圖片比例**（PsychQuant/macdoc#9、#10）：依 page marker 插入
  `\setcounter{page}{N}`，依 figure bbox 補上 `width=<w>\textwidth`，並印出摘要；無法處理的頁或圖逐筆列出原因。

### Changed

- CLI binary **0.9.0 → 0.10.0**（ooxml-swift 3.10.0、pdf-to-latex-swift 0.3.0；兩個 config.json 寫入者共用跨程序鎖，PsychQuant/macdoc#204）。

## [1.6.2] - 2026-09-24

### Added

- **CLI 端到端 slot 測試**（PsychQuant/macdoc#193）：`Tests/MacDocCLITests/WordReverseSlotE2ETests.swift`
  新增 4 個測試，實際跑 `macdoc word render` 二進位（不只檢查生成腳本的參數名稱），改掉 slot 的
  call-site 值後讀回重建的 docx，斷言指定段落文字真的變了、鄰居段落沒被動到。涵蓋三種 slot 形式：
  DSL-spellable 段落、op-level（`// @slot`，格式化多 run 段落）、raw-channel（`// @slot-raw`，整個
  `word/document.xml` 落 raw）；raw-channel 另有一個以 REC-O-01 官方表單為對象、gated on
  `MACDOC_TEMPLATE_DIR`（env 缺席時乾淨 `XCTSkip`）的變體。

### Changed

- **`swiftify` skill 補上 MCP 端 paragraphs-only 的已知落差**（PsychQuant/macdoc#193）：`--paragraphs-only`
  目前是 CLI-only，che-word-mcp 沒有對應的參數或工具、回應也不會具名 `paragraph-no-paraId`；純走 MCP 的
  呼叫端目前只能改走 CLI 完成這條備援路徑。
- **`swiftify` 以 release artifact 重測量測案例**（PsychQuant/macdoc#193）：下載 0.7.0、0.8.0、0.9.0 三個官方 release
  binary，以 sha256 辨識版本（不靠 `--version` 字串），重跑 REC-O-01 的 coverage 與「raw slot 填空白段落」。coverage 三版相同；
  slot 行為三版各異（0.7.0 印「已寫入」但沒填值、0.8.0 填了但 run 沒有 rPr、0.9.0 沿用段落標記字型），整理成表格寫進 skill，
  並附上以 sha256 核對手上版本的方法。
- `binary_version` 不變（0.9.0）——本次未改 CLI 原始碼行為，只加測試與文件。

## [1.6.1] - 2026-09-24

### Changed

- **`swiftify` 寫明空白段落的 slot 格式來源**（PsychQuant/macdoc#199）。段落裡沒有任何 run 時，填入的文字取段落標記的 rPr，
  需要 CLI 0.9.0+ 或 che-word-mcp 4.1.0+；較舊的版本會落到 docDefaults。已用 v0.9.0 release binary 在官方表單上實測。
  `binary_version` 不變（0.9.0）。
- 補上 `15bd4dc` 漏掉的 marketplace.json 版號與本條目：該 commit 只 bump 了 plugin.json。

## [1.6.0] - 2026-09-24

### Changed

- `binary_version` 0.8.0 → **0.9.0**，`binary_sha256` 換成 v0.9.0 的值；shell 1.5.5 → 1.6.0。CLI 0.9.0（Developer ID 簽章、
  Apple 公證，arm64）自 0.8.0 以來的使用者可見變化：
  - **文件格式 profile**（#185）：`macdoc config document show / import-official / set-default`；`convert --to docx` 與
    `word render` 的 `--profile inherit|official` 與 `--document-config`。與 che-word-mcp 4.1.0+ 共用
    `~/.config/macdoc/config.json` 的 `document` 區段。`config ai` / `config ocr` 寫入時不再洗掉這個區段
    （pdf-to-latex-swift 0.1.1）。
  - **預設 `word reverse` 在 stderr 提示 `--paragraphs-only`**：只在 `word/document.xml` 因 `paragraph-no-paraId` 落 raw 時出現（#181）。
  - **raw-channel slot 填入官方表單的空白欄位時，文字沿用段落標記的字型**，不再落到 docDefaults（#199，ooxml-swift 3.9.0）。
  - bib 轉換器的整合測試改用 repo 內的合成 fixture，clean clone 可跑（#186）。
- **skills**：
  - `macdoc` skill 新增 `config document` 一節，並補上 `--profile` 選項。
  - `swiftify` 把 coverage-only、具名根因、stderr 提示依實際出貨版本分層（0.8.0 的 #176/#177、0.9.0 的 #181）；表格與 raw
    的敘述更正為「canonical minimal table 可 typed 升級，不支援的 rich 表格才可能讓整個 part 落 raw」（#181、#200）；
    覆寫一律先取得使用者同意，範例改用新的輸出路徑。
- README 的文件格式 profile 一節由「原始碼建置功能，尚未發布」改為版本下限說明。

## [1.5.5] - 2026-09-23

### Fixed

- **依 #198 的 Codex 跨模型審查修正四處過度概括**（PsychQuant/macdoc#198；上一輪 verify 時 Codex 因額度限制沒跑成，這次補跑）。
  - swiftify 版本列不再泛稱「更舊的 render 不會報錯」：只有 CLI 0.7.0 實測過，更早的 CLI 與 che-word-mcp 4.0.6 以前標明未實測。
  - 「含表格的文件會走 raw-channel slot」改成條件句：文件落在 raw channel 時才需要 0.8.0+，是否落 raw 以 `--coverage`
    或腳本裡的 `// @slot-raw` 為準（swiftify「典型情境」第 0 步與 macdoc skill 的 `--slot` 列）。
  - 警告框寫明實測用的是 0.7.0 與 0.8.0 兩個官方 release binary。
  - 更正 1.5.4 條目對 1.5.3 的描述（1.5.3 也改了版本列，不只第 3 步）。
- `binary_version` 不變（0.8.0）。

## [1.5.4] - 2026-09-23

### Fixed

- **版本下限補進讀者實際會照抄的地方**（PsychQuant/macdoc#198 verify 的 in-scope fix）。1.5.3 更新了版本列與第 3 步的警告框，
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
