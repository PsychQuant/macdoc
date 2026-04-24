## ADDED Requirements

### Requirement: DocxReader parses w:sdt into structured ContentControl values

DocxReader SHALL recognize `<w:sdt>` elements during document parsing and produce structured `ContentControl` instances. The structured representation SHALL replace the current practice of preserving SDT XML as a `Run.rawXML` blob.

Each parsed `ContentControl` SHALL include: id (from `<w:id w:val>`), tag (from `<w:tag w:val>`), alias (from `<w:alias w:val>`), type (inferred from `<w:sdtPr>` type markers), lockType (from `<w:lock w:val>`), placeholder (from `<w:placeholder>`), and the raw content XML of the `<w:sdtContent>` region.

#### Scenario: Parse plain-text SDT

- **GIVEN** a document containing `<w:p><w:sdt><w:sdtPr><w:tag w:val="client_name"/><w:alias w:val="Client Name"/><w:text/></w:sdtPr><w:sdtContent><w:r><w:t>Acme</w:t></w:r></w:sdtContent></w:sdt></w:p>`
- **WHEN** DocxReader reads the document
- **THEN** the resulting Paragraph has a ContentControl entry with `type=.plainText`, `tag="client_name"`, `alias="Client Name"`, content "Acme"
- **AND** the Paragraph's runs do not contain the SDT XML as rawXML

### Requirement: SDTParser distinguishes all 12 SDT types

The parser SHALL identify the SDT type by inspecting `<w:sdtPr>` children in this priority order: `<w:text/>` → plainText, `<w:picture/>` → picture, `<w:date>` → date, `<w:dropDownList>` → dropDownList, `<w:comboBox>` → comboBox, `<w14:checkbox>` → checkbox, `<w:bibliography/>` → bibliography, `<w:citation/>` → citation, `<w:group/>` → group, `<w15:repeatingSection>` → repeatingSection, `<w15:repeatingSectionItem>` → repeatingSectionItem. Absence of any type marker SHALL default to richText.

#### Scenario: Checkbox SDT with extended namespace

- **GIVEN** `<w:sdt><w:sdtPr><w14:checkbox xmlns:w14="..."/></w:sdtPr>...</w:sdt>`
- **WHEN** DocxReader reads the element
- **THEN** the ContentControl has `type=.checkbox`

#### Scenario: Repeating section with w15 namespace

- **GIVEN** `<w:sdt><w:sdtPr><w15:repeatingSection xmlns:w15="..."/></w:sdtPr>...</w:sdt>`
- **WHEN** DocxReader reads the element
- **THEN** the ContentControl has `type=.repeatingSection`

### Requirement: SDTParser handles nested SDTs by preserving tree structure

When an SDT contains other SDT elements in its `<w:sdtContent>`, the outer ContentControl SHALL include a `children: [ContentControl]` field populated with the parsed nested controls. Each child carries a `parentSdtId` reference to the outer SDT's id.

#### Scenario: Group containing plain-text children

- **GIVEN** a group SDT with two nested plainText SDTs
- **WHEN** DocxReader reads the document
- **THEN** the outer ContentControl has `type=.group`, `children.count == 2`
- **AND** both child ContentControls have `parentSdtId` equal to the outer id

### Requirement: SDTParser handles block-level SDTs wrapping paragraphs and tables

When `<w:sdt>` appears directly inside `<w:body>` or `<w:tc>` (not inside a `<w:p>`), DocxReader SHALL represent it as a block-level ContentControl containing child BodyElements (paragraphs or tables). The container's position in the body children list is preserved.

#### Scenario: Block-level SDT wrapping two paragraphs

- **GIVEN** `<w:body><w:sdt>...<w:sdtContent><w:p>A</w:p><w:p>B</w:p></w:sdtContent></w:sdt></w:body>`
- **WHEN** DocxReader reads the document
- **THEN** the document body contains one block-level ContentControl whose children are two Paragraph values with text "A" and "B"

### Requirement: SDT round-trip preserves byte-level content fidelity

A document read then written without modification SHALL produce SDT XML that Word opens without errors and that preserves every `<w:sdtPr>` child element attribute. Reorderings are permitted when the OOXML schema treats children as unordered; otherwise the original order SHALL be preserved.

#### Scenario: Read-write round-trip on fixture

- **GIVEN** a test fixture `sdt-template.docx` containing one SDT per supported type (11 SDTs)
- **WHEN** DocxReader reads the fixture and DocxWriter emits it back to disk with no modifications
- **THEN** the output document opens in Word 2021+ without any error dialog
- **AND** each output SDT's id, tag, alias, type marker, lockType, and placeholder match the input

