## ADDED Requirements

### Requirement: R document builder API

The package SHALL expose an R API for Phase 1 document construction. The API SHALL include `word_document()`, `add_heading()`, `add_paragraph()`, `add_text_run()`, `add_table()`, and `render()`. Builder functions SHALL return updated document objects rather than mutating hidden global state.

#### Scenario: Build a simple report object

- **WHEN** an R user creates `doc <- word_document()`, then calls `add_heading(doc, "Q1 Report", level = 1)`, and then calls `add_paragraph(doc, "Revenue grew 15%")`
- **THEN** the returned document object contains one heading block and one paragraph block in order

#### Scenario: Add a plain data frame table

- **WHEN** an R user calls `add_table(doc, data.frame(group = c("A", "B"), mean = c(1.2, 3.4)))`
- **THEN** the returned document object contains a table block with two columns and two data rows

### Requirement: Deterministic Swift code generation

The package SHALL serialize a document object into deterministic Swift source that imports `WordBuilderSwift`, constructs equivalent `Document`, `Section`, `Paragraph`, `TextRun`, and `Table` values, and writes a `.docx` file through the WordBuilderSwift packer. The same R document object and options SHALL produce byte-identical Swift source.

#### Scenario: Generate Swift for heading and paragraph

- **WHEN** the package serializes a document containing heading `Q1 Report` and paragraph `Revenue grew 15%`
- **THEN** the generated Swift source imports `WordBuilderSwift`
- **AND** the generated Swift source contains the text literals `Q1 Report` and `Revenue grew 15%`

#### Scenario: Stable generation

- **WHEN** the same R document object is serialized twice with the same options
- **THEN** the two generated Swift files are byte-identical

##### Example: repeated serialization

- **GIVEN** a document object with one heading `Q1 Report`, one paragraph `Revenue grew 15%`, and one two-row table
- **WHEN** the package writes `report-a.swift` and `report-b.swift` from that object with identical options
- **THEN** `report-a.swift` and `report-b.swift` have identical bytes

### Requirement: Render uses persistent Swift package cache

The `render()` function SHALL create or reuse a persistent Swift package cache under the platform user cache directory. The cache key SHALL include the pinned `word-builder-swift` version. Rendering SHALL execute Swift from that cache, write the requested `.docx` output, and return a structured result containing output path, Swift source path, cache path, and process status.

#### Scenario: First render initializes cache

- **WHEN** an R user calls `render(doc, output = "q1-report.docx")` and no cache exists for the pinned `word-builder-swift` version
- **THEN** the package creates the cache package, writes generated Swift, executes Swift, and returns the output path and cache path

#### Scenario: Second render reuses cache

- **WHEN** a cache exists for the pinned `word-builder-swift` version
- **THEN** `render()` reuses that cache instead of creating a new Swift package directory

### Requirement: Generated Swift artifact retention

The `render()` function SHALL retain the generated Swift source file by default. The retained source path SHALL be visible in the render result. If the user supplies an explicit Swift source output path, the package SHALL write the generated Swift there.

#### Scenario: Retain generated Swift next to output

- **WHEN** an R user calls `render(doc, output = "q1-report.docx")` without a Swift source path
- **THEN** the package keeps a generated Swift source file and returns its path in the render result

#### Scenario: User-specified Swift source path

- **WHEN** an R user calls `render(doc, output = "q1-report.docx", swift_output = "q1-report.swift")`
- **THEN** the generated Swift source is written to `q1-report.swift`

### Requirement: Swift toolchain preflight

The package SHALL check for a usable `swift` executable before attempting render execution. If Swift is unavailable, `render()` SHALL fail with a clear error that identifies the missing executable and does not create a `.docx` output file.

#### Scenario: Swift missing from PATH

- **WHEN** `render()` runs in an environment where `swift` cannot be found on PATH
- **THEN** `render()` returns an error explaining that the Swift toolchain is required
- **AND** the requested `.docx` output file is not created

### Requirement: MVP test strategy

The package SHALL include golden-file tests for generated Swift and separate integration tests for Swift execution and `.docx` readback. Routine tests SHALL pass without compiling Swift. Integration tests SHALL be explicitly marked so they can run locally or periodically when the Swift toolchain is available.

#### Scenario: Golden-file code generation test

- **WHEN** the test suite serializes a known R document fixture
- **THEN** the generated Swift matches the checked-in golden Swift file

##### Example: fixture and golden file

- **GIVEN** `tests/fixtures/basic_report.rds` contains one heading, one paragraph, and one data-frame table
- **WHEN** the golden-file test serializes that fixture
- **THEN** the generated Swift matches `tests/testthat/_snaps/basic_report.swift`

#### Scenario: Integration render test

- **WHEN** integration tests are enabled and Swift is available
- **THEN** the test suite renders a `.docx` and verifies readback text for heading, paragraph, and table content
