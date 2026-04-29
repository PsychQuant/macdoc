## 1. Track A — formalize pdf-to-latex-swift remote

- [x] 1.1 Re-verify remote-vs-local byte equality with `diff -rq /tmp/pdf-to-latex-swift-remote /Users/che/Developer/macdoc/packages/pdf-to-latex-swift` — must return empty output (no diff), confirming the reconciliation assumption from the **Decision: Track A reclaims the existing PsychQuant/pdf-to-latex-swift remote** holds at implementation time.
- [x] 1.2 Clone fresh into scratch: `git clone https://github.com/PsychQuant/pdf-to-latex-swift.git /tmp/pdf-to-latex-swift-tag && cd /tmp/pdf-to-latex-swift-tag && git tag v0.1.0 && git push origin v0.1.0` — publishes the **simplified-pdf-ocr Implementation location** invariant at the package level.
- [x] 1.3 Edit macdoc `Package.swift` line 15: replace `.package(name: "pdf-to-latex-swift", path: "packages/pdf-to-latex-swift")` with `.package(url: "https://github.com/PsychQuant/pdf-to-latex-swift.git", from: "0.1.0")`. This is the contract change that makes the **simplified-pdf-ocr Implementation location** scenario "Package.swift does not declare a local path dependency" pass.
- [x] 1.4 `cd /Users/che/Developer/macdoc && swift package update pdf-to-latex-swift` — confirm `Package.resolved` now has `pdf-to-latex-swift` with `kind: remoteSourceControl` pointing at the GitHub URL.
- [x] 1.5 Verify none of the pre-existing pins drifted in `Package.resolved`: `note-core-swift@0.1.3`, `note-to-pdf-swift@0.1.2`, `word-builder-swift@0.9.0`, `ooxml-swift@0.7.0`. If any drifted, `swift package update <name>` to restore. Addresses the **Risks / Trade-offs: Package.resolved cascade during swift package update**.
- [x] 1.6 `swift build` — must link cleanly. Specifically confirm `MacDoc+PDF.swift`, `MacDoc+PDF+Phase2.swift`, `MacDoc+Config.swift`, `MacDoc+OCR.swift` still compile against `PDFToLaTeXCore` from the new url dep.
- [x] 1.7 Delete local `packages/pdf-to-latex-swift/` directory: `rm -rf packages/pdf-to-latex-swift`. Commit Package.swift + Package.resolved changes + directory removal in one commit referencing #79.

## 2. Track B — clean extraction of ocr-swift

Per **Decision: Track B serializes after Track A**, all tasks in this group run only after all tasks in group 1 (Track A) are complete and verified with a green macdoc build. Do NOT start task 2.1 while any 1.x task is still pending.

- [x] 2.1 Verify `.gitignore` inside `packages/ocr-swift/` excludes `.build/`, `.swiftpm/`, `Package.resolved` — protects against the **Risks / Trade-offs: Accidental .build/ commit** scenario. If missing, create a `.gitignore` using the same template as note-core-swift's.
- [x] 2.2 `cd packages/ocr-swift && git init -b main && git add . && git commit -q -m "init: OCRCore v0.1.0 extracted from macdoc (#79)"`. Confirm repo size is < 10 MB (ZIP compression of Swift sources is tiny; if it balloons, .build/ leaked).
- [x] 2.3 `gh repo create PsychQuant/ocr-swift --public --source=. --remote=origin --push --description "OCR pipeline — MLX + Ollama backends, PDFKit extractor (extracted from macdoc via #79)"` — creates and pushes the repo. This makes the remote side of the **mlx-model-management Implementation location** requirement verifiable.
- [x] 2.4 `git tag v0.1.0 && git push origin v0.1.0` — publishes the tag that macdoc's `from: "0.1.0"` constraint will resolve against.
- [x] 2.5 Edit macdoc `Package.swift` line 31: replace `.package(name: "OCRSwift", path: "packages/ocr-swift")` with `.package(url: "https://github.com/PsychQuant/ocr-swift.git", from: "0.1.0")`. Makes the **mlx-model-management Implementation location** scenario "Package.swift does not declare a local path dependency" pass.
- [x] 2.6 `swift package update ocr-swift` — confirm `Package.resolved` now has `ocr-swift` with `kind: remoteSourceControl` pointing at the GitHub URL.
- [x] 2.7 Re-verify pre-existing pins haven't drifted: `note-core-swift@0.1.3`, `note-to-pdf-swift@0.1.2`, `word-builder-swift@0.9.0`, `ooxml-swift@0.7.0`, `pdf-to-latex-swift@0.1.0` (the one Track A just pinned). Same **Package.resolved cascade** risk as Track A.
- [x] 2.8 `swift build` — **specifically verify `Sources/MacDocCLI/PageOCRRunner.swift` compiles** against `MLXBackend(modelConfig:)` / `OllamaBackend(host:)` / `OCRPipeline(backend:)` from the new url dep. Addresses the **Risks / Trade-offs: PR #84's OCRBackend wiring breaks** concern.
- [x] 2.9 If `swift build` fails with module-resolution errors: run `swift package purge-cache && swift package resolve && swift build`. Confirm the `swift package purge-cache` fallback path from the risk register works.
- [x] 2.10 Delete local `packages/ocr-swift/` directory: `rm -rf packages/ocr-swift`. Commit Package.swift + Package.resolved changes + directory removal in one commit referencing #79.

## 3. Track C — delete WordToMDTests scaffolding

- [x] 3.1 Grep for `WordToMDTests` across all tracked files: `git grep WordToMDTests`. Confirm the only references are the `Package.swift` testTarget declaration (lines 60-64) and the empty directory itself — no other code, docs, or CI refers to specific test names. Justifies the **Decision: Track C deletes the WordToMDTests testTarget**.
- [x] 3.2 Delete the entire `Tests/WordToMDTests/` directory: `rm -rf Tests/WordToMDTests`.
- [x] 3.3 Edit macdoc `Package.swift`: remove the `.testTarget(name: "WordToMDTests", …)` block (currently lines 60-64) and any references to `"WordToMDTests"` elsewhere in the file.
- [x] 3.4 `swift test` — confirm the remaining 28 tests (26 Swift Testing + 2 MacDocCLITests XCTest) still pass with no regression. Matches the **Goals / Non-Goals: Existing 28 passing tests on main all still pass**.
- [x] 3.5 Commit Track C changes in one commit referencing #79.

## 4. Track D — clean-clone end-to-end verification

- [x] 4.1 On a fresh temp directory, `git clone https://github.com/PsychQuant/macdoc.git /tmp/macdoc-clean-verify && cd /tmp/macdoc-clean-verify` — must succeed without any pre-existing local state. Checks out the branch that Tracks A+B+C landed on (not main yet).
- [x] 4.2 `swift package resolve` in the clean clone — confirm both `pdf-to-latex-swift` and `ocr-swift` resolve from their GitHub URLs and no `packages/*/` local directories get created during resolution. Validates both **mlx-model-management Implementation location** and **simplified-pdf-ocr Implementation location** scenarios "Clean clone of macdoc resolves the implementation from the remote repository".
- [x] 4.3 `swift build` in the clean clone — must succeed without any local filesystem pre-state. Validates the **Goals: A fresh git clone && swift build succeeds**.
- [x] 4.4 `swift test` in the clean clone — all 28 tests pass or XCTSkip cleanly. The `.note` smoke tests from #81 will XCTSkip (test-files/ is gitignored, expected per that issue's Option B).
- [x] 4.5 `rm -rf /tmp/macdoc-clean-verify` — cleanup after verification.

## 5. Documentation + housekeeping

- [x] 5.1 Update macdoc's top-level `CLAUDE.md` "Sub-Repositories" table (around lines 347-360): add rows for `pdf-to-latex-swift` and `ocr-swift` pointing to their new `PsychQuant/*` URLs. Remove or update any existing mention that implied these were local-only.
- [x] 5.2 Update `CLAUDE.md` "Package Dependencies" architecture diagram (around lines 83-97): remove references to `pdf-to-latex-swift` and `ocr-swift` as local packages; they now match the other `PsychQuant/*` remote deps.
- [x] 5.3 Commit documentation updates in one commit referencing #79.

## 6. Merge to main

- [x] 6.1 Branch name must be `refactor/extract-remaining-packages-79` per the **Decision: Single branch with squash-merge PR**. Verify current branch matches; rename with `git branch -m` if not.
- [x] 6.2 Push branch: `git push origin refactor/extract-remaining-packages-79 -u`.
- [x] 6.3 Open PR via `gh pr create --base main --head refactor/extract-remaining-packages-79 --title "refactor: extract pdf-to-latex-swift + ocr-swift + delete WordToMDTests testTarget (#79)"` with a body summarizing Tracks A / B / C / D results.
- [x] 6.4 Squash-merge via `gh pr merge --squash --delete-branch` — matches the **Decision: Single branch with squash-merge PR** and the merge-strategy precedent from PR #82.
- [x] 6.5 `git checkout main && git pull --ff-only origin main && swift build` — confirm main still builds after merge, covering the **Decision: Both new repos start at v0.1.0, no macdoc release tag** (no tag step needed).
