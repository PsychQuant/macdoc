## ADDED Requirements

### Requirement: Run preserves unknown OOXML child elements via rawElements carrier

The `Run` typed model SHALL provide a `rawElements: [(name: String, xml: String)]?` field. The Reader (`DocxReader.parseRun`) SHALL collect any direct child of `<w:r>` whose local name is NOT among the recognized typed kinds (`rPr`, `t`, `drawing`, `oMath`, `oMathPara`) into this array, in source-document order. For each collected element, `name` SHALL be the local name (e.g., `"pict"`, `"object"`, `"ruby"`) and `xml` SHALL be the verbatim serialized XML of that element.

The Writer (`Run.toXML()`) SHALL emit typed children in the existing fixed order (`rPr`, then text/drawing/rawXML), then SHALL append every entry in `rawElements` (in array order) immediately after the typed children but before the closing `</w:r>` tag. The verbatim `xml` portion SHALL be emitted byte-for-byte without re-parsing.

When `rawElements` is `nil` or empty, the writer behavior SHALL be identical to the pre-fix behavior (no-op append). When the Reader encounters a `<w:r>` with no unknown children, it SHALL set `rawElements` to `nil` (NOT an empty array) so programmatic Run construction without rawElements remains Equatable-equal to reader-loaded Runs without unknown elements.

#### Scenario: VML watermark Run round-trips byte-equal

- **GIVEN** a `<w:r>` element with `<w:rPr><w:noProof/></w:rPr>` and `<w:pict><v:shape>...</v:shape></w:pict>` and no `<w:t>` child (typical NTPU watermark structure)
- **WHEN** `parseRun` processes the element
- **THEN** the resulting `Run.text` is `""`, `Run.properties.noProof` is `true`, and `Run.rawElements` contains exactly one entry `(name: "pict", xml: "<w:pict><v:shape>...</v:shape></w:pict>")`
- **AND** `Run.drawing` is `nil` (`<w:pict>` is NOT a `<w:drawing>`)
- **WHEN** `Run.toXML()` is called on the parsed Run
- **THEN** the emitted XML contains `<w:rPr><w:noProof/></w:rPr>` followed by the verbatim `<w:pict>...` block, byte-equal to the source `<w:pict>` substring

##### Example: Round-trip preserves verbatim VML

Given source XML:
```xml
<w:r>
  <w:rPr><w:noProof/></w:rPr>
  <w:pict>
    <v:shape id="WordPictureWatermark" type="#_x0000_t136" style="position:absolute;mso-position-horizontal:center" fillcolor="silver">
      <v:textpath style="font-family:&quot;Arial&quot;" string="DRAFT"/>
    </v:shape>
  </w:pict>
</w:r>
```

After parseRun:
```swift
Run(
  text: "",
  properties: RunProperties(noProof: true),
  drawing: nil,
  rawElements: [(
    name: "pict",
    xml: #"<w:pict><v:shape id="WordPictureWatermark" type="#_x0000_t136" style="position:absolute;mso-position-horizontal:center" fillcolor="silver"><v:textpath style="font-family:&quot;Arial&quot;" string="DRAFT"/></v:shape></w:pict>"#
  )]
)
```

After Run.toXML(): the emitted `<w:r>...</w:r>` contains the verbatim `<w:pict>` substring (whitespace differences in the wrapper acceptable; the unknown portion byte-preserved).

#### Scenario: Run with multiple unknown elements preserves source order

- **GIVEN** a `<w:r>` element with two unknown children in source order: `<w:pict>...</w:pict>` followed by `<w:object>...</w:object>` (hypothetical co-located embed)
- **WHEN** `parseRun` processes the element
- **THEN** `Run.rawElements` is `[(name: "pict", xml: "<w:pict>...</w:pict>"), (name: "object", xml: "<w:object>...</w:object>")]` in that order
- **WHEN** `Run.toXML()` emits
- **THEN** the `<w:pict>` block precedes the `<w:object>` block in the output

#### Scenario: Equatable conformance treats nil and missing-rawElements as equal

- **GIVEN** `let r1 = Run(text: "hello")` (programmatic construction, `rawElements` defaults to nil)
- **AND** `let r2` is the result of parsing `<w:r><w:t>hello</w:t></w:r>` via `parseRun` (no unknown children → `rawElements = nil`)
- **THEN** `r1 == r2` SHALL be `true`

### Requirement: Header/Footer round-trip preserves VML watermarks via Run-layer carrier

When a header or footer paragraph contains a Run with `rawElements`, the full container round-trip (`DocxReader.read` → mutate → `DocxWriter.write` overlay-mode re-emit) SHALL preserve the unknown XML portion byte-for-byte. Specifically: when `Header.toXML()` invokes `Paragraph.toXML()` invokes `Run.toXML()`, the rawElements emit chain ensures the final `word/headerN.xml` byte content for the unknown portion equals the source byte content (modulo XML whitespace in the typed-children wrapper).

#### Scenario: update_all_fields preserves VML watermark in header

- **GIVEN** a `.docx` whose `word/header1.xml` contains a `<w:p>` → `<w:r>` → `<w:pict>` → `<v:shape>` watermark structure
- **AND** the document body contains a SEQ Figure field that needs updating
- **WHEN** `WordDocument.updateAllFields()` is called and `DocxWriter.write(doc, to:)` saves the result
- **THEN** the saved `word/header1.xml` byte content for the `<w:pict>` block equals the source byte content
- **AND** the source `<v:shape>` `string` attribute (e.g., `"DRAFT"`) survives in the saved file

#### Scenario: update_header preserves VML watermark when only changing paragraph text

- **GIVEN** a `.docx` with `word/header1.xml` containing one paragraph (e.g., chapter caption) AND a separate paragraph carrying a VML watermark
- **WHEN** `WordDocument.updateHeader(id:text:)` is called to change the chapter caption text
- **AND** the document is saved via `DocxWriter.write(doc, to:)`
- **THEN** the saved `word/header1.xml` retains the watermark paragraph's `<w:pict>` byte-for-byte
- **AND** the chapter caption paragraph reflects the new text

