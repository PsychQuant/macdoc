## Context

Script execution has two faces: the `execute_script` MCP tool and the `macdoc word render` CLI command. A prior change promoted the orchestration — parse, replay, write, compare — into a single shared function in the transcode module, so that both faces would behave identically by construction rather than by convention.

That promotion delivered parity for everything inside the shared function. Two guarantees were left outside it, and both are now known to be wrong:

- The overwrite gate stayed on the CLI command, so the MCP face never got it.
- The package is written to the final output path and then read back for comparison, so a failed verification has already destroyed whatever was at that path — on both faces.

A third defect is not about placement at all: the MCP face returns a failed verdict inside a successful response, so a caller checking only call success reads failure as pass.

The constraint that shapes this design is that the shared function lives in a separate repository consumed as a versioned remote dependency. Changing its signature costs a full release cycle: tag the library, bump the pin in both consumers, resolve. That cost is worth paying once, and argues for making the signature right in a single pass rather than iterating.

## Goals / Non-Goals

**Goals:**

- Make a failed verification observable as failure on both faces.
- Make failed execution non-destructive: nothing is published unless it verified, or unless no verification was asked for.
- Place the overwrite gate where a future third consumer inherits it without action.
- Keep the result type honest about what it did and did not do.

**Non-Goals:**

- Preserving a structured broken-parts payload on the MCP failure path. See the decision on failure signalling.
- Reworking the server's tool-dispatch layer so a handler can set the error flag and return a JSON body at the same time. That is the architecturally correct home for the previous point, and it is tracked separately.
- Any change to the reverse or export direction.
- Renaming either face. The names differ deliberately and that is already settled.

## Decisions

### Move the overwrite gate into the shared entry point

The entry point takes an overwrite parameter defaulting to refuse. Both faces map their own surface onto it — the CLI overwrite flag and a new MCP overwrite parameter — and neither retains a gate of its own.

*Alternative considered: add a matching gate to the MCP wrapper.* Rejected because it reproduces the root cause. Two gates on two wrappers must be kept in agreement by discipline, and the defect being fixed is precisely what happens when that discipline lapses. It would also leave a third consumer unprotected by default. The gate must sit where the shared behavior sits.

The gate fires before the rebuild work is done, not after: refusing early avoids spending the replay and packaging cost on output that will be rejected.

### Write to a temporary path, verify, then move into place

The rebuilt package is written to a temporary path, compared against the reference, and moved onto the requested output path only when the verdict passes or no verification was requested.

The temporary path is created in the same directory as the requested output. A temporary file in a system temporary directory would frequently sit on a different filesystem, which turns the final move into a copy — losing atomicity and doubling the write. Same-directory placement also inherits the same permission requirements the write already had, so it introduces no new failure mode of its own.

*Alternative considered: keep writing directly to the output path and restore a backup on failure.* Rejected because the restore path is itself failure-prone — it must handle a crash between destroying and restoring, and it must decide what to do when there was no original file. Writing to the side and publishing on success has no such window: at every instant the output path holds either the old contents or the new verified contents.

### Require explicit overwrite for same-path self-verification

Supplying one path as both output and reference is a supported pattern — it asks "does this script rebuild this document exactly?" That pattern necessarily targets a path that already exists, so a default-refuse overwrite gate rejects it unless the caller opts in.

This is the correct outcome rather than a case to special-case away. A caller using that pattern genuinely is overwriting the reference document, and should say so. Special-casing it would carve a hole in the gate at exactly the spot where the file being protected is the one the caller most likely wants to keep.

Existing coverage of the same-path pattern therefore has to opt in explicitly, which makes the requirement visible in the tests rather than implicit.

### Keep the read-before-write ordering requirement even though the temporary write also protects it

The reference is already required to be read into memory before anything is written. Writing to a temporary path means a late read would no longer corrupt the comparison, so that requirement stops being load-bearing for this failure mode.

It stays anyway. Deleting it would be the active choice, and it would leave the invariant depending on a single mechanism: if the temporary-write structure is ever reverted or bypassed for performance, an early read is the only thing still standing between the caller and a comparison of a file against itself. Two independent guarantees against a silent-pass failure is the right number.

### Report no written path when nothing was committed

The result's written path becomes optional and is absent when the entry point published nothing.

This follows a rule the result type already applies to the verdict, where absent means "this did not happen" rather than "this happened and the answer was no". Reporting the requested output path unconditionally would state that a file was written to a location that may still hold its original contents — a worse failure than the one being fixed, because it is a positive false claim rather than a missing signal.

The CLI consequence is an ordering change: the write is announced after the verdict is known, not before. The current sequence announces the write and then fails, which reads as "wrote it, then something went wrong" when in fact nothing was written.

### Signal a failed verification as an error, accepting loss of the structured payload

The MCP tool raises on a false verdict instead of returning it, and the differing parts travel in the error text.

*Alternative considered: return the structured payload with the error flag set.* This is the architecturally correct answer and it is not adopted here. The dispatch layer renders a raised error as plain text and returns a body only on success, so getting both would mean changing the shape every tool handler returns. That is a change to the whole server for the sake of one tool, and it deserves its own issue rather than being smuggled into a bug fix.

The information is not lost, only destructured: the failure text names each differing part. Callers that consumed the broken-parts list were overwhelmingly displaying it, not branching on it. The one thing they could not previously do — detect the failure at all — is what this change gives them.

## Implementation Contract

**Behavior.** After this change, on both faces:

- Executing a script when a file already exists at the requested output path fails, names the existing path, and leaves that file byte-identical to what it was — unless the caller explicitly requested overwrite.
- Executing a script with a reference that the rebuild does not match fails. The requested output path is left holding its previous contents, or holding nothing if it did not previously exist. The failure names every part that differed.
- Executing a script with no reference writes the rebuilt document and reports no verdict of any kind.
- Executing a script whose rebuild matches the supplied reference writes the document and reports a passing verdict.

**Interface.** The shared entry point gains a parameter controlling overwrite, defaulting to refuse. Its result type's written-path field becomes optional, carrying a value only when a document was published; the existing verdict field keeps its current three-state meaning. The MCP tool gains a boolean overwrite parameter in its input schema, defaulting to refuse, documented as such. The MCP success response omits the written-path key when nothing was published, in the same manner it already omits the verdict keys when no reference was supplied. The CLI's existing overwrite flag changes meaning from "the CLI will permit this" to "the entry point is asked to permit this"; its spelling and user-visible behavior are unchanged.

**Failure modes.** Refusal to overwrite, and failed verification, are both failures — a non-zero exit on the CLI face and a tool error on the MCP face. A missing script path or missing reference path remains a failure raised before any write, as today. Nothing about these failures is intentionally silent.

**Acceptance criteria.**

- A test asserts that a pre-existing output file is unchanged after a run that fails verification, and that no file is created when verification fails and none existed.
- A test asserts that a pre-existing output file is unchanged after a run refused for lack of overwrite permission.
- A test asserts the same-path self-verification pattern still compares against pre-write contents, now with overwrite requested explicitly, and still refuses without it.
- A test asserts the result carries no written path when nothing was committed.
- A test asserts a failed verification through the MCP handler surfaces as an error whose text names the differing parts.
- A test asserts both faces agree on the same script for both verdicts, extending the existing agreement coverage to the failure path.
- Searching the source finds exactly one place where an existing output file is refused.

**Scope boundaries.** In scope: the shared entry point, the two faces that call it, their tests, the dependency pins that carry the new signature, and the three skill documents that describe the behavior to users. Out of scope: the dispatch-layer restructuring, the reverse and export direction, and any renaming.

## Risks / Trade-offs

- **Existing MCP callers that relied on silent overwrite start failing** → Both breaking changes ship in one release so callers absorb the disruption once. The changed default is stated in the tool description, the changelog, and the skill document, and the failure names the existing path rather than failing obscurely.
- **A crash between writing the temporary package and moving it leaves a stray file** → The temporary file is removed on every failure path, including verification failure. A crash hard enough to skip that leaves one file beside the intended output, which is recoverable and visible; the alternative failure mode being traded away is a destroyed original, which is neither.
- **The structured broken-parts list stops being machine-readable on the MCP failure path** → Recorded as a deliberate trade-off with its own follow-up issue rather than silently accepted. The parts remain named in the failure text.
- **Three repositories must be released in order for the change to be usable** → The library releases first, then both consumers pin it. Until the pins move, each consumer builds against the old signature and is unaffected, so a partially-completed chain is inert rather than broken.

## Migration Plan

1. Change the shared entry point and its tests; release the library under a new version.
2. Bump the pin in both consumers, then adapt each face to the new signature.
3. Update the three skill documents to state the new overwrite default and the non-destructive failure behavior.
4. Release the consumers.

Rollback is pinning both consumers back to the previous library version; because the consumers' adaptations are what require the new signature, rolling the pin back requires rolling back those adaptations in the same step.
