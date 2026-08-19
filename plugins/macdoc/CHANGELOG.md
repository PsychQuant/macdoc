# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

> ⚠ This file was bootstrapped by `changelog-tools:changelog-init` from the
> `plugin.json` description field. Section categorization is best-effort —
> review and refine `Added` / `Changed` / `Fixed` etc. as needed.

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
