# ooxml-reader-tree-loading Specification

> **Related**: this capability is the production-code half of `word-aligned-state-sync` Phase 1 task 2.6 — it provides the bridge between the lossless `XmlNode` tree IO landed in v0.30.0 and the typed-view tree-projection contracts shipped in v0.31.0 (`ooxml-paragraph-tree-projection`) and v0.31.1 (`ooxml-typed-views-tree-projection`). Reader-side wiring of header / footer / footnote / endnote / comment typed values to their xmlNodes is deferred to follow-up `header-footer-tree-wiring-impl`. Per-parser unknown-child preservation (task 2.7 of `word-aligned-state-sync`) is deferred to `reader-unknown-child-coverage-impl`. Revision tree round-trip (tasks 2.8-2.10) is deferred to `reader-revision-tree-impl`.

## Purpose

Defines the contract for `DocxReader` populating `WordDocument.xmlTrees` (a public read-only `[String: XmlTree]` dictionary keyed by OOXML part path) and the opt-in `wireTreeBackedViews: true` mode that sets `xmlNode` on body-level `Paragraph` and `Table` typed values from the loaded `<w:body>` direct children. Without this capability, the typed views shipped in v0.31.0 / v0.31.1 (`Type(xmlNode:)` constructors, `id` accessors, mode-aware tree-walking computed properties) are unreachable from Reader-produced documents — Reader call sites construct via legacy constructors only, leaving `xmlNode == nil` everywhere. This capability is what makes Phase 2 (Operation log persistence, target ooxml-swift v0.32.0) able to address Reader-produced documents by `ElementID`.

This capability covers:

1. **xmlTrees population** — `DocxReader.read(from:)` SHALL populate `document.xmlTrees[partPath]` for every primary OOXML part it loads (`word/document.xml`, `word/styles.xml`, `word/numbering.xml`, `word/settings.xml`, `word/comments.xml`, `word/footnotes.xml`, `word/endnotes.xml`, every `word/header*.xml`, every `word/footer*.xml`); relationship parts (`*.rels`, `[Content_Types].xml`) are intentionally out of scope
2. **partTree accessor** — `WordDocument.partTree(at: String) -> XmlTree?` returns `xmlTrees[partPath]` and `nil` for unknown paths
3. **Equatable preservation** — `WordDocument.Equatable` ignores `xmlTrees` (the existing manual `==` is inclusion-list semantics so `xmlTrees` is naturally excluded by not appearing in the field list, matching the existing exclusion of `preservedArchive` and `modifiedParts`); two reads of the same source docx compare equal even with distinct `XmlTree` instances
4. **Default-mode behavior preservation** — `DocxReader.read(from:)` (no `wireTreeBackedViews:` argument) keeps every Reader-produced typed value detached, byte-equivalent to ooxml-swift v0.31.1; che-word-mcp's 297-test regression gate continues to validate this
5. **Opt-in wireTreeBackedViews mode** — `DocxReader.read(from:wireTreeBackedViews: true)` walks the `<w:body>` direct children of `xmlTrees["word/document.xml"]` and position-matches against `document.body.children`, setting `Paragraph.xmlNode` / `Table.xmlNode` on each body-level typed value; nested structure (cells, runs) auto-propagates via the v0.31.1 mode-aware computed accessors at access time without additional Reader-side wiring
6. **Defensive position matcher** — when `<w:body>` direct children include element kinds the typed parser does not produce as `body.children` entries (e.g., `<w:sectPr>`, unexpected revision wrappers), the matcher SHALL skip those XML children without advancing the cursor so subsequent `<w:p>` / `<w:tbl>` still match correctly

The capability does not own the tree itself (that is the v0.30.0 lossless tree IO capability), the typed views (those are `ooxml-paragraph-tree-projection` and `ooxml-typed-views-tree-projection`), the operation log (Phase 2 of `word-aligned-state-sync`), or the legacy `XMLDocument`-based Reader path (which is still used in parallel and is removed in Phase 5 / v1.0.0). It is the narrow contract for "Reader builds the tree alongside the typed model and optionally wires body-level typed views to that tree."

## Requirements

### Requirement: WordDocument carries XmlTree per loaded OOXML part

`WordDocument` SHALL expose a public read-only stored property `xmlTrees: [String: XmlTree]` keyed by OOXML part path (e.g., `"word/document.xml"`, `"word/styles.xml"`). The dictionary SHALL be internally settable so `DocxReader` populates it; external mutation SHALL be prevented at the type system level.

`WordDocument` SHALL expose a public convenience accessor `partTree(at: String) -> XmlTree?` returning `xmlTrees[partPath]`.

`WordDocument`'s `Equatable` conformance SHALL exclude the `xmlTrees` field — two `WordDocument` values with byte-identical content but distinct `XmlTree` class instances SHALL compare equal.

#### Scenario: xmlTrees is publicly readable

- **GIVEN** a `WordDocument` returned by any `DocxReader.read(from:)` call
- **WHEN** `document.xmlTrees` is accessed
- **THEN** the returned dictionary SHALL be readable from outside the `OOXMLSwift` module

#### Scenario: xmlTrees is not externally mutable

- **GIVEN** a `WordDocument` returned by any `DocxReader.read(from:)` call
- **WHEN** external code attempts to assign `document.xmlTrees = [:]`
- **THEN** the compile SHALL fail (the property has internal-set visibility)

#### Scenario: partTree returns nil for unknown part path

- **GIVEN** a `WordDocument` returned by `DocxReader.read(from:)` on any docx
- **WHEN** `document.partTree(at: "word/this-part-does-not-exist.xml")` is called
- **THEN** the returned value SHALL be `nil`

#### Scenario: Equatable ignores xmlTrees

- **GIVEN** two `WordDocument` values `doc1` and `doc2` produced by reading the same source docx file twice
- **WHEN** they are compared with `==`
- **THEN** the comparison SHALL return `true` even though `doc1.xmlTrees["word/document.xml"]` and `doc2.xmlTrees["word/document.xml"]` are distinct `XmlTree` instances


<!-- @trace
source: reader-tree-loading-impl
updated: 2026-05-07
code:
  - .remember/logs/autonomous/save-071551.log
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-095047.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-093255.log
  - .remember/logs/autonomous/save-144433.log
  - .remember/logs/autonomous/save-092853.log
  - .remember/logs/autonomous/save-144550.log
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-050705.log
  - .remember/logs/autonomous/save-093825.log
  - .remember/logs/autonomous/save-143020.log
  - .remember/logs/autonomous/save-143628.log
  - .remember/logs/autonomous/save-144618.log
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-084624.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-090944.log
  - .remember/logs/autonomous/save-093013.log
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-095142.log
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-143856.log
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-144132.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-095546.log
  - .remember/logs/autonomous/save-093030.log
  - .remember/logs/autonomous/save-053605.log
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-144003.log
  - .remember/logs/autonomous/save-094627.log
  - .remember/logs/autonomous/save-130250.log
  - .remember/logs/autonomous/save-132950.log
  - .remember/logs/autonomous/save-125453.log
  - .remember/logs/autonomous/save-050704.log
  - .remember/logs/autonomous/save-053409.log
  - .remember/logs/autonomous/save-095118.log
  - .remember/logs/autonomous/save-093149.log
  - .remember/logs/autonomous/save-060210.log
  - .remember/logs/autonomous/save-095539.log
  - .remember/logs/autonomous/save-095621.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-143318.log
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-093300.log
  - .remember/logs/autonomous/save-093340.log
  - .remember/logs/autonomous/save-070717.log
  - .remember/logs/autonomous/save-091107.log
  - .remember/logs/autonomous/save-143700.log
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-093138.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-093007.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-090656.log
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-093039.log
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-125949.log
  - .remember/logs/autonomous/save-130300.log
  - .remember/logs/autonomous/save-131902.log
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-143733.log
  - .remember/logs/autonomous/save-094041.log
-->

---
### Requirement: DocxReader populates xmlTrees during read

`DocxReader.read(from: URL)` SHALL populate `document.xmlTrees[partPath]` by calling `XmlTreeReader.parse(_:)` on the bytes of every primary OOXML part it loads. Primary parts in scope:

- `word/document.xml`
- `word/styles.xml` (when present)
- `word/numbering.xml` (when present)
- `word/settings.xml` (when present)
- `word/comments.xml` (when present)
- `word/footnotes.xml` (when present)
- `word/endnotes.xml` (when present)
- Each `word/header*.xml` (one entry per header part)
- Each `word/footer*.xml` (one entry per footer part)
- Each `word/customXml/*.xml` (one entry per custom XML part)

Relationship and metadata parts (`[Content_Types].xml`, any `_rels/*.rels` part) SHALL NOT be loaded into `xmlTrees` — they are out of scope for typed-view wiring and remain handled by the existing `RelationshipsCollection` parser.

If `XmlTreeReader.parse(_:)` throws on any part, the throw SHALL propagate from `DocxReader.read(from:)` — Reader SHALL NOT silently swallow tree-parse failures.

#### Scenario: xmlTrees populated for document.xml

- **GIVEN** a docx file containing at minimum a `word/document.xml` part
- **WHEN** `DocxReader.read(from: docxURL)` is called
- **THEN** the returned `document.xmlTrees["word/document.xml"]` SHALL be a non-nil `XmlTree`
- **AND** the tree's `root` SHALL be an `XmlNode` whose `localName == "document"`

#### Scenario: xmlTrees populated for every primary part present in the source

- **GIVEN** a docx file containing `word/document.xml`, `word/styles.xml`, `word/numbering.xml`, `word/settings.xml`, and at least one `word/header*.xml`
- **WHEN** `DocxReader.read(from: docxURL)` is called
- **THEN** `document.xmlTrees` SHALL contain non-nil entries for every primary part listed above
- **AND** the `<header*>` part path key SHALL match the actual filename (e.g., `"word/header1.xml"` if the file is `header1.xml`)

#### Scenario: Optional parts that are absent are not in xmlTrees

- **GIVEN** a docx file with no `word/footnotes.xml` part
- **WHEN** `DocxReader.read(from: docxURL)` is called
- **THEN** `document.xmlTrees["word/footnotes.xml"]` SHALL be `nil`
- **AND** `document.partTree(at: "word/footnotes.xml")` SHALL return `nil`


<!-- @trace
source: reader-tree-loading-impl
updated: 2026-05-07
code:
  - .remember/logs/autonomous/save-071551.log
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-095047.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-093255.log
  - .remember/logs/autonomous/save-144433.log
  - .remember/logs/autonomous/save-092853.log
  - .remember/logs/autonomous/save-144550.log
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-050705.log
  - .remember/logs/autonomous/save-093825.log
  - .remember/logs/autonomous/save-143020.log
  - .remember/logs/autonomous/save-143628.log
  - .remember/logs/autonomous/save-144618.log
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-084624.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-090944.log
  - .remember/logs/autonomous/save-093013.log
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-095142.log
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-143856.log
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-144132.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-095546.log
  - .remember/logs/autonomous/save-093030.log
  - .remember/logs/autonomous/save-053605.log
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-144003.log
  - .remember/logs/autonomous/save-094627.log
  - .remember/logs/autonomous/save-130250.log
  - .remember/logs/autonomous/save-132950.log
  - .remember/logs/autonomous/save-125453.log
  - .remember/logs/autonomous/save-050704.log
  - .remember/logs/autonomous/save-053409.log
  - .remember/logs/autonomous/save-095118.log
  - .remember/logs/autonomous/save-093149.log
  - .remember/logs/autonomous/save-060210.log
  - .remember/logs/autonomous/save-095539.log
  - .remember/logs/autonomous/save-095621.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-143318.log
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-093300.log
  - .remember/logs/autonomous/save-093340.log
  - .remember/logs/autonomous/save-070717.log
  - .remember/logs/autonomous/save-091107.log
  - .remember/logs/autonomous/save-143700.log
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-093138.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-093007.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-090656.log
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-093039.log
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-125949.log
  - .remember/logs/autonomous/save-130300.log
  - .remember/logs/autonomous/save-131902.log
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-143733.log
  - .remember/logs/autonomous/save-094041.log
-->

---
### Requirement: Default Reader behavior preserves v0.31.1 detached typed-view semantics

`DocxReader.read(from: URL)` (no `wireTreeBackedViews` parameter, equivalent to `wireTreeBackedViews: false`) SHALL leave every Reader-produced typed value (`Paragraph`, `Run`, `Table`, `TableRow`, `TableCell`, `SectionProperties`) in **detached mode** — i.e., `xmlNode == nil` on every typed value reachable from `document.body.children`, headers, footers, comments, footnotes, endnotes.

`document.xmlTrees` SHALL still be populated per the previous requirement, but typed values SHALL NOT be wired to it.

This requirement preserves byte-equivalent observable behavior for downstream consumers (che-word-mcp's 297-test regression gate). External callers who do not pass `wireTreeBackedViews: true` SHALL see no behavior change versus ooxml-swift v0.31.1.

#### Scenario: default-mode body Paragraph is detached

- **GIVEN** a docx file containing at least one body-level paragraph
- **WHEN** `DocxReader.read(from: docxURL)` is called WITHOUT `wireTreeBackedViews:`
- **THEN** for every `BodyChild.paragraph(p)` in `document.body.children`, `p.xmlNode` SHALL be `nil`
- **AND** `p.id` SHALL be `nil`

#### Scenario: default-mode body Table is detached

- **GIVEN** a docx file containing at least one body-level table
- **WHEN** `DocxReader.read(from: docxURL)` is called WITHOUT `wireTreeBackedViews:`
- **THEN** for every `BodyChild.table(t)` in `document.body.children`, `t.xmlNode` SHALL be `nil`
- **AND** `t.id` SHALL be `nil`


<!-- @trace
source: reader-tree-loading-impl
updated: 2026-05-07
code:
  - .remember/logs/autonomous/save-071551.log
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-095047.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-093255.log
  - .remember/logs/autonomous/save-144433.log
  - .remember/logs/autonomous/save-092853.log
  - .remember/logs/autonomous/save-144550.log
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-050705.log
  - .remember/logs/autonomous/save-093825.log
  - .remember/logs/autonomous/save-143020.log
  - .remember/logs/autonomous/save-143628.log
  - .remember/logs/autonomous/save-144618.log
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-084624.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-090944.log
  - .remember/logs/autonomous/save-093013.log
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-095142.log
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-143856.log
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-144132.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-095546.log
  - .remember/logs/autonomous/save-093030.log
  - .remember/logs/autonomous/save-053605.log
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-144003.log
  - .remember/logs/autonomous/save-094627.log
  - .remember/logs/autonomous/save-130250.log
  - .remember/logs/autonomous/save-132950.log
  - .remember/logs/autonomous/save-125453.log
  - .remember/logs/autonomous/save-050704.log
  - .remember/logs/autonomous/save-053409.log
  - .remember/logs/autonomous/save-095118.log
  - .remember/logs/autonomous/save-093149.log
  - .remember/logs/autonomous/save-060210.log
  - .remember/logs/autonomous/save-095539.log
  - .remember/logs/autonomous/save-095621.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-143318.log
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-093300.log
  - .remember/logs/autonomous/save-093340.log
  - .remember/logs/autonomous/save-070717.log
  - .remember/logs/autonomous/save-091107.log
  - .remember/logs/autonomous/save-143700.log
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-093138.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-093007.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-090656.log
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-093039.log
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-125949.log
  - .remember/logs/autonomous/save-130300.log
  - .remember/logs/autonomous/save-131902.log
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-143733.log
  - .remember/logs/autonomous/save-094041.log
-->

---
### Requirement: wireTreeBackedViews opt-in mode wires body-level Paragraph and Table

`DocxReader.read(from: URL, wireTreeBackedViews: true)` SHALL, after constructing the typed model, walk the `<w:body>` direct children inside `xmlTrees["word/document.xml"]` and position-match against `document.body.children`. For each match:

- A `<w:p>` direct child of `<w:body>` matched with a `BodyChild.paragraph(var p)` entry SHALL set `p.xmlNode` to that `<w:p>` `XmlNode` and write the updated paragraph back into `document.body.children`.
- A `<w:tbl>` direct child of `<w:body>` matched with a `BodyChild.table(var t)` entry SHALL set `t.xmlNode` to that `<w:tbl>` `XmlNode` and write the updated table back.
- A `<w:sectPr>` direct child of `<w:body>` SHALL NOT be wired to any `body.children` entry (section-level metadata; out of scope for body wiring).
- Any other `<w:body>` direct child kind SHALL NOT crash; the cursor SHALL skip the corresponding `body.children` entry defensively.

Nested typed views (cell paragraphs, run-internal anything) SHALL NOT be wired by Reader. They SHALL be reached through the v0.31.1 mode-aware computed accessors (`TableCell.paragraphs` returns `[Paragraph(xmlNode:)]` per `<w:p>` child of the wrapped `<w:tc>`, etc.) at access time.

The opt-in wiring SHALL be additive — typed values still carry their legacy stored fields (text, properties, etc.) populated by the existing parser, but in tree-backed mode the mode-aware computed accessors shadow those legacy fields with tree-walked values.

#### Scenario: wireTreeBackedViews sets xmlNode on body Paragraphs

- **GIVEN** a docx file containing at least one body-level paragraph
- **WHEN** `DocxReader.read(from: docxURL, wireTreeBackedViews: true)` is called
- **THEN** for every `BodyChild.paragraph(p)` in `document.body.children`, `p.xmlNode` SHALL be a non-nil `XmlNode` whose `localName == "p"`
- **AND** that `XmlNode` SHALL be reachable from `document.xmlTrees["word/document.xml"].root` by walking children

#### Scenario: wireTreeBackedViews sets xmlNode on body Tables

- **GIVEN** a docx file containing at least one body-level table
- **WHEN** `DocxReader.read(from: docxURL, wireTreeBackedViews: true)` is called
- **THEN** for every `BodyChild.table(t)` in `document.body.children`, `t.xmlNode` SHALL be a non-nil `XmlNode` whose `localName == "tbl"`

#### Scenario: wireTreeBackedViews on cell-internal paragraph propagates via computed accessor

- **GIVEN** a docx file containing a body-level table with at least one cell containing at least one paragraph
- **WHEN** `DocxReader.read(from: docxURL, wireTreeBackedViews: true)` is called
- **AND** the body Table is accessed via `document.body.children[i].table?` (so it has `xmlNode != nil`)
- **AND** `table.rows[0].cells[0].paragraphs[0]` is accessed
- **THEN** the returned cell-internal Paragraph SHALL have `xmlNode != nil` (auto-propagated via the v0.31.1 `TableCell.paragraphs` mode-aware computed accessor)

#### Scenario: wireTreeBackedViews handles unexpected body child kinds without crashing

- **GIVEN** a docx file whose `<w:body>` contains a child element kind that the typed parser does not produce as a `body.children` entry (e.g., a stray `<w:proofErr>` or an unrecognized OOXML extension element)
- **WHEN** `DocxReader.read(from: docxURL, wireTreeBackedViews: true)` is called
- **THEN** the call SHALL NOT crash
- **AND** the body-level Paragraphs and Tables that DO have matching `<w:p>` / `<w:tbl>` `<w:body>` children SHALL still get their `xmlNode` set correctly


<!-- @trace
source: reader-tree-loading-impl
updated: 2026-05-07
code:
  - .remember/logs/autonomous/save-071551.log
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-095047.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-093255.log
  - .remember/logs/autonomous/save-144433.log
  - .remember/logs/autonomous/save-092853.log
  - .remember/logs/autonomous/save-144550.log
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-050705.log
  - .remember/logs/autonomous/save-093825.log
  - .remember/logs/autonomous/save-143020.log
  - .remember/logs/autonomous/save-143628.log
  - .remember/logs/autonomous/save-144618.log
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-084624.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-090944.log
  - .remember/logs/autonomous/save-093013.log
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-095142.log
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-143856.log
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-144132.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-095546.log
  - .remember/logs/autonomous/save-093030.log
  - .remember/logs/autonomous/save-053605.log
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-144003.log
  - .remember/logs/autonomous/save-094627.log
  - .remember/logs/autonomous/save-130250.log
  - .remember/logs/autonomous/save-132950.log
  - .remember/logs/autonomous/save-125453.log
  - .remember/logs/autonomous/save-050704.log
  - .remember/logs/autonomous/save-053409.log
  - .remember/logs/autonomous/save-095118.log
  - .remember/logs/autonomous/save-093149.log
  - .remember/logs/autonomous/save-060210.log
  - .remember/logs/autonomous/save-095539.log
  - .remember/logs/autonomous/save-095621.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-143318.log
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-093300.log
  - .remember/logs/autonomous/save-093340.log
  - .remember/logs/autonomous/save-070717.log
  - .remember/logs/autonomous/save-091107.log
  - .remember/logs/autonomous/save-143700.log
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-093138.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-093007.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-090656.log
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-093039.log
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-125949.log
  - .remember/logs/autonomous/save-130300.log
  - .remember/logs/autonomous/save-131902.log
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-143733.log
  - .remember/logs/autonomous/save-094041.log
-->

---
### Requirement: che-word-mcp regression gate stays green against the wired Reader

The full che-word-mcp test suite (297 production tests as of 2026-05-07) SHALL pass against an ooxml-swift containing this change after `Package.resolved` is bumped to v0.31.2. Zero test SHALL fail. Zero test SHALL exhibit observable output diff versus the pre-change baseline.

Because che-word-mcp call sites do NOT pass `wireTreeBackedViews:`, they hit the default-mode path; behavior MUST remain byte-equivalent to v0.31.1.

#### Scenario: che-word-mcp 297-test suite passes against v0.31.2

- **GIVEN** che-word-mcp's 297 production tests pinned to ooxml-swift v0.31.2 (this change)
- **WHEN** `swift test` runs in `mcp/che-word-mcp/`
- **THEN** the result SHALL be: 297 tests / 9 skipped / 0 failures
- **AND** zero observable output diff versus the v0.31.1 baseline


<!-- @trace
source: reader-tree-loading-impl
updated: 2026-05-07
code:
  - .remember/logs/autonomous/save-071551.log
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-095047.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-093255.log
  - .remember/logs/autonomous/save-144433.log
  - .remember/logs/autonomous/save-092853.log
  - .remember/logs/autonomous/save-144550.log
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-050705.log
  - .remember/logs/autonomous/save-093825.log
  - .remember/logs/autonomous/save-143020.log
  - .remember/logs/autonomous/save-143628.log
  - .remember/logs/autonomous/save-144618.log
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-084624.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-090944.log
  - .remember/logs/autonomous/save-093013.log
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-095142.log
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-143856.log
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-144132.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-095546.log
  - .remember/logs/autonomous/save-093030.log
  - .remember/logs/autonomous/save-053605.log
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-144003.log
  - .remember/logs/autonomous/save-094627.log
  - .remember/logs/autonomous/save-130250.log
  - .remember/logs/autonomous/save-132950.log
  - .remember/logs/autonomous/save-125453.log
  - .remember/logs/autonomous/save-050704.log
  - .remember/logs/autonomous/save-053409.log
  - .remember/logs/autonomous/save-095118.log
  - .remember/logs/autonomous/save-093149.log
  - .remember/logs/autonomous/save-060210.log
  - .remember/logs/autonomous/save-095539.log
  - .remember/logs/autonomous/save-095621.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-143318.log
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-093300.log
  - .remember/logs/autonomous/save-093340.log
  - .remember/logs/autonomous/save-070717.log
  - .remember/logs/autonomous/save-091107.log
  - .remember/logs/autonomous/save-143700.log
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-093138.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-093007.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-090656.log
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-093039.log
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-125949.log
  - .remember/logs/autonomous/save-130300.log
  - .remember/logs/autonomous/save-131902.log
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-143733.log
  - .remember/logs/autonomous/save-094041.log
-->

---
### Requirement: ReaderTreeLoadingTests pinned coverage

A new test file `Tests/OOXMLSwiftTests/ReaderTreeLoadingTests.swift` SHALL be added with at least 6 XCTestCase methods pinning the requirements above. The tests SHALL use the existing golden corpus fixtures (`multi-section-thesis.docx`, `vml-rich.docx`, `cjk-settings.docx`, `comment-anchored.docx` from `Tests/OOXMLSwiftTests/Fixtures/`) to avoid synthesizing new docx files.

The tests SHALL pass GREEN against the implementation in the same release (no `#if false` gate phase).

#### Scenario: ReaderTreeLoadingTests passes GREEN

- **WHEN** `swift test --filter ReaderTreeLoadingTests` runs against this change
- **THEN** every test method SHALL pass
- **AND** the test runner SHALL report at least 6 passing tests with 0 failures

<!-- @trace
source: reader-tree-loading-impl
updated: 2026-05-07
code:
  - .remember/logs/autonomous/save-071551.log
  - .remember/logs/autonomous/save-092944.log
  - .remember/logs/autonomous/save-095047.log
  - .remember/logs/autonomous/save-130140.log
  - .remember/logs/autonomous/save-095040.log
  - .remember/logs/autonomous/save-091219.log
  - .remember/logs/autonomous/save-093255.log
  - .remember/logs/autonomous/save-144433.log
  - .remember/logs/autonomous/save-092853.log
  - .remember/logs/autonomous/save-144550.log
  - .remember/logs/autonomous/save-094953.log
  - .remember/logs/autonomous/save-050705.log
  - .remember/logs/autonomous/save-093825.log
  - .remember/logs/autonomous/save-143020.log
  - .remember/logs/autonomous/save-143628.log
  - .remember/logs/autonomous/save-144618.log
  - .remember/logs/autonomous/save-092901.log
  - .remember/logs/autonomous/save-084624.log
  - mcp/che-word-mcp
  - .remember/logs/autonomous/save-092843.log
  - .remember/logs/autonomous/save-071130.log
  - .remember/logs/autonomous/save-090944.log
  - .remember/logs/autonomous/save-093013.log
  - .remember/logs/autonomous/save-093124.log
  - .remember/logs/autonomous/save-095142.log
  - .remember/logs/autonomous/save-095147.log
  - .remember/logs/autonomous/save-092804.log
  - .remember/logs/autonomous/save-143856.log
  - .remember/logs/autonomous/save-144334.log
  - .remember/logs/autonomous/save-144132.log
  - .remember/logs/autonomous/save-095049.log
  - .remember/logs/autonomous/save-095059.log
  - .remember/logs/autonomous/save-095546.log
  - .remember/logs/autonomous/save-093030.log
  - .remember/logs/autonomous/save-053605.log
  - .remember/logs/autonomous/save-093223.log
  - .remember/logs/autonomous/save-144003.log
  - .remember/logs/autonomous/save-094627.log
  - .remember/logs/autonomous/save-130250.log
  - .remember/logs/autonomous/save-132950.log
  - .remember/logs/autonomous/save-125453.log
  - .remember/logs/autonomous/save-050704.log
  - .remember/logs/autonomous/save-053409.log
  - .remember/logs/autonomous/save-095118.log
  - .remember/logs/autonomous/save-093149.log
  - .remember/logs/autonomous/save-060210.log
  - .remember/logs/autonomous/save-095539.log
  - .remember/logs/autonomous/save-095621.log
  - .remember/logs/autonomous/save-143013.log
  - .remember/logs/autonomous/save-144448.log
  - .remember/logs/autonomous/save-125924.log
  - .remember/logs/autonomous/save-143318.log
  - .remember/logs/autonomous/save-092636.log
  - .remember/logs/autonomous/save-092657.log
  - .remember/logs/autonomous/save-093312.log
  - .remember/logs/autonomous/save-144827.log
  - .remember/logs/autonomous/save-093300.log
  - .remember/logs/autonomous/save-093340.log
  - .remember/logs/autonomous/save-070717.log
  - .remember/logs/autonomous/save-091107.log
  - .remember/logs/autonomous/save-143700.log
  - .remember/logs/autonomous/save-071148.log
  - .remember/logs/autonomous/save-092931.log
  - .remember/logs/autonomous/save-094757.log
  - .remember/logs/autonomous/save-091137.log
  - .remember/logs/autonomous/save-094804.log
  - .remember/logs/autonomous/save-130011.log
  - .remember/logs/autonomous/save-093138.log
  - .remember/logs/autonomous/save-092705.log
  - .remember/logs/autonomous/save-093007.log
  - .remember/logs/autonomous/save-095037.log
  - .remember/logs/autonomous/save-090656.log
  - .remember/logs/autonomous/save-092823.log
  - .remember/logs/autonomous/save-093039.log
  - .remember/logs/autonomous/save-125131.log
  - .remember/logs/autonomous/save-125949.log
  - .remember/logs/autonomous/save-130300.log
  - .remember/logs/autonomous/save-131902.log
  - .remember/logs/autonomous/save-143140.log
  - .remember/logs/autonomous/save-144617.log
  - .remember/logs/autonomous/save-092917.log
  - .remember/logs/autonomous/save-143733.log
  - .remember/logs/autonomous/save-094041.log
-->