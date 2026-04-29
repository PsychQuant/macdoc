## ADDED Requirements

### Requirement: WordDocument retains source archive tempDir for round-trip preservation

The `ooxml-swift` `WordDocument` SHALL expose a private `archiveTempDir: URL?` property whose value points to the unzip tempDir created by `DocxReader.read(from:)`. `DocxReader.read(from:)` SHALL NOT delete the unzip tempDir at end-of-call (the prior `defer { ZipHelper.cleanup(tempDir) }` is removed). Documents constructed via `WordDocument(...)` initializers (no source ZIP) SHALL have `archiveTempDir == nil`.

#### Scenario: Reader-loaded document carries archive tempDir

- **WHEN** `DocxReader.read(from: url)` returns a `WordDocument`
- **THEN** the returned document's `archiveTempDir` is non-nil and points to a directory containing the extracted source ZIP entries
- **AND** the directory is NOT deleted before `WordDocument.close()` is called

#### Scenario: Initializer-built document has no archive tempDir

- **WHEN** `WordDocument(...)` is invoked via any non-Reader initializer
- **THEN** the returned document's `archiveTempDir` is nil

### Requirement: WordDocument.close() releases the archive tempDir

The `ooxml-swift` `WordDocument` SHALL expose `public mutating func close()` that, when `archiveTempDir != nil`, calls `ZipHelper.cleanup(archiveTempDir!)` and sets `archiveTempDir = nil`. `close()` SHALL be idempotent — calling it on a document with `archiveTempDir == nil` is a no-op and MUST NOT throw.

#### Scenario: Close releases tempDir on a Reader-loaded document

- **WHEN** `var doc = try DocxReader.read(from: url)` followed by `doc.close()` is invoked
- **THEN** the original tempDir directory no longer exists on disk
- **AND** subsequent `doc.archiveTempDir` is nil

#### Scenario: Close is idempotent

- **WHEN** `doc.close()` is invoked twice in succession
- **THEN** neither call throws and the tempDir is released exactly once

### Requirement: DocxWriter overlay mode preserves unknown OOXML parts byte-for-byte

When `WordDocument.archiveTempDir != nil`, `DocxWriter.write(_ document:, to dest:)` SHALL operate in overlay mode: instead of building a fresh scratch tempDir, the writer SHALL overwrite the typed-model parts (document.xml, styles.xml, numbering.xml, headers, footers, footnotes.xml, endnotes.xml, comments.xml, media images, relationships) directly into `archiveTempDir`, then `ZipHelper.zip(archiveTempDir, to: dest)`. All parts in `archiveTempDir` that the typed model does NOT manage (theme/, webSettings.xml, people.xml, commentsExtended.xml, commentsExtensible.xml, commentsIds.xml, tableStyles.xml, fontTable.xml entries the writer didn't emit, glossary/, customXml/, etc.) SHALL be preserved byte-for-byte.

#### Scenario: Read-write without modification preserves all unknown parts

- **WHEN** `let doc = try DocxReader.read(from: src); try DocxWriter.write(doc, to: dest)` runs with no edits in between
- **THEN** `unzip -l src` and `unzip -l dest` produce identical entry lists (same files, same order may differ, but same set)
- **AND** for every entry path EXCEPT typed-model-managed parts (document.xml, styles.xml, numbering.xml, headers, footers, footnotes.xml, endnotes.xml, comments.xml, _rels/document.xml.rels, [Content_Types].xml, media), the byte content of the entry in `dest` is identical to that in `src`

#### Scenario: Initializer-built document falls back to scratch mode

- **WHEN** `let doc = WordDocument(...)` (no source ZIP) is written via `DocxWriter.write(doc, to: dest)`
- **THEN** the writer produces a fresh `.docx` containing only the parts the typed model holds
- **AND** the writer behavior is identical to the prior (pre-this-change) DocxWriter behavior

### Requirement: ContentTypesOverlay merges typed parts with preserved Override entries

The `ooxml-swift` package SHALL provide a `struct ContentTypesOverlay` with a method `merge(typedParts: [PartDescriptor]) -> String` that produces a `[Content_Types].xml` body by: (1) parsing original `<Override>` entries from `archiveTempDir`'s `[Content_Types].xml`, (2) replacing original entries whose PartName matches a typed part with the typed-part-derived entry (typed model is authoritative for parts it manages), (3) adding new entries for typed parts that have no original Override (e.g., a freshly-inserted image), (4) preserving original entries for unknown PartNames (e.g., `/word/theme/theme1.xml`, `/word/people.xml`) unchanged. The same algorithm SHALL run for `<Default>` content type extensions.

#### Scenario: Overlay preserves theme Override and adds new image Override

- **WHEN** the original `[Content_Types].xml` has Overrides for `/word/document.xml` and `/word/theme/theme1.xml`, and the typed model holds an additional new image at `/word/media/imageNew.png`
- **THEN** the merged Content_Types contains exactly the Override for `/word/document.xml` (replaced from typed model), the Override for `/word/theme/theme1.xml` (preserved), and the Override for `/word/media/imageNew.png` (new)
- **AND** there are no duplicate PartName entries

#### Scenario: Overlay handles deleted typed parts

- **WHEN** the original `[Content_Types].xml` has an Override for `/word/footnotes.xml`, but the typed model's `footnotes` collection is empty after a `delete_footnote` operation
- **THEN** the merged Content_Types does NOT contain the `/word/footnotes.xml` Override
- **AND** the writer also does NOT emit `/word/footnotes.xml` to the tempDir

### Requirement: RelationshipIdAllocator generates collision-free rIds across preserved and typed relationships

The `ooxml-swift` package SHALL provide a `class RelationshipIdAllocator` initialized at write time. Its initializer SHALL accept the parsed original `_rels/document.xml.rels` content from `archiveTempDir` plus the typed model's relationship-bearing fields (headers, footers, images, hyperlink references, comments, footnotes, endnotes). On init it SHALL scan both for in-use `rId` integers and compute `nextId = max(observedIds) + 1`. The class SHALL expose `func allocate() -> String` returning `"rId\(nextId)"` and incrementing `nextId`, and `func reserve(_ id: String)` marking an existing ID as taken. The naive counter pattern `usedCount = headers.count + footers.count + ...` at the prior `DocxWriter.swift:238` SHALL be removed in favor of allocator calls.

#### Scenario: Allocator avoids collision with preserved original rId

- **WHEN** the original `_rels/document.xml.rels` contains `rId7` and the typed model has 3 headers (which under the prior naive counter would be assigned rIds 1-3)
- **AND** `allocator.allocate()` is called once
- **THEN** the returned rId is `"rId8"` (max original + 1)
- **AND** subsequent `allocate()` calls return `"rId9"`, `"rId10"`, etc.

#### Scenario: Reserve marks existing ID as taken

- **WHEN** `allocator.reserve("rId12")` is called
- **THEN** subsequent `allocator.allocate()` calls do NOT return `"rId12"`
- **AND** the next allocated ID is `max(observedBefore, 12) + 1`

### Requirement: Round-trip fidelity regression test asserts byte-equality on minimal-multipart fixture

The `ooxml-swift` test suite SHALL contain `Tests/OOXMLSwiftTests/RoundTripFidelityTests.swift` with at least one test case that: (1) reads the binary fixture `Tests/OOXMLSwiftTests/Fixtures/minimal-multipart.docx`, (2) immediately writes it to a destination URL with no edits, (3) asserts the destination ZIP entry list equals the source entry list (set equality on entry paths), (4) for every entry path EXCEPT typed-managed parts (document.xml, styles.xml, comments.xml, _rels/, [Content_Types].xml, media), asserts byte-content equality. The fixture SHALL contain at minimum: 1 body paragraph + 1 default header + 1 default footer + theme1.xml with `minorEastAsia` font set + 1 `<w15:person>` in people.xml + webSettings.xml setting `relyOnVML=true` + 1 image in media/.

#### Scenario: Round-trip preserves theme1.xml byte-for-byte

- **WHEN** the round-trip test runs against `minimal-multipart.docx`
- **THEN** `dest`'s `word/theme/theme1.xml` content is byte-identical to `src`'s `word/theme/theme1.xml`

#### Scenario: Round-trip preserves people.xml byte-for-byte

- **WHEN** the round-trip test runs against `minimal-multipart.docx`
- **THEN** `dest`'s `word/people.xml` content is byte-identical to `src`'s `word/people.xml`

#### Scenario: Round-trip preserves webSettings.xml byte-for-byte

- **WHEN** the round-trip test runs against `minimal-multipart.docx`
- **THEN** `dest`'s `word/webSettings.xml` content is byte-identical to `src`'s `word/webSettings.xml`

#### Scenario: Round-trip preserves [Content_Types].xml Override entries

- **WHEN** the round-trip test runs against `minimal-multipart.docx`
- **THEN** the set of `<Override>` PartName values in `dest`'s `[Content_Types].xml` equals the set in `src`'s `[Content_Types].xml`
