## Context

`paragraph-tree-projection-impl` (v0.31.0) and `sibling-types-tree-projection-impl` (v0.31.1) shipped `Type(xmlNode:)` constructors. But `DocxReader` does not use them — Reader still constructs typed values via legacy constructors, leaving `xmlNode == nil`. This change adds the production-code path that:

1. Loads each OOXML part as an `XmlTree` alongside the existing `XMLDocument`-based typed parser, storing trees on `WordDocument.xmlTrees`
2. Provides an opt-in mode (`wireTreeBackedViews: true`) that walks `<w:body>` direct children and sets `Paragraph.xmlNode` / `Table.xmlNode` on the corresponding typed values

Prior art consulted:
- `openspec/specs/ooxml-tree-io/spec.md` — defines `XmlTreeReader.parse(_:)` / `XmlTreeWriter.serialize(_:)` (landed v0.30.0)
- `openspec/specs/ooxml-paragraph-tree-projection/spec.md` (v0.31.0) and `openspec/specs/ooxml-typed-views-tree-projection/spec.md` (v0.31.1) — define `Type(xmlNode:)` constructors, the `id` accessor, and tree-walking computed properties this change wires up
- `packages/ooxml-swift/Sources/OOXMLSwift/IO/DocxReader.swift` (3539 lines) — current Reader, has ~10 explicit `Data(contentsOf: <part>)` calls, no `XmlTreeReader.parse` calls
- `packages/ooxml-swift/Sources/OOXMLSwift/Models/Document.swift` (5197 lines) — current `WordDocument` struct, has `preservedArchive: PreservedArchive?` + `modifiedParts: Set<String>` for round-trip preservation but no `xmlTrees` field
- `packages/ooxml-swift/Tests/OOXMLSwiftTests/TreeRoundTripCorpusTests.swift` — existing tests proving `XmlTreeReader.parse` works on the four corpus fixtures (`multi-section-thesis.docx`, `vml-rich.docx`, `cjk-settings.docx`, `comment-anchored.docx`)

## Goals

1. Populate `WordDocument.xmlTrees` for every OOXML part Reader loads
2. Provide opt-in `wireTreeBackedViews: true` that sets `xmlNode` on body-level `Paragraph` and `Table` typed values
3. Default Reader behavior (no parameter, or `wireTreeBackedViews: false`) remains byte-equivalent to v0.31.1 — zero observable behavior change for che-word-mcp's 297-test gate
4. Add test coverage for both `xmlTrees` population and opt-in wiring
5. Ship as ooxml-swift v0.31.2 (additive minor patch)
6. Maintain che-word-mcp regression gate at 0 failures

## Non-Goals

- Wiring nested typed views (cell paragraphs, run-internal anything) — propagates from body-level wiring via the v0.31.1 mode-aware computed accessors
- Wiring header / footer / footnote / endnote / comment typed views — separate follow-up `header-footer-tree-wiring-impl`
- Replacing legacy `XMLDocument` parser path — Phase 5 of `word-aligned-state-sync` (target v1.0.0)
- Op-log routing on Reader-produced typed views — Phase 2 of `word-aligned-state-sync` (separate change, target v0.32.0)
- Streaming / partial XmlTree parses — out of scope
- Tasks 2.7-2.10 of `word-aligned-state-sync` (per-parser unknown-child preservation + revision tree round-trip + revision typed-view backed by tree) — separate follow-up changes

## Decisions

### Decision 1: `xmlTrees` is a public read-only stored property on WordDocument

`WordDocument` gains:

```swift
public internal(set) var xmlTrees: [String: XmlTree] = [:]
```

The internal-set restriction prevents external code from corrupting Reader-loaded trees but allows reading. A read-only convenience accessor `partTree(at: String) -> XmlTree?` returns `xmlTrees[partPath]`.

`xmlTrees` participates in `Equatable` derivation IF `XmlTree: Equatable` — but `XmlTree` is currently NOT `Equatable` because it carries `sourceBytes: Data` and `root: XmlNode` (class identity). To avoid breaking auto-synthesized `WordDocument.Equatable`, the field is excluded from equality semantics: `WordDocument` needs a custom `Equatable` that ignores `xmlTrees` (matching the existing exclusion of `preservedArchive` and `modifiedParts`).

**Why `[String: XmlTree]` and not `[String: XmlNode]`**: `XmlTree` carries `sourceBytes: Data` which `XmlTreeWriter.serialize` requires for clean-subtree fast-path emit. Storing only `XmlNode` would lose the byte cache.

### Decision 2: DocxReader populates xmlTrees during the existing per-part read flow

Instead of adding a separate "load all trees" pass, the `XmlTreeReader.parse(data)` call piggybacks on each existing `Data(contentsOf: <part>)` call inside `DocxReader.read`. Pattern:

```swift
let documentData = try Data(contentsOf: documentURL)
// existing: try Self.rejectDTD + XMLDocument(data: documentData)
// NEW: also build the XmlTree
document.xmlTrees["word/document.xml"] = try XmlTreeReader.parse(documentData)
```

This is added at every Reader site that loads a primary part: `word/document.xml`, `word/styles.xml`, `word/numbering.xml`, `word/settings.xml`, `word/comments.xml`, `word/footnotes.xml`, `word/endnotes.xml`, each `word/header*.xml`, each `word/footer*.xml`, `word/customXml/*.xml`. Approximately 10-12 insertion points.

Parts NOT loaded into `xmlTrees`: `[Content_Types].xml`, `_rels/.rels`, `word/_rels/document.xml.rels`, `word/_rels/header*.xml.rels`, etc. These are relationship/metadata files handled by separate `RelationshipsCollection` parsing — they are out of scope for typed-view wiring (follow-up `relationships-tree-loading-impl` if needed).

### Decision 3: `wireTreeBackedViews: Bool = false` is the new opt-in parameter

`DocxReader.read(from:)` signature becomes:

```swift
public static func read(from url: URL, wireTreeBackedViews: Bool = false) throws -> WordDocument
```

The defaulted parameter ensures every existing call site (`DocxReader.read(from: url)`) compiles unchanged. Default `false` keeps the v0.31.1 behavioral surface — typed views are detached, identical to today.

When `wireTreeBackedViews: true`:
- After the existing typed-model construction completes
- Walk `xmlTrees["word/document.xml"].root.children` (the `<w:document>` root's children, looking for the `<w:body>` element)
- Inside `<w:body>`, iterate direct children in order
- Track a position cursor `i` into `document.body.children`
- For each `<w:body>` direct child:
  - If it is `<w:p>` and `document.body.children[i]` is `.paragraph(var p)`: set `p.xmlNode = thatNode`, write back
  - If it is `<w:tbl>` and `document.body.children[i]` is `.table(var t)`: set `t.xmlNode = thatNode`, write back
  - If it is `<w:sectPr>`: no body.children entry maps to this (it's section-level metadata) — skip
  - Otherwise: skip the body.children entry too (defensive — keeps cursor in sync if `<w:body>` has unexpected children)

This is the **simple positional matcher**. It works because the existing `parseBodyChildren` walks `<w:body>` in source order and produces `body.children` in the same order. Position-matching is robust as long as the two parsers see the same document — which they do (same source bytes).

### Decision 4: Body-level wiring only; nested structure propagates via v0.31.1 computed accessors

Once `Table.xmlNode` is set at body level, `table.rows` (mode-aware computed from v0.31.1) walks `<w:tr>` children of the wrapped `<w:tbl>` and returns `[TableRow(xmlNode:)]`. Each returned `TableRow.cells` returns `[TableCell(xmlNode:)]`. Each returned `TableCell.paragraphs` returns `[Paragraph(xmlNode:)]`. So nested typed views are auto-tree-backed without any additional Reader-side wiring code.

This is a **deliberate scope-tightening**: Reader's wiring loop only iterates body-level `<w:body>` direct children. Cell-internal paragraphs / row-internal cells / etc. are reached through v0.31.1's computed accessors at access time, not at Reader time.

**Caveat**: this means cell-internal paragraphs returned via `cell.paragraphs` are FRESHLY constructed `Paragraph(xmlNode:)` values on each access — they do NOT carry the legacy stored fields that the parser populated for `_legacyParagraphs`. For Phase 1, this is consistent with `ooxml-typed-views-tree-projection` Decision 6 / Phase 1 stub semantics: tree-backed mode reads from the tree, not from any cached legacy data. Existing che-word-mcp tests that traverse `cell.paragraphs[0].runs[0].text` still work because the tree contains the same text — just via the tree-walking path instead of the legacy-stored path. This is the regression risk the che-word-mcp gate validates.

### Decision 5: Equatable on WordDocument needs to ignore xmlTrees

`WordDocument: Equatable` is currently auto-synthesized. Adding `xmlTrees: [String: XmlTree]` would either:
(a) Require `XmlTree: Equatable` (which isn't defined and would need identity-based or content-based — neither is right)
(b) Break auto-synthesis silently with a compile error if `XmlTree` doesn't conform

Option chosen: **define a custom `WordDocument.Equatable` that explicitly ignores `xmlTrees`** (parallel to the existing un-mentioned exclusion of `preservedArchive` and `modifiedParts` — those work today only because Equatable derivation skips internally-marked fields when their types are non-Equatable).

The custom `Equatable` enumerates all stored fields except `xmlTrees`, `preservedArchive`, `modifiedParts`. This change is mechanical but touches Document.swift's `Equatable` derivation surface. Test coverage: `testWordDocumentEqualityIgnoresXmlTrees` (two reads of the same docx produce equal `WordDocument` values even though their `xmlTrees` are distinct class instances).

### Decision 6: Test fixture choice — use the existing corpus in `Tests/.../Fixtures`

Tests use the four golden corpus fixtures already proven to round-trip via `TreeRoundTripCorpusTests`: `multi-section-thesis.docx`, `vml-rich.docx`, `cjk-settings.docx`, `comment-anchored.docx`. New tests live in a new file `ReaderTreeLoadingTests.swift` and import the existing `CorpusFixtureBuilder` to load them.

Test coverage:
- `testReader_xmlTreesPopulatedForDocumentXml` — open multi-section-thesis.docx, assert `document.xmlTrees["word/document.xml"]` is non-nil
- `testReader_xmlTreesPopulatedForAllParts` — open vml-rich.docx, assert `xmlTrees` keys include all primary parts (`word/document.xml`, `word/styles.xml`, etc.)
- `testReader_partTreeReturnsNilForUnknownPath` — `document.partTree(at: "word/nonexistent.xml")` is nil
- `testReader_defaultModeKeepsTypedViewsDetached` — open multi-section-thesis.docx WITHOUT `wireTreeBackedViews:`; iterate body.children; assert every Paragraph and Table has `xmlNode == nil`
- `testReader_wireTreeBackedViewsSetsBodyParagraphXmlNode` — open multi-section-thesis.docx WITH `wireTreeBackedViews: true`; assert each body-level Paragraph has `xmlNode != nil` AND `xmlNode.localName == "p"`
- `testReader_wireTreeBackedViewsSetsBodyTableXmlNode` — same but assert body-level Tables have `xmlNode != nil` AND `xmlNode.localName == "tbl"`
- `testWordDocumentEqualityIgnoresXmlTrees` — read the same docx twice; assert `doc1 == doc2` despite distinct `XmlTree` instances

### Decision 7: Test gate convention identical to v0.31.1

Tests land GREEN-from-the-start (no `#if false` gate). This matches `sibling-types-tree-projection-impl` Decision 7.

## Risks / Trade-offs

| Risk | Mitigation |
|------|------------|
| `XmlTreeReader.parse` may fail on real-world OOXML the production parser tolerates | The four golden corpus fixtures are real-world OOXML proven to parse via `TreeRoundTripCorpusTests`. If `XmlTreeReader.parse` fails on a part, this change's Reader path catches the throw and SHALL surface it (no silent swallow). If a known-edge-case fixture fails, scope it to a follow-up bug change. |
| Wiring positional mismatch breaks `body.children[i]` matching | Defensive: skip cursor advancement when types don't match. Logs a warning via stderr. Unit test `testReader_wiringWithUnexpectedBodyChild` covers a synthesized fixture with an unmapped `<w:body>` child kind. |
| Custom `Equatable` change regresses other paths that depend on auto-synth | Run full ooxml-swift suite (928+ tests pre-change baseline) — any test asserting on `WordDocument` equality catches drift. The custom Equatable is content-equivalent except for the explicitly-excluded fields. |
| Doubled parse cost (XMLDocument + XmlTreeReader on every part) | Acceptable for v0.31.x: doc parsing is ~10ms per typical thesis chapter; doubling to ~20ms is negligible vs. the seconds-long overall Reader path. Phase 5 (v1.0.0) removes the legacy path so cost halves again. |
| `wireTreeBackedViews: true` users may inadvertently rely on tree-backed Reader-produced cell paragraphs having parsed RunProperties (which Phase 1 stub doesn't provide) | Documented loudly in Decision 4 and in the spec scenarios. Phase 1 stub semantics from `ooxml-typed-views-tree-projection` apply uniformly. |

## Open Items

- (none — Decision 4 explicitly captures the cell-paragraph fresh-construction caveat; Decision 5 explicitly captures the Equatable change)
