## ADDED Requirements

### Requirement: Header struct preserves originalFileName from source archive

The `ooxml-swift` `Header` struct SHALL expose `public var originalFileName: String?` recording the actual archive file path the header was read from (e.g., `"header4.xml"`). `DocxReader.read()` SHALL populate `originalFileName` from each header's relationship `Target` attribute in `_rels/document.xml.rels`. When the typed model creates a new header (via `Header.withText` / `Header.withPageNumber` initializer or `WordDocument.addHeader`), `originalFileName` SHALL remain `nil` and the existing type-based default naming logic in `Header.fileName` SHALL apply.

#### Scenario: Reader populates originalFileName from rels Target

- **WHEN** `DocxReader.read()` parses a document whose `_rels/document.xml.rels` has `<Relationship Id="rId8" Type=".../header" Target="header4.xml"/>`
- **THEN** the corresponding parsed `Header` instance has `originalFileName == "header4.xml"`

#### Scenario: Header.fileName returns originalFileName when present

- **WHEN** a `Header` instance has `originalFileName == "header4.xml"` and `type == .default`
- **THEN** `header.fileName == "header4.xml"` (NOT `"header1.xml"` per the legacy type-based default)

#### Scenario: Header.fileName falls back to type-based default when originalFileName nil

- **WHEN** a freshly-built `Header(id: "rId99", paragraphs: [], type: .default)` instance with `originalFileName == nil`
- **THEN** `header.fileName == "header1.xml"` (legacy behavior preserved for newly-added headers)

### Requirement: Footer struct preserves originalFileName from source archive

The `ooxml-swift` `Footer` struct SHALL expose `public var originalFileName: String?` with the same semantics as `Header.originalFileName`. `DocxReader.read()` SHALL populate it from each footer's relationship Target. `Footer.fileName` SHALL return `originalFileName ?? type-based-default`.

#### Scenario: Reader populates Footer.originalFileName from rels Target

- **WHEN** `DocxReader.read()` parses a document whose rels declares `<Relationship Id="rId10" Type=".../footer" Target="footer3.xml"/>`
- **THEN** the corresponding parsed `Footer` instance has `originalFileName == "footer3.xml"` and `footer.fileName == "footer3.xml"`

### Requirement: Multi-instance same-type headers/footers preserve distinct fileNames

When a source archive contains multiple headers of the same type (e.g., 6 default headers across multiple sections, mapping to `header1.xml` through `header6.xml`), `WordDocument.headers` SHALL contain 6 distinct `Header` instances each with a different `originalFileName` reflecting the actual archive path. `headers.map { $0.fileName }` SHALL return 6 distinct strings, never collapsing to a single fileName.

#### Scenario: NTPU thesis 6 default headers preserve distinct fileNames

- **WHEN** `DocxReader.read()` parses a document with 6 default headers at archive paths `header1.xml` through `header6.xml`
- **THEN** `doc.headers.count == 6`
- **AND** `Set(doc.headers.map { $0.fileName }) == Set(["header1.xml", "header2.xml", "header3.xml", "header4.xml", "header5.xml", "header6.xml"])`

#### Scenario: list_headers tool can address each header by distinct fileName

- **WHEN** an external tool iterates `doc.headers` and reads each header's content via `archiveTempDir.appendingPathComponent("word/\(header.fileName)")`
- **THEN** each header's content is read from a distinct file (no two headers map to the same file)
