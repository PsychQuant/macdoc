## Context

`word-builder-swift` provides the Swift-side document builder, but R users still route analysis results through `officer`, `rmarkdown`, Pandoc, or manual copy/paste. Issue #88 proposes a different pipeline: R remains the analysis environment, and the R package generates a Swift script that imports `WordBuilderSwift` and writes the final `.docx`. The generated Swift script is a durable intermediate artifact, which is the main product difference from existing R-to-Word workflows.

The MVP is best treated as a new repository with a macOS-first support statement. The proposal lives here because the issue and project direction are tracked in macdoc, but implementation belongs in a future R package repository.

## Goals / Non-Goals

**Goals:**

- Define an MVP package named `wordbuilder` in a future PsychQuant repository.
- Support headings, paragraphs, text runs, and unstyled data-frame tables.
- Generate deterministic Swift source that imports `WordBuilderSwift` and writes `.docx`.
- Retain generated Swift by default.
- Use a persistent Swift package cache so repeated renders avoid repeated project setup.
- Establish golden-file and integration testing strategy.

**Non-Goals:**

- Support ggplot2 image embedding in Phase 1.
- Support APA table styling, citations, cross-references, headers, footers, numbering, or bookmarks in Phase 1.
- Support Windows in Phase 1.
- Commit to CRAN release in Phase 1.
- Modify macdoc CLI or `word-builder-swift` unless implementation reveals a blocker.

## Decisions

### Use a separate PsychQuant R package repository

Create a future repository for the package rather than placing R source inside macdoc. The R package has its own lifecycle, tests, README, generated examples, and user-facing installation flow. The macdoc issue remains the planning tracker, and the implementation repository can link back to #88.

Alternative considered: put the R package under `macdoc/packages/`. Rejected because R package structure, testing, and distribution conventions differ from SwiftPM packages and would add a second package ecosystem to this repo.

### Name the package `wordbuilder`

Use lowercase `wordbuilder` as the R package name and keep `WordBuilderSwift` as the generated Swift import. Lowercase package naming is easier to type in R code and avoids ambiguity with the Swift module name.

Alternative considered: `wordBuilder`, `rswiftdocx`, and `docx.swift`. Rejected for the MVP because `wordbuilder` is direct, searchable, and maps to the existing Swift package without punctuation.

### Generate Swift directly instead of routing through macdoc

`render()` writes a Swift source file and executes Swift through a package cache that depends on `word-builder-swift`. It does not call `macdoc convert`, because this workflow is document construction rather than format conversion, and the generated Swift script is itself the reviewable artifact.

Alternative considered: call a future `macdoc docx build` command. Rejected for the MVP because #88 can proceed independently of #92 once it has a pinned `WordBuilderSwift` dependency.

### Retain generated Swift by default

`render()` keeps the generated Swift file next to the output document or at a caller-provided path. The path is returned in the render result with the `.docx` path. Temporary cleanup can be an explicit option after the default durable artifact workflow is proven.

Alternative considered: delete generated Swift after successful render. Rejected because the reviewable intermediate is the core differentiator.

### Use a persistent Swift package cache

The package creates or reuses a cache directory under the platform user cache location. The cache contains a SwiftPM package that pins a `word-builder-swift` version. Individual renders write a Swift source file into the cache or copy it into a runner target, execute Swift, and return output paths. The cache key includes the pinned `word-builder-swift` version.

Alternative considered: create a fresh Swift package in a temporary directory for each render. Rejected because cold package setup would make iterative report work too slow.

### Test generated Swift separately from end-to-end rendering

Most automated tests compare generated Swift to golden files. End-to-end tests that require the Swift toolchain compile and run generated Swift, then read back `.docx` content, but they are marked as local or periodic integration tests. This keeps routine R tests fast while still proving the pipeline.

Alternative considered: run Swift in every test. Rejected because Swift toolchain installation and compile time would make basic package checks brittle.

## Risks / Trade-offs

- [Risk] Swift toolchain detection fails for R users. → Mitigation: `render()` performs a preflight check for `swift` on PATH and returns an actionable error before generating output.
- [Risk] Cold compile latency is too high. → Mitigation: persistent cache keyed by `word-builder-swift` version, plus clear logging for first-run setup.
- [Risk] Phase 1 looks weaker than `officer`. → Mitigation: position the MVP around reviewable Swift artifacts and reproducibility, not feature parity.
- [Risk] Generated Swift golden files become noisy. → Mitigation: use stable formatting, deterministic object ordering, and minimal codegen helpers.
- [Risk] `word-builder-swift` lacks a needed Phase 1 primitive. → Mitigation: open a separate upstream issue and keep #88 MVP scope to supported primitives.
