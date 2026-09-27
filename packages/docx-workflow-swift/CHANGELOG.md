# Changelog

All notable changes to `docx-workflow-swift` are recorded here.

## Unreleased

### Fixed

- **`set_bold` 對任何文件都會失敗，manifest 必填的 `substring` 欄位從未被使用**（macdoc#232）。`EditPlanner` 過去把 `set_bold` 編譯成 `OOXMLEdit.setBold(target: 錨點段落 ID, value: true)`——`setBold` 對應 ooxml-swift 的 `Operation.setRunFormat`，reducer 要求目標是 `<w:r>`，指向段落一律失敗（`ReducerError.malformedOp("setRunFormat target must be <w:r>")`），`substring` 完全沒被讀取。改用 ooxml-swift 3.16.0 新增的 `OOXMLEdit.setBoldInRange(target:substring:value:instance:)`：以段落 ElementID＋`substring` 定位段落中的一段文字，必要時就地切分 run，只對比對到的範圍套格式，段落其餘文字與其他 run 不受影響；`instance` 用預設第 1 次出現。空字串的 `substring` 在 `EditPlanner.compile` 階段就以 `.pending` 回報（與 `wrap_link` 對不可解析 URL 的既有處理一致），不會被送到 reducer 才失敗。同版 ooxml-swift 也讓 `ReducerError` 實作 `LocalizedError`，`macdoc docx apply` 找不到 substring（或範圍跨越修訂、超連結等邊界）時，錯誤輸出改為含 ooxml-swift 給的具體原因（例如 `setRunFormatInRange: substring "X" occurrence 1 not found`），不再只剩泛用的「error 1」；失敗時 CLI 以非零 exit 結束，輸出檔完全不寫入（#137 的交易語意，`Executor.apply` 在 `doc.apply(edit)` 拋錯時位於 `DocxWriter.write` 之前，候選檔從未產生）。
- **`Executor.apply` 不再刪除或重寫未被 step 觸及的 part**（macdoc#231）。過去以 `DocxWriter.writeData`（scratch 模式）產生輸出，從 typed model 重新序列化全部 part：模型不產生的 part（主題、註腳、尾註、webSettings、自訂 XML）被靜默刪除，其餘每個 part 都被重寫，卻仍回報成功。改用 overlay 模式的 `DocxWriter.write(_:to:)` 後，輸出以 baseline 的原始 archive 為底，只取代 step 實際改動的 part；寫入同時是原子的（暫存檔加改名）。以真實 Word 範本（13 個 part）實測：`insert_paragraph` 只改 `word/document.xml`，`wrap_link` 另加 `word/_rels/document.xml.rels`，無一 part 被刪。回歸測試 `ExecutorTests.testApplyPreservesPartsTheStepDoesNotTouch` 以帶 theme relationship 與自訂 part 的 baseline 逐 part 比對。
- **CertifiedTransaction 的憑證寫入失敗不再蓋掉交易本身的成功/失敗訊號**（macdoc#137 對抗式審查 R2，review-c137.md CRITICAL Finding 1）。修前：憑證在 commit 之後才寫，寫入失敗丟出的不是 CertificationError，呼叫端接不住，導致成功的 apply 也回報失敗、失敗的 apply 則整段吃掉真正的失敗原因與 rejected-candidate 路徑。修法兩層：交易開始前先驗證 `--certificate` 目的地（父目錄存在、可寫、路徑本身不是既有目錄），不符直接以新的 `CertificationError.certificateDestinationInvalid(path:reason:)` 中止、不寫任何檔案；驗證通過後才發生的寫入失敗（競態）改走原子寫法且不再拋錯，改用新的 `certificateWarnHandler` callback 回報，交易本身的回傳/拋出結果完全不受影響。
- **CertifiedTransaction 的輸出路徑若是既有目錄會被靜默整個刪除取代**（同一輪審查 MEDIUM Finding 2）。`commit` 呼叫的 `FileManager.replaceItemAt` 對「目的地是目錄」會直接刪除整個目錄樹再放上新檔案、不報錯。新增 `CertificationError.outputPathIsDirectory(path:)`，在交易開始前（與上一條同一步）拒絕，不做任何寫入。
- **`Layer1Gate` 的 `[Content_Types].xml` Default Extension 比對改成不分大小寫**（OPC（ECMA-376 Part 2）對 Content Types stream `Default` 元素的規定；同一輪審查 LOW L2）。
- **`Layer1Gate` 的 relationship Target 解析前先做百分比解碼**（例如 `%20`；同一輪審查 LOW L3）。
- **`--certificate` 指定的路徑若與 `--output`、`--input`（baseline）、manifest 或 rejected 候選檔路徑相同，直接拒絕**（macdoc#137）。憑證的寫入時機在 commit 之後；兩個路徑字面相同（或透過 hard link、大小寫不敏感檔案系統實際指向同一檔案）時，憑證 JSON 會覆寫剛驗證過的輸出檔或使用者的來源檔案，且 CLI 原本仍回報成功、不印任何警告。現在會在交易開始前先擋下，新增 `CertificationError.certificateDestinationConflictsWithOtherPath` 與公開的 `CertifiedTransaction.filesAreIdentical(_:_:)`。
- **`commit` 改名操作的最後一步改用 POSIX `rename(2)`，不再用 `FileManager.replaceItemAt`**（macdoc#137）。輸出路徑若在通過前置檢查之後、實際改名之前剛好被建成目錄，`rename(2)` 會直接以 `EISDIR` 拒絕，不會像過去那樣把目錄與其內容整個刪除取代；候選檔會保留在 rejected 路徑供診斷，新增 `CertificationError.commitFailed`。
- **`Layer1Gate` 的 `[Content_Types].xml` Override PartName 比對也改成不分大小寫**（macdoc#137），與 Default Extension 的規則一致，皆依 OPC（ECMA-376 Part 2）對 Content Types stream 的規定。
- **`--certificate` 與 `--output` 只差大小寫、且兩者事前都不存在時，憑證寫入仍會蓋掉剛驗證過的輸出**（macdoc#137）。前一條「路徑相同直接拒絕」的檢查在兩個檔案都還不存在時看不出兩者其實是同一個檔案（大小寫不敏感檔案系統上，`Out.docx` 與 `out.docx`一旦其中之一被建立就是同一檔）；commit 建出輸出之後，緊接著的憑證寫入才會撞上、把輸出覆寫成憑證 JSON，而交易仍回報成功。現在在 commit 之後、寫憑證之前多做一次同檔判定，命中時不寫憑證、改用既有的憑證寫入失敗回報機制，交易本身「已成功 commit」的結果不受影響、照實回報。
- **`--output` 若本身是指向他處檔案的符號連結，會被靜默拆掉、換成真檔，原本的別名關係與使用者可能沒注意到的資料分岔就此發生**（macdoc#137）。`commit` 改名操作使用的 POSIX `rename(2)` 對「目的地是符號連結」的處理方式是直接替換連結本身、不會 follow 連結去改動它指向的檔案——過去的做法在同一情境下會直接失敗且兩邊都不動。現在交易開始前與 commit 前都會偵測 `--output` 是否為符號連結，偵測到就拒絕、不做任何寫入（或保留候選檔供診斷），新增 `CertificationError.outputPathIsSymlink`。
- **覆寫既有 `--output` 檔案時，原本的權限位、ACL、擴充屬性會被悄悄換成新檔案的預設值，可能把使用者刻意設緊的權限放寬**（macdoc#137）。commit 改名操作本身不會像過去的作法那樣保留被取代檔案的這些屬性。現在若輸出路徑已存在，commit 前會把舊檔的權限、ACL、擴充屬性複製到候選檔（不含修改時間——內容確實變了；建立時間則會保留舊檔的值）；複製本身失敗時不會讓新檔案帶著更寬的權限落地，改為拒絕 commit、保留候選檔，新增 `CertificationError.metadataPreservationFailed`。

### Added

- **BREAKING**：新增 `CertifiedTransaction`（macdoc#137 第一階段，Word-imitation 方法論的 Layer 1：package 與位元組保留）。`CertifiedTransaction.apply` 包裝 `Executor` + `Verifier`：在記憶體套用 manifest、把候選檔寫在輸出旁、對候選檔（不是已經寫出的輸出檔）評估新的 `Layer1Gate`（part 集合是否相符、允許範圍外的 part 是否位元組相同、package 是否可重新開啟且內部一致）與 manifest 的 `verify` 斷言，全部通過才把候選檔原子改名成輸出。**任何 gate 或 verify 失敗都不再寫入或更動輸出路徑**——先前的模式（`Executor.apply` 接著另外呼叫 `Verifier.verify`，也就是這次改版之前 `macdoc docx apply` 的走法）是無條件先寫輸出、事後才檢查，所以一次失敗的 verify 仍會留下檔案。失敗時候選檔改名保留在 `<output-stem>.rejected.<ext>`（取代前一次留下的同名檔）供診斷；`intentUnavailable`（manifest 內的 step type 不在允許表中）是唯一在候選檔存在之前就失敗的例外。新增的公開型別：`MutationIntent`（由封閉的 step-type 對照表推導允許變更的 part，表中沒有的 functional step type 一律失敗閉合，不做相似性推論）、`Layer1Gate` / `Layer1Result` / `Layer1Violation`、`CertificationCertificate` / `CertificationStatus` / `VerifyOutcome` / `NotEvaluatedLayer`（JSON 證書；`status` 只有 `layer1Verified` 或 `rejected`，schema 上不可能出現 `certified`；Layer 2、Layer 3 一律 `notEvaluated` 並附 `reason`，不宣稱未量測過的東西）、`CertificationError`（`gateFailed`、`verifyFailed`、`baselineChanged`、`intentUnavailable`，後續再加 `outputPathIsDirectory(path:)`、`certificateDestinationInvalid(path:reason:)`、`certificateDestinationConflictsWithOtherPath(certificatePath:conflictingRole:conflictingPath:)`、`commitFailed(path:reason:rejectedCandidatePath:)`、`outputPathIsSymlink(path:linkTarget:rejectedCandidatePath:)`、`metadataPreservationFailed(path:reason:rejectedCandidatePath:)`，見上方 Fixed 條目）、公開的 `CertifiedTransaction.filesAreIdentical(_:_:) -> Bool`（判斷兩個路徑是否指向同一檔案：先比對標準化後的路徑字串，兩者都存在時再比對 device/inode，涵蓋 hard link 與大小寫不敏感檔案系統）。`apply` 另外多一個 `certificateWarnHandler: (String) -> Void`（有預設值，來源相容），用來回報「憑證目的地驗證通過、但寫入時仍失敗」這種競態，見上方 Fixed 條目。`Executor` 與 `Verifier` 本身未變——沒有改用 `CertifiedTransaction` 的既有直接呼叫者不受影響。

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
