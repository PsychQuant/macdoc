## Why

macdoc's long-term value is a trustworthy layer for modifying Word documents (macdoc#137): a modification must change only what it was meant to change, and the result must say exactly what was proven. Today `macdoc docx apply` offers no such guarantee. It writes the result straight to the final output path, and only afterwards evaluates the optional `verify` assertions. So a failed check still leaves the bad file behind. macdoc#231 showed the failure is real: before its fix, every successful apply silently dropped the theme, footnotes, endnotes and webSettings parts and rewrote every other part, and still reported success. This change makes Layer 1 of the Word-imitation methodology (package and byte preservation) a gate that every `docx apply` passes before anything reaches the output path. It is the first slice of macdoc#137; later slices add Layer 2 (typed round-trip) and Layer 3 (real-Word render oracle).

## What Changes

- New certified transaction in `DocxWorkflowLib`. It applies the manifest in memory, writes a candidate file next to the output, evaluates every gate against baseline and candidate, and only then atomically renames the candidate onto the output path. On any failure the output path is untouched; the rejected candidate is kept beside it for diagnosis.
- New mutation intent derived from the manifest. Each runtime-functional step type maps to the set of OOXML parts it may change, through a closed table. A step type missing from the table fails the transaction; the table is never extended by inference.
- New Layer 1 gate. It requires all of the following:
  - The candidate's part set equals the baseline's.
  - Every part outside the allowed set is byte-identical.
  - The candidate re-opens through `DocxReader`.
  - Every XML part is well-formed.
  - `[Content_Types].xml` covers every part.
  - Every internal relationship target exists.
- The manifest's `verify` assertions are evaluated against the candidate before commit, instead of against an output that has already been written.
- A TOCTOU guard records the baseline's SHA-256 when it is read and re-checks it immediately before the commit.
- New certificate, a JSON document with:
  - baseline and candidate hashes;
  - the intent and the allowed parts;
  - the parts actually changed;
  - per-layer results.
  Layer 2 and Layer 3 are recorded as `notEvaluated`. The overall status is `layer1Verified` or `rejected`, never `certified`, so the certificate claims nothing that was not measured.
- `macdoc docx apply` routes through the transaction and gains `--certificate <path>`.
- **BREAKING**: when a `verify` assertion or a gate fails, `macdoc docx apply` no longer writes the output file. Previously the output was written before verification ran. The exit code stays non-zero as before.

## Capabilities

### New Capabilities

- `docx-mutation-certification`: the certified transaction, mutation-intent derivation, the Layer 1 gate, the TOCTOU guard, and the certificate format.

### Modified Capabilities

- `docx-workflow-cli`: `macdoc docx apply` commits its output only through the certified transaction and accepts `--certificate`.

## Impact

- Affected specs: `docx-mutation-certification` (new), `docx-workflow-cli` (modified)
- Affected code:
  - New: packages/docx-workflow-swift/Sources/DocxWorkflowLib/CertifiedTransaction.swift, packages/docx-workflow-swift/Sources/DocxWorkflowLib/MutationIntent.swift, packages/docx-workflow-swift/Sources/DocxWorkflowLib/Layer1Gate.swift, packages/docx-workflow-swift/Sources/DocxWorkflowLib/CertificationCertificate.swift, packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/CertifiedTransactionTests.swift, packages/docx-workflow-swift/Tests/DocxWorkflowLibTests/Layer1GateTests.swift
  - Modified: packages/docx-workflow-swift/Sources/DocxWorkflowLib/Executor.swift, packages/docx-workflow-swift/CHANGELOG.md, Sources/MacDocCLI/MacDoc+Docx.swift, Tests/MacDocCLITests/MacDocDocxIntegrationTests.swift
