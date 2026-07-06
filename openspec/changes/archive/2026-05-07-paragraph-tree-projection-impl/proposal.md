## Why

The RED scaffold at `packages/ooxml-swift/Tests/OOXMLSwiftTests/ParagraphTreeProjectionTests.swift` (9 tests, currently `#if false` gated to allow the test target to compile) pins the API surface of a tree-backed `Paragraph` view that does not yet exist in `packages/ooxml-swift/Sources/OOXMLSwift/Models/Paragraph.swift`. Without that implementation, Phase 4 of the sibling change `word-aligned-state-sync` (Script transcoder, target ooxml-swift v0.34.0) is blocked — the script transcoder reads `Paragraph(xmlNode:)` and `paragraph.id` from typed views, both of which require this refactor. The existing fixture corpus (`mdocx-fixture-corpus`, archived 2026-05-07) ships 18 `.mdocx.swift` design-frozen specs that exercise the tree-backed Paragraph surface during Phase B activation; without that surface existing, none of Phase B's per-fixture assertions can run.

This change implements the tree-backed Paragraph view in production code, flips the RED scaffold to GREEN, and verifies che-word-mcp's 271 production tests remain GREEN against the new internals (the public Paragraph API does not change — only the implementation underneath).

This is the production-code portion of `word-aligned-state-sync` Phase 1 task 2.1, scoped narrowly to `Paragraph.swift` so the refactor lands as one focused change. Sibling type refactors (`Run`, `Table`, `TableRow`, `TableCell`, `SectionProperties`, `Settings`) are explicitly out of scope here — they remain Phase 1 tasks 2.2-2.5 inside `word-aligned-state-sync` and follow the same pattern this change establishes.

## What Changes

- **NEW**: `Paragraph(xmlNode: XmlNode)` constructor that wraps an existing OOXML `<w:p>` node and exposes typed view accessors over its tree state. Co-exists with the legacy `Paragraph(runs:, properties:, ...)` constructor (Phase 5 of word-aligned-state-sync removes the legacy form; Phase 1 keeps both).
- **NEW**: `paragraph.id: String?` computed property derived from `XmlNode.stableID` (which reads `w14:paraId`, `w:bookmarkId`, `r:id`, `w14:textId` in priority order) with `lib:<UUID>` fallback when `XmlNode.libraryUUID` is set. Detached paragraphs (legacy constructor, no xmlNode) return `nil`.
- **NEW**: Tree-backed read accessors for `paragraph.text`, `paragraph.runs`. Each call walks the wrapped xmlNode's children at access time, never caching. Mutating the tree directly (e.g., appending a `<w:r>` child) is observable through the view without reconstructing the `Paragraph` value.
- **NEW**: Tree-backed write accessor for `paragraph.text` (Phase 1 stub). Writing replaces the wrapped xmlNode's `<w:r>` children with a single `<w:r><w:t>` element carrying the new text and flips `xmlNode.isDirty = true`. **Phase 2 of `word-aligned-state-sync` will route this through the op log; Phase 1 stubs the routing as direct tree mutation so getters keep returning the new value via the tree-walking getter path.**
- **NEW**: Identity-based `Equatable` conformance for tree-backed Paragraphs: two `Paragraph`s wrapping the SAME xmlNode are equal; two wrapping different xmlNodes with byte-identical content are NOT equal. Op log addresses paragraphs by `id` (== identity); content equality would silently merge log entries that target different elements.
- **MODIFIED**: `Tests/OOXMLSwiftTests/ParagraphTreeProjectionTests.swift` — the `#if false` compile gate is removed. All 9 tests SHALL run and pass GREEN against the new implementation.
- **NON-BREAKING**: che-word-mcp's 271 production tests SHALL run GREEN against the new ooxml-swift. The public Paragraph API surface (every method and property used by Phase 0 & current consumers) is preserved byte-equivalent; only internals shift to tree-backed.

## Capabilities

### New Capabilities

- `ooxml-paragraph-tree-projection`: Tree-backed Paragraph view contract. Defines the constructor surface, identity model (`paragraph.id` derivation rules), getter routing (text + runs walk the underlying tree at access time), setter routing (Phase 1 stub mutates tree directly + flips isDirty; Phase 2 will route through op log), legacy detached-mode coexistence, and equality semantics (identity-based).

### Modified Capabilities

(none — public surfaces of the existing paragraph-related capabilities are preserved as-is; only the internal storage path changes, which those specs treat as implementation detail. The relevant existing canonical specs are not modified by this change.)

## Impact

- Affected specs:
  - New: `openspec/specs/ooxml-paragraph-tree-projection/spec.md`
- Affected code:
  - Modified: `packages/ooxml-swift/Sources/OOXMLSwift/Models/Paragraph.swift` (the 1028-line struct gains a `xmlNode: XmlNode?` stored property + tree-aware accessors; existing legacy stored properties remain for detached mode and back-compat)
  - Modified: `packages/ooxml-swift/Tests/OOXMLSwiftTests/ParagraphTreeProjectionTests.swift` (remove `#if false` compile gate; 9 tests go from compile-gated RED to runtime GREEN)
  - New: (none — no new source files)
  - Removed: (none in this change; Phase 5 of `word-aligned-state-sync` removes the legacy detached path)
- Affected dependencies:
  - che-word-mcp (downstream lib consumer): no source change required; its 271 tests are the regression gate. They MUST stay GREEN through this change.
  - macdoc CLI (downstream consumer via word-to-md-swift, md-to-word-swift): no source change required; rebuild against new ooxml-swift via `swift package update`.
  - `word-aligned-state-sync` Phase 1 task 2.1 (the production-code portion): completed by this change. Phase 1 tasks 2.2-2.5 (sibling type refactors) follow the pattern this change establishes but stay in `word-aligned-state-sync`.
- Affected fixtures:
  - `mdocx-fixture-corpus` (archived 2026-05-07): unaffected at Phase A. When Phase B activates (separate future change), fixture 01 `01-dual-extension-recognition` becomes the first end-to-end smoke that exercises this tree-backed Paragraph through the WordDSLSwift module.
