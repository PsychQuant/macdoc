## 1. Mutation intent

- [x] 1.1 Mutation intent is derived from a closed step-type table. `MutationIntent.derive(from:)` returns the union of the table rows for runtime-functional steps; pending steps contribute nothing; an unlisted functional step type throws `CertificationError.intentUnavailable(stepType:)`. Implements the design decision "Derive allowed parts from step types through a closed table". Verified by `MutationIntentTests` covering every row of the spec's "Allowed-part derivation" example and the unknown-type failure, written RED first.

## 2. Layer 1 gate

- [x] 2.1 [P] Layer 1 gate proves package and byte preservation — part-set and byte checks. `Layer1Gate.evaluate` reports `partAdded`, `partRemoved`, and `unexpectedChange` with both sizes and the first differing offset. `changedParts` lists every differing part. This follows the design decision "Compare non-target parts by exact bytes, not canonical XML". Verified by `Layer1GateTests` cases for a clean pass, a dropped theme part, an added part and an unallowed `word/styles.xml` change, all written RED first.
- [x] 2.2 Layer 1 gate package-integrity checks. The candidate must re-open through `DocxReader` (`unreadablePackage`). Every `.xml` and `.rels` part must be well-formed (`malformedXML`). `[Content_Types].xml` must cover every part through an `Override` or an extension `Default` (`missingContentType`). Every internal relationship target must exist (`danglingRelationship`). Verified by one `Layer1GateTests` case per violation, each built from a synthetic package.

## 3. Certificate

- [x] 3.1 [P] Certificate claims only evaluated layers. `CertificationCertificate` is `Codable` with `schemaVersion` 1. `status` is `layer1Verified` or `rejected` and never `certified`. `layer2` and `layer3` are `notEvaluated` with a non-empty reason. The `verify` outcome is `passed`, `failed` or `notRequested`, and the certificate carries hashes, allowed and changed parts, URLs and a timestamp. This follows the design decision "Certificate claims only the layers that were evaluated". Verified by `CertificateTests`: a JSON round-trip, a check that the status vocabulary cannot encode `certified`, and a check of the key names.

## 4. Certified transaction

- [x] 4.1 Certified transaction commits only after every gate passes. It writes the candidate in the output directory and renames it onto the output only on success; on failure it renames the candidate to `<output-stem>.rejected.docx` and leaves the output path byte-identical. This follows the design decisions "Place the certified transaction at the workflow boundary, not inside OOXMLSwift apply" and "Write the candidate next to the output and keep a rejected candidate for diagnosis". Verified by `CertifiedTransactionTests`: a success case (output written, no leftovers) and a gate-failure case (a pre-existing output is unchanged and the rejected file holds the candidate bytes).
- [x] 4.2 The manifest `verify` assertions run against the candidate before commit. A verify failure throws `CertificationError.verifyFailed` and never creates the output. Verified by a `CertifiedTransactionTests` case whose `expected_paragraphs_min` is unmet while the output path did not exist beforehand.
- [x] 4.3 Guard the baseline against change between read and commit. The baseline SHA-256 recorded at read time is recomputed before the rename, and a mismatch throws `CertificationError.baselineChanged` with the output untouched. Verified by a `CertifiedTransactionTests` case that uses an internal test hook between the gate and the commit to rewrite the baseline.

## 5. CLI

- [x] 5.1 docx apply commits its output only through the certified transaction, and gains `--certificate <path>`, written on success and on failure. On failure, stderr names the failure kind and the rejected-candidate path, and the exit code is non-zero. Verified by two `MacDocDocxIntegrationTests` cases: `--certificate` producing a `layer1Verified` JSON on success, and a failing `verify` leaving `out.docx` absent.

## 6. Documentation and regression

- [ ] 6.1 Record the behavior change and the assumptions:
  - `packages/docx-workflow-swift/CHANGELOG.md` gains an entry marking as **BREAKING** that the output is no longer written when a gate or `verify` fails. **Done** — see the `### Added` entry under `## Unreleased`, beside the #231 entry.
  - The design decision "Assumptions recorded for macdoc#137's open decisions (unattended run)" is restated in a comment on macdoc#137, so the owner can overturn any assumption. **Comment 草稿已寫**（`/Users/che/.claude/jobs/b84d123c/tmp/post/c137-assumptions.md`），**待協調者發文** — 依工作指示本次執行者不得在 GitHub 留言或改 issue，草稿留待協調者（或擁有者本人）審閱後手動貼上。
  Verified by content review of the CHANGELOG entry and the posted comment URL. CHANGELOG 半段已核可；comment 半段待貼文後再核可、再打勾。
- [x] 6.2 Full regression. Run:
  - `swift test` in `packages/docx-workflow-swift`, which must include the macdoc#231 regression test `ExecutorTests.testApplyPreservesPartsTheStepDoesNotTouch`;
  - `swift test` at the macdoc root;
  - a manual run of `macdoc docx apply` with `--certificate` against a real Word template, for one `insert_paragraph` manifest and one `wrap_link` manifest.
  Verified by 0 failures in both suites and by the two certificates having `status` `layer1Verified` with `changedParts` equal to the allowed parts.

## 7. R2 — adversarial review fixes (review-c137.md)

- [x] 7.1 CRITICAL (Finding 1): a certificate-write failure must never overwrite the transaction's own success/failure signal. Two layers: (a) pre-flight validation of the `--certificate` destination (parent directory exists and is writable, destination itself is not a directory) before anything is written, throwing `CertificationError.certificateDestinationInvalid(path:reason:)`; (b) a write that still fails after that check passes (a race) is reported only through a new `certificateWarnHandler` callback and never changes `apply`'s return/throw outcome. Implements the design decisions "R2: Pre-flight checks reject an unwritable output or certificate destination before anything is touched" and "R2: A certificate write failing after pre-flight validation passed does not change the transaction's own result". Verified by `CertifiedTransactionTests` (destination invalid against a would-succeed and a would-fail-verify manifest; the write-race against a would-succeed and a would-fail-verify outcome, via the new `testHookAfterCommitBeforeCertificateWrite` seam) and by `MacDocDocxIntegrationTests` (destination invalid against both outcomes at the CLI), all written RED first.
- [x] 7.2 MEDIUM (Finding 2): an output path that already exists and is a directory must be rejected before any write, not silently deleted by `FileManager.replaceItemAt`. New `CertificationError.outputPathIsDirectory(path:)`, checked in the same pre-flight step as 7.1. Verified by a `CertifiedTransactionTests` case and a `MacDocDocxIntegrationTests` case, each confirming the directory and its contents survive intact, written RED first.
- [x] 7.3 LOW cleanup, bundled:
  - L1: `Manifest.swift`'s `Step` enum header comment corrected — it grouped 8 cases as "Phase 1 runtime-functional" though only 4 (`insertParagraph`/`removeParagraph`/`setBold`/`wrapLink`) actually are, per `EditPlanner.swift` and `MutationIntent.isRuntimeFunctional`. Documentation only, no test.
  - L2: `Layer1Gate`'s `[Content_Types].xml` `Default` `Extension` matching made case-insensitive (OPC ECMA-376 Part 2 §10.1.2.2.1). Verified by `Layer1GateTests.testContentTypeDefaultExtensionMatchIsCaseInsensitive`, written RED first.
  - L3: relationship `Target` percent-decoded before resolution. Verified by `Layer1GateTests.testRelationshipTargetIsPercentDecodedBeforeResolution`, written RED first.
  - L4: dedicated `../` relative-target test pair added (positive: resolves to an existing sibling-directory part; negative: reported dangling when that part is absent, proving the traversal is exercised). Both pass unmodified against the existing `resolveTarget`/`ownerDirectory` logic — a characterization test confirming code the review already judged correct by inspection, not a bug fix.
  - L5: `MacDoc+Docx.swift`'s `Apply.run()` wraps any non-`CertificationError` failure (manifest/baseline read errors, existing Executor errors such as `set_bold`'s macdoc#232) with the repo's Traditional Chinese `錯誤：` prefix instead of letting swift-argument-parser's default English printer show through. CLI presentation only — does not fix any underlying error. Verified by `MacDocDocxIntegrationTests.testNonCertificationErrorIsWrappedWithChinesePrefix`, written RED first.
  Verified overall by `spectra analyze`/`validate` staying clean and both full test suites passing 0 failures (see the R2 section of `/Users/che/.claude/jobs/b84d123c/tmp/reports/c137-layer1.md`).
