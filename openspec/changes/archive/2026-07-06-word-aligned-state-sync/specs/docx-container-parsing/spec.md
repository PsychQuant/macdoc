## ADDED Requirements

### Requirement: All parts preserved via XmlNode tree alongside typed views

In addition to the existing typed-model coverage of named parts, `DocxReader.read(from:)` SHALL load every part listed in `[Content_Types].xml` into the underlying `XmlNode` tree provided by the `ooxml-tree-io` capability. Parts the typed model does not consume (e.g., `word/glossary/document.xml`, `word/customXml/*.xml`, `customXml/itemProps*.xml`) SHALL remain accessible via the tree and SHALL serialize byte-equal on round-trip when not modified.

#### Scenario: Unknown part survives round-trip

- **GIVEN** an input docx containing `customXml/item1.xml` and `customXml/itemProps1.xml` parts
- **WHEN** `DocxReader.read(from:)` runs followed by `DocxWriter.write(document, to: out)` with no mutations
- **THEN** the output docx contains `customXml/item1.xml` and `customXml/itemProps1.xml` byte-equal to the input

#### Scenario: Unknown elements within known parts survive round-trip

- **GIVEN** `word/document.xml` containing `<mc:AlternateContent>`, `<w:pict>`, `<w:hdrShapeDefaults>`, and `<w:rsids>` (none typed-modelled today)
- **WHEN** the document is read and written with no mutations
- **THEN** every such element appears byte-equal in the output `word/document.xml`

### Requirement: Reader does not silently drop element classes

`DocxReader.parseBody`, `DocxReader.parseSettings`, `DocxReader.parseStyles`, `DocxReader.parseHeaders`, `DocxReader.parseFooters`, `DocxReader.parseFootnotes`, and `DocxReader.parseEndnotes` SHALL NOT discard XML elements they do not type-model. Unrecognized children SHALL flow through to the underlying `XmlNode` tree and remain available for serialization.

#### Scenario: parseSettings retains all settings.xml children

- **GIVEN** `word/settings.xml` containing `<w:zoom>`, `<w:bordersDoNotSurroundHeader>`, `<w:characterSpacingControl>`, `<w:hdrShapeDefaults>`, `<w:footnotePr>`, `<w:endnotePr>`, `<w:compat>`, `<w:rsids>`, `<w:mathPr>`, `<w:themeFontLang>`
- **WHEN** the document is read and written with no mutations
- **THEN** all of the above elements appear in the output `word/settings.xml` byte-equal to the input

##### Example: settings.xml round-trip preservation

- **GIVEN** an input `word/settings.xml` of 19,083 bytes
- **WHEN** the document round-trips through `DocxReader.read` + `DocxWriter.write` with no edits
- **THEN** the output `word/settings.xml` is byte-equal to the input (no shrinkage, no element drop)

### Requirement: Multi-section sectPr preservation

`DocxReader.parseBody` SHALL preserve every `<w:sectPr>` element at its original position in the body, including section-break sectPrs nested inside `<w:p><w:pPr>` and the final body-end sectPr. The typed `Document.body.sections` view SHALL reflect every section; the underlying tree SHALL retain every `<w:sectPr>` byte-equal on no-op round-trip.

#### Scenario: Three-section thesis round-trips

- **GIVEN** a docx with three `<w:sectPr>` elements (front matter / body / cover, each carrying its own `<w:headerReference>` and `<w:footerReference>`)
- **WHEN** the document is read and written with no mutations
- **THEN** the output contains three `<w:sectPr>` elements at the same positions, each retaining all `<w:headerReference>`, `<w:footerReference>`, `<w:pgSz>`, `<w:pgMar>`, `<w:pgNumType>`, `<w:titlePg>`, `<w:cols>`, and `<w:docGrid>` children byte-equal to the input

### Requirement: Container parts preserve unknown children identically to body

`DocxReader.parseHeaders`, `DocxReader.parseFooters`, `DocxReader.parseFootnotes`, `DocxReader.parseEndnotes`, and `DocxReader.parseComments` SHALL apply the same preservation rule as the body: unrecognized children flow into the tree and round-trip byte-equal when untouched.

#### Scenario: Header VML survives round-trip

- **GIVEN** `word/header1.xml` contains `<w:pict>` carrying VML watermark XML
- **WHEN** the document is read and written with no mutations
- **THEN** `word/header1.xml` in the output contains the same `<w:pict>` element byte-equal to the input
