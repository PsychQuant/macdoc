## ADDED Requirements

### Requirement: DocxReader parses bookmark range markers as Paragraph children

`DocxReader` SHALL parse `<w:bookmarkStart w:id="..." w:name="..."/>` and `<w:bookmarkEnd w:id="..."/>` elements found as direct children of `<w:p>` elements. Each parsed `<w:bookmarkStart>` SHALL be added to `Paragraph.bookmarks` as a `Bookmark(id: Int, name: String)` plus a `BookmarkRangeMarker(kind: .start, id: Int, position: Int)` entry on `Paragraph.bookmarkMarkers`. Each parsed `<w:bookmarkEnd>` SHALL be added as a `BookmarkRangeMarker(kind: .end, id: Int, position: Int)` entry. The `position` field SHALL be assigned in source-document order during the walk.

When the source paragraph contains zero bookmark markers, `Paragraph.bookmarks` SHALL be empty and `Paragraph.bookmarkMarkers` SHALL be empty (NOT `nil`-valued or unset).

#### Scenario: Reader populates Paragraph.bookmarks for source bookmark pair

- **GIVEN** a paragraph with source XML `<w:p><w:bookmarkStart w:id="42" w:name="ref-foo"/><w:r><w:t>X</w:t></w:r><w:bookmarkEnd w:id="42"/></w:p>`
- **WHEN** `DocxReader` parses the paragraph
- **THEN** `Paragraph.bookmarks` contains exactly one `Bookmark` with `id == 42` and `name == "ref-foo"`
- **AND** `Paragraph.bookmarkMarkers` contains two entries: one `.start` at position 0 with id 42, one `.end` at position 2 with id 42
- **AND** `Paragraph.runs` contains one Run with text `"X"` at position 1

### Requirement: DocxReader parses hyperlink wrapper with typed runs and raw passthrough

`DocxReader` SHALL parse `<w:hyperlink>` elements found as direct children of `<w:p>` and populate `Paragraph.hyperlinks` with `Hyperlink` instances. For each parsed hyperlink:
- The `runs: [Run]` field SHALL be populated by recursively parsing inner `<w:r>` children using the same Run parser used for direct paragraph runs.
- The `relationshipId: String?` field SHALL be set from the source `r:id` attribute when present, otherwise `nil`.
- The `anchor: String?` field SHALL be set from the source `w:anchor` attribute when present, otherwise `nil`.
- The `tooltip: String?` field SHALL be set from the source `w:tooltip` attribute when present.
- The `history: Bool` field SHALL be set to `false` when `w:history="0"` is present, otherwise `true`.
- The `rawAttributes: [String: String]` field SHALL contain any attribute on `<w:hyperlink>` not in the recognized set (`r:id`, `w:anchor`, `w:tooltip`, `w:history`, `w:tgtFrame`, `w:docLocation`).
- The `rawChildren: [String]` field SHALL contain verbatim XML strings of any direct child of `<w:hyperlink>` whose local name is not `r` (Run).
- The `position: Int` field SHALL be assigned in source-document order during the walk.

The existing `Hyperlink.text: String` field SHALL become a computed property defined as `runs.map { $0.text }.joined()` so existing callers continue to read the concatenated text without modification.

#### Scenario: External URL hyperlink with multi-run text round-trips with anchor and runs

- **GIVEN** a paragraph with source XML `<w:p><w:hyperlink r:id="rId7" w:tooltip="external"><w:r><w:t>click </w:t></w:r><w:r><w:rPr><w:b/></w:rPr><w:t>here</w:t></w:r></w:hyperlink></w:p>`
- **WHEN** `DocxReader` parses the paragraph
- **THEN** `Paragraph.hyperlinks` contains one `Hyperlink` with `relationshipId == "rId7"`, `anchor == nil`, `tooltip == "external"`, and `runs.count == 2`
- **AND** `runs[0].text == "click "` with no bold
- **AND** `runs[1].text == "here"` with `properties.bold == true`
- **AND** the computed `text` property returns `"click here"`

### Requirement: DocxReader parses fldSimple wrapper as typed FieldSimple model

`DocxReader` SHALL parse `<w:fldSimple>` elements found as direct children of `<w:p>` and populate `Paragraph.fieldSimples: [FieldSimple]`. For each parsed field:
- The `instr: String` field SHALL be set from the source `w:instr` attribute (preserving leading/trailing whitespace exactly as found in source).
- The `runs: [Run]` field SHALL be populated by recursively parsing inner `<w:r>` children.
- The `rawAttributes: [String: String]` field SHALL contain any attribute on `<w:fldSimple>` not in the recognized set (`w:instr`, `w:fldLock`, `w:dirty`).
- The `position: Int` field SHALL be assigned in source-document order during the walk.

#### Scenario: SEQ Table caption fldSimple parses with instr and result run

- **GIVEN** a paragraph with source XML `<w:p><w:r><w:t>Table </w:t></w:r><w:fldSimple w:instr=" SEQ Table \* ARABIC "><w:r><w:t>1</w:t></w:r></w:fldSimple><w:r><w:t>: caption text</w:t></w:r></w:p>`
- **WHEN** `DocxReader` parses the paragraph
- **THEN** `Paragraph.fieldSimples` contains one `FieldSimple` with `instr == " SEQ Table \* ARABIC "` (leading/trailing space preserved)
- **AND** the FieldSimple's `runs.count == 1` with `runs[0].text == "1"`
- **AND** `Paragraph.runs` contains two entries with text `"Table "` and `": caption text"`
- **AND** the FieldSimple's position is 1, between the two paragraph runs at positions 0 and 2

### Requirement: DocxReader parses AlternateContent wrapper preserving raw XML and extracting fallback runs

`DocxReader` SHALL parse `<mc:AlternateContent>` elements found as direct children of `<w:p>` and populate `Paragraph.alternateContents: [AlternateContent]`. For each parsed block:
- The `rawXML: String` field SHALL contain the verbatim source XML of the entire `<mc:AlternateContent>` block, byte-equivalent to the source bytes.
- The `fallbackRuns: [Run]` field SHALL be populated by recursively parsing `<w:r>` children found inside the `<mc:Fallback>` sub-element. When `<mc:Fallback>` is absent or contains no `<w:r>` children, `fallbackRuns` SHALL be empty.
- The `position: Int` field SHALL be assigned in source-document order during the walk.

The Writer SHALL emit the block by writing the `rawXML` field verbatim. Modifications to `fallbackRuns` SHALL NOT be re-serialized into `rawXML` automatically; tools that wish to apply edits to the fallback content SHALL invoke a dedicated `regenerateRawXMLFromFallbackRuns()` method (out of scope for this requirement; the typed read-side surface is the v3.13.0 deliverable).

#### Scenario: Math AlternateContent parses with verbatim raw XML and fallback runs

- **GIVEN** a paragraph with source XML `<w:p><mc:AlternateContent><mc:Choice Requires="wps14"><w:drawing><!-- 1KB drawing --></w:drawing></mc:Choice><mc:Fallback><w:r><w:t>GJR-GARCH(1,1)</w:t></w:r></mc:Fallback></mc:AlternateContent></w:p>`
- **WHEN** `DocxReader` parses the paragraph
- **THEN** `Paragraph.alternateContents` contains one `AlternateContent` whose `rawXML` is the byte-identical source XML of the `<mc:AlternateContent>` block (including `<mc:Choice>` content)
- **AND** the entry's `fallbackRuns.count == 1` with `runs[0].text == "GJR-GARCH(1,1)"`
- **WHEN** `DocxWriter.write(_:to:)` emits the paragraph with no mutations
- **THEN** the output paragraph contains the original `<mc:AlternateContent>` block byte-equivalent to source

### Requirement: DocxReader parses unmodeled <w:p> children as raw-carrier markers with position

For every `<w:p>` child element local name not covered by typed parsers (`r`, `pPr`, `ins`, `del`, `moveFrom`, `moveTo`, `sdt`, `hyperlink`, `fldSimple`, `bookmarkStart`, `bookmarkEnd`) and not covered by `<mc:AlternateContent>` parsing, `DocxReader` SHALL populate one of the following raw-carrier collections on `Paragraph` based on the element local name:

- `<w:commentRangeStart>` / `<w:commentRangeEnd>` → `Paragraph.commentRangeMarkers: [CommentRangeMarker]`
- `<w:permStart>` / `<w:permEnd>` → `Paragraph.permissionRangeMarkers: [PermissionRangeMarker]`
- `<w:proofErr>` → `Paragraph.proofErrorMarkers: [ProofErrorMarker]`
- `<w:smartTag>` → `Paragraph.smartTags: [SmartTagBlock]`
- `<w:customXml>` → `Paragraph.customXmlBlocks: [CustomXmlBlock]`
- `<w:dir>` / `<w:bdo>` → `Paragraph.bidiOverrides: [BidiOverrideBlock]`

Each raw-carrier instance SHALL hold the verbatim source XML of the element in a `rawXML: String` field plus `position: Int` for ordering.

When the Reader encounters a `<w:p>` child whose local name does not match any typed parser, any raw-carrier registered above, or any inherited Run-children parser, the Reader SHALL log a warning to standard error including the element local name, source line number, and parent paragraph position. The element's verbatim XML SHALL be added to a fallback `Paragraph.unrecognizedChildren: [(name: String, xml: String, position: Int)]` collection so it survives the round-trip even if the team has not yet added a dedicated raw-carrier type for it.

#### Scenario: Comment range markers preserved across no-op round-trip

- **GIVEN** a paragraph with source XML `<w:p><w:commentRangeStart w:id="3"/><w:r><w:t>commented text</w:t></w:r><w:commentRangeEnd w:id="3"/></w:p>`
- **WHEN** `DocxReader` parses the paragraph
- **THEN** `Paragraph.commentRangeMarkers` contains two entries: one `.start` at position 0 with id 3, one `.end` at position 2 with id 3
- **WHEN** `DocxWriter.write(_:to:)` emits the paragraph with no mutations
- **THEN** the output paragraph contains both `<w:commentRangeStart w:id="3"/>` and `<w:commentRangeEnd w:id="3"/>` at the original source positions

#### Scenario: Unrecognized child element warning and fallback preservation

- **GIVEN** a paragraph containing a hypothetical `<w:experimentalElement w:foo="bar"/>` child that no registered parser recognizes
- **WHEN** `DocxReader` parses the paragraph
- **THEN** the Reader logs a warning to standard error containing `experimentalElement` and the source position
- **AND** `Paragraph.unrecognizedChildren` contains one entry with `name == "experimentalElement"` and verbatim `xml` and `position` matching the source order
- **WHEN** `DocxWriter.write(_:to:)` emits the paragraph with no mutations
- **THEN** the output paragraph contains the verbatim `<w:experimentalElement>` block at the original position
