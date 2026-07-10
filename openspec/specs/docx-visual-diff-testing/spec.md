# docx-visual-diff-testing Specification

## Purpose

TBD - created by archiving change 'format-alignment-engine'. Update Purpose after archive.

## Requirements

### Requirement: Gated visual regression harness

The test suite SHALL provide a visual-diff harness gated behind `RUN_WORD_INTEGRATION=1`: it converts two docx files to PDF via live Microsoft Word (AppleScript `save as PDF`, following the WordLiveRoundTripTests driving pattern), renders each PDF page to a bitmap using native frameworks (PDFKit/CoreGraphics), and computes a per-page pixel-difference ratio. A comparison fails when any page's ratio exceeds the configured threshold. Without the gate or without Word installed, harness tests SHALL skip loudly.

#### Scenario: identical documents pass

- **WHEN** a reference and its byte-equal rebuild are compared
- **THEN** every page's difference ratio is 0 and the comparison passes

#### Scenario: layout drift is caught

- **GIVEN** a rebuild that lost the second section's two-column layout
- **WHEN** the visual diff runs
- **THEN** the affected page's ratio exceeds the threshold and the comparison fails naming that page


<!-- @trace
source: format-alignment-engine
updated: 2026-07-08
code:
  - mcp/che-word-mcp
-->

---
### Requirement: Native conversion channel only

The docx→PDF channel SHALL be Microsoft Word via AppleScript. The harness SHALL NOT depend on LibreOffice or other external layout engines (different engines introduce diff noise unrelated to document content; native-macos-compat governs).

#### Scenario: missing Word skips, not fails

- **WHEN** the harness runs on a machine without Microsoft Word
- **THEN** tests skip with an explicit message rather than failing or falling back to another engine

<!-- @trace
source: format-alignment-engine
updated: 2026-07-08
code:
  - mcp/che-word-mcp
-->

---
### Requirement: Geometry measurement extends the harness beyond pixel ratios

The visual-diff harness SHALL provide geometry measurement over rendered PDFs using native frameworks only (PDFKit/CoreGraphics): page count, per-page page box, per-page text-line boxes, and a derived median baseline-to-baseline distance (measured line pitch). Geometry helpers SHALL be unit-testable on committed PDF fixtures without Microsoft Word and without the `RUN_WORD_INTEGRATION` gate. For a page with fewer than two text lines, the derived line pitch SHALL be nil; measurement consumers that require text on a page SHALL treat nil as a failure, not a skip.

#### Scenario: Line geometry from a committed fixture

- **GIVEN** a committed PDF fixture with a known number of text lines at known positions
- **WHEN** the geometry helper extracts line boxes and the median line pitch for page 1
- **THEN** the line-box count matches the fixture's known line count and the median line pitch matches the fixture's known baseline distance within measurement tolerance

#### Scenario: Sparse page yields nil line pitch

- **WHEN** the median line pitch is requested for a page containing fewer than two text lines
- **THEN** the helper returns nil, and a probe that expected text on that page fails rather than skips

#### Scenario: Page box and page count without Word

- **WHEN** geometry helpers run in a plain `swift test` invocation without `RUN_WORD_INTEGRATION=1`
- **THEN** page count and page box extraction succeed on committed fixtures — no gate, no Word dependency, no skip

<!-- @trace
source: render-effect-semantics
updated: 2026-07-10
code:
  - mcp/che-word-mcp
-->