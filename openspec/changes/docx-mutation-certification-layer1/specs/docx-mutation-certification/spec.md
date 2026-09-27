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
- `[Content_Types].xml` assigns a content type to every part, by `Override` or by extension `Default`. Otherwise the result is `missingContentType`.
- Every internal relationship target resolves to an existing part. Otherwise the result is `danglingRelationship`.

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

### Requirement: Certified transaction commits only after every gate passes

`CertifiedTransaction.apply` SHALL run the following sequence:

1. Read the baseline and record its SHA-256.
2. Apply the manifest in memory.
3. Write a candidate file in the output's directory.
4. Evaluate the Layer 1 gate.
5. Evaluate the manifest's `verify` assertions against the candidate.
6. Recompute the baseline SHA-256.
7. Only if everything passed, atomically rename the candidate onto the output path.

On any failure, the output path SHALL remain exactly as it was before the call. Nothing SHALL be created, truncated or replaced there. The candidate SHALL be renamed to `<output-stem>.rejected.docx` beside the output, replacing any previous rejected file, and its URL SHALL be recorded in the certificate.

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
