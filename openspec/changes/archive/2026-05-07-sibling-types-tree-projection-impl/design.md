## Context

`paragraph-tree-projection-impl` (archived 2026-05-07, ooxml-swift v0.31.0) shipped the tree-backed view pattern for `Paragraph`. This change applies the same pattern to the remaining typed views in scope for Phase 1 of `word-aligned-state-sync` (Run, Table family, SectionProperties). The pattern itself is already locked in the archived `ooxml-paragraph-tree-projection` capability spec — this change does not re-litigate it; it captures the per-type variations that arise when applying the pattern to types with different shape than `Paragraph`.

Prior art consulted:
- `openspec/specs/ooxml-paragraph-tree-projection/spec.md` — the contract this change extends
- `openspec/changes/archive/2026-05-07-paragraph-tree-projection-impl/design.md` — the per-type design that this change parallels
- `packages/ooxml-swift/Sources/OOXMLSwift/Models/Paragraph.swift` (modified by paragraph-tree-projection-impl) — the reference implementation

Current state of target source files:
- `Run.swift` — 519 lines, single struct `Run` (line 17) with 7 stored fields including the `rawXML` / `rawElements` escape hatches
- `Table.swift` — 618 lines, three structs in one file: `Table` (line 4), `TableRow` (line 46), `TableCell` (line 76)
- `Section.swift` — 376 lines, single struct `SectionProperties` (line 6) with 12+ structured fields, each mapped to a distinct `<w:sectPr>` child element

## Goals

1. Apply the tree-backed view pattern to `Run`, `Table`, `TableRow`, `TableCell`, `SectionProperties`
2. Keep all existing legacy stored fields and constructors so detached mode behavior stays byte-equivalent
3. Add identity-based equality for tree-backed mode + content equality for detached mode (matches Paragraph)
4. Pin each refactored type's API surface with a RED scaffold test class that lifts to GREEN once the implementation lands
5. Ship as ooxml-swift v0.31.1 (additive minor patch on top of v0.31.0)
6. Maintain che-word-mcp's 297-test regression gate at 0 failures

## Non-Goals

- Refactoring `Settings` (Phase 1 task 2.5 of `word-aligned-state-sync`) — no `Settings` struct exists; deferred to a separate change that first extracts it
- Rewiring `DocxReader` to produce tree-backed values (task 2.6 of `word-aligned-state-sync`)
- Op-log routing on setters (Phase 2 of `word-aligned-state-sync`, target v0.32.0)
- Full tree-walking accessors for all 12+ `SectionProperties` structured fields — Phase 1 stub does identity-only on `SectionProperties` (see Decision 6 below)
- Touching `RunProperties`, `TableProperties`, `TableCellProperties`, `TableRowProperties`, etc. — those are simple value types that don't need tree-backing in Phase 1

## Decisions

### Decision 1: Same struct-with-class-reference pattern as Paragraph

Each refactored type keeps its existing `struct` declaration. The new `xmlNode: XmlNode?` stored property holds a class reference (`XmlNode` is a `class`), so two value-copies of the same Run/Table/Cell share the same underlying tree state. Mutations through one copy are visible through the other.

This is byte-identical to the decision recorded in `paragraph-tree-projection-impl/design.md` Decision 1.

### Decision 2: `id: String?` derives from `XmlNode.stableID` with `lib:` UUID fallback

Each type gains a `public var id: String?` computed property:
- Tree-backed: `xmlNode.stableID` if any OOXML stable-ID attribute is present, else `"lib:\(libraryUUID.uuidString)"` if `libraryUUID` is set, else `nil`
- Detached: `nil`

Note: `<w:r>`, `<w:tbl>`, `<w:tr>`, `<w:tc>`, `<w:sectPr>` do not natively carry `w14:paraId` / `w:bookmarkId`; their stable IDs come from `w:id` (Run revision), `r:id` (Hyperlink/Image relationships), or the `lib:` UUID fallback. The op log will address them by these surrogate IDs.

### Decision 3: Tree-walking getters for the primary content accessor only

For each type, the **primary content accessor** becomes mode-aware computed:

| Type | Primary content accessor | Tree-backed getter |
|------|--------------------------|---------------------|
| `Run` | `text: String` | concatenate `<w:t>` `textContent` from direct children |
| `Run` | `properties: RunProperties` | parse from `<w:rPr>` direct child (Phase 1 stub: return default `RunProperties()` if no `<w:rPr>`) |
| `Table` | `rows: [TableRow]` | walk `<w:tr>` children, return one `TableRow(xmlNode:)` per child |
| `TableRow` | `cells: [TableCell]` | walk `<w:tc>` children, return one `TableCell(xmlNode:)` per child |
| `TableCell` | `paragraphs: [Paragraph]` | walk `<w:p>` children, return one `Paragraph(xmlNode:)` per child (uses already-shipped Paragraph tree-backed constructor) |
| `TableCell` | `nestedTables: [Table]` | walk `<w:tbl>` children, return one `Table(xmlNode:)` per child |

**Phase 1 stub**: when the tree-backed getter cannot easily reconstruct the legacy field shape (e.g., `Run.properties` requires parsing `<w:rPr>`), it returns the default value. Phase 2 will add full tree-walking parsers; Phase 1 keeps the API surface stable while deferring deep parsing to the existing detached-mode reader.

### Decision 4: Phase 1 stub setters mutate the tree directly

Following the Paragraph stub pattern (Decision 4 of `paragraph-tree-projection-impl/design.md`):

| Type | Setter | Phase 1 stub behavior |
|------|--------|------------------------|
| `Run.text =` | tree-backed: replace `<w:r>`'s `<w:t>` children with one new `<w:t>X</w:t>`, call `markDirty()`; detached: write to legacy stored field |
| `Run.properties =` | tree-backed: ghost write to legacy buffer (Phase 1 limitation; Phase 2 op-log will route properly); detached: write to legacy stored field |
| `Table.rows =` | tree-backed: ghost write to legacy buffer; detached: write to legacy stored field |
| `TableRow.cells =`, `TableCell.paragraphs =`, etc. | same ghost-write pattern |

Phase 1's promise is "che-word-mcp tests stay green." Reader produces detached values for these types in v0.31.1, so all existing call sites go through detached mode. Tree-backed mode is opt-in for downstream library code that explicitly constructs `Run(xmlNode:)`, `Table(xmlNode:)`, etc.

### Decision 5: Identity-based `Equatable` for all five types

Each refactored type replaces its auto-synthesized `Equatable` with the same mode-aware implementation pattern locked in `paragraph-tree-projection-impl` Decision 5:

```
== switch (lhs.xmlNode, rhs.xmlNode):
  (a?, b?) → a === b           // both tree-backed: identity
  (nil, nil) → contentEquals    // both detached: enumerate stored fields
  default → false               // mixed mode: never equal
```

Each type gets its own `private static func contentEquals(_ lhs:_:_ rhs:) -> Bool` enumerating its stored legacy fields. The enumeration is mechanical; no behavioral changes vs. the auto-synth in detached mode.

### Decision 6: SectionProperties tree-backed mode is identity-only in Phase 1

`SectionProperties` has 12+ structured fields (`pageSize`, `pageMargins`, `orientation`, `columns`, `docGrid`, `headerReferences`, `footerReferences`, `lineNumbers`, `verticalAlignment`, `pageNumberFormat`, `pageNumberStartValue`, `titlePageDistinct`, `sectionBreakType`), each backed by a distinct `<w:sectPr>` child element (`<w:pgSz>`, `<w:pgMar>`, `<w:cols>`, `<w:docGrid>`, `<w:headerReference>`, `<w:footerReference>`, `<w:lnNumType>`, `<w:vAlign>`, `<w:pgNumType>`, `<w:type>`).

Implementing full tree-walking parsers for all 12+ fields is a substantial body of work that does not fit Phase 1's scope (would push this change to ~6-8 hr from the targeted 1.5-3 hr). The Paragraph pattern's `text`/`runs` accessors are simple concatenations; SectionProperties' field-by-field XML parsing is qualitatively different work.

**Phase 1 simplification**: tree-backed `SectionProperties` provides:
- `xmlNode: XmlNode?` stored property + `init(xmlNode:)` constructor (so the op log can address sections by identity)
- `id: String?` computed property (per Decision 2)
- Mode-aware identity-vs-content `Equatable` (per Decision 5)
- All 12+ structured fields remain as legacy stored properties; tree-backed mode does NOT auto-populate them. Callers reading structured fields from a tree-backed `SectionProperties` get the default values they would get from `SectionProperties()`.

**Why this is acceptable**: in Phase 1, Reader still produces detached `SectionProperties` (with structured fields populated by the existing parser). Tree-backed `SectionProperties` is opt-in for downstream library code. Phase 4 (Script transcoder) needs identity to address sections via op log, not deep field access — so identity-only tree-backing is sufficient.

**Follow-up**: a separate Spectra change (`section-properties-tree-walking-impl`, Phase 2 prerequisite) will add full tree-walking parsers for the 12+ fields. That change is explicitly out of scope here and is recorded in `word-aligned-state-sync`'s tasks.md as a follow-up to task 2.4.

### Decision 7: Test gate convention identical to Paragraph

Each new test file (`RunTreeProjectionTests.swift`, `TableTreeProjectionTests.swift`, `SectionPropertiesTreeProjectionTests.swift`) is committed RED with the implementation tasks; once the implementation lands the gate is removed (matches `paragraph-tree-projection-impl` Decision 6). For this change, since implementation lands in the same task batch as the tests, the tests are written GREEN-from-the-start (no `#if false` gate phase needed). This matches the pattern already used for `MdocxFixtureNormalizerTests`.

## Risks / Trade-offs

| Risk | Mitigation |
|------|------------|
| `Run.rawXML` / `rawElements` escape hatches don't fit cleanly into tree-walking | Keep as legacy stored fields; tree-backed mode reads them as default `nil`. Phase 2 op log will route any rawXML mutations explicitly. |
| `TableCell` returns tree-backed `Paragraph` from its computed `paragraphs` accessor — deep tree dependency between types | Already validated: `Paragraph(xmlNode:)` exists from v0.31.0; this just uses it. |
| `SectionProperties` Phase 1 simplification (Decision 6) could surprise callers who expect tree-backed `pageSize` to read from `<w:pgSz>` | Acceptable because Reader still produces detached values; tree-backed `SectionProperties` is opt-in. Documented clearly in spec scenarios + follow-up change registered. |
| Identity equality might break a legacy test that compared two reader-produced typed values for content equality after tree-backing them via opt-in API | Same risk as paragraph-tree-projection-impl — Reader still produces detached values, so existing tests are unaffected. New code that opts into tree-backing accepts the new equality semantics. |
| Cross-file test changes (3 new test files) might mis-build | Each test file is independent; build failure in one does not cascade. Same `[P]` parallel pattern as Paragraph. |

## Open Items

- (none — Decision 6 explicitly captures the SectionProperties simplification as in-scope; follow-up registered)
