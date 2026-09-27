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

Output-path races other than "the destination became a directory" or "the destination is/becomes a symlink" (for example another process writing ordinary file bytes to a REGULAR file already at the output between check and rename) are out of scope. The rename replaces whatever is there, which is the same semantics as today. (R3: the directory case is no longer out of scope — see "R3: Commit uses POSIX `rename(2)`..." below. R4: the symlink case is no longer out of scope either — see "R4: Reject an output path that is (or becomes) a symbolic link" below. This line was stale after each of those fixes landed and is corrected here per the R3 review's own point that a reader would otherwise assume every output-path race was still open.)

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

### R3b: re-check the certificate destination against the just-committed paths immediately before writing it

Added after a third review pass on R3's own fix (macdoc#137, the case-insensitive-collision residual noted below R3's Decision). R3's `filesAreIdentical` pre-flight check has a blind spot by construction: its device/inode tier only fires when both paths already exist, and at Step 0 (before any write) neither `--output` nor `--certificate` need exist yet. On a case-insensitive volume (APFS's default), `--output Out.docx --certificate out.docx` — differing only by case, neither present beforehand — passes pre-flight with both tiers silent, then commit creates `Out.docx`, and the certificate write that follows resolves `out.docx` to the very same inode and overwrites it with certificate JSON. The transaction itself still reports success (`layer1Verified`), because by every check it ran, it was.

The fix does not try to predict this ahead of time (that would mean querying volume case-sensitivity, which the review that requested this fix explicitly asked to avoid). Instead, it re-runs `filesAreIdentical` a second time, at the one moment the answer can no longer be wrong: immediately after `commit` has succeeded and immediately before the certificate write. By then the output exists (commit just created it), so tier 2's device/inode comparison is live and catches the collision unconditionally — case-insensitive collision, hard link, or literal path, it does not need to know which. The same re-check runs on the rejected branch, against the rejected-candidate path, for the same reason.

A hit routes through the existing `certificateWarnHandler` mechanism from the R2 decision above, not a new `CertificationError` case: the transaction's own result (the commit already happened) is unaffected and reported exactly as it would be without `--certificate`, and the certificate is simply not written. The warning names the colliding role and both paths in Traditional Chinese.

- **Alternative**: query each path's volume for `.volumeSupportsCaseSensitiveNamesKey` and fold case in the pre-flight comparison whenever it answers case-insensitive. Rejected per explicit instruction: this needs the query to be reliable (it can return inconclusive), needs its own dedicated test coverage on both kinds of volume, and a case-folding rule risks misfiring on a case-sensitive external volume that happens to fail the query. A post-commit re-check needs none of that — it observes the real filesystem after the fact instead of predicting it.
- **Alternative**: throw a new `CertificationError` case instead of routing through `certificateWarnHandler`. Rejected: the transaction's own outcome (commit succeeded) is not in question here, only whether the certificate could be written at its requested path — exactly the shape the R2 decision already carved out `certificateWarnHandler` for. Introducing a second mechanism for the same shape of problem would be inconsistent without adding anything a caller can act on differently.
- This closes the residual limitation recorded in Risks / Trade-offs below (R3) for the output/baseline/rejected-candidate collisions. The manifest-path collision (checked only by the CLI layer, before `apply` is ever called) is unaffected by this fix and remains covered by R3's pre-flight check alone, because the CLI's own pre-flight collision check there does not have a "before" and "after" `apply` to straddle — it only ever runs once, before the manifest path could plausibly be recreated as something else mid-transaction.

### R4: Reject an output path that is (or becomes) a symbolic link

Added after a third-round adversarial review of R3's own fix (macdoc#137, review-c137-r3.md Finding E, HIGH). R3 switched `commit` from `FileManager.replaceItemAt` to POSIX `rename(2)` to close Finding B's directory-TOCTOU. `rename(2)`'s destination semantics, though, differ from `replaceItemAt`'s in a case nobody had checked yet: when `rename(2)`'s `new` argument names an existing symbolic link, it replaces the symlink's OWN directory entry — it does not follow the link to modify whatever it points to. Before R3, `replaceItemAt` threw `NSCocoaErrorDomain Code=4` for this same scenario and touched neither the symlink nor its target (a safe, if unhelpful, failure). After R3, the same scenario succeeds: the symlink is silently replaced by a real file, the file it used to point to is left completely untouched, and the alias relationship the caller had deliberately set up is severed without any warning — `apply` reports `layer1Verified` and exit 0 either way, and nothing distinguishes this from a normal successful write.

The chosen fix is REJECTION, not "follow the symlink" or "warn but still replace it": `validateOutputIsNotSymlink` uses `lstat(2)` (not `stat(2)`, which follows the link and would misreport a dangling symlink as "does not exist") to detect the case at Step 0, before anything is touched, and throws `CertificationError.outputPathIsSymlink(path:linkTarget:rejectedCandidatePath:)`. This restores the same "safe failure" shape `replaceItemAt` gave before R3 — nothing is touched, the caller finds out immediately — without picking a side (overwriting the symlink vs. overwriting its target) that could each be wrong depending on what the caller meant.

The same check runs a second time, immediately before the commit rename (in the success branch only — the rejected branch renames onto the rejected-candidate path, not the output, so it is not exposed to this scenario), to narrow the TOCTOU window between pre-flight and commit: nothing prevents another process from replacing the output path with a symlink during the window Step 1 through Step 4 occupy (baseline read, `Executor.apply`, the Layer 1 gate, `Verifier.verify`, the baseline re-hash). This mirrors the R3 Finding B pattern of re-checking immediately before the operation that matters, rather than trusting a single point-in-time check. Unlike Finding B, this second check does NOT close the window completely — it is a second point-in-time check, not a change of primitive, because `rename(2)` itself has no "refuse if the destination is a symlink" mode the way it has "refuse if the destination is a directory" (`EISDIR`). A symlink could in principle still appear in the instant between this second check and the `rename(2)` call itself. This narrower, honestly-disclosed residual race is recorded below in Risks / Trade-offs, rather than claimed as closed.

- **Alternative**: follow the symlink and treat its target as the real output path. Rejected: this changes which file gets Layer 1-verified content without the caller asking for that translation, and a manifest step's `--output` argument would then silently mean something different from what it says on the command line.
- **Alternative**: warn (via a mechanism like `certificateWarnHandler`) but still let the replacement happen. Rejected: unlike a certificate-write race (a purely cosmetic side artifact, which is why `certificateWarnHandler` exists for it), replacing a symlink is a structural change to the caller's own filesystem layout — once replaced, the alias cannot be un-severed by any later retry, so this needs to be fail-closed, not fail-open-with-a-note.
- **Alternative**: only check at pre-flight, accepting the TOCTOU gap as-is (the same trade-off R2's `validateOutputIsNotDirectory` made before R3 closed it for directories). Rejected: the review explicitly asked for the second check; and unlike the directory case, there is no atomic primitive here to switch to instead — `rename(2)` does not refuse a symlink destination the way it refuses a directory one — so a second point-in-time check, honestly disclosed as narrowing rather than closing, is what is actually achievable here without inventing a different commit mechanism.

### R4: Restore a replaced output's permissions, ACL and extended attributes before committing over it

Added after the same review (Finding F, HIGH, security-relevant). `FileManager.replaceItemAt` (used before R3) preserved a replaced file's POSIX permissions, ACL and extended attributes — Apple documents this as a deliberate "safe save" property. Plain `rename(2)` (used since R3) has no such property: the destination's directory entry simply now points at the candidate's own inode, so a caller re-running `apply` against an output they had deliberately locked down (for example `chmod 640` on a `.docx` holding unpublished research) would see those permissions silently widened back to the process's default umask on every successful rerun — a security-relevant regression the R3 rename(2) switch introduced as a side effect of fixing Finding B, without anyone checking for it at the time.

The fix, `preserveMetadataIfOverwriting(candidateURL:outputURL:)`, runs immediately before the commit rename, only when `outputURL` already exists and is not a directory (a no-op for a brand-new output, and deliberately deferring to Finding B's own `commitFailed`/`EISDIR` handling when the destination unexpectedly turned out to be a directory instead — see its doc comment). It uses `copyfile(3)` with `COPYFILE_SECURITY | COPYFILE_XATTR` (mode, ACL, extended attributes; ownership too, subject to the same non-root, same-user constraints any caller of this CLI already operates under) to copy the OLD output's metadata onto the candidate. `COPYFILE_STAT` — part of `COPYFILE_SECURITY` — also copies modification time, which is deliberately undone immediately afterward (the candidate's own modification time, captured before the `copyfile` call, is restored): the content genuinely changed, so claiming the old modification time would misrepresent when the current bytes were actually written. Creation time is the opposite case — deliberately carried over from the old output, via `FileManager` rather than relying on `copyfile`'s own (unspecified-for-birthtime) behavior, so a file's birth date survives an edit made through this transaction the same way it would survive an edit made directly in Word.

If the `copyfile(3)` call itself fails (for example the existing output became unreadable between pre-flight and here), `CertificationError.metadataPreservationFailed(path:reason:rejectedCandidatePath:)` is thrown and the commit is rejected outright — the candidate is preserved at the rejected-candidate path, exactly like a gate or verify failure, rather than proceeding and letting the new file land with looser access than the file it replaced had.

- **Alternative**: keep using bare `rename(2)` and accept the metadata loss as a known limitation. Rejected: the review's own reproduction (a `640`-permissioned output silently becoming `644`, with an unrelated custom xattr silently vanishing) is exactly the kind of confirmable, every-single-time regression this project's Risks / Trade-offs convention distinguishes from a merely theoretical one — recorded as a deferred trade-off, not fixed, only when closing it is genuinely costly or risky, neither of which applies here.
- **Alternative**: go back to `FileManager.replaceItemAt` for the metadata-preserving case and special-case the directory-destination check separately. Rejected: this reopens Finding B's exact TOCTOU (an intervening directory destination is silently deleted, not refused) for the sake of a property `copyfile(3)` can restore without giving that back up — there is no need to choose between the two fixes when `rename(2)` plus an explicit `copyfile(3)` step gets both.
- **Alternative**: on a `copyfile(3)` failure, proceed with the commit anyway and only warn. Rejected per the review's explicit requirement: landing a file with looser permissions than the one it replaced is the exact failure mode Finding F identified as security-relevant; a warning a caller might not see is not an adequate substitute for simply not doing it.

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

Before step 1, pre-flight checks run: the output path must not already be a directory (R2) or a symbolic link (R4); when `--certificate` is given, its destination must be writable (R2) and must not be the same file as the output, the baseline, the rejected-candidate path, or (checked by the CLI, before it even calls `apply`) the manifest's own file path (R3). Any of these failing means nothing is written at all: exit non-zero, output untouched, stderr names the problem.

Immediately before step 5's rename: the output-is-a-symlink check runs a second time (R4, narrowing — not fully closing — the TOCTOU window between pre-flight and commit), and, when the output already exists, its permissions/ACL/extended attributes are copied onto the candidate (R4) so the commit does not silently widen them back to the candidate's own default. Step 5's rename itself is POSIX `rename(2)` (R3), not `FileManager.replaceItemAt`: it refuses a directory destination with `EISDIR` instead of silently deleting it, closing the TOCTOU window between the pre-flight check above and the commit itself for THAT case. If the rename still fails this way, the candidate is preserved at the rejected-candidate path (or, if that also fails, at its own temporary path) and `commitFailed` is thrown.

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
  - (R3b) Immediately before the certificate write — after commit has succeeded, so the output (and, on the rejected branch, the rejected-candidate path) now definitely exist — `filesAreIdentical` is re-run against the certificate destination and the output/baseline/rejected-candidate paths a second time. A hit takes the same `certificateWarnHandler` path as the race above, naming the collision, and the certificate is not written; the transaction's own result is unaffected.
  - `.outputPathIsSymlink(path:linkTarget:rejectedCandidatePath:)` (R4) — the output path is itself a symbolic link. Thrown at pre-flight (`rejectedCandidatePath` is `nil` — no candidate exists yet) or, if the symlink appeared only in the window between pre-flight and commit, immediately before the rename (`rejectedCandidatePath` is the path the already-gate-passed candidate was preserved at).
  - `.metadataPreservationFailed(path:reason:rejectedCandidatePath:)` (R4) — the output path already exists, but copying its permissions/ACL/extended attributes onto the candidate (`copyfile(3)`) itself failed; the commit is rejected rather than let the candidate land with looser access than the file it would have replaced. The candidate is preserved at `rejectedCandidatePath`, or `nil` if even that fallback rename failed.
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

Every failure leaves the output path untouched. `intentUnavailable`, `outputPathIsDirectory`, `certificateDestinationInvalid` (R2), `certificateDestinationConflictsWithOtherPath` (R3) and an `outputPathIsSymlink` caught at pre-flight (R4) fail before a candidate exists, so no candidate is kept for those. `gateFailed`, `verifyFailed`, `baselineChanged`, `commitFailed` (R3), an `outputPathIsSymlink` caught at the pre-rename recheck (R4), and `metadataPreservationFailed` (R4) keep the rejected candidate and report its path — except `commitFailed` reports `rejectedCandidatePath: nil` in the (narrower still) case where even the fallback rename to the rejected path also failed, in which case the candidate is left at its own temporary path instead; `outputPathIsSymlink` and `metadataPreservationFailed` follow the same nil-on-double-failure convention.

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
  - (R3b) a certificate destination that collides with the output only by case, on a case-insensitive filesystem, where neither path exists before the call — the collision is invisible to pre-flight but caught by the post-commit re-check: the transaction still reports `layer1Verified`, the output is still the committed `.docx`, and `certificateWarnHandler` fires naming the collision.
  - (R4) an output path that is already a symbolic link is rejected before any write, `rejectedCandidatePath` is `nil`, and the symlink's own target is unchanged; a symlink appearing at the output path only between pre-flight and commit (via a test-only hook) is likewise rejected, with the candidate preserved at the rejected-candidate path.
  - (R4) overwriting an existing output preserves its POSIX permissions, extended attributes and creation date — but NOT its modification time, since the content genuinely changed — while a brand-new output is unaffected (kept at its own default permissions). A `copyfile(3)` failure while copying that metadata rejects the commit and preserves the candidate at the rejected-candidate path, leaving the old output's bytes untouched.
- A macdoc CLI integration test shows `--certificate` writing the JSON.
- A second integration test shows a failing `verify` assertion leaving the output path absent.
- (R2) A macdoc CLI integration test shows an invalid `--certificate` destination failing before any write, in Traditional Chinese, exit non-zero, even when the underlying manifest would otherwise have succeeded or otherwise have failed verify.
- (R2) A macdoc CLI integration test shows an output path that is an existing directory being rejected without deleting it.
- (R2) A macdoc CLI integration test shows a non-`CertificationError` failure (e.g. a missing manifest file) still using the Traditional Chinese "錯誤：" prefix, not swift-argument-parser's default English top-level error printer.
- (R3) macdoc CLI integration tests show `--certificate` equal to `--output`, to `--input`, and to the manifest's own path each rejected before any write, with the colliding file's bytes unchanged.
- (R3) A macdoc CLI integration test shows a certificate destination that passes pre-flight (`isWritableFile` on a directory whose mode has the write bit but not the search bit) but still fails to actually write: the transaction's own success is still reported and the output still exists, but the exit code is non-zero.
- (R3b) A macdoc CLI integration test shows the case-insensitive `--output Out.docx --certificate out.docx` collision (neither existing beforehand) caught after commit: exit non-zero, the transaction's own success still reported (`已寫入` in stderr), and the output file still starts with the ZIP signature, not certificate JSON. Skips itself (with a stated reason) on a case-sensitive filesystem.
- (R4) A macdoc CLI integration test shows `--output` naming a symlink to an unrelated file rejected: exit non-zero, stderr names the symlink case, the symlink itself still resolves to the same target, and the target's bytes are unchanged.
- (R4) A macdoc CLI integration test shows an existing `0640` output with a custom extended attribute and a fixed creation date surviving a successful `apply`: exit 0, permissions still `0640`, the extended attribute still readable, and the creation date unchanged.
- (R4) A macdoc CLI integration test shows a `copyfile(3)` failure (the existing output made unreadable, mode `0`) rejecting the commit: exit non-zero, and the old output's bytes byte-for-byte unchanged once read access is restored for the assertion.
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
- **(R3, resolved by R3b) A certificate destination colliding with the output or the baseline only by case, on a case-insensitive volume, before either file exists yet** → Closed by the R3b decision above: rather than trying to predict the collision at pre-flight (which would need a volume-attribute query), `filesAreIdentical` is re-run against the certificate destination immediately after commit, when the output (or rejected-candidate path) is guaranteed to exist — at which point the device/inode tier catches the case-insensitive collision unconditionally, with no volume query needed. A hit skips the certificate write and reports the collision through `certificateWarnHandler`; the transaction's own result is unaffected. Covered by `CertifiedTransactionTests.testCertificateDestinationCollidingWithOutputOnlyByCaseIsCaughtAfterCommit` and the matching CLI integration test, both of which detect a case-insensitive filesystem empirically (create a mixed-case file, check whether its lowercased path resolves to it) rather than querying volume attributes, and skip themselves with a stated reason on a case-sensitive filesystem.
- **(R4, honestly recorded, not closed) A symlink appearing at the output path in the instant between the pre-rename `validateOutputIsNotSymlink` recheck and the `rename(2)` call itself** → Not closed, unlike the directory case (R3's Finding B fix), because `rename(2)` has no mode that refuses a symlink destination the way `EISDIR` refuses a directory one — there is no atomic primitive to switch to here, only a second point-in-time check, which narrows the window (from "the whole transaction's duration" down to "the gap between one `lstat(2)` call and one `rename(2)` call") without eliminating it. A caller relying on `--output` never being replaced by a symlink mid-run, in an environment where another process is actively racing to install one at that exact path, could still hit the R1/R2-era `replaceItemAt` behavior gap this fix otherwise closes. Considered acceptable: the window is now microseconds instead of the length of the whole `apply` call (baseline read through the Layer 1 gate and `verify`), and no adversarial-review probe — including the one that found the original Finding E — has been able to hit it in practice.
- **(R4) `copyfile(3)`'s ownership (uid/gid) restoration is subject to normal `chown` privilege limits** → `COPYFILE_SECURITY` includes ownership, but a non-root process cannot `chown` a file to a different owner; since this transaction always runs as the same OS user who owns both the old output and the newly-written candidate, ownership is already identical in the common case and this limitation has no practical effect for `macdoc docx apply`'s actual callers. Recorded for completeness, not because it currently causes a problem.
