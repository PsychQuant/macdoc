## Context

macdoc#137 asks that every document modification be provably lossless and that its result state exactly what was proven. The Word-imitation methodology already defines three layers of evidence:

- Layer 1: bytes and package integrity.
- Layer 2: typed round-trip.
- Layer 3: real-Word rendering.

These layers exist as tests and research tooling. No production write path is gated by them.

The production path examined here is `macdoc docx apply`. It is backed by `DocxWorkflowLib.Executor.apply` followed by `Verifier.verify` in the CLI. Its current order is apply, then write the final output, then verify. A verify failure therefore still leaves the output file behind.

macdoc#231 found that the writer used by `Executor` was scratch mode. It dropped four parts and rewrote every other part of a real Word template on every successful apply. The fix, overlay-mode `DocxWriter.write(_:to:)`, is merged separately and is a prerequisite here: with it, a real `insert_paragraph` changes only `word/document.xml`, and a real `wrap_link` changes only `word/document.xml` and `word/_rels/document.xml.rels`. That observation is what makes a byte-preservation gate practical.

This change is the first slice of macdoc#137. It covers `macdoc docx apply` only.

## Goals / Non-Goals

**Goals:**

- `macdoc docx apply` never writes its output unless every gate has passed. A failure leaves the output path exactly as it was.
- Every part the manifest's steps are not allowed to touch is proven byte-identical between baseline and output. No part is added or dropped.
- The output is proven to be a well-formed package:
  - It re-opens through `DocxReader`.
  - Every XML part is well-formed.
  - Every part has a content type.
  - Every internal relationship target exists.
- A machine-readable certificate records what was proven and, equally, what was not evaluated.

**Non-Goals:**

- Layer 2 (typed round-trip / trial-rebuild gate) and Layer 3 (real-Word render oracle). They are later slices of macdoc#137. This change records both as `notEvaluated`.
- Certifying che-word-mcp saves, autosaves or `finalize_document`. The same holds for direct `DocxWriter` callers and any other write path. They stay uncertified and are not touched here.
- Verifying that the intended change inside an allowed part is itself correct. For example: the inserted paragraph has the right text and nothing else in `word/document.xml` moved. That is sub-part preservation, deferred to the Layer 2 slice.
- Fixing `set_bold` (macdoc#232) or adding run splitting (macdoc#110).
- Canonical-XML (c14n) comparison. Byte identity is used; see the decisions below.

## Decisions

### Place the certified transaction at the workflow boundary, not inside OOXMLSwift apply

The transaction lives in `DocxWorkflowLib`, wrapping `Executor`.

- **Alternative**: enforce preservation inside `WordDocument.apply` in ooxml-swift. Rejected for this slice. It needs a cross-repo release. It would also couple the deterministic core to package-level policy, such as which parts a step may touch.
- The macdoc#137 diagnosis recommends a layered coordinator at the tool boundary. This decision follows it.
- The core may still gain its own preservation check later; the two layers do not conflict.

### Derive allowed parts from step types through a closed table

Each runtime-functional step type maps to an explicit set of package parts it may change:

| Step type | Allowed parts |
|---|---|
| `insert_paragraph` | `word/document.xml` |
| `remove_paragraph` | `word/document.xml` |
| `set_bold` | `word/document.xml` |
| `wrap_link` | `word/document.xml`, `word/_rels/document.xml.rels` |

The table is closed. A step type that compiles to a functional edit but has no row fails the transaction with `intentUnavailable`; nothing is inferred from similarity to another step. Pending (skipped) steps contribute no parts.

- **Alternative**: let the manifest declare its own allowed parts. Rejected as the default. The manifest author could then widen the gate silently. A later slice MAY let a manifest narrow the derived set, never widen it.

### Compare non-target parts by exact bytes, not canonical XML

Parts outside the allowed set must be byte-identical.

- **Alternative**: canonical XML (c14n). Rejected for this slice. After macdoc#231, untouched parts are copied verbatim, so exact bytes is both achievable and strictly stronger.
- c14n would hide real drift, such as attribute reordering or namespace rewrites, which Word may treat differently.
- The existing `byte_preserved_parts` verify mode also compares raw bytes, so this is consistent.

### Write the candidate next to the output and keep a rejected candidate for diagnosis

The candidate is written in the output's directory, as `<output-stem>.candidate-<UUID>.docx`, so the final rename stays on one volume and is atomic.

- On success, the candidate is renamed onto the output path.
- On failure, it is renamed to `<output-stem>.rejected.docx`, replacing any earlier rejected file. Its path is reported, so the evidence macdoc#137 asks for is available without re-running.
- The output path itself is never created, truncated or replaced on failure.

### Certificate claims only the layers that were evaluated

The certificate status is `layer1Verified` or `rejected`. It is never `certified`. Layer 2 and Layer 3 are recorded as `notEvaluated`, with a reason naming the future slice.

This applies macdoc#137's "no probe, no claim" rule to the certificate itself. A consumer that needs all three layers can read the per-layer fields and refuse `notEvaluated`.

### Guard the baseline against change between read and commit

The baseline's SHA-256 is recorded when it is read. It is recomputed immediately before the commit rename; a mismatch fails with `baselineChanged`.

Output-path races (another process writing the output between check and rename) are out of scope. The rename replaces whatever is there, which is the same semantics as today.

### Assumptions recorded for macdoc#137's open decisions (unattended run)

macdoc#137 left three decisions for a discussion with the owner. This slice was produced by an unattended `/idd-all` run, which proceeds on documented assumptions rather than stopping. Each assumption is scoped so that a different later choice needs no rework here.

1. **Certified / uncertified boundary**: only `macdoc docx apply` is certified in this slice. Other write paths remain uncertified and make no certification claim.
2. **Word-oracle strictness**: not decided here. Layer 3 is out of scope and recorded as `notEvaluated`.
3. **Rollout order**: this slice, then Layer 2 as a typed round-trip gate, then Layer 3 as a render-oracle protocol with fail-closed semantics, then che-word-mcp `finalize_document` integration.

## Implementation Contract

**Behavior**

`macdoc docx apply <manifest> --input <baseline> --output <output> [--certificate <path>]` behaves as follows:

1. Reads the baseline and records its SHA-256.
2. Applies the steps in memory and writes the candidate.
3. Runs the Layer 1 gate, then the manifest's `verify` assertions, both against the candidate.
4. Re-checks the baseline hash.
5. Renames the candidate onto the output.

When `--certificate` is given, the certificate JSON is written to that path in both the success and the failure case. On success, the exit code is 0 and stderr reports the output path, as today. On failure, the exit code is non-zero, the output path is untouched, and stderr names the failure and the rejected-candidate path.

**Interface** (`DocxWorkflowLib`, public)

- `MutationIntent` holds the allowed parts and the per-step summary. It is derived with `MutationIntent.derive(from: Manifest)`, which throws `CertificationError.intentUnavailable(stepType:)`.
- `Layer1Gate.evaluate(baseline: URL, candidate: URL, intent: MutationIntent) -> Layer1Result`. `Layer1Result` carries `passed: Bool`, `changedParts: [String]` and `violations: [Layer1Violation]`.
- `Layer1Violation` is a closed enum:
  - `partAdded(String)`
  - `partRemoved(String)`
  - `unexpectedChange(part: String, baselineSize: Int, candidateSize: Int, firstDifferingOffset: Int)`
  - `unreadablePackage(String)`
  - `malformedXML(part: String, message: String)`
  - `missingContentType(part: String)`
  - `danglingRelationship(source: String, target: String)`
- `CertifiedTransaction.apply(manifest:baselineURL:outputURL:certificateURL:warnHandler:) throws -> CertificationCertificate`. It throws `CertificationError` with these cases:
  - `.gateFailed(CertificationCertificate)`
  - `.verifyFailed(VerifyError, CertificationCertificate)`
  - `.baselineChanged(CertificationCertificate)`
  - `.intentUnavailable(stepType:)`
- `CertificationCertificate` is `Codable`. Its JSON keys are:
  - `schemaVersion`, fixed at 1
  - `status`: `layer1Verified` or `rejected`
  - `baselineSHA256`, `candidateSHA256`
  - `allowedParts`, `changedParts`
  - `layer1`: `passed` plus `violations`
  - `layer2`: `notEvaluated` plus `reason`
  - `layer3`: `notEvaluated` plus `reason`
  - `verify`: `passed`, `failed` or `notRequested`
  - `outputURL`, `rejectedCandidateURL`, `createdAt`

**Failure modes**

Every failure leaves the output path untouched. Only `intentUnavailable` fails before a candidate exists, so no candidate is kept for it. Every other failure keeps the rejected candidate and reports its path.

**Acceptance criteria**

- `Layer1GateTests` covers each `Layer1Violation` case with a synthetic package.
- `CertifiedTransactionTests` covers each of these cases:
  - success, where the output is written and the certificate is `layer1Verified`;
  - gate failure, where the output path is untouched and the rejected candidate exists;
  - verify failure, where the output path is untouched;
  - baseline changed before commit;
  - intent unavailable.
- A macdoc CLI integration test shows `--certificate` writing the JSON.
- A second integration test shows a failing `verify` assertion leaving the output path absent.
- The macdoc#231 regression test still passes.

**Scope boundaries**

- In scope: `DocxWorkflowLib` transaction, intent, gate and certificate; `macdoc docx apply` wiring and the `--certificate` flag.
- Out of scope:
  - `macdoc docx verify`, `plan` and `diff`, which are unchanged;
  - che-word-mcp;
  - ooxml-swift;
  - Layer 2 and Layer 3;
  - `set_bold` behavior.

## Risks / Trade-offs

- **The writer changes something outside the allowed set in a case not yet seen** (for example `docProps/app.xml` statistics) → The gate rejects and names the part, which is the intended fail-closed outcome. If a legitimate part must change, it is added to the closed table in a reviewed change, never loosened at runtime.
- **Behavior change for callers who relied on the output existing after a failed verify** → Marked BREAKING in the proposal and CHANGELOG. The rejected candidate preserves the same bytes for anyone who needs them.
- **Byte identity is stricter than necessary for some future writer** → Acceptable. Loosening to c14n is a deliberate, reviewable decision, not a default.
- **The certificate could be misread as a full certification** → The status vocabulary never uses `certified`, and `layer2` and `layer3` say `notEvaluated` explicitly.
