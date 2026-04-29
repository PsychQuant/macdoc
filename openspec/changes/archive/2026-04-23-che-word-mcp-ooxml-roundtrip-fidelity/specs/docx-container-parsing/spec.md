## ADDED Requirements

### Requirement: DocxReader retains source unzip tempDir on the returned WordDocument

The `ooxml-swift` `DocxReader.read(from:)` SHALL extract the source `.docx` ZIP to a tempDir AND retain that tempDir's URL on the returned `WordDocument` instance via the `archiveTempDir` property. The Reader SHALL NOT delete the tempDir before returning. The tempDir SHALL contain every entry from the source ZIP, regardless of whether the typed model parsed those entries. This requirement supersedes the prior implicit behavior of `defer { ZipHelper.cleanup(tempDir) }` at the end of `DocxReader.read()`.

#### Scenario: Reader returns document with tempDir containing all source entries

- **WHEN** `let doc = try DocxReader.read(from: url)` runs against a `.docx` containing `word/document.xml`, `word/theme/theme1.xml`, `word/people.xml`, and `word/webSettings.xml`
- **THEN** `doc.archiveTempDir` is non-nil
- **AND** the directory at `doc.archiveTempDir!` contains `word/document.xml`, `word/theme/theme1.xml`, `word/people.xml`, and `word/webSettings.xml` as files

#### Scenario: Reader does not delete tempDir before returning

- **WHEN** `let doc = try DocxReader.read(from: url)` returns
- **THEN** the tempDir at `doc.archiveTempDir!` exists on disk and is readable
- **AND** the prior `defer { ZipHelper.cleanup(tempDir) }` cleanup at end of `DocxReader.read()` is removed

### Requirement: Container coverage extends to opaque preservation of all unknown parts

The `ooxml-swift` container `read → write` cycle SHALL preserve every part present in the source ZIP, including parts the typed model does not parse: `word/theme/theme1.xml` and the entire `word/theme/` folder, `word/webSettings.xml`, `word/people.xml`, `word/commentsExtended.xml`, `word/commentsExtensible.xml`, `word/commentsIds.xml`, `word/tableStyles.xml`, `word/glossary/` entries, `word/customXml/` entries, and any other parts not explicitly typed-managed. Preservation is opaque (byte-for-byte) for unknown parts; typed parts are re-emitted from the typed model.

#### Scenario: Theme part preserved without typed parsing

- **WHEN** a document with `word/theme/theme1.xml` is read and immediately written without modification
- **THEN** the destination `.docx` contains `word/theme/theme1.xml` whose bytes equal the source

#### Scenario: Glossary parts preserved without typed parsing

- **WHEN** a document containing `word/glossary/document.xml` and `word/glossary/_rels/document.xml.rels` is read and immediately written without modification
- **THEN** the destination `.docx` contains both glossary entries with byte-for-byte equal contents
