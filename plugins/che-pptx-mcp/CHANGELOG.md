# Changelog

All notable changes to the che-pptx-mcp plugin shell will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.1.0] - 2026-07-02

### Added

- 首次 marketplace 發布（PsychQuant/macdoc marketplace，Refs PsychQuant/macdoc#112）。
- Wrapper 供應鏈驗證：release `.sha256` asset 比對（mismatch 拒裝）+ `codesign` TeamIdentifier `6W377FS7BS` 硬閘（不過即刪除、保留既有 binary）— per #112 push security review。
- `.mcp.json` + version-aware auto-download wrapper（自 `PsychQuant/che-pptx-mcp` GitHub Releases 下載 signed + notarized universal binary）。
