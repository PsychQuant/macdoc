## ADDED Requirements

### Requirement: ParagraphProperties SHALL preserve paragraph-mark RunProperties through round-trip

The `ParagraphProperties` model SHALL provide a `markRunProperties: RunProperties?` field that captures the `<w:rPr>` direct child of `<w:pPr>` (paragraph-mark formatting per ECMA-376 §17.3.1.27 CT_PPrBase). The Reader SHALL extract this field by reusing the existing `parseRunProperties(from:)` helper — typed extraction (4-axis `<w:rFonts>`, `<w:noProof>`, `<w:kern>`, 3-axis `<w:lang>`) and raw passthrough (`rawChildren` for unknown rPr children including `w14:*` effects) MUST behave identically to run-level rPr handling. The Writer SHALL emit `<w:rPr>...</w:rPr>` inside `<w:pPr>` whenever `markRunProperties` is non-nil.

#### Scenario: Paragraph-mark rPr 4-axis rFonts preserved through round-trip

- **GIVEN** a `.docx` file containing `<w:pPr><w:rPr><w:rFonts w:ascii="Times New Roman" w:hAnsi="Times New Roman" w:eastAsia="DFKai-SB" w:cs="Times New Roman"/></w:rPr></w:pPr>` on at least one paragraph
- **WHEN** `DocxReader.read(from:)` parses the file and `DocxWriter.write(_:to:)` re-serializes after marking `word/document.xml` modified
- **THEN** the output `<w:pPr>` SHALL contain a nested `<w:rPr>` with `<w:rFonts>` carrying all 4 attributes (`w:ascii`, `w:hAnsi`, `w:eastAsia`, `w:cs`) equal to the source values

#### Scenario: Paragraph-mark rPr lang preserved through round-trip

- **GIVEN** a `.docx` file containing `<w:pPr><w:rPr><w:lang w:val="en-US" w:eastAsia="zh-TW" w:bidi="ar-SA"/></w:rPr></w:pPr>` on at least one paragraph
- **WHEN** the document is read and written back with `word/document.xml` in `modifiedParts`
- **THEN** the output `<w:pPr>` SHALL contain `<w:rPr>` with `<w:lang>` carrying all 3 attributes equal to source

#### Scenario: Paragraph-mark rPr w14 namespace effects preserved as raw children

- **GIVEN** a `.docx` file containing `<w:pPr><w:rPr><w14:textOutline w14:w="9525"><w14:solidFill><w14:srgbClr w14:val="000000"/></w14:solidFill></w14:textOutline></w:rPr></w:pPr>`
- **WHEN** the document is read and written back with `word/document.xml` in `modifiedParts`
- **THEN** the output `<w:pPr><w:rPr>` SHALL contain the `<w14:textOutline>` element with its full child tree byte-equivalent to the source

#### Scenario: Paragraph without paragraph-mark rPr round-trips unchanged

- **GIVEN** a `.docx` file containing `<w:pPr><w:pStyle w:val="Normal"/></w:pPr>` (no nested `<w:rPr>`)
- **WHEN** the document is read and written back with `word/document.xml` in `modifiedParts`
- **THEN** the output `<w:pPr>` SHALL NOT contain any `<w:rPr>` child element (`markRunProperties` defaults to nil and is not emitted)

### Requirement: Paragraph SHALL preserve w14:paraId and w14:textId attributes through round-trip

The `Paragraph` model SHALL provide `w14ParaId: String?` and `w14TextId: String?` fields capturing the `w14:paraId` and `w14:textId` attributes on the `<w:p>` opening tag. The Reader SHALL extract both attributes when present. The Writer SHALL emit each attribute on the `<w:p>` opening tag whenever the corresponding field is non-nil. Values SHALL be preserved as opaque strings (no parsing or normalization) — Word's GUIDs are 8-character hex tokens that round-trip byte-for-byte.

#### Scenario: w14:paraId and w14:textId round-trip preserved

- **GIVEN** a `.docx` file containing `<w:p w14:paraId="0AB12345" w14:textId="01234567"><w:r><w:t>text</w:t></w:r></w:p>`
- **WHEN** the document is read and written back with `word/document.xml` in `modifiedParts`
- **THEN** the output `<w:p>` opening tag SHALL contain `w14:paraId="0AB12345"` and `w14:textId="01234567"` byte-equivalent to source

#### Scenario: Paragraph with only w14:paraId (no w14:textId) round-trips correctly

- **GIVEN** a `.docx` file containing `<w:p w14:paraId="DEADBEEF"><w:r><w:t>text</w:t></w:r></w:p>` (paraId without textId)
- **WHEN** the document is read and written back with `word/document.xml` in `modifiedParts`
- **THEN** the output `<w:p>` opening tag SHALL contain `w14:paraId="DEADBEEF"` and SHALL NOT contain `w14:textId`

#### Scenario: Paragraph without w14 attributes round-trips unchanged

- **GIVEN** a `.docx` file containing `<w:p><w:r><w:t>text</w:t></w:r></w:p>` (no w14:* attributes)
- **WHEN** the document is read and written back with `word/document.xml` in `modifiedParts`
- **THEN** the output `<w:p>` opening tag SHALL NOT contain any `w14:paraId` or `w14:textId` attribute

### Requirement: testDocumentContentEqualityInvariant matrix-pin SHALL ratchet paragraph-level preservation floors

The cross-cutting `testDocumentContentEqualityInvariant` matrix-pin test SHALL include explicit ratio-floor assertions for paragraph-level preservation classes that ratchet upward as sub-stacks D and E land. After sub-stack D lands, the `<w:lang ` retention floor SHALL be ≥ 0.95 (was 0.45). After sub-stack E lands, the `w14:` retention floor SHALL be ≥ 0.95 (was 0.04). After both sub-stacks land, the thesis-fixture `document.xml` `sizeLossRatio` ceiling SHALL be ≤ 0.05 (was 0.175). Each ratchet SHALL be committed in the same change as the implementation that justifies it.

#### Scenario: Matrix-pin fails when paragraph-mark rPr regresses post-D

- **GIVEN** the thesis fixture round-tripped after sub-stack D lands, with `<w:lang ` retention floor asserted at ≥ 0.95
- **WHEN** a future regression in `parseParagraphProperties` reintroduces silent drop of `<w:pPr><w:rPr>` and `<w:lang>` retention drops below 0.95
- **THEN** `testDocumentContentEqualityInvariant` SHALL fail with a ratio-floor violation identifying the `<w:lang>` preservation class

#### Scenario: Matrix-pin fails when w14:paraId regresses post-E

- **GIVEN** the thesis fixture round-tripped after sub-stack E lands, with `w14:` retention floor asserted at ≥ 0.95
- **WHEN** a future regression in `parseParagraph` drops `w14:paraId` extraction and w14: token retention falls below 0.95
- **THEN** `testDocumentContentEqualityInvariant` SHALL fail with a ratio-floor violation identifying the `w14:` preservation class

#### Scenario: Matrix-pin sizeLossRatio ceiling reflects combined gains

- **GIVEN** the thesis fixture round-tripped after both sub-stacks D and E land
- **WHEN** the matrix-pin computes `sizeLossRatio = (sourceBytes - roundTrippedBytes) / sourceBytes` for `word/document.xml`
- **THEN** the ratio SHALL be ≤ 0.05 and the assertion `XCTAssertLessThanOrEqual(sizeLossRatio, 0.05)` SHALL pass
