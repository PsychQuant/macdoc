# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

> ⚠ This file was bootstrapped by `changelog-tools:changelog-init` from the
> `plugin.json` description field. Section categorization is best-effort —
> review and refine `Added` / `Changed` / `Fixed` etc. as needed.

## [1.5.1] - 2026-09-01

### Fixed

- SessionStart 在執行常駐 `~/bin/macdoc --version` 或採用 sidecar fast path 前，先以 Developer ID requirement 重驗 binary（PsychQuant/macdoc#161）。簽章不符時不執行該檔，改強制嘗試一次下載；下載失敗仍維持 session fail-soft。

### Tests

- 新增 resident binary 對抗測試：偽造正確版本但 codesign 失敗的 binary 不得被執行；合法且版本相符的 binary 必須先驗簽、再執行版本探測，且維持零網路 fast path。

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
