## Summary

Extract the two remaining gitignored Swift packages (`pdf-to-latex-swift`, `ocr-swift`) to independent `PsychQuant/*` GitHub repositories and delete the empty `WordToMDTests` testTarget from macdoc's `Package.swift`, so that a fresh `git clone && swift build` on macdoc's main branch succeeds without any local filesystem pre-state.

## Motivation

Issue [#79](https://github.com/PsychQuant/macdoc/issues/79) tracks the systemic "gitignored packages" problem that PR #82 (the note-* packages extraction for #78) left unfinished. Codex independent verification of #78 caught that a clean clone of macdoc fails because:

- `packages/pdf-to-latex-swift/` (762 MB with `.build`, 556 KB of source + tests) is matched by `.gitignore`'s blanket `packages/` rule with no whitelist entry. Source files exist only on the developer's filesystem.
- `packages/ocr-swift/` (2.7 GB with `.build`, 28 KB of source + tests) has the same pattern. **PR #84's Qwen3-VL/OCRBackend refactor depends on this package's `OCRBackend` protocol**, so this isn't hypothetical — main is currently broken for new contributors.
- `Tests/WordToMDTests/` is referenced by macdoc's `Package.swift:60-64` testTarget but is an **empty directory** with an empty `Fixtures/` subdirectory — scaffolding that produces zero tests.

This refactor mirrors the `note-*` extraction approach that #78 / PR #82 established as the ecosystem pattern (`common-converter-swift`, `word-to-md-swift`, `note-core-swift`, etc.).

## Proposed Solution

Three independent tracks, serialized for clean attribution:

### Track A — `pdf-to-latex-swift` (formalize existing remote)

Surprise finding from discuss: `PsychQuant/pdf-to-latex-swift` **already exists** (pushed 2026-04-16 from an earlier aborted extraction attempt). `diff -rq` against local confirms the tree is byte-identical — Sources, Tests, `Package.swift` all match. No reconciliation is needed; only ceremony.

- Clone `PsychQuant/pdf-to-latex-swift` to overwrite local `packages/pdf-to-latex-swift/` (identical content, just needed for `.git` metadata; or delete local entirely since SPM resolves via `url:` anyway)
- `git tag v0.1.0 && git push origin v0.1.0`
- macdoc `Package.swift:15`: `.package(name: "pdf-to-latex-swift", path: "packages/pdf-to-latex-swift")` → `.package(url: "https://github.com/PsychQuant/pdf-to-latex-swift.git", from: "0.1.0")`
- `swift package update` + `swift build` + confirm consumers still link (`MacDoc+PDF.swift`, `MacDoc+PDF+Phase2.swift`)
- Delete local `packages/pdf-to-latex-swift/` directory (redundant once the remote `url:` resolves)

### Track B — `ocr-swift` (clean extraction, #78 playbook)

No remote yet; source of truth is local (24 KB, 5 Swift files). This is the unambiguous case.

- Verify `.gitignore` in `packages/ocr-swift/` excludes `.build/` (the 2.7 GB we don't want committed)
- `cd packages/ocr-swift && git init && git add . && git commit -m "init: OCRCore v0.1.0 extracted from macdoc (#79)"`
- `gh repo create PsychQuant/ocr-swift --public --source=. --remote=origin --push --description "OCR pipeline — MLX + Ollama backends, PDFKit extractor"`
- `git tag v0.1.0 && git push origin v0.1.0`
- macdoc `Package.swift:31`: `.package(name: "OCRSwift", path: "packages/ocr-swift")` → `.package(url: "https://github.com/PsychQuant/ocr-swift.git", from: "0.1.0")`
- `swift package update` + `swift build` + **verify PR #84's `PageOCRRunner.swift` still links** (the Qwen3-VL refactor using `MLXBackend` + `OllamaBackend` must continue to compile)
- Delete local `packages/ocr-swift/` directory

### Track C — `WordToMDTests` (delete dead scaffolding)

- Grep `WordToMDTests` across all tracked files — confirm nothing references specific test names or fixtures
- Delete `Tests/WordToMDTests/` directory (only contains empty `Fixtures/`)
- Remove testTarget declaration from `Package.swift:60-64`
- `swift test` — confirm existing 28 tests still pass (26 Swift Testing + 2 MacDocCLITests XCTest)

### Track D — Clean-clone verification (after A + B + C)

- On a fresh scratch directory: `git clone https://github.com/PsychQuant/macdoc.git && cd macdoc && swift build` — must succeed without any local pre-state (the goal this issue explicitly calls out)
- `swift test` on the cloned copy — all tests either pass or XCTSkip cleanly (the `.note` smoke tests from #81 will skip because `test-files/` is gitignored — expected)

## Non-Goals

- **Address the "gitignored packages" pattern for all remaining `packages/*` entries**. This change resolves the two known offenders (`pdf-to-latex-swift`, `ocr-swift`). Any future package added under `packages/*` must either be explicitly whitelisted in `.gitignore` or extracted to a `PsychQuant/*` repo at creation time. Enforcement via CI is out of scope.
- **Modify ocr-swift / pdf-to-latex-swift source code**. The extraction preserves behaviour byte-identically. Any refactor of the code *inside* those packages (e.g., OCRBackend API changes) is owned by separate issues.
- **Tag macdoc as `v0.5.1`**. This is infrastructure-only; no user-visible CLI change. A release tag would be ceremony with no new capability. (The macdoc commit will still go to main via squash-merge PR as usual.)
- **Port `word-to-md-swift` or `common-converter-swift`**. Those are already remote deps (since before #78). Not in scope.
- **Add CI gate for the clean-clone verification**. Track D is a one-shot manual check. GitHub Actions setup is out of scope.
- **Populate `Tests/WordToMDTests/Fixtures/` with actual test fixtures**. Option (C) chose delete-not-populate per discuss conclusion. If real tests are wanted later, a separate issue creates them.

## Alternatives Considered

- **Option (b) from issue #79: whitelist `pdf-to-latex-swift` + `ocr-swift` in `.gitignore` and commit in-tree**. Rejected because:
  - The existing ecosystem pattern is remote-repos-over-whitelists (`common-converter-swift`, `word-to-md-swift`, note-*, word-builder-swift all went remote in #71 / #78)
  - Keeping them in-tree bloats macdoc's git history and blocks independent versioning
  - `pdf-to-latex-swift` already has a remote repo waiting to be formalized — not using it wastes prior work

- **Populate `WordToMDTests` with placeholder tests instead of deleting**. Rejected because:
  - Scaffolding without substance is indistinguishable from bug (it looked like a real testTarget but produced 0 tests)
  - `#81`'s `NotePDFConvertTests` already follows the "real test, real assertion" pattern — adding an empty placeholder regresses from that standard
  - If real tests are wanted, `#81`-style smoke coverage for `WordToMDSwift` belongs in a separate issue with a real motivation

- **Parallel tracks (A and B concurrently) instead of serial**. Rejected because:
  - `swift package update` mid-refactor re-resolves other pinned versions (we caught the note-to-pdf-swift 0.1.2 → 0.1.0 silent downgrade during #78 verify when `word-builder-swift` was added)
  - Serial makes regression attribution trivial; parallel doubles the investigation surface if something breaks
  - Time savings would be ~30 min; risk savings of serial outweigh that

- **3 separate PRs (one per track) instead of a single squash-merge PR**. Rejected because:
  - Tracks are semantically one deliverable ("close the systemic gitignore-blackhole issue")
  - `#82` set the precedent: multi-issue work can squash-merge cleanly
  - Finer PR granularity only helps if reviewers want to approve A+B but block C — unlikely self-review scenario

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `mlx-model-management`: Implementation now lives in `PsychQuant/ocr-swift` (was local `packages/ocr-swift/`); behaviour unchanged. Delta adds a `Implementation location` requirement pinning the remote-repo invariant.
- `simplified-pdf-ocr`: Implementation now lives in `PsychQuant/pdf-to-latex-swift` (was local `packages/pdf-to-latex-swift/`); behaviour unchanged. Delta adds the same `Implementation location` requirement.

## Impact

- **Affected specs**: `mlx-model-management` + `simplified-pdf-ocr` get a new `Implementation location` requirement (delta specs under this change's `specs/`). No behaviour change — just pins the repo boundary so future refactors can't silently re-inline these packages without updating the spec.
- **New repos**: `PsychQuant/ocr-swift` (created fresh). `PsychQuant/pdf-to-latex-swift` already exists (just needs v0.1.0 tag + formalization).
- **Affected code**:
  - `macdoc/Package.swift` lines 15 + 31 swapped from `path:` to `.package(url:)`; lines 60-64 testTarget deleted.
  - `macdoc/Package.resolved` updated by SPM (new pins for the two `url:` packages, existing pins retained).
  - `macdoc/Tests/WordToMDTests/` directory deleted.
  - `macdoc/packages/pdf-to-latex-swift/` directory deleted after remote resolves.
  - `macdoc/packages/ocr-swift/` directory deleted after extraction.
  - `CLAUDE.md` — update the Sub-Repositories table (lines ~347-360) to list `pdf-to-latex-swift` + `ocr-swift` under the "standalone repos" column, mirroring the `note-*` entries.
- **Dependency version pins**: Must verify after each `swift package update` that these pre-existing pins do not drift: `note-core-swift@0.1.3`, `note-to-pdf-swift@0.1.2`, `word-builder-swift@0.9.0`, `ooxml-swift@0.7.0`. Same class of regression risk caught during #78 verify (Finding regression.P1).
- **Branch**: Single `refactor/extract-remaining-packages-79` branch. Squash-merge to main.
