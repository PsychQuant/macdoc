## ADDED Requirements

### Requirement: Gated visual regression harness

The test suite SHALL provide a visual-diff harness gated behind `RUN_WORD_INTEGRATION=1`: it converts two docx files to PDF via live Microsoft Word (AppleScript `save as PDF`, following the WordLiveRoundTripTests driving pattern), renders each PDF page to a bitmap using native frameworks (PDFKit/CoreGraphics), and computes a per-page pixel-difference ratio. A comparison fails when any page's ratio exceeds the configured threshold. Without the gate or without Word installed, harness tests SHALL skip loudly.

#### Scenario: identical documents pass

- **WHEN** a reference and its byte-equal rebuild are compared
- **THEN** every page's difference ratio is 0 and the comparison passes

#### Scenario: layout drift is caught

- **GIVEN** a rebuild that lost the second section's two-column layout
- **WHEN** the visual diff runs
- **THEN** the affected page's ratio exceeds the threshold and the comparison fails naming that page

### Requirement: Native conversion channel only

The docx→PDF channel SHALL be Microsoft Word via AppleScript. The harness SHALL NOT depend on LibreOffice or other external layout engines (different engines introduce diff noise unrelated to document content; native-macos-compat governs).

#### Scenario: missing Word skips, not fails

- **WHEN** the harness runs on a machine without Microsoft Word
- **THEN** tests skip with an explicit message rather than failing or falling back to another engine
