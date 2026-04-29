## ADDED Requirements

### Requirement: DocxReader SHALL extract w14:paraId and w14:textId attributes from body paragraphs

`DocxReader.parseParagraph` SHALL extract the `w14:paraId` and `w14:textId` attributes from `<w:p>` opening tags into the `Paragraph` model's `w14ParaId` and `w14TextId` fields. Both attributes SHALL be treated as opaque string tokens (no parsing, no validation, no normalization). When an attribute is absent on the source `<w:p>` tag, the corresponding model field SHALL be nil. Extraction SHALL apply uniformly across all parts that use the body paragraph parser: `word/document.xml`, `word/header*.xml`, `word/footer*.xml`, `word/footnotes.xml`, `word/endnotes.xml`. The existing `parseComments` extraction of `w14:paraId` for comment threading (DocxReader.swift:3165) SHALL be unchanged — comment-internal extraction operates on a separate code path and remains independent.

#### Scenario: Body paragraph with w14:paraId extracted into Paragraph.w14ParaId

- **GIVEN** a `.docx` file `word/document.xml` containing `<w:body><w:p w14:paraId="0AB12345" w14:textId="01234567"><w:r><w:t>text</w:t></w:r></w:p></w:body>`
- **WHEN** `DocxReader.read(from:)` parses the file
- **THEN** the resulting `WordDocument.body.children[0]` SHALL be a `Paragraph` with `w14ParaId == "0AB12345"` and `w14TextId == "01234567"`

#### Scenario: Body paragraph without w14 attributes results in nil fields

- **GIVEN** a `.docx` file `word/document.xml` containing `<w:body><w:p><w:r><w:t>text</w:t></w:r></w:p></w:body>` (no w14:* attributes)
- **WHEN** `DocxReader.read(from:)` parses the file
- **THEN** the resulting `Paragraph` SHALL have `w14ParaId == nil` and `w14TextId == nil`

#### Scenario: Header paragraph w14 extraction matches body extraction

- **GIVEN** a `.docx` file `word/header1.xml` containing `<w:hdr><w:p w14:paraId="DEADBEEF"><w:r><w:t>header text</w:t></w:r></w:p></w:hdr>`
- **WHEN** `DocxReader.read(from:)` parses the file
- **THEN** the header's first paragraph SHALL have `w14ParaId == "DEADBEEF"` and `w14TextId == nil`
