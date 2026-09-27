# Changelog

All notable changes to `docx-workflow-swift` are recorded here.

## Unreleased

### Fixed

- **`Executor.apply` 不再刪除或重寫未被 step 觸及的 part**（macdoc#231）。過去以 `DocxWriter.writeData`（scratch 模式）產生輸出，從 typed model 重新序列化全部 part：模型不產生的 part（主題、註腳、尾註、webSettings、自訂 XML）被靜默刪除，其餘每個 part 都被重寫，卻仍回報成功。改用 overlay 模式的 `DocxWriter.write(_:to:)` 後，輸出以 baseline 的原始 archive 為底，只取代 step 實際改動的 part；寫入同時是原子的（暫存檔加改名）。以真實 Word 範本（13 個 part）實測：`insert_paragraph` 只改 `word/document.xml`，`wrap_link` 另加 `word/_rels/document.xml.rels`，無一 part 被刪。回歸測試 `ExecutorTests.testApplyPreservesPartsTheStepDoesNotTouch` 以帶 theme relationship 與自訂 part 的 baseline 逐 part 比對。

## 0.1.0 — 2026-06-01 (in progress)

Initial release — Layer 3 manifest-driven docx-edit library on top of word-builder-swift v1.0.0.

### Added

Phase 1 public surface in `Sources/DocxWorkflowLib/`:

- `public struct Manifest: Codable` — root manifest type (`baseline`, `output`, `steps`, optional `verify`).
- `public enum Step: Codable` — tagged-enum-by-`type` covering Phase 1 runtime-functional step types (`replaceText`, `insertParagraph`, `setParagraphStyle`, `wrapLink`, `setBold`, `setItalic`, `setUnderline`, `removeParagraph`) plus Phase 2c-pending cases (`insertImage`, `insertTable`, `setCellText`, `insertEquation`).
- `public enum Anchor: Codable` — `.beforeText`, `.afterText`, `.paragraphIndex` variants.
- `public struct VerifyAssertions: Codable` — Phase 1 post-condition catalog (`expectedImages`, `expectedParagraphsMin`, `expectedBookmarksMin`, `libxml2Valid`, `bytePreservedParts`).
- `public struct AnchorResolver` + `public enum AnchorError` — deterministic resolution (multi-match = FAIL, zero-match = FAIL, exact-one = succeed).
- `public struct Executor` + `public struct ExecutorResult` — sequential step application against `LensDocument` with `warnHandler` for Phase 2c-pending steps.
- `public struct Verifier` + `public enum VerifyError` — Phase 1 post-condition evaluation.
- `@_exported import WordBuilderSwift` so a single `import DocxWorkflowLib` surfaces `Edit`, `OOXMLEdit`, `WordEdit`, `LensDocument`, `WordRange`, `ParagraphRef`, `EditError`, plus `WordDocument`, `DocxReader`, `DocxWriter`.

### References

- macdoc#92 — issue driving the work.
- macdoc#99 ADR-009 — Layer 3 DSL front-end framing.
- openspec change `macdoc-docx-workflow-cli` — design + spec contract.
- word-builder-swift v1.0.0 (`PsychQuant/word-builder-swift@eb8958a`) — lens-model dependency.
- ooxml-swift#71 — Phase 2c Reducer follow-up tracker.

### v0.1.0 known gaps

- Table-mutation / image-insertion / equation-insertion step types decode but emit warn-and-skip at runtime, pending ooxml-swift#71 Phase 2c.
- `libxml2_valid` uses Foundation `XMLParser` (more permissive than `xmllint`); native libxml2 binding is a future change.
- YAML manifest decoder deferred — JSON-Codable only.
- `archive-first` auto-snapshot integration deferred to Phase 3.
