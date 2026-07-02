# Changelog

All notable changes to the che-pptx-mcp plugin shell will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.1.2] - 2026-07-02

### Changed

- **Plugin-scoped 安裝目錄（PsychQuant/macdoc#117）**：binary 與 sidecar 從共享 `~/bin/` 遷至 `$PLUGIN_ROOT/.bin-cache/` — 跨 marketplace 同名 plugin 碰撞 by construction 不可能；plugin 更新自然汰換 cache（重下載走完整驗證鏈）。舊 `~/bin` 副本不主動刪除（可能為使用者手動安裝），首次啟動 stderr 註記一次。

## [0.1.1] - 2026-07-02

### Changed

- shell/binary 版本解耦（PsychQuant/macdoc#116）：新增 `binary_version` 欄位（=0.1.0）；wrapper 改為 binary_version-first 解析，key 存在但空值 fail-closed，key 缺席才 fallback `version`（backward compat）。

## [0.1.0] - 2026-07-02

### Added

- 首次 marketplace 發布（PsychQuant/macdoc marketplace，Refs PsychQuant/macdoc#112）。
- Wrapper 供應鏈驗證（#112 security review R1+R2）：sha256 asset 比對為**強制**（缺失/格式錯/mismatch 均拒裝，integrity gate）+ requirement-based `codesign` 驗證鏈定 Apple anchor + Team OU `6W377FS7BS`（authenticity gate — 取代可被 Identifier 欄位偽造的 grep 形式）+ pinned version 不 fallback latest + `curl -f --proto '=https'` + mktemp 唯一暫存檔。驗證失敗一律保留既有 binary（fail-to-known-good）。
- `.mcp.json` + version-aware auto-download wrapper（自 `PsychQuant/che-pptx-mcp` GitHub Releases 下載 signed + notarized universal binary）。
