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

Output-path races other than "the destination became a directory" (for example another process writing ordinary file bytes to the output between check and rename) are out of scope. The rename replaces whatever is there, which is the same semantics as today. (R3: the directory case is no longer out of scope — see "R3: Commit uses POSIX `rename(2)`..." below. This line was stale after that fix landed and is corrected here per the R3 review's own point that a reader would otherwise assume every output-path race was still open.)

### R2: Pre-flight checks reject an unwritable output or certificate destination before anything is touched

Added in R2 after an adversarial review (macdoc#137 review-c137.md, CRITICAL Finding 1 and MEDIUM Finding 2). Before step 1 (reading the baseline), `apply` runs two checks that depend only on the arguments, not on the manifest or the baseline's content:

- The output path, if it already exists, must not be a directory. `FileManager.replaceItemAt` — what `commit` uses — silently deletes an existing directory (and everything in it) to replace it with a file; this check turns that into a named, reported failure (`CertificationError.outputPathIsDirectory`) before any write, instead of data loss.
- When `--certificate` is given, its destination must be writable: the parent directory must exist and be writable, and the destination itself, if something is already there, must not be a directory. Otherwise `CertificationError.certificateDestinationInvalid(path:reason:)` is thrown before any write.

Both checks fail closed and leave everything — baseline, output, and any prior rejected candidate — exactly as it was. Neither carries a `CertificationCertificate`: like `intentUnavailable`, they fail before a candidate exists.

- **Alternative**: check the certificate destination only, since that was the reviewed reproduction. Rejected — the same `FileManager.replaceItemAt` call that made the certificate race matter also makes an existing output directory a silent-deletion hazard, and the fix is the same shape (validate before touching anything), so both are covered together.

### R2: A certificate write failing after pre-flight validation passed does not change the transaction's own result

Also from review-c137.md Finding 1. Pre-flight validation (above) catches the common case — a certificate path pointing at a directory that does not exist yet, which was the review's literal CLI reproduction. It cannot catch a genuine race: the destination passed validation, but something removed the directory, revoked the permission, or filled the disk before the write actually happened.

For that narrower case, `apply` still writes the certificate atomically (`Data.write(options: .atomic)` — temp file plus rename, in the same directory), but a failure there is reported only through a new `certificateWarnHandler: (String) -> Void` callback, never by changing whether `apply` returns or throws:

- If the transaction itself succeeded, `apply` still returns the `layer1Verified` certificate and the output is still committed; `certificateWarnHandler` is called once with a description of the write failure. The CLI (`docx-workflow-cli` spec) turns this into: report the success as usual, print the warning, and exit non-zero anyway — a caller must not treat a `--certificate` file that does not actually exist as ground truth just because the underlying `apply` "succeeded".
- If the transaction failed, `apply` still throws the same `CertificationError` case it would have thrown anyway (`gateFailed`, `verifyFailed` or `baselineChanged`), carrying the same certificate and the same `rejectedCandidateURL`; `certificateWarnHandler` is called once, in addition.

- **Alternative**: make the race throw its own `CertificationError` case (e.g. `certificateWriteFailed(underlying:certificate:)`), carrying whichever certificate was already decided. Rejected: it would force every catch site to re-derive "was the underlying transaction success or failure" from a certificate's `status` field instead of from the normal case it already switches on, and — because the exact same certificate is available either way — it adds a vocabulary without adding information the callback does not already convey more simply.
- **Alternative**: let the race throw and treat it exactly like `intentUnavailable` (transaction-level failure). Rejected: the commit has already happened by the time the certificate write runs. Treating a purely cosmetic side-effect failure as if the whole transaction failed would misrepresent a real, already-committed `layer1Verified` output as rejected.

### R3: Certificate destination must not collide with another path this transaction uses

Added after a second adversarial review (macdoc#137 review-c137-r2.md, Finding A, CRITICAL). R2's pre-flight check validated only that the certificate destination was writable on its own — it never checked whether that destination was the SAME file as the output, the baseline, or the rejected-candidate path. Because the certificate write happens after the commit, a colliding path let the certificate JSON silently overwrite the just-committed output (or the caller's own baseline), while `apply` still reported success: exit 0, no warning, `certificateWarnHandler` never called (the write itself "succeeded" — just at the wrong path).

The check (`CertifiedTransaction.filesAreIdentical(_:_:) -> Bool`, public) compares two tiers:

1. Both paths' `resolvingSymlinksInPath().standardizedFileURL` compared as strings. Catches the literal case (identical strings, `./out.docx` vs `out.docx`) and symlink-resolved collisions, regardless of whether either file exists yet.
2. When both paths exist, their device and inode (`FileManager.attributesOfItem`'s `.systemNumber` / `.systemFileNumber`) compared for equality. Catches a hard link, and a case-insensitive filesystem's collision between two differently cased paths that tier 1 cannot fold when the leaf component does not yet exist (APFS is case-insensitive by default — `Out.docx` and `out.docx` name the same file once either is created, but `resolvingSymlinksInPath` cannot know that ahead of creation).

`CertifiedTransaction` itself checks the certificate destination against the output, the baseline, and the rejected-candidate path (all three are paths it already has). The manifest's own file path is NOT among them — `apply` receives an already-decoded `Manifest` value, never the path it came from — so that fourth conflict (`--certificate` == the manifest argument) is checked by the CLI layer instead, using the same public `filesAreIdentical`, constructing the same `CertificationError.certificateDestinationConflictsWithOtherPath` case before ever calling `apply`.

- **Alternative**: string comparison only (no device/inode tier). Rejected: it would miss the hard-link and case-insensitive-filesystem collisions, which are exactly the "looks different, is the same file" cases string comparison cannot see by construction.
- **Alternative**: have `CertifiedTransaction` accept the manifest's file path too, so all four checks live in one place. Rejected: `CertifiedTransaction.apply`'s contract is manifest-VALUE-in, not manifest-PATH-in (per the R1 Implementation Contract), and widening it to also carry a path used only for a diagnostic check is a bigger interface change than exposing one public comparison function for the CLI to reuse.

### R3: Commit uses POSIX `rename(2)`, not `FileManager.replaceItemAt`, so a directory destination is refused instead of deleted

Added after the same review (Finding B, MEDIUM). R2's `validateOutputIsNotDirectory` pre-flight check closed the case where the output path was ALREADY a directory when `apply` started. It did not close — and could not, being a point-in-time check — the TOCTOU window between that check (step 0) and the actual commit (step 5): if something creates a directory at the output path during that window (baseline read, intent derivation, `Executor.apply`, the Layer 1 gate, `Verifier.verify`, the baseline re-hash all run in between), `FileManager.replaceItemAt` still silently deletes it, exactly as before R2's fix — just triggered by a narrower, genuinely racy window instead of a static pre-existing condition. Unlike the certificate-write race (which has `certificateWarnHandler`), there was no warning mechanism for this one at all.

The fix does not add a second check — a second point-in-time check narrows the window without closing it, and per the review, would itself need yet another check to defend the SECOND check's own gap, indefinitely. Instead, `commit(from:to:)` now calls the raw POSIX `rename(2)` syscall (`Darwin.rename`) instead of `FileManager.replaceItemAt`. `rename(2)`'s own semantics are exactly what is needed: replacing an existing regular file is atomic, and replacing an existing DIRECTORY is refused outright with `EISDIR` — there is no separate check-then-act pair to race, because the refusal is a property of the single, atomic operation itself.

When the commit-to-output rename fails this way, the candidate — which already passed every gate — is not discarded: it is renamed to the rejected-candidate path instead (the same path a normal gate/verify failure would use), and `CertificationError.commitFailed(path:reason:rejectedCandidatePath:)` is thrown. If even that fallback rename fails (the rejected-candidate slot raced too), the candidate is left at its own temporary path rather than let the deferred cleanup delete the last remaining evidence; `rejectedCandidatePath` is `nil` in that case.

- **Alternative**: add a second `validateOutputIsNotDirectory` call immediately before the rename. Rejected per the review's own framing — it narrows the window but does not close it, and dresses up an unclosed TOCTOU as a closed one.
- **Alternative**: keep `FileManager.replaceItemAt` and catch its failure some other way. Rejected: `replaceItemAt` does not fail on a directory destination — it deletes it — so there is no failure to catch; the primitive itself has to change.
- `commitFailed` does not carry a `CertificationCertificate`, unlike `gateFailed`/`verifyFailed`/`baselineChanged`. This mirrors `intentUnavailable`/`outputPathIsDirectory`/`certificateDestinationInvalid`/`certificateDestinationConflictsWithOtherPath`: it is a failure of the machinery finishing its job (here, literally the last step), not an evaluated Layer 1 verdict. Layer 1 did pass in this case, but introducing a third `CertificationStatus` value to say so is a larger schema change than this fix warrants; the certificate vocabulary question is left for a later slice if it turns out to matter in practice.

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

Before step 1, pre-flight checks run: the output path must not already be a directory (R2); when `--certificate` is given, its destination must be writable (R2) and must not be the same file as the output, the baseline, the rejected-candidate path, or (checked by the CLI, before it even calls `apply`) the manifest's own file path (R3). Any of these failing means nothing is written at all: exit non-zero, output untouched, stderr names the problem.

Step 5's rename is POSIX `rename(2)` (R3), not `FileManager.replaceItemAt`: it refuses a directory destination with `EISDIR` instead of silently deleting it, closing the TOCTOU window between the pre-flight check above and the commit itself. If the rename still fails this way, the candidate is preserved at the rejected-candidate path (or, if that also fails, at its own temporary path) and `commitFailed` is thrown.

When `--certificate` is given and passes pre-flight, the certificate JSON is written to that path in both the success and the failure case, atomically. On success, the exit code is 0 and stderr reports the output path, as today — UNLESS the certificate write itself then fails (R2: a race, since pre-flight already passed), in which case stderr reports the output path AND a certificate-write warning, and the exit code is non-zero (so a caller does not treat a missing certificate file as ground truth just because the transaction succeeded). On failure, the exit code is non-zero, the output path is untouched, and stderr names the failure and the rejected-candidate path — plus the same certificate-write warning, when the certificate write also failed.

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
- `CertifiedTransaction.apply(manifest:baselineURL:outputURL:certificateURL:warnHandler:certificateWarnHandler:) throws -> CertificationCertificate` (R2 adds `certificateWarnHandler`, defaulted to a no-op, so this is source-compatible with the R1 signature). It throws `CertificationError` with these cases:
  - `.gateFailed(CertificationCertificate)`
  - `.verifyFailed(VerifyError, CertificationCertificate)`
  - `.baselineChanged(CertificationCertificate)`
  - `.intentUnavailable(stepType:)`
  - `.outputPathIsDirectory(path:)` (R2) — the output path already exists and is a directory; thrown before any candidate is written.
  - `.certificateDestinationInvalid(path:reason:)` (R2) — the `--certificate` destination is unwritable; thrown before any candidate is written.
  - `.certificateDestinationConflictsWithOtherPath(certificatePath:conflictingRole:conflictingPath:)` (R3) — the `--certificate` destination is the same file (per `filesAreIdentical`) as the output, the baseline, or the rejected-candidate path; thrown before any candidate is written. The CLI layer throws the same case, constructed directly, for the fourth conflict (the manifest's own file path) it alone knows about.
  - `.commitFailed(path:reason:rejectedCandidatePath:)` (R3) — every gate and every requested `verify` assertion passed, but the final `rename(2)` itself failed (most commonly `EISDIR`, because something occupied the destination with a directory between pre-flight and the commit). `rejectedCandidatePath` names where the candidate was preserved, or is `nil` if even that fallback rename failed.
  - A certificate write that fails AFTER `certificateDestinationInvalid`'s check has passed (a race) does NOT throw a `CertificationError` case. It calls `certificateWarnHandler(String)` once and otherwise leaves `apply`'s return/throw behavior exactly as it would have been without `--certificate` at all.
- `CertifiedTransaction.filesAreIdentical(_ a: URL, _ b: URL) -> Bool` (R3, public, static) — the same-file rule above. Exposed specifically so the CLI can apply it to the manifest's file path, which `CertifiedTransaction` itself never sees.
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

Every failure leaves the output path untouched. `intentUnavailable`, `outputPathIsDirectory`, `certificateDestinationInvalid` (R2) and `certificateDestinationConflictsWithOtherPath` (R3) fail before a candidate exists, so no candidate is kept for any of them. `gateFailed`, `verifyFailed`, `baselineChanged` and `commitFailed` (R3) keep the rejected candidate and report its path — except `commitFailed` reports `rejectedCandidatePath: nil` in the (narrower still) case where even the fallback rename to the rejected path also failed, in which case the candidate is left at its own temporary path instead.

A certificate write failing after `certificateDestinationInvalid`'s check has passed (R2, a race) is not a failure mode of the transaction itself — see the R2 decision above. It is reported via `certificateWarnHandler` alongside whatever the transaction's own outcome already was.

**Acceptance criteria**

- `Layer1GateTests` covers each `Layer1Violation` case with a synthetic package.
- `CertifiedTransactionTests` covers each of these cases:
  - success, where the output is written and the certificate is `layer1Verified`;
  - gate failure, where the output path is untouched and the rejected candidate exists;
  - verify failure, where the output path is untouched;
  - baseline changed before commit;
  - intent unavailable;
  - (R2) certificate destination invalid, tried against both a manifest that would otherwise succeed and one that would otherwise fail verify — pre-flight wins either way, before anything is written;
  - (R2) output path is an existing directory — rejected before any write, the directory and its contents survive;
  - (R2) a certificate write failing after pre-flight validation passed (a race, via a test-only hook) does not change the transaction's own returned or thrown result, tried against both a successful and a rejected outcome.
  - (R3) a certificate destination that collides with the output, the baseline, or the rejected-candidate path is rejected before any write, tried against a hard link (not just a literal-identical string) for the device/inode comparison tier.
  - (R3) a directory appearing at the output path between pre-flight and commit (via a test-only hook) does not get deleted; the candidate is preserved at the rejected-candidate path and `commitFailed` is thrown.
- A macdoc CLI integration test shows `--certificate` writing the JSON.
- A second integration test shows a failing `verify` assertion leaving the output path absent.
- (R2) A macdoc CLI integration test shows an invalid `--certificate` destination failing before any write, in Traditional Chinese, exit non-zero, even when the underlying manifest would otherwise have succeeded or otherwise have failed verify.
- (R2) A macdoc CLI integration test shows an output path that is an existing directory being rejected without deleting it.
- (R2) A macdoc CLI integration test shows a non-`CertificationError` failure (e.g. a missing manifest file) still using the Traditional Chinese "錯誤：" prefix, not swift-argument-parser's default English top-level error printer.
- (R3) macdoc CLI integration tests show `--certificate` equal to `--output`, to `--input`, and to the manifest's own path each rejected before any write, with the colliding file's bytes unchanged.
- (R3) A macdoc CLI integration test shows a certificate destination that passes pre-flight (`isWritableFile` on a directory whose mode has the write bit but not the search bit) but still fails to actually write: the transaction's own success is still reported and the output still exists, but the exit code is non-zero.
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
- **(R3, known limitation) A certificate destination colliding with the output or the baseline only by case, on a case-insensitive volume, before either file exists yet** → Not caught. `filesAreIdentical`'s tier 1 (string comparison) cannot fold a case difference in a leaf component that has not been created yet — there is nothing on disk yet to ask "what case does this actually have"; tier 2 (device/inode) requires existence. The scenario the review specified this check against ("兩者都已存在時" — once both already exist) IS covered; the narrower pre-existence variant (typically: a brand-new `--output`, never before written, and a `--certificate` that differs from it only by case) is not. Closing it would mean querying each path's volume for `.volumeSupportsCaseSensitiveNamesKey` and folding case whenever the answer is case-insensitive (true for APFS's default, which this repo already special-cases elsewhere — see `native-macos-compat.md`) or the query is inconclusive — deferred rather than added under review-response time pressure, to avoid introducing a case-folding rule that could misfire on a case-sensitive external volume without dedicated test coverage of its own.
