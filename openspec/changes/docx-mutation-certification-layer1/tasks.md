## 1. Mutation intent

- [x] 1.1 Mutation intent is derived from a closed step-type table. `MutationIntent.derive(from:)` returns the union of the table rows for runtime-functional steps; pending steps contribute nothing; an unlisted functional step type throws `CertificationError.intentUnavailable(stepType:)`. Implements the design decision "Derive allowed parts from step types through a closed table". Verified by `MutationIntentTests` covering every row of the spec's "Allowed-part derivation" example and the unknown-type failure, written RED first.

## 2. Layer 1 gate

- [x] 2.1 [P] Layer 1 gate proves package and byte preservation — part-set and byte checks. `Layer1Gate.evaluate` reports `partAdded`, `partRemoved`, and `unexpectedChange` with both sizes and the first differing offset. `changedParts` lists every differing part. This follows the design decision "Compare non-target parts by exact bytes, not canonical XML". Verified by `Layer1GateTests` cases for a clean pass, a dropped theme part, an added part and an unallowed `word/styles.xml` change, all written RED first.
- [x] 2.2 Layer 1 gate package-integrity checks. The candidate must re-open through `DocxReader` (`unreadablePackage`). Every `.xml` and `.rels` part must be well-formed (`malformedXML`). `[Content_Types].xml` must cover every part through an `Override` or an extension `Default` (`missingContentType`). Every internal relationship target must exist (`danglingRelationship`). Verified by one `Layer1GateTests` case per violation, each built from a synthetic package.

## 3. Certificate

- [x] 3.1 [P] Certificate claims only evaluated layers. `CertificationCertificate` is `Codable` with `schemaVersion` 1. `status` is `layer1Verified` or `rejected` and never `certified`. `layer2` and `layer3` are `notEvaluated` with a non-empty reason. The `verify` outcome is `passed`, `failed` or `notRequested`, and the certificate carries hashes, allowed and changed parts, URLs and a timestamp. This follows the design decision "Certificate claims only the layers that were evaluated". Verified by `CertificateTests`: a JSON round-trip, a check that the status vocabulary cannot encode `certified`, and a check of the key names.

## 4. Certified transaction

- [ ] 4.1 Certified transaction commits only after every gate passes. It writes the candidate in the output directory and renames it onto the output only on success; on failure it renames the candidate to `<output-stem>.rejected.docx` and leaves the output path byte-identical. This follows the design decisions "Place the certified transaction at the workflow boundary, not inside OOXMLSwift apply" and "Write the candidate next to the output and keep a rejected candidate for diagnosis". Verified by `CertifiedTransactionTests`: a success case (output written, no leftovers) and a gate-failure case (a pre-existing output is unchanged and the rejected file holds the candidate bytes).
- [ ] 4.2 The manifest `verify` assertions run against the candidate before commit. A verify failure throws `CertificationError.verifyFailed` and never creates the output. Verified by a `CertifiedTransactionTests` case whose `expected_paragraphs_min` is unmet while the output path did not exist beforehand.
- [ ] 4.3 Guard the baseline against change between read and commit. The baseline SHA-256 recorded at read time is recomputed before the rename, and a mismatch throws `CertificationError.baselineChanged` with the output untouched. Verified by a `CertifiedTransactionTests` case that uses an internal test hook between the gate and the commit to rewrite the baseline.

## 5. CLI

- [ ] 5.1 docx apply commits its output only through the certified transaction, and gains `--certificate <path>`, written on success and on failure. On failure, stderr names the failure kind and the rejected-candidate path, and the exit code is non-zero. Verified by two `MacDocDocxIntegrationTests` cases: `--certificate` producing a `layer1Verified` JSON on success, and a failing `verify` leaving `out.docx` absent.

## 6. Documentation and regression

- [ ] 6.1 Record the behavior change and the assumptions:
  - `packages/docx-workflow-swift/CHANGELOG.md` gains an entry marking as **BREAKING** that the output is no longer written when a gate or `verify` fails.
  - The design decision "Assumptions recorded for macdoc#137's open decisions (unattended run)" is restated in a comment on macdoc#137, so the owner can overturn any assumption.
  Verified by content review of the CHANGELOG entry and the posted comment URL.
- [ ] 6.2 Full regression. Run:
  - `swift test` in `packages/docx-workflow-swift`, which must include the macdoc#231 regression test `ExecutorTests.testApplyPreservesPartsTheStepDoesNotTouch`;
  - `swift test` at the macdoc root;
  - a manual run of `macdoc docx apply` with `--certificate` against a real Word template, for one `insert_paragraph` manifest and one `wrap_link` manifest.
  Verified by 0 failures in both suites and by the two certificates having `status` `layer1Verified` with `changedParts` equal to the allowed parts.
