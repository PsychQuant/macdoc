## Context

macdoc is a CLI tool built with swift-argument-parser. It has 15 conversion routes via `macdoc convert --to <format> <file>`. Each converter is a separate Swift package with its own unit tests, but the CLI layer (argument parsing, format routing, output handling, error messages) has no test coverage. The root `Tests/` directory is empty.

## Goals / Non-Goals

**Goals:**

- Test the full CLI path: argument parsing → format detection → conversion → output
- Cover all 15 routes with at least one happy-path test each
- Test key flags: `--full`, `--css`, `--frontmatter`, `--html-extensions`, `--output`, `--stdout`
- Test error cases: missing file, unsupported format pair, invalid flags
- Keep test execution fast (< 30 seconds total)

**Non-Goals:**

- Testing converter quality (that's the unit tests' job in each package)
- Testing PDF/OCR output quality (Vision.framework dependency makes these flaky in CI)
- Testing marker output (directory-based, more complex assertion logic — defer to later)

## Decisions

### Process-based testing via compiled binary

Run `swift build` once, then use `Process` to invoke `.build/debug/macdoc` for each test. This tests the real CLI path including argument-parser behavior. Swift Testing's `#expect` is used for assertions.

Alternative: Import MacDocCLI as a library and test functions directly. Rejected — misses argument parsing bugs and doesn't test the actual user-facing interface.

### Minimal programmatic test fixtures

Generate fixture files programmatically in test setup (not checked into git). For .docx, use ooxml-swift's `DocxWriter` to create a minimal valid file. For .md/.html/.srt/.bib/.tex, write text content directly. This avoids binary files in the repo and makes tests self-contained.

Alternative: Ship fixture files in `Tests/Fixtures/`. Rejected — binary files bloat the repo, and fixtures drift from the format as packages evolve.

### Categorized test structure

Group tests by capability:
1. `ConvertRouteTests.swift` — one test per route (15 routes)
2. `ConvertFlagTests.swift` — flag combinations (--full, --css, --frontmatter, etc.)
3. `ErrorHandlingTests.swift` — missing file, unsupported routes, invalid args

### Output verification strategy

For text formats (md, html, json): verify stdout contains expected substrings (not exact match — too brittle).
For binary formats (docx): verify file exists at output path and is non-empty.
For all: verify exit code is 0 for success, non-zero for errors.

## Risks / Trade-offs

- [Risk] PDF-based routes (`pdf → md`, `pdf → docx`) depend on PDFKit, which may behave differently in test environments → Mitigation: Use a minimal PDF fixture; skip if PDFKit fails gracefully
- [Risk] TeX route requires specific preamble handling → Mitigation: Use a minimal .tex file that exercises basic parsing only
- [Trade-off] Substring verification is less precise than exact output matching → Acceptable: catches routing and crash bugs while tolerating converter output changes
