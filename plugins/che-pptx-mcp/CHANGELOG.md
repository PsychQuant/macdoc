# Changelog

All notable changes to the che-pptx-mcp plugin shell will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.3.0] - 2026-09-24

### Changed

- `binary_version` 0.2.0 → **0.3.0**（依賴 pptx-swift 0.3.0）：
  - 存出的簡報帶有每張圖片的 relationship、media part 與 content type，不論圖片是插入的還是讀進來的（PsychQuant/pptx-swift#1）。
  - 原生比例考慮 EXIF 方向；`fit_picture_to_native_aspect` 以 `srcRect` 裁切後的可見區域計算（PsychQuant/pptx-swift#2）。
  - 整數參數改為嚴格 JSON 型別與範圍檢查，無效時回錯而不 crash（PsychQuant/che-pptx-mcp#5）；新元素 id 涵蓋群組內的元素（#6）；重用有未存檔修改的 `doc_id` 會被拒絕（#8）；另修正 `insert_image` 同名覆寫、autosave 失敗仍清掉 dirty、`delete_image` 誤刪非圖片元素。
- skill 的誠實邊界同步更新：拿掉「插入圖片後 PowerPoint 可能要求修復」與「裁切／EXIF 尚未建模」兩條，補上群組存檔會遺失（PsychQuant/pptx-swift#5）、整數參數嚴格化與 `doc_id` 保護。
- gitlink `mcp/che-pptx-mcp` 指向 v0.3.0 的 release commit。

## [0.2.0] - 2026-09-24

### Changed

- `binary_version` 0.1.0 → **0.2.0**；shell 0.1.3 → 0.2.0。binary 0.2.0（Developer ID 簽章、Apple 公證，universal）新增三個**以公分為單位**的幾何工具（PsychQuant/macdoc#90 第一片，工具數 37 → 40）：`set_placeholder_geometry`、`place_picture_at`、`fit_picture_to_native_aspect`。這三個工具先完成所有驗證再修改文件；參數依 JSON 型別嚴格驗證，NaN／Infinity／極大值回傳錯誤而不 crash。依賴 pptx-swift 0.2.0。
- skill 補上三個工具與其誠實邊界：群組拒絕、超出投影片時照常套用並回報警告、裁切與 EXIF 方向尚未建模（PsychQuant/pptx-swift#2），以及**插入圖片後存檔，PowerPoint 可能要求修復**（PsychQuant/pptx-swift#1，既有問題）。

## [0.1.3] - 2026-08-24

### Added

- 新增 `che-pptx-mcp` skill（PsychQuant/macdoc#159）：提供 Direct／Session 工作流、具名 MCP tools、0-based index／EMU 慣例，以及 PDF／render 尚未支援的誠實邊界。

## [0.1.2] - 2026-07-02

### Changed

- **Plugin-scoped 安裝目錄（PsychQuant/macdoc#117）**：binary 與 sidecar 從共享 `~/bin/` 遷至 **plugin 層級**的 `.bin-cache/`（`<marketplace>/<plugin>/.bin-cache/`，即 version 目錄的上一層）— 跨 marketplace / 跨 plugin 碰撞 by construction 不可能，且跨 shell 版本持久（保留 #116 sidecar 短路，shell-only bump 不重下載；binary_version 變更才重下載）。舊 `~/bin` 副本不主動刪除（可能為使用者手動安裝），首次啟動 stderr 註記一次。

## [0.1.1] - 2026-07-02

### Changed

- shell/binary 版本解耦（PsychQuant/macdoc#116）：新增 `binary_version` 欄位（=0.1.0）；wrapper 改為 binary_version-first 解析，key 存在但空值 fail-closed，key 缺席才 fallback `version`（backward compat）。

## [0.1.0] - 2026-07-02

### Added

- 首次 marketplace 發布（PsychQuant/macdoc marketplace，Refs PsychQuant/macdoc#112）。
- Wrapper 供應鏈驗證（#112 security review R1+R2）：sha256 asset 比對為**強制**（缺失/格式錯/mismatch 均拒裝，integrity gate）+ requirement-based `codesign` 驗證鏈定 Apple anchor + Team OU `6W377FS7BS`（authenticity gate — 取代可被 Identifier 欄位偽造的 grep 形式）+ pinned version 不 fallback latest + `curl -f --proto '=https'` + mktemp 唯一暫存檔。驗證失敗一律保留既有 binary（fail-to-known-good）。
- `.mcp.json` + version-aware auto-download wrapper（自 `PsychQuant/che-pptx-mcp` GitHub Releases 下載 signed + notarized universal binary）。
