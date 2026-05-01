## Why

Issue #88 proposes a reproducible R-to-Word workflow where R analysis objects emit a reviewable Swift script that calls `WordBuilderSwift` and produces `.docx`. The MVP needs a scoped SDD proposal before any repository is created because it crosses R APIs, Swift toolchain execution, cache layout, generated artifact retention, and test strategy.

## What Changes

- Define a new macOS-first R package, working name `wordbuilder`, in a future repository owned by PsychQuant.
- Provide an R API for the Phase 1 document model:
  - `word_document()`
  - `add_heading()`
  - `add_paragraph()`
  - `add_text_run()`
  - `add_table()` for plain data frames
  - `render()` for generating Swift, running Swift, and returning the `.docx` path
- Generate a runnable Swift source file that imports `WordBuilderSwift` and uses a pinned `word-builder-swift` release.
- Retain the generated `.swift` file by default so it can be reviewed, committed, edited, and rerun outside R.
- Execute Swift through a persistent package/cache directory under the user cache location so repeated renders avoid cold package setup.
- Add golden-file tests for generated Swift and a local/periodic integration test that runs Swift and reads back `.docx` content.

## Non-Goals

- No ggplot2 image embedding in Phase 1.
- No table styling, APA table formatting, citations, cross-references, headers, footers, or numbering in Phase 1.
- No Windows support in Phase 1.
- No CRAN release commitment in Phase 1; GitHub distribution is sufficient until toolchain requirements stabilize.
- No changes to macdoc CLI or `word-builder-swift` unless the MVP exposes a blocking upstream gap.

## Capabilities

### New Capabilities

- `r-word-builder-mvp`: R package MVP that serializes R report objects into runnable WordBuilderSwift scripts and produces `.docx` output with retained intermediate Swift artifacts.

### Modified Capabilities

(none)

## Impact

- Affected specs: r-word-builder-mvp
- Affected code:
  - New external repository: PsychQuant/r-word-builder
  - Modified in this repository: none
- Related systems:
  - Consumes `word-builder-swift` as the canonical `.docx` writer.
  - Requires Swift toolchain discovery from R.
  - Tracks GitHub issue #88.
