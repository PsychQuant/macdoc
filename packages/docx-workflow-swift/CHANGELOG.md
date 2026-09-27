# Changelog

All notable changes to `docx-workflow-swift` are recorded here.

## Unreleased

### Fixed

- **`Executor.apply` 不再刪除或重寫未被 step 觸及的 part**（macdoc#231）。過去以 `DocxWriter.writeData`（scratch 模式）產生輸出，從 typed model 重新序列化全部 part：模型不產生的 part（主題、註腳、尾註、webSettings、自訂 XML）被靜默刪除，其餘每個 part 都被重寫，卻仍回報成功。改用 overlay 模式的 `DocxWriter.write(_:to:)` 後，輸出以 baseline 的原始 archive 為底，只取代 step 實際改動的 part；寫入同時是原子的（暫存檔加改名）。以真實 Word 範本（13 個 part）實測：`insert_paragraph` 只改 `word/document.xml`，`wrap_link` 另加 `word/_rels/document.xml.rels`，無一 part 被刪。回歸測試 `ExecutorTests.testApplyPreservesPartsTheStepDoesNotTouch` 以帶 theme relationship 與自訂 part 的 baseline 逐 part 比對。
- **CertifiedTransaction 的憑證寫入失敗不再蓋掉交易本身的成功/失敗訊號**（macdoc#137 對抗式審查 R2，review-c137.md CRITICAL Finding 1）。修前：憑證在 commit 之後才寫，寫入失敗丟出的不是 CertificationError，呼叫端接不住，導致成功的 apply 也回報失敗、失敗的 apply 則整段吃掉真正的失敗原因與 rejected-candidate 路徑。修法兩層：交易開始前先驗證 `--certificate` 目的地（父目錄存在、可寫、路徑本身不是既有目錄），不符直接以新的 `CertificationError.certificateDestinationInvalid(path:reason:)` 中止、不寫任何檔案；驗證通過後才發生的寫入失敗（競態）改走原子寫法且不再拋錯，改用新的 `certificateWarnHandler` callback 回報，交易本身的回傳/拋出結果完全不受影響。
- **CertifiedTransaction 的輸出路徑若是既有目錄會被靜默整個刪除取代**（同一輪審查 MEDIUM Finding 2）。`commit` 呼叫的 `FileManager.replaceItemAt` 對「目的地是目錄」會直接刪除整個目錄樹再放上新檔案、不報錯。新增 `CertificationError.outputPathIsDirectory(path:)`，在交易開始前（與上一條同一步）拒絕，不做任何寫入。
- **`Layer1Gate` 的 `[Content_Types].xml` Default Extension 比對改成不分大小寫**（OPC ECMA-376 Part 2 §10.1.2.2.1 的規定；同一輪審查 LOW L2）。
- **`Layer1Gate` 的 relationship Target 解析前先做百分比解碼**（例如 `%20`；同一輪審查 LOW L3）。

### Added

- **BREAKING**：新增 `CertifiedTransaction`（macdoc#137 第一階段，Word-imitation 方法論的 Layer 1：package 與位元組保留）。`CertifiedTransaction.apply` 包裝 `Executor` + `Verifier`：在記憶體套用 manifest、把候選檔寫在輸出旁、對候選檔（不是已經寫出的輸出檔）評估新的 `Layer1Gate`（part 集合是否相符、允許範圍外的 part 是否位元組相同、package 是否可重新開啟且內部一致）與 manifest 的 `verify` 斷言，全部通過才把候選檔原子改名成輸出。**任何 gate 或 verify 失敗都不再寫入或更動輸出路徑**——先前的模式（`Executor.apply` 接著另外呼叫 `Verifier.verify`，也就是這次改版之前 `macdoc docx apply` 的走法）是無條件先寫輸出、事後才檢查，所以一次失敗的 verify 仍會留下檔案。失敗時候選檔改名保留在 `<output-stem>.rejected.<ext>`（取代前一次留下的同名檔）供診斷；`intentUnavailable`（manifest 內的 step type 不在允許表中）是唯一在候選檔存在之前就失敗的例外。新增的公開型別：`MutationIntent`（由封閉的 step-type 對照表推導允許變更的 part，表中沒有的 functional step type 一律失敗閉合，不做相似性推論）、`Layer1Gate` / `Layer1Result` / `Layer1Violation`、`CertificationCertificate` / `CertificationStatus` / `VerifyOutcome` / `NotEvaluatedLayer`（JSON 證書；`status` 只有 `layer1Verified` 或 `rejected`，schema 上不可能出現 `certified`；Layer 2、Layer 3 一律 `notEvaluated` 並附 `reason`，不宣稱未量測過的東西）、`CertificationError`（`gateFailed`、`verifyFailed`、`baselineChanged`、`intentUnavailable`，R2 再加 `outputPathIsDirectory(path:)` 與 `certificateDestinationInvalid(path:reason:)`，見上方 Fixed 條目）。`apply` 另外多一個 `certificateWarnHandler: (String) -> Void`（有預設值，來源相容），用來回報「憑證目的地驗證通過、但寫入時仍失敗」這種競態，見上方 Fixed 條目。`Executor` 與 `Verifier` 本身未變——沒有改用 `CertifiedTransaction` 的既有直接呼叫者不受影響。

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
