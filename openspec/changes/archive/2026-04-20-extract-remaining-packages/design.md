## Context

Macdoc's `packages/*` directory hosts Swift packages consumed by the main CLI and MCPs. The original intent was that `packages/*` entries are either:

1. Remote `PsychQuant/*` repos resolved via `.package(url:)` (the post-#71 ecosystem default), OR
2. In-tree local source explicitly `!`-whitelisted in `.gitignore` (e.g., `srt-to-html-swift`, `md-to-html-swift`)

Three paths drifted into a third state — matched by the blanket `packages/` ignore rule with no whitelist entry AND no remote repo — meaning the source lived only on the developer's machine:

- `packages/pdf-to-latex-swift/` (556 KB source)
- `packages/ocr-swift/` (24 KB source)
- `Tests/WordToMDTests/` (0 KB — empty scaffolding)

#78 fixed this for the three `note-*` packages. Issue #79 tracks the remaining work for `pdf-to-latex-swift` and `ocr-swift` plus the `WordToMDTests` decision. Codex's independent verification of #78 flagged that a fresh `git clone` of macdoc fails `swift build` because of these drifted paths — so this isn't theoretical.

Discussion (2026-04-19) uncovered one surprise: `PsychQuant/pdf-to-latex-swift` **already exists** as a public repo pushed 2026-04-16, and `diff -rq` confirms its Sources and Package.swift are byte-identical to local. An earlier aborted extraction attempt got most of the way but didn't tag `v0.1.0` or swap macdoc's dep. This downgrades Track A's risk from "reconcile divergence" to "formalize existing remote."

**Stakeholders**: developers onboarding to macdoc (blocked by clean-clone failure), PsychQuant maintainers (benefit from clean repo boundary for independent versioning), downstream consumers of `OCRCore` / `PDFToLaTeXCore` (so far internal — `macdoc` CLI only).

**Constraints**:

- Must preserve PR #84's `OCRBackend` protocol wiring — the Qwen3-VL refactor in `PageOCRRunner.swift` just landed on main (`897682b`) and depends on `MLXBackend` + `OllamaBackend` types from `ocr-swift`. Extraction must not break that compile.
- Must avoid the Package.resolved silent-downgrade class of regression caught during #78 verify (note-to-pdf-swift 0.1.2 → 0.1.0 when word-builder-swift was added). SPM re-resolves can cascade; we pin and re-verify after each step.
- macOS-native stack (MLX, Quartz PDFKit) — no cross-platform concerns.
- Must honor the ecosystem pattern `note-*` established in #78: remote-repo preferred over whitelist, `v0.1.0` starting tag, `https://github.com/PsychQuant/*.git` URLs in macdoc `Package.swift`.

## Goals / Non-Goals

**Goals:**

- A fresh `git clone https://github.com/PsychQuant/macdoc.git && swift build` succeeds without any local filesystem pre-state.
- `pdf-to-latex-swift` and `ocr-swift` both resolvable as remote `url:` deps with a `v0.1.0` tag.
- macdoc `Package.swift` uses only remote `url:` deps or in-tree `!`-whitelisted `path:` deps — no "ghost paths" matched by the blanket `packages/` rule.
- Existing 28 passing tests on main (26 Swift Testing + 2 MacDocCLITests XCTest) all still pass after this change.
- Empty `WordToMDTests` testTarget removed so the Package.swift matches reality.
- Pre-existing dependency pins preserved: `note-core-swift@0.1.3`, `note-to-pdf-swift@0.1.2`, `word-builder-swift@0.9.0`, `ooxml-swift@0.7.0` all unchanged after `swift package update`.

**Non-Goals:**

- Modify ocr-swift or pdf-to-latex-swift source code. The extraction preserves behaviour byte-identically.
- Enforce the "no ghost paths" invariant via CI / pre-commit hooks. One-time audit here; enforcement is a separate concern.
- Populate `Tests/WordToMDTests/` with real tests. If wanted later, a separate issue creates them (explicitly rejected here per Track C decision).
- Tag macdoc as `v0.5.1`. No user-visible CLI change; ceremony without benefit.
- Port other `PsychQuant/*` packages that are already remote (`word-to-md-swift`, `common-converter-swift`, note-*, word-builder-swift, ooxml-swift). Out of scope.
- Set up CI for the clean-clone verification (Track D). One-shot manual check here; GitHub Actions is a separate concern.

## Decisions

### Decision: Track A reclaims the existing PsychQuant/pdf-to-latex-swift remote

**Approach**: Use the 2026-04-16-pushed remote as-is. No local merge needed because `diff -rq` proves byte-identical trees. Tag `v0.1.0` on remote HEAD. Swap macdoc `Package.swift:15` from local `path:` to `.package(url: "https://github.com/PsychQuant/pdf-to-latex-swift.git", from: "0.1.0")`. Delete local `packages/pdf-to-latex-swift/` directory (SPM resolves from URL; local dir becomes dead weight).

**Why**: The remote exists; using it avoids wasted prior work. Byte-identical content means zero reconciliation cost. Deleting the local dir prevents future contributors from accidentally editing the local copy instead of cloning the remote.

**Alternatives considered**:

- *Discard remote, push local fresh*: Rejected — would force-push over someone's earlier work with no upside (content is identical anyway).
- *Diff first, merge if divergent*: The discovery workflow *was* "diff first" — it happened during discuss. The diff returned empty, collapsing this alternative into the chosen approach.

### Decision: Track B serializes after Track A

**Approach**: Finish all Track A phases (A.1–A.6 incl. `swift build` green on new url dep) before starting Track B (`git init` on `packages/ocr-swift/`).

**Why**: During #78 verify, adding `word-builder-swift` as a new dep caused SPM to silently downgrade `note-to-pdf-swift` 0.1.2 → 0.1.0 in Package.resolved (regression Finding P1). Serial extraction means if a new cascading downgrade happens, we know exactly which dep addition triggered it. Parallel tracks multiply the forensic surface.

**Alternatives considered**:

- *Parallel A + B on separate branches, merge sequentially*: Rejected — same Package.resolved conflict when branches re-resolve dependencies at merge time. Time savings (~30 min) not worth the risk.

### Decision: Track C deletes the WordToMDTests testTarget

**Approach**: Delete `Tests/WordToMDTests/` directory (empty anyway). Remove `.testTarget(name: "WordToMDTests", …)` block from macdoc `Package.swift` lines 60-64. Add commit-message note citing #79 Track C decision.

**Why**: The directory is genuinely empty — 0 Swift files, empty `Fixtures/` subdirectory. A testTarget that declares fixtures but has no test files isn't "latent infrastructure," it's dead scaffolding. Keeping it forever means every `swift test` has to build an empty target for no reason. Matches #81's "Option B" philosophy (don't maintain scaffolding that does nothing).

**Alternatives considered**:

- *Populate with a minimal placeholder test*: Rejected — regresses from #81's real-assertion standard. Either write real tests (separate issue, clear motivation) or delete.
- *File a follow-up issue "populate WordToMDTests or remove"*: Rejected — kicks the decision down the road with no new information to inform it. Better to decide now given the directory's actual state.

### Decision: Both new repos start at v0.1.0, no macdoc release tag

**Approach**: `git tag v0.1.0` on `PsychQuant/pdf-to-latex-swift` (after Track A reconciliation) and `PsychQuant/ocr-swift` (fresh from Track B). No `macdoc v0.5.1` tag; the squash-merged PR commit is the record.

**Why**: `v0.1.0` matches the note-* precedent set by #78 / PR #82. Neither new remote has any earlier tag to collide with. macdoc's `v0.5.0` was tied to a user-visible feature (#76 note-to-pdf); this is pure infrastructure with no new CLI surface — a release tag would be ceremony with no meaning.

**Alternatives considered**:

- *Tag macdoc v0.5.1 to match convention*: Rejected — no convention requires it; v0.5.0 was for feature, not dep wiring.
- *Start pdf-to-latex-swift at a higher version reflecting prior iteration*: Rejected — the remote has no tags yet, so v0.1.0 is correct.

### Decision: Single branch with squash-merge PR

**Approach**: Do all 3 tracks as sequential commits (or one squash commit at merge time) on one feature branch. Squash-merge to main.

**Why**: Tracks are mechanically independent but semantically one deliverable ("close the systemic gitignore-blackhole issue"). #82's precedent shows multi-issue work can squash-merge cleanly. Self-review doesn't need finer PR granularity. One reviewable unit = one verification pass.

**Alternatives considered**:

- *Three separate PRs, one per track*: Rejected — triples ceremony (3 PRs × diagnose/implement/verify/close) for work that conceptually reads as one refactor. Finer granularity helps only if an external reviewer wants to approve subset.

## Risks / Trade-offs

**Package.resolved cascade during `swift package update`** → Same class as #78 verify's P1 finding (word-builder-swift addition caused note-to-pdf-swift downgrade). **Mitigation**: After each track's `swift package update`, diff `Package.resolved` to confirm these pins didn't drift: `note-core-swift@0.1.3`, `note-to-pdf-swift@0.1.2`, `word-builder-swift@0.9.0`, `ooxml-swift@0.7.0`. If any drifted, `swift package update <name>` to restore before continuing.

**PR #84's OCRBackend wiring breaks under the new url-dep resolution** → `PageOCRRunner.swift` on main (`897682b`) uses `MLXBackend(modelConfig:)` / `OllamaBackend(host:)` + `OCRPipeline(backend:)` API surface that exists in local `packages/ocr-swift/Sources/`. Extraction preserves the API (byte-identical), but SPM module resolution under `url:` may hit a caching issue. **Mitigation**: B.5 step explicitly runs `swift build` on macdoc after the dep swap and inspects `PageOCRRunner.swift` linkage via compiler diagnostics. If it fails, `swift package purge-cache && swift package resolve` before rebuild.

**Accidental `.build/` commit blows up new repo size** → `packages/ocr-swift/.build/` is 2.7 GB; `packages/pdf-to-latex-swift/.build/` is 762 MB. Without a proper `.gitignore`, the first `git add .` would push all of this to GitHub. **Mitigation**: B.1 explicitly verifies `.gitignore` contains `.build/` before staging. Track A is safe because the existing remote repo was created with proper `.gitignore` already (the 2026-04-16 push was <10 MB per remote repo stats).

**macdoc build-time regression for external contributors who do `swift package update` frequently** → The two new `url:` deps add network fetch cost on every clean resolve. **Accepted**: The cost is bounded (first fetch caches locally); SPM does not re-fetch on subsequent `swift build`. Same trade-off already accepted for all existing `PsychQuant/*` remote deps.

**Ghost paths re-appear in future `packages/*` additions** → The invariant "`packages/*` entries must be either `url:` or whitelisted" is not enforced by any tool. **Accepted**: One-shot audit here; future enforcement is a separate concern. At minimum, CLAUDE.md documentation update (Impact section) makes the invariant visible to future contributors.

## Migration Plan

- **Each track is append-only**: apply A → verify build → commit. Apply B → verify build → commit. Apply C → verify build → commit. Each step is independently revertable via `git revert` if something breaks.
- **Rollback**: if a track's verification fails, revert the commit, keep the prior commits. The refactor is incremental; no all-or-nothing risk.
- **No user communication needed**: zero user-visible CLI change. Existing `macdoc` binaries continue to work unchanged. New contributors benefit; existing contributors see no difference.

## Open Questions

None. Discuss converged on all 5 assumptions (proceed with Track A formalize-remote, Track B serial-after-A, Track C delete testTarget, v0.1.0 versioning, single squash-merge branch). The one unknown was Track A divergence — resolved during discuss by `diff -rq` showing byte-identical trees.

If implementation surfaces a new question (e.g., PR #84 linkage breaks unexpectedly), it is captured as a task blocker and escalated via comment on #79 before deviating from this plan.
