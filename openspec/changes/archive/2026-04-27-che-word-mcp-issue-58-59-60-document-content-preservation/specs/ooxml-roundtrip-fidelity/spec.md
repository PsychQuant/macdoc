## ADDED Requirements

### Requirement: RunProperties SHALL preserve typed and unknown rPr child elements through round-trip

The `RunProperties` model SHALL provide typed fields for the common OOXML rPr child elements `<w:noProof>` (boolean flag), `<w:kern>` (integer minimum kerning size), `<w:lang>` (3-axis: `w:val`, `w:eastAsia`, `w:bidi`), and `<w:rFonts>` (4-axis: `w:ascii`, `w:hAnsi`, `w:eastAsia`, `w:cs`). Unrecognized rPr direct children — primarily `w14:*` namespace effects (`<w14:textOutline>`, `<w14:glow>`, `<w14:shadow>`, `<w14:reflection>`, `<w14:textFill>`, `<w14:scene3d>`) — SHALL be preserved via a `RunProperties.rawChildren: [RawElement]?` raw-passthrough field rather than silently dropped.

#### Scenario: rFonts 4-axis attributes preserved through round-trip

- **GIVEN** a `.docx` file containing `<w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:eastAsia="DFKai-SB" w:cs="Times New Roman"/>` inside a `<w:rPr>` block
- **WHEN** `DocxReader.read(from:)` parses the file and `DocxWriter.write(_:to:)` re-serializes after marking `word/document.xml` modified
- **THEN** the output rPr block SHALL contain `<w:rFonts>` with all 4 attributes (`w:ascii`, `w:hAnsi`, `w:eastAsia`, `w:cs`) present and equal to the source values

#### Scenario: noProof and kern fields preserved through round-trip

- **GIVEN** a `.docx` file containing `<w:rPr><w:noProof/><w:kern w:val="32"/></w:rPr>` on at least one run
- **WHEN** the document is read and written back with `word/document.xml` in `modifiedParts`
- **THEN** the output rPr block SHALL contain both `<w:noProof/>` and `<w:kern w:val="32"/>` elements

#### Scenario: w14 namespace effects preserved as raw children

- **GIVEN** a `.docx` file containing `<w:rPr>...<w14:textOutline w14:w="9525" w14:cap="rnd"><w14:solidFill>...</w14:solidFill></w14:textOutline></w:rPr>`
- **WHEN** the document is read and written back with `word/document.xml` in `modifiedParts`
- **THEN** the output rPr block SHALL contain the `<w14:textOutline>` element with its full child tree byte-equivalent to the source

### Requirement: <w:t> whitespace content SHALL survive Reader-side parser limitations

The `DocxReader` SHALL preserve `<w:t>` text content even when Foundation `XMLDocument` strips whitespace-only text node `stringValue` to empty string. This applies to all parts using the same parser: `word/document.xml`, `word/header*.xml`, `word/footer*.xml`, `word/footnotes.xml`, `word/endnotes.xml`, `word/comments.xml`. The mechanism is a pre-parse byte-stream scan that captures `<w:t xml:space="preserve">[whitespace]</w:t>` content keyed by element sequence index, consulted by `parseRun` when `t.stringValue.isEmpty`.

#### Scenario: Whitespace-only w:t round-trips byte-equivalent

- **GIVEN** a `.docx` file containing `<w:r><w:t xml:space="preserve">     </w:t></w:r>` (5-character space) in body text
- **WHEN** the document is read, marked modified, and written back
- **THEN** the output SHALL contain the same `<w:r><w:t xml:space="preserve">     </w:t></w:r>` element with the 5-character space content preserved

#### Scenario: Whitespace preservation extends to header parts

- **GIVEN** a `.docx` file with a header containing `<w:r><w:t xml:space="preserve">  </w:t></w:r>` between non-whitespace runs
- **WHEN** the document is read, the header is mutated (forcing `word/header1.xml` into `modifiedParts`), and written
- **THEN** the output `word/header1.xml` SHALL preserve the 2-character whitespace `<w:t>` element

### Requirement: testDocumentContentEqualityInvariant matrix-pin SHALL assert content equality across preservation classes

The test framework SHALL include a cross-cutting `testDocumentContentEqualityInvariant` test that for the thesis fixture asserts content equality between source and round-tripped `word/document.xml` across three preservation classes simultaneously: (1) `<w:bookmarkStart>` element count parity (catches paragraph-child-schema regressions), (2) `<w:t>` total character content parity (catches whitespace overlay regressions), (3) `<w:rFonts>` / `<w:noProof>` / `<w:lang>` / `<w:kern>` / `w14:*` count parity (catches RunProperties field-loss regressions). The pin asserts content equality, not byte equality — Word's own canonicalization (e.g., adjacent run consolidation) is allowed to differ.

#### Scenario: Matrix-pin fails when any preservation class regresses

- **GIVEN** the thesis fixture with 45 `<w:bookmarkStart>` elements, 6015 `<w:rFonts>` elements, and N total `<w:t>` characters in source
- **WHEN** a regression in any one preservation class causes the round-tripped output to have fewer of any of those counts
- **THEN** `testDocumentContentEqualityInvariant` SHALL fail with an `XCTAssertEqual` mismatch identifying which preservation class regressed
- **AND** the test SHALL pass when all three preservation classes round-trip equivalently

#### Scenario: Matrix-pin tolerates legitimate Word canonicalization

- **GIVEN** a fixture where Word's own save behavior would consolidate adjacent runs with identical formatting (a legitimate non-loss canonicalization)
- **WHEN** the round-tripped output has fewer `<w:r>` elements than source but the joined `<w:t>` text content and `<w:rFonts>` / `<w:noProof>` / `<w:lang>` / `<w:kern>` / `w14:*` counts are equal
- **THEN** `testDocumentContentEqualityInvariant` SHALL pass — the assertion is on content equality (counts and joined text), not on element-by-element byte equality
