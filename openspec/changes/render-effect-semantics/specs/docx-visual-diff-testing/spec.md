## ADDED Requirements

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
