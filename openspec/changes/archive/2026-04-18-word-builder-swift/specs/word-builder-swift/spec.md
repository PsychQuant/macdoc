## ADDED Requirements

### Requirement: Public API mirrors docx.js top-level types

The `WordBuilderSwift` module SHALL expose public Swift types whose names exactly match the corresponding `docx.js` 9.6.x public exports. For Phase 1 the mirrored types are `Document`, `Section`, `Paragraph`, `TextRun`, `Run`, `Table`, `TableRow`, `TableCell`, `Packer`, `HeadingLevel`, and `AlignmentType`.

#### Scenario: Translating a `docx.js` snippet to Swift preserves type names

- **WHEN** a developer takes the `docx.js` README snippet `new Document({ sections: [{ children: [new Paragraph({ children: [new TextRun("Hello")] })] }] })`
- **THEN** the Swift equivalent SHALL compile as `Document(sections: [Section(children: [Paragraph(children: [TextRun("Hello")])])])` without renaming any public type

#### Scenario: Public API surface does not include Swift-specific renames

- **WHEN** a user imports `WordBuilderSwift` and lists the public types
- **THEN** names such as `WordDocument`, `TextBlock`, or `WordParagraph` SHALL NOT appear as public types — only the `docx.js`-mirror names

### Requirement: TextRun accepts a bare String and an options-style init

The `TextRun` type SHALL provide at minimum two initializers: `TextRun(_ text: String)` and `TextRun(text:bold:italics:underline:color:...)` where every parameter has a default value. Both initializers SHALL produce a `TextRun` that renders identical text runs in the output `.docx` when the same text and no formatting are supplied.

#### Scenario: Bare-string TextRun compiles and renders text

- **WHEN** a user writes `TextRun("Hello World")`
- **THEN** the code SHALL compile, and the rendered `.docx` SHALL contain the literal text "Hello World" in one run

#### Scenario: Options-style TextRun applies formatting

- **WHEN** a user writes `TextRun(text: "Bold text", bold: true)`
- **THEN** the rendered `.docx` SHALL contain one run whose `RunProperties` has `bold = true` and whose text is "Bold text"

### Requirement: Paragraph accepts heading, alignment, and children as init parameters with defaults

The `Paragraph` type SHALL provide an initializer that accepts at minimum `heading: HeadingLevel?`, `alignment: AlignmentType?`, and `children: [ParagraphChild]`, each with a default value of `nil` or `[]`. A `ParagraphChild` SHALL include at minimum `TextRun` and `Run`. Passing no arguments SHALL produce a valid empty paragraph.

#### Scenario: Heading-level paragraph renders with heading style

- **WHEN** a user writes `Paragraph(heading: .heading1, children: [TextRun("Q1 Report")])`
- **THEN** the rendered `.docx` SHALL contain one paragraph whose style reference resolves to `Heading1`

#### Scenario: Empty paragraph initialization is valid

- **WHEN** a user writes `Paragraph()`
- **THEN** the code SHALL compile and the paragraph SHALL be emittable by `Packer.toData` without raising an error

### Requirement: Table accepts rows of cells and renders to OOXML table

The `Table` type SHALL accept an initializer with at minimum a `rows: [TableRow]` parameter. The `TableRow` type SHALL accept `children: [TableCell]`. The `TableCell` type SHALL accept `children: [Paragraph]`. The rendered `.docx` SHALL produce a `<w:tbl>` element whose rows and cells match the input structure one-to-one.

#### Scenario: Simple 2x2 table renders with correct structure

- **WHEN** a user creates `Table(rows: [TableRow(children: [TableCell(children: [Paragraph(children: [TextRun("A")])]), TableCell(children: [Paragraph(children: [TextRun("B")])])]), TableRow(children: [TableCell(children: [Paragraph(children: [TextRun("C")])]), TableCell(children: [Paragraph(children: [TextRun("D")])])])])` and packs it
- **THEN** the rendered `.docx` SHALL contain a table with 2 `<w:tr>` rows, each containing 2 `<w:tc>` cells whose text content in reading order SHALL be `A`, `B`, `C`, `D`

### Requirement: Document accepts a sections array and Phase 1 emits only the first section

The `Document` type SHALL accept an initializer with a `sections: [Section]` parameter. For Phase 1, `Packer.toData(_:)` SHALL emit only the first section's children into the document body. If the `sections` array is empty, `Packer.toData(_:)` SHALL throw `WordBuilderError.emptyDocument`.

#### Scenario: Single-section document renders children

- **WHEN** a user creates `Document(sections: [Section(children: [Paragraph(children: [TextRun("Body")])])])` and calls `Packer.toData(_:)`
- **THEN** the returned `Data` SHALL represent a valid `.docx` whose body contains one paragraph with text "Body"

#### Scenario: Multi-section document emits only section zero in Phase 1

- **WHEN** a user creates `Document(sections: [Section(children: [Paragraph(children: [TextRun("First")])]), Section(children: [Paragraph(children: [TextRun("Second")])])])` and calls `Packer.toData(_:)`
- **THEN** the returned `.docx` body SHALL contain the paragraph with text "First" and SHALL NOT contain the text "Second"

#### Scenario: Empty sections array throws

- **WHEN** a user creates `Document(sections: [])` and calls `Packer.toData(_:)`
- **THEN** the call SHALL throw `WordBuilderError.emptyDocument`

### Requirement: Packer provides toData, toFile, and toBase64String static methods

The `Packer` type SHALL be an `enum` (uninhabited namespace) exposing three static methods: `toData(_ document: Document) throws -> Data`, `toFile(_ document: Document, url: URL) throws`, and `toBase64String(_ document: Document) throws -> String`. `toFile` SHALL invoke `toData` then write the bytes to `url`. `toBase64String` SHALL invoke `toData` then base64-encode the result.

#### Scenario: `Packer.toData` returns a valid `.docx` zip archive

- **WHEN** a user calls `Packer.toData(someDocument)` on a non-empty document
- **THEN** the returned `Data` SHALL begin with the ZIP magic bytes `0x50 0x4B 0x03 0x04` and SHALL be readable by `OOXMLSwift.DocxReader` without throwing

#### Scenario: `Packer.toFile` writes equivalent bytes to disk

- **WHEN** a user calls `Packer.toFile(someDocument, url: tempURL)` and separately calls `Packer.toData(someDocument)`
- **THEN** the file content at `tempURL` SHALL be byte-equal to the `Data` returned by `toData`

#### Scenario: `Packer` cannot be instantiated

- **WHEN** a developer attempts to write `Packer()`
- **THEN** the code SHALL fail to compile because `Packer` is an uninhabited `enum`

### Requirement: HeadingLevel and AlignmentType enums mirror docx.js values

The `HeadingLevel` enum SHALL include at minimum the cases `heading1`, `heading2`, `heading3`, `heading4`, `heading5`, `heading6`, corresponding to `docx.js` `HeadingLevel.HEADING_1` through `HEADING_6`. The `AlignmentType` enum SHALL include at minimum the cases `start`, `center`, `end`, `both`, corresponding to `docx.js` `AlignmentType.START`, `CENTER`, `END`, `BOTH`. Each case SHALL map to the correct OOXML value on output.

#### Scenario: HeadingLevel.heading1 maps to `Heading1` style

- **WHEN** a paragraph is created with `heading: .heading1` and rendered
- **THEN** the output `<w:pPr>` SHALL contain `<w:pStyle w:val="Heading1"/>`

#### Scenario: AlignmentType.center maps to OOXML `center`

- **WHEN** a paragraph is created with `alignment: .center` and rendered
- **THEN** the output `<w:pPr>` SHALL contain `<w:jc w:val="center"/>`

### Requirement: Version number mirrors docx.js minor version

The `word-builder-swift` package SHALL publish releases whose minor version equals the `docx.js` minor version being mirrored minus 9 (i.e. `docx.js 9.6.x` corresponds to `word-builder-swift 0.9.x`). The Phase 1 initial release SHALL be tagged `0.9.0`.

#### Scenario: Phase 1 release tag

- **WHEN** Phase 1 implementation is complete and a release is cut
- **THEN** the git tag and `Package.swift` version SHALL be `0.9.0`

### Requirement: reference docx-js is read-only, no code copying

The `reference/docx-js/` directory SHALL remain a read-only reference for API shape and naming. Source code from `reference/docx-js/` SHALL NOT be copied verbatim into `word-builder-swift`. Only type names, public option field names, and example snippet structures SHALL be mirrored; implementation logic MUST be written independently.

#### Scenario: No literal code duplication exists between `reference/docx-js/` and `word-builder-swift`

- **WHEN** a reviewer diffs `word-builder-swift/Sources/` against `reference/docx-js/src/`
- **THEN** no function body, class body, or contiguous 5+ line block SHALL match byte-for-byte between the two trees

### Requirement: OOXMLSwift.DocxWriter exposes writeData for in-memory output

The `OOXMLSwift.DocxWriter` type SHALL expose a public static method `writeData(_ document: WordDocument) throws -> Data` that returns the bytes of a `.docx` archive without writing to disk. The existing `write(_:to: URL)` method SHALL continue to accept a `URL` and produce byte-equal output to `writeData` followed by writing the returned `Data` to `url`.

#### Scenario: `writeData` and `write` produce identical bytes

- **WHEN** a user calls `DocxWriter.writeData(doc)` and separately calls `DocxWriter.write(doc, to: tempURL)` with the same `WordDocument`
- **THEN** the `Data` from `writeData` SHALL be byte-equal to the content of the file at `tempURL`

#### Scenario: `writeData` performs no disk I/O in its hot path

- **WHEN** `DocxWriter.writeData(doc)` executes
- **THEN** it SHALL NOT create any file in `FileManager.default.temporaryDirectory` that persists after the call returns (internal temp directories used during zipping SHALL be cleaned up before the call returns)

### Requirement: Phase 1 ships five worked examples translated from docx.js README

The `word-builder-swift` repository SHALL include five runnable examples under `examples/`, each consisting of a `.swift` file that produces a `.docx` output. Each example SHALL correspond to a specific `docx.js` README snippet, documented in a header comment that cites the source URL.

#### Scenario: Each example compiles and produces a valid `.docx`

- **WHEN** `swift run` is invoked on each example `.swift` file
- **THEN** each invocation SHALL exit with status `0` and SHALL produce a `.docx` file whose contents can be opened by `DocxReader.read(...)` without error
