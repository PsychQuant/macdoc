## ADDED Requirements

### Requirement: DocxWriter detects archiveTempDir and switches to overlay mode

The `ooxml-swift` `DocxWriter.write(_ document: WordDocument, to dest: URL)` SHALL inspect `document.archiveTempDir`. When the property is non-nil (Reader-loaded round-trip mode), the writer SHALL: (1) overwrite typed-model-managed parts directly into `archiveTempDir` (document.xml, styles.xml, numbering.xml, headers, footers, footnotes.xml, endnotes.xml, comments.xml, media images), (2) write the overlay-merged `[Content_Types].xml` and `_rels/document.xml.rels` into `archiveTempDir`, (3) `ZipHelper.zip(archiveTempDir, to: dest)`. When `archiveTempDir == nil` (initializer-built document), the writer SHALL fall back to the prior scratch-tempDir behavior unchanged.

#### Scenario: Overlay mode preserves unknown parts in destination

- **WHEN** `let doc = try DocxReader.read(from: src); try DocxWriter.write(doc, to: dest)` runs with `src` containing `word/theme/theme1.xml`
- **THEN** `dest` contains `word/theme/theme1.xml` with byte content equal to `src`'s
- **AND** `doc.archiveTempDir` was used as the overlay base

#### Scenario: Scratch mode unchanged for initializer-built documents

- **WHEN** `let doc = WordDocument(...); try DocxWriter.write(doc, to: dest)` runs (no source ZIP)
- **THEN** the writer behavior matches the prior pre-overlay implementation
- **AND** `dest` contains only parts the typed model declares (no preserved-from-source parts since there was no source)

### Requirement: ContentTypesOverlay merge produces a single Override per PartName

The `ooxml-swift` `ContentTypesOverlay` SHALL produce a `[Content_Types].xml` body whose `<Override>` set is the deduplicated merge of: (a) original `<Override>` entries from `archiveTempDir`'s `[Content_Types].xml` for PartNames the typed model does NOT manage, and (b) typed-part-derived `<Override>` entries for PartNames the typed model emits. PartNames present in both sets SHALL appear exactly once, with the typed-part-derived entry taking precedence. PartNames present only in (a) SHALL be preserved unchanged. PartNames present only in (b) (e.g., a freshly-inserted image) SHALL be added.

#### Scenario: Theme Override preserved while document Override comes from typed model

- **WHEN** original `[Content_Types].xml` has Overrides for `/word/document.xml` and `/word/theme/theme1.xml`, and the typed model emits `/word/document.xml`
- **THEN** the merged `[Content_Types].xml` has exactly one `<Override>` for `/word/document.xml` (from typed model) and exactly one for `/word/theme/theme1.xml` (preserved)
- **AND** there are no duplicate `<Override>` entries

#### Scenario: New image Override added

- **WHEN** original `[Content_Types].xml` has no Override for `/word/media/imageNew.png`, but the typed model emits that media entry after `insert_image`
- **THEN** the merged `[Content_Types].xml` contains an `<Override>` for `/word/media/imageNew.png` with content type `image/png` (or matching the file's actual content type)

#### Scenario: Default content type extensions preserved with same merge rule

- **WHEN** original `[Content_Types].xml` has `<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>` and `<Default Extension="xml" ContentType="application/xml"/>`
- **THEN** the merged `[Content_Types].xml` contains both `<Default>` entries (preserved verbatim) plus any new extensions implied by the typed model's media files

### Requirement: RelationshipIdAllocator scans original rels and typed fields together

The `ooxml-swift` package SHALL provide `class RelationshipIdAllocator`. Its initializer SHALL accept the parsed original `_rels/document.xml.rels` content from `archiveTempDir` plus the typed model's relationship-bearing collections (headers, footers, images, hyperlink references, comments, footnotes, endnotes). On init it SHALL parse all `Id="rId<N>"` integers from the original rels XML and from typed fields, compute `nextId = max(observed) + 1`. The class SHALL expose `func allocate() -> String` returning `"rId\(nextId)"` and incrementing internally, and `func reserve(_ id: String)` marking an ID as taken (no-op if already taken). The naive counter pattern at the prior `DocxWriter.swift:238` (`usedCount = headers.count + footers.count + images.count + ...`) SHALL be replaced by allocator calls.

#### Scenario: Allocator avoids collision with preserved original rId

- **WHEN** the original `_rels/document.xml.rels` contains `<Relationship Id="rId7"...>` and the typed model has 3 headers
- **AND** `allocator.allocate()` is called once
- **THEN** the returned ID is `"rId8"` (max(observed) + 1, where observed includes 7 from original)
- **AND** subsequent `allocate()` calls return `"rId9"`, `"rId10"`, etc. with no repeats and no `"rId7"` reuse

#### Scenario: Reserve marks an explicit ID as taken

- **WHEN** `allocator.reserve("rId12")` is called on an allocator whose previous max observed was 5
- **THEN** subsequent `allocator.allocate()` calls do NOT return `"rId12"`
- **AND** the next allocated ID is `"rId13"`

#### Scenario: Allocator handles non-numeric rId values gracefully

- **WHEN** the original rels contains `<Relationship Id="rIdAbc"...>` (non-numeric suffix)
- **THEN** the allocator skips that ID for max calculation (treats it as unobservable)
- **AND** continues allocating numeric IDs based on numeric observations only
