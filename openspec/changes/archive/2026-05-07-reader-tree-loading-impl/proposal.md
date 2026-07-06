## Why

`paragraph-tree-projection-impl` (v0.31.0) and `sibling-types-tree-projection-impl` (v0.31.1) shipped tree-backed constructors `Type(xmlNode:)` for `Paragraph`, `Run`, `Table`, `TableRow`, `TableCell`, `SectionProperties` — but **`DocxReader` never produces tree-backed values**. Reader call sites construct typed values via the legacy constructors (`Paragraph(runs:, properties:)`, etc.), which leave `xmlNode == nil`. As a result, the entire 297-test che-word-mcp regression gate exercises only the detached path; tree-backed mode is opt-in for downstream code that explicitly constructs tree-backed values (which nothing in the macdoc workspace currently does).

For Phase 2 (Operation log persistence, target ooxml-swift v0.32.0) to address Reader-produced documents by `ElementID`, the typed views populated by `DocxReader.read(from:)` MUST carry their corresponding `XmlNode`. That requires two new pieces:

1. **XmlTrees stored per part** — `WordDocument` needs to own the lossless `XmlTree` for every OOXML part loaded by Reader (currently Reader only stores the typed model + the unzipped tempDir; the parsed XmlNode tree is never built in production code paths — only in tests).
2. **Opt-in wiring of typed views to their xmlNode** — given the trees, walk `<w:body>` direct children, position-match against `Document.body.children`, and set `Paragraph.xmlNode` / `Table.xmlNode` for each.

This change implements the production-code half of `word-aligned-state-sync` Phase 1 task 2.6 ("Update DocxReader to satisfy the **all parts preserved via XmlNode tree alongside typed views** requirement: load every part listed in `[Content_Types].xml` into the tree"). Both pieces above ship in this change.

The change is **strictly additive**: `DocxReader.read(from:)` keeps the same signature with a new defaulted parameter (`wireTreeBackedViews: Bool = false`), so existing call sites compile unchanged. Default Reader behavior remains exactly what it was in v0.31.1 — every typed view is detached, `xmlTrees` is populated but consumers can ignore it. che-word-mcp's 297-test regression gate catches any default-mode behavioral drift.

## What Changes

- **NEW**: `WordDocument.xmlTrees: [String: XmlTree]` — a public read-only dictionary keyed by OOXML part path (e.g., `"word/document.xml"`, `"word/settings.xml"`, `"word/styles.xml"`). Internally settable so `DocxReader` populates it.
- **NEW**: `WordDocument.partTree(at: String) -> XmlTree?` — convenience accessor that reads from `xmlTrees`.
- **MODIFIED**: `DocxReader.read(from: URL, wireTreeBackedViews: Bool = false) -> WordDocument` — default parameter `wireTreeBackedViews: Bool = false`. When the parameter is `false` (default), Reader behavior is byte-equivalent to v0.31.1 EXCEPT that `xmlTrees` is now populated for every part Reader loads (additive — existing callers can ignore it).
- **NEW**: When `wireTreeBackedViews: true` is passed, after the typed model is constructed, Reader walks the `<w:body>` direct children of `xmlTrees["word/document.xml"].root` and position-matches each `<w:p>` / `<w:tbl>` against the corresponding entry in `document.body.children`, then sets `Paragraph.xmlNode` / `Table.xmlNode` on each matched typed view. This wires Reader-produced body-level Paragraphs and Tables to their underlying XmlNode so Phase 2's op log can address them by `ElementID`.
- **NEW**: Test file `Tests/OOXMLSwiftTests/ReaderTreeLoadingTests.swift` — at least 6 tests covering: xmlTrees populated for every loaded part, partTree returns nil for unknown paths, wireTreeBackedViews=false leaves all typed views detached (behavior preservation), wireTreeBackedViews=true sets xmlNode on body-level Paragraphs, wireTreeBackedViews=true sets xmlNode on body-level Tables, position-matching is robust against documents with mixed body children.
- **NON-BREAKING**: All existing `DocxReader.read(from:)` callers compile unchanged because `wireTreeBackedViews` is defaulted. che-word-mcp's 297 tests stay GREEN.

## Non-Goals

- **Wiring nested typed views (cell-internal Paragraphs, run-internal anything)** — out of scope. When `wireTreeBackedViews: true` sets `Table.xmlNode`, the v0.31.1 `TableCell.paragraphs` getter (mode-aware computed) automatically returns tree-backed Paragraphs by walking the wrapped `<w:tbl>` → `<w:tr>` → `<w:tc>` → `<w:p>` chain. No additional Reader-side wiring is needed for nested structure; it propagates from the body-level wiring point automatically.
- **Wiring header / footer / footnote / endnote / comment typed views** — out of scope. Their typed parsers operate on separate parts (`word/header1.xml`, etc.) that are loaded into `xmlTrees` but not wired in this change. A follow-up `header-footer-tree-wiring-impl` will add the per-container wiring once the body case is shaken out.
- **Replacing the legacy parser path with tree-walking** — out of scope. Reader keeps the existing `XMLDocument` (libxml2-backed) parser to populate detached typed values; the new XmlTree is built **alongside**. Phase 5 of `word-aligned-state-sync` (target v1.0.0) removes the legacy parser path; Phase 1 keeps both for back-compat.
- **Op-log routing on Reader-produced typed views** — Phase 2 of `word-aligned-state-sync` (separate change, target v0.32.0). This change provides the prerequisite (xmlNode is set on Reader-produced typed views when opt-in) but does not wire setters to the op log.
- **Changing `XmlTreeReader` to support streaming / partial parses** — out of scope. The existing `XmlTreeReader.parse(_ data: Data) -> XmlTree` API is used as-is.

## Capabilities

### New Capabilities

- `ooxml-reader-tree-loading`: Defines the contract for DocxReader populating WordDocument xmlTrees (one lossless XmlTree per OOXML part loaded) and the opt-in wireTreeBackedViews mode that sets xmlNode on body-level Paragraph and Table typed values. Sibling to the lossless XmlNode tree IO capability landed in v0.30.0 (which owns the XmlNode / XmlTree data types and the parse/serialize primitives) and to the typed-view tree-projection capabilities ooxml-paragraph-tree-projection / ooxml-typed-views-tree-projection (which own the typed-view contracts being wired here).

### Modified Capabilities

(none — the v0.30.0 lossless tree IO capability is consumed unchanged; no public API of the XmlNode / XmlTree data types changes.)

## Impact

- Affected specs:
  - New: `openspec/specs/ooxml-reader-tree-loading/spec.md`
- Affected code:
  - Modified: `packages/ooxml-swift/Sources/OOXMLSwift/Models/Document.swift` (gain `xmlTrees: [String: XmlTree]` public stored property and `partTree(at:)` accessor)
  - Modified: `packages/ooxml-swift/Sources/OOXMLSwift/IO/DocxReader.swift` (read entry point gains `wireTreeBackedViews: Bool = false` parameter; per-part loads also call `XmlTreeReader.parse` and write into `document.xmlTrees`; opt-in body-level wiring path added at end of read)
  - New: `packages/ooxml-swift/Tests/OOXMLSwiftTests/ReaderTreeLoadingTests.swift` (test file pinning xmlTrees population and opt-in wiring behavior)
- Affected dependencies:
  - che-word-mcp (downstream lib consumer): no source change required; its 297 production tests are the regression gate. They MUST stay GREEN through this change after Package.resolved bump to v0.31.2.
  - macdoc CLI: no source change required.
- Affected releases:
  - ooxml-swift v0.31.2 (additive minor patch since v0.31.1 already shipped tree-backed constructors).
- Affected sibling Spectra changes:
  - `word-aligned-state-sync` Phase 1 task 2.6 marked done after this change archives. Tasks 2.7-2.10 (per-parser unknown-child + revision tree round-trip + revision typed-view) remain pending; recorded as follow-up `reader-revision-tree-impl` and `reader-unknown-child-coverage-impl`.
