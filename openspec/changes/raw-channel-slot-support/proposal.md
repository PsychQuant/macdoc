## Why

swiftify 的招牌情境「以官方範本定點填寫」在最典型的輸入上不可用：官方表單幾乎必含表格 → `word/document.xml` 整個 part 落 raw channel → 任何 `--slot name=<paraId>` 直接失敗（`no body paragraph with id ... in the log`），即使該 paraId 確實存在於 XML。`template-content-slots` spec 的既有 requirement（「given slot designations (paragraph ids…) SHALL emit a script whose designated content positions accept caller-provided values」）字面上並未排除 raw-channel 文件——現行實作是 spec 承諾範圍的缺口。swiftify SKILL.md 亦明文承諾 raw channel「能填 slot」。（PsychQuant/macdoc#171；診斷 comment 5425354597）

Root cause（已證實）：`ScriptExporter.exportSwift(log:slots:)` 的 slot 驗證只掃 OperationLog 的 `.appendParagraph` entries，而 raw-channel 文件的 document.xml 以單一 `.carryPart(partPath:xml:)` op 進 log——log 內沒有任何 paragraph 層級 op，paraId lookup 必然落空。既有 op-level substitution（`// @slot` directive）前提是 paragraph 以 `appendParagraph` op 存在，對 part 級 blob 構不到。

## What Changes

新增第三類 slot——**raw-channel slot**（part 級 carryPart blob 內以 `w14:paraId` 定位的文字替換）。五個已對齊的設計決定（spectra-discuss 收斂、使用者確認）：

1. **掛在 `exportSwift` 驗證 fallback**：`.appendParagraph` 未命中時，掃 `.carryPart(partPath: "word/document.xml")` 的 XML 找 `w14:paraId="<id>"` 段落；命中 → 建 raw-channel slot；仍未命中才報既有錯誤（訊息補 raw-channel 根因提示）。reverse 端與 byte-equal upgrade gate 完全不動。
2. **表示延伸既有 directive 機制**：`// @slot-raw <name> <paraId>` 置於 carryPart op 前（與既有 `// @slot <name> <paraId>` 同款 pre-pass parse）。
3. **替換在 import/execute 時做 run 級手術**：以 paraId 定位段落、保留 pPr、rPr 取該段主文字 run（文字最長者）、段落文字坍縮為單一 `<w:t>` run。多 run 段落的 run 級格式（段內部分粗體等）坍縮為主 run 格式——表單填寫場景的既定語意。
4. **Default identity shortcut**：slot 值＝default（export 時抽取的段落 `<w:t>` 併文）→ 完全不動 blob → 既有 `--verify-against` byte-equal 閘門自動成立，驗證架構零新增。
5. **paraId 於 blob 內重複 → fail loudly**（`slotDesignationFailure`），不猜第一個——填錯官方表單欄位是最糟失敗模式。

swiftify SKILL.md 同步收斂：raw channel 段的「能填 slot」從承諾變為含行為細節的現況描述（run 坍縮語意、identity shortcut）。

## Non-Goals

- 不動 reverse 端／DSL upgrade gate（部分升級 raw part 的爆炸半徑一個量級起跳）
- 不做 run 級格式保留的 run-diff 對映（表單場景用不到；坍縮語意已足）
- 不支援 document.xml 以外的 part（headers/footers 的 raw slot 留待實際需求）
- 不做 style-based selector 的 raw-channel 版（spec 既有 requirement 提及 style selectors；raw channel 僅支援 paraId 定位）
- MCP 面不需獨立改動——`che-word-mcp-script-pipeline-tools` spec 的「rides the CLI's code path」requirement 使 `export_script(slots:)`/`execute_script` 自動繼承（parity 測試涵蓋）

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `template-content-slots`: 新增 raw-channel slot requirement——carryPart blob 內 paraId 定位替換、default identity shortcut、run 坍縮語意、paraId 重複 fail-loud；既有 DSL/op-level slot requirements 不變

## Impact

- Affected specs: `template-content-slots`（modified）
- Affected code:
  - New: packages/ooxml-swift/Tests/OOXMLSwiftTests/RawChannelSlotTests.swift
  - Modified: packages/ooxml-swift/Sources/OOXMLSwift/Transcode/ScriptTranscoder.swift, plugins/macdoc/skills/swiftify/SKILL.md
  - Removed: (none)
