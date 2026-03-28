## Why

macdoc CLI has 15 conversion routes (`convert --to <format> <file>`) but zero end-to-end tests. Each package has its own unit tests (44 test files across ~20 packages), but no test covers the full path: CLI argument parsing → format detection → converter invocation → output generation. This means regressions in routing, flag handling, or error messages go undetected until manual testing.

## What Changes

- Add a test target `MacDocCLITests` to the root `Package.swift`
- Create test fixtures: minimal valid files for each input format (.docx, .html, .md, .srt, .bib, .pdf, .tex, .note)
- Write E2E tests that invoke the compiled `macdoc` binary via `Process`, verify stdout output and exit codes
- Cover all 15 conversion routes, flag combinations (--full, --css, --frontmatter, --html-extensions), and error cases (missing file, unsupported route)

## Capabilities

### New Capabilities

- `e2e-test-infrastructure`: Test harness for running macdoc CLI as a subprocess — fixture management, Process wrapper, output assertion helpers
- `e2e-conversion-routes`: E2E test coverage for all 15 convert routes and flag combinations

### Modified Capabilities

(none)

## Impact

- New files: `Tests/MacDocCLITests/`, `Tests/Fixtures/`
- Modified files: `Package.swift` (add test target)
- No changes to production code — tests only
