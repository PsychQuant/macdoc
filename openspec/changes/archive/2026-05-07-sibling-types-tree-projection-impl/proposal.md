## Why

Phase 1 of `word-aligned-state-sync` mandates that **every typed view** (`Paragraph`, `Run`, `Table`/`TableRow`/`TableCell`, `SectionProperties`, `Settings`) becomes a tree-backed projection over the `XmlNode` DOM landed in v0.30.0. The Paragraph half shipped as ooxml-swift v0.31.0 (Spectra change `paragraph-tree-projection-impl`, 2026-05-07) and pinned the pattern: `xmlNode: XmlNode?` stored property, mode-aware computed accessors, identity-based `Equatable` for tree-backed mode, legacy stored-property fallback for detached mode.

Phase 2 (Operation log, target v0.32.0) requires `OperationLog.append(_ op:)` to address mutations by `ElementID` against any typed view — Paragraph alone is not enough. Phase 4 (Script transcoder, target v0.34.0) emits `WordDSLSwift` source whose root types include `Run`, `Table`, `Section` (not just `Paragraph`). Both downstream phases are blocked until the sibling typed views match Paragraph's tree-backed shape.

This change ships the **mechanical extension** of the Paragraph pattern to three sibling source files: `Run.swift` (519 lines), `Table.swift` (618 lines, hosts `Table` + `TableRow` + `TableCell`), and `Section.swift` (376 lines, hosts `SectionProperties`). No design exploration is needed — the pattern is fully defined by the archived `ooxml-paragraph-tree-projection` capability spec; this change applies it.

The companion sibling refactor for `Settings` (Phase 1 task 2.5 of `word-aligned-state-sync`) is **explicitly deferred**: the codebase has no standalone `Settings` struct (settings handling lives inside `Document.swift`); a separate change must extract `Settings` as a struct first before tree-backing it.

## What Changes

- **NEW**: `Run(xmlNode: XmlNode)` constructor on `Run` — wraps a `<w:r>` element. Co-exists with the legacy `Run(text:, properties:)` constructor.
- **NEW**: `run.id: String?` computed property — derived from `XmlNode.stableID` with `"lib:<UUID>"` fallback; returns `nil` for detached runs.
- **NEW**: `run.text` and `run.properties` become mode-aware computed properties — tree-backed getter walks the wrapped xmlNode at every access; detached getter reads the legacy stored properties.
- **NEW**: `Table(xmlNode: XmlNode)`, `TableRow(xmlNode: XmlNode)`, `TableCell(xmlNode: XmlNode)` constructors — wrap `<w:tbl>`, `<w:tr>`, `<w:tc>` elements respectively. Each gets a parallel `id: String?` computed property and mode-aware `rows` / `cells` / `paragraphs` accessors.
- **NEW**: `SectionProperties(xmlNode: XmlNode)` constructor — wraps a `<w:sectPr>` element. `id: String?` computed; mode-aware accessors for the structured fields parsed from `<w:sectPr>`.
- **MODIFIED**: `Run`, `Table`, `TableRow`, `TableCell`, `SectionProperties` — auto-synthesized `Equatable` replaced with mode-aware identity-vs-content semantics matching `Paragraph`'s pattern (both tree-backed → identity on xmlNode; both detached → content equality on stored fields; mixed → `false`).
- **NEW**: Test scaffolds `RunTreeProjectionTests`, `TableTreeProjectionTests`, `SectionPropertiesTreeProjectionTests` — one test class per refactored type, each pinning the same surface as `ParagraphTreeProjectionTests` did for Paragraph.
- **NON-BREAKING**: All existing legacy constructors and stored properties on these types are preserved unchanged. Reader continues to produce detached values for these types; tree-backed instances are opt-in for downstream library code.

## Non-Goals

- **`Settings` refactor (Phase 1 task 2.5 of `word-aligned-state-sync`)** — out of scope. There is no `Settings` struct in `packages/ooxml-swift/Sources/OOXMLSwift/Models/`; settings handling lives inside `Document.swift`. A separate change must extract `Settings` as a struct first.
- **`DocxReader` rewiring to produce tree-backed values** — out of scope. That is task 2.6 of `word-aligned-state-sync`; this change keeps Reader producing detached values so the behavioral surface stays byte-equivalent.
- **Op-log routing on setters** — out of scope. Phase 2 of `word-aligned-state-sync` (target v0.32.0) replaces the Phase 1 stub setters with op-log routing. This change keeps the Phase 1 stub semantics established by `paragraph-tree-projection-impl` (tree-backed setter mutates the wrapped xmlNode directly + calls `markDirty()`; detached setter falls through to legacy stored-property write).
- **Run-style formatting preservation in tree-backed text setter** — explicitly accepted as Phase 1 stub destructive behavior (matches Paragraph). Phase 2 op-log will preserve formatting.
- **Touching any source file beyond `Run.swift`, `Table.swift`, `Section.swift` and the corresponding test files** — out of scope. Reader, Writer, Document, and other typed views are untouched in this change.

## Capabilities

### New Capabilities

- `ooxml-typed-views-tree-projection`: Tree-backed view contract for the sibling typed views (`Run`, `Table`, `TableRow`, `TableCell`, `SectionProperties`). Defines the constructor surface, identity model, getter routing (mode-aware computed properties), setter routing (Phase 1 stub mutates tree directly + flips isDirty), legacy detached-mode coexistence, and equality semantics (identity-based for tree-backed; content-based for detached). Sibling to `ooxml-paragraph-tree-projection` — same shape, applied to four additional types.

### Modified Capabilities

(none — public surfaces of ooxml-paragraph-text-mirror, ooxml-paragraph-child-schema-coverage, ooxml-mutation-surface-safety are preserved as-is; only the internal storage paths of the listed sibling types shift to tree-backed.)

## Impact

- Affected specs:
  - New: `openspec/specs/ooxml-typed-views-tree-projection/spec.md`
- Affected code:
  - Modified: `packages/ooxml-swift/Sources/OOXMLSwift/Models/Run.swift` (gain `xmlNode: XmlNode?` + `init(xmlNode:)` + `id` + mode-aware `text`/`properties` accessors + custom Equatable)
  - Modified: `packages/ooxml-swift/Sources/OOXMLSwift/Models/Table.swift` (same pattern applied to `Table`, `TableRow`, `TableCell`; each gains tree-backed constructor + `id` + mode-aware row/cell/paragraph accessors + custom Equatable)
  - Modified: `packages/ooxml-swift/Sources/OOXMLSwift/Models/Section.swift` (same pattern applied to `SectionProperties`)
  - New: `packages/ooxml-swift/Tests/OOXMLSwiftTests/RunTreeProjectionTests.swift` (RED scaffold pinning `Run(xmlNode:)` + `run.id` + tree-walking accessors + identity equality)
  - New: `packages/ooxml-swift/Tests/OOXMLSwiftTests/TableTreeProjectionTests.swift` (parallel scaffold for Table/TableRow/TableCell)
  - New: `packages/ooxml-swift/Tests/OOXMLSwiftTests/SectionPropertiesTreeProjectionTests.swift` (parallel scaffold for SectionProperties)
- Affected dependencies:
  - che-word-mcp (downstream lib consumer): no source change required; its 297 production tests are the regression gate. They MUST stay GREEN through this change after the post-release Package.resolved bump to v0.31.1.
  - macdoc CLI: no source change required.
- Affected releases:
  - ooxml-swift v0.31.1 (additive minor patch — v0.31.0 already shipped Paragraph; this change extends the same pattern to siblings).
- Affected sibling Spectra changes:
  - `word-aligned-state-sync` Phase 1 tasks 2.2 + 2.3 + 2.4 marked done after this change archives. Task 2.5 remains pending (Settings refactor blocked by missing Settings struct).
