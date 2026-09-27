## Purpose

Docx mutation certification makes every `macdoc docx apply` prove, before anything reaches the output path, that the manifest changed only the package parts its steps are allowed to change and that the result is a well-formed package. The certificate it produces states exactly which evidence layers were evaluated and never claims a layer that was not measured.

## ADDED Requirements

### Requirement: Mutation intent is derived from a closed step-type table

`MutationIntent.derive(from:)` SHALL compute the set of package parts a manifest is allowed to change as the union, over its runtime-functional steps, of a fixed per-step-type table. Pending (skipped) steps SHALL contribute no parts. The table SHALL be exactly:

| Step type | Allowed parts |
|---|---|
| `insert_paragraph` | `word/document.xml` |
| `remove_paragraph` | `word/document.xml` |
| `set_bold` | `word/document.xml` |
| `wrap_link` | `word/document.xml`, `word/_rels/document.xml.rels` |

A runtime-functional step whose type has no row SHALL cause `derive(from:)` to throw `CertificationError.intentUnavailable(stepType:)`. The table SHALL NOT be extended by similarity to another step type, and a manifest SHALL NOT widen the derived set.

#### Scenario: Link step allows the relationships part

- **WHEN** a manifest contains one `insert_paragraph` step and one `wrap_link` step
- **THEN** the derived allowed parts are exactly `word/document.xml` and `word/_rels/document.xml.rels`

##### Example: Allowed-part derivation

| Functional steps | Allowed parts |
| ---------------- | ------------- |
| `insert_paragraph` | `word/document.xml` |
| `remove_paragraph`, `set_bold` | `word/document.xml` |
| `insert_paragraph`, `wrap_link` | `word/document.xml`, `word/_rels/document.xml.rels` |
| (only pending steps) | (empty set) |

#### Scenario: Unknown functional step type fails closed

- **WHEN** a manifest contains a runtime-functional step type that has no row in the table
- **THEN** `derive(from:)` throws `CertificationError.intentUnavailable` naming that step type
- **AND** no candidate file is written

### Requirement: Layer 1 gate proves package and byte preservation

`Layer1Gate.evaluate(baseline:candidate:intent:)` SHALL pass only when all of the following hold. Otherwise it SHALL fail with one `Layer1Violation` per breach:

- The candidate's set of part names equals the baseline's. A missing part yields `partRemoved`; an extra part yields `partAdded`.
- Every part outside the intent's allowed set is byte-identical between baseline and candidate. A breach yields `unexpectedChange`, carrying both sizes and the first differing byte offset.
- The candidate re-opens through `DocxReader`. Otherwise the result is `unreadablePackage`.
- Every part whose name ends in `.xml` or `.rels` parses as well-formed XML. Otherwise the result is `malformedXML`.
- `[Content_Types].xml` assigns a content type to every part, by `Override` or by extension `Default`. Both the `Override` element's `PartName` attribute and the `Default` element's `Extension` attribute comparisons SHALL be case-insensitive, per OPC (ECMA-376 Part 2): the Content Types stream compares part names and extensions the same way regardless of which element carries them. Otherwise the result is `missingContentType`.
- Every internal relationship target, percent-decoded first, resolves to an existing part. Otherwise the result is `danglingRelationship`, naming the target as it was written (not decoded).

The result SHALL list `changedParts`, the parts whose bytes differ, whether or not they were allowed.

#### Scenario: Step touches only its allowed part

- **WHEN** a baseline carrying a theme part and a custom XML part has one `insert_paragraph` applied
- **THEN** the gate passes with `changedParts` equal to `word/document.xml`

#### Scenario: A dropped part is reported

- **WHEN** the candidate lacks `word/theme/theme1.xml` that the baseline has
- **THEN** the gate fails with `partRemoved("word/theme/theme1.xml")`

#### Scenario: An unallowed change is reported with its offset

- **WHEN** `word/styles.xml` differs between baseline and candidate and is not in the allowed set
- **THEN** the gate fails with `unexpectedChange` naming `word/styles.xml`, both sizes, and the first differing offset

#### Scenario: Dangling relationship is reported

- **WHEN** a relationship in the candidate targets a part that does not exist in the candidate
- **THEN** the gate fails with `danglingRelationship` naming the source relationships part and the target

#### Scenario: Content-type Default extension match is case-insensitive

- **WHEN** `[Content_Types].xml`'s `Default` for a part's extension is written in a different case than the part's own extension (for example `Extension="RELS"` covering a part ending in `.rels`)
- **THEN** the gate does not report `missingContentType` for that part

#### Scenario: Content-type Override part-name match is case-insensitive

- **WHEN** `[Content_Types].xml`'s `Override` for a part is written with a `PartName` in a different case than the part's own name, and no generic `Default` for that extension covers it
- **THEN** the gate does not report `missingContentType` for that part

#### Scenario: Relationship target is percent-decoded before resolution

- **WHEN** a relationship's `Target` is percent-encoded (for example a space written as `%20`) and the decoded path resolves to a part that exists
- **THEN** the gate does not report `danglingRelationship` for that relationship

### Requirement: Pre-flight destination checks reject an unwritable output or certificate path before any write

Before `CertifiedTransaction.apply` reads the baseline, it SHALL reject these destinations without creating, truncating or replacing anything:

- The output path, if it already exists and is a directory, SHALL cause `apply` to throw `CertificationError.outputPathIsDirectory(path:)`.
- When a certificate URL is given, its destination SHALL be validated: the parent directory SHALL exist and be writable, and the destination itself, if something already exists there, SHALL NOT be a directory. Otherwise `apply` SHALL throw `CertificationError.certificateDestinationInvalid(path:reason:)`.
- When a certificate URL is given, it SHALL NOT refer to the same file — per `CertifiedTransaction.filesAreIdentical(_:_:)` — as the output path, the baseline path, or the rejected-candidate path this same call would use. Otherwise `apply` SHALL throw `CertificationError.certificateDestinationConflictsWithOtherPath(certificatePath:conflictingRole:conflictingPath:)`.

`filesAreIdentical(_:_:)` SHALL consider two paths the same file when either their symlink-resolved, standardized paths are textually equal, or — when both actually exist — they share the same device and inode.

None of these cases SHALL produce a `CertificationCertificate`; like `intentUnavailable`, all fail before any candidate exists. These checks SHALL run regardless of whether the manifest's steps and `verify` block would otherwise have succeeded or failed.

#### Scenario: Output path is an existing directory

- **WHEN** the output path already exists and is a directory
- **THEN** `apply` throws `CertificationError.outputPathIsDirectory`
- **AND** the directory and everything in it are unchanged
- **AND** the baseline is unchanged

#### Scenario: Certificate destination is invalid

- **WHEN** a certificate URL is given whose parent directory does not exist
- **THEN** `apply` throws `CertificationError.certificateDestinationInvalid` naming the path and a reason
- **AND** neither the output, the certificate, nor any candidate file is created
- **AND** this holds whether the manifest's steps and `verify` block would otherwise have caused a successful or a rejected transaction

#### Scenario: Certificate destination equals the output or the baseline path

- **WHEN** the certificate URL is the same file as the output path, or the same file as the baseline path
- **THEN** `apply` throws `CertificationError.certificateDestinationConflictsWithOtherPath`, naming which path it collided with
- **AND** neither the output, the certificate, nor any candidate file is created
- **AND** the baseline's bytes are unchanged

#### Scenario: Certificate destination equals the baseline via a hard link

- **WHEN** the certificate URL is a different path string than the baseline path, but a hard link to the same inode
- **THEN** `apply` throws `CertificationError.certificateDestinationConflictsWithOtherPath`
- **AND** the baseline's bytes, read through either path, are unchanged

### Requirement: A certificate write failing after pre-flight validation passed does not change the transaction's own result

After the certificate destination has passed the pre-flight check above, `CertifiedTransaction.apply` SHALL write the certificate atomically. If that write still fails (a race — the destination changed between the check and the write), `apply` SHALL NOT let that failure change whether it returns or throws for the transaction itself, and SHALL NOT change which `CertificationCertificate` it returns or carries. It SHALL instead invoke a `certificateWarnHandler` callback exactly once with a description of the failure.

#### Scenario: Certificate write fails after a successful commit

- **WHEN** the Layer 1 gate and every requested `verify` assertion pass, the output is committed, and the certificate write then fails despite the destination having passed pre-flight validation
- **THEN** `apply` still returns a certificate with `status` `layer1Verified`
- **AND** the output path still holds the candidate's bytes
- **AND** `certificateWarnHandler` is called once
- **AND** no file exists at the certificate destination

#### Scenario: Certificate write fails after a rejected commit

- **WHEN** a manifest `verify` assertion fails, the candidate is committed to the rejected-candidate path, and the certificate write then fails despite the destination having passed pre-flight validation
- **THEN** `apply` still throws `CertificationError.verifyFailed` carrying the same `VerifyError` and a certificate whose `rejectedCandidateURL` is set
- **AND** `certificateWarnHandler` is called once

### Requirement: Certified transaction commits only after every gate passes

`CertifiedTransaction.apply` SHALL run the following sequence:

1. Read the baseline and record its SHA-256.
2. Apply the manifest in memory.
3. Write a candidate file in the output's directory.
4. Evaluate the Layer 1 gate.
5. Evaluate the manifest's `verify` assertions against the candidate.
6. Recompute the baseline SHA-256.
7. Only if everything passed, atomically rename the candidate onto the output path via POSIX `rename(2)`, which SHALL refuse a directory destination (`EISDIR`) rather than delete it.

On any failure, the output path SHALL remain exactly as it was before the call. Nothing SHALL be created, truncated or replaced there. The candidate SHALL be renamed to `<output-stem>.rejected.docx` beside the output, replacing any previous rejected file, and its URL SHALL be recorded in the certificate.

If step 7's rename itself fails — for example because something occupied the output path with a directory after pre-flight validation ran — `apply` SHALL throw `CertificationError.commitFailed(path:reason:rejectedCandidatePath:)` instead of committing. It SHALL first attempt to preserve the candidate at the rejected-candidate path; `rejectedCandidatePath` SHALL be that path when this attempt succeeds, and `nil` only when it also fails, in which case the candidate SHALL remain at its own temporary path rather than be deleted.

#### Scenario: Successful apply writes the output

- **WHEN** every gate and every `verify` assertion passes
- **THEN** the output path contains the candidate's bytes and no candidate or rejected file remains in the directory

#### Scenario: Gate failure leaves the output untouched

- **WHEN** the output path already holds a file and the Layer 1 gate fails
- **THEN** the output path still holds the original bytes
- **AND** `<output-stem>.rejected.docx` holds the candidate's bytes

#### Scenario: Verify failure no longer writes the output

- **WHEN** the output path does not exist and a manifest `verify` assertion fails
- **THEN** the output path still does not exist and the error is `CertificationError.verifyFailed`

#### Scenario: Baseline changed before commit

- **WHEN** the baseline file's bytes change after it was read and before the commit
- **THEN** the transaction throws `CertificationError.baselineChanged` and the output path is untouched

#### Scenario: A directory appears at the output path between pre-flight and commit

- **WHEN** every gate and every `verify` assertion passes, but something creates a directory at the output path after the pre-flight check ran and before the commit rename
- **THEN** the transaction throws `CertificationError.commitFailed`
- **AND** the directory and its contents are unchanged (not deleted)
- **AND** the candidate is preserved at the rejected-candidate path, carrying the applied change

### Requirement: Certificate claims only evaluated layers

Every `CertifiedTransaction.apply` call SHALL produce a `CertificationCertificate`, returned on success and carried by the error on failure. It SHALL be encoded as JSON with `schemaVersion` 1. Its `status` SHALL be `layer1Verified` when the Layer 1 gate passed and every requested `verify` assertion passed, and `rejected` otherwise. The value `certified` SHALL NOT be used by this schema version. The `layer2` and `layer3` fields SHALL both be `notEvaluated` with a non-empty `reason`. The certificate SHALL carry:

- `baselineSHA256` and `candidateSHA256`
- `allowedParts` and `changedParts`
- the Layer 1 result, including any violations
- the `verify` outcome: `passed`, `failed` or `notRequested`
- the output URL, and the rejected-candidate URL when there is one
- a creation timestamp

#### Scenario: Successful certificate

- **WHEN** a single `insert_paragraph` manifest with no `verify` block is applied successfully
- **THEN** the certificate has `status` `layer1Verified`, `verify` `notRequested`, `layer2` and `layer3` `notEvaluated`, and `changedParts` equal to `word/document.xml`

#### Scenario: Rejected certificate

- **WHEN** the Layer 1 gate fails
- **THEN** the certificate has `status` `rejected`, lists the violations, and carries the rejected-candidate URL
