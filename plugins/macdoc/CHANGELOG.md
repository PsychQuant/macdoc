# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

> ⚠ This file was bootstrapped by `changelog-tools:changelog-init` from the
> `plugin.json` description field. Section categorization is best-effort —
> review and refine `Added` / `Changed` / `Fixed` etc. as needed.

## [1.2.0] - 2026-07-02

### Added

- **CLI binary 自動安裝（PsychQuant/macdoc#114）**：`hooks/session-start.sh` 於 session 啟動比對 `~/bin/macdoc --version` 與 `binary_version`（=0.5.0，首次 CLI release），缺/不符即下載並以強制 sha256 + Developer ID requirement 驗證後安裝（與 MCP wrappers / release gate 同一把尺）。Session fail-soft（任何失敗警告即止、絕不擋 session）、artifact fail-closed（未驗過不裝）。arm64-only（CLI 依賴 MLX）。

## [Unreleased]

## [1.1.0] - (date unknown — please fill in)

### Changed
- macOS 原生文件處理 CLI — 格式轉換、VLM OCR（含 host profile 設定）、SRT 處理
