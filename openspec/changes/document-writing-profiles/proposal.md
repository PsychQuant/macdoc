## Why

macdoc#185 要求文件寫作預設可宣告且跨 CLI／MCP 一致，避免寫死字型或誤改既有文件。使用者已選定以目前 Normal.dotm 的格式快照作 official 基底，並要求 Mac／Windows Word 驗收。

## What Changes

- 新增 inherit／official profiles，共用 config 的 document 區段與明確逐次覆寫。
- OOXML 上游提供純格式快照匯入／套用，保留安全樣式、主題、段落與版面，不讀全域 config。
- 新建文件預設 inherit；既有編輯與腳本重播只在顯式指定時套 profile。
- AI/OCR 保存設定時保留其他 consumer 的欄位。

## Capabilities

### New Capabilities

- `document-writing-profiles`: 安全格式快照、profile 決策、跨 consumer 行為與設定共存。

### Modified Capabilities

(none)；未選取 profile 的既有脚本契約不變。

## Impact

- Affected specs: document-writing-profiles
- Affected code:
  - Modified: `Sources/MacDocCLI/MacDoc+Config.swift`
  - Modified: `Sources/MacDocCLI/MacDoc+Word.swift`
  - Modified: `Sources/MacDocCLI/MacDoc+Convert.swift`
  - New: `Sources/MacDocCLI/DocumentProfileConfig.swift`
  - New: `Tests/MacDocCLITests/DocumentProfileTests.swift`
- 上游依賴追蹤：PsychQuant/ooxml-swift#158（共用 API）、PsychQuant/pdf-to-latex-swift#2（設定保留）、PsychQuant/che-word-mcp#223（MCP 介面）。各 repo 在隔離工作樹修改，不動 dependency checkout。

