## Context

`Paragraph` in `packages/ooxml-swift/Sources/OOXMLSwift/Models/Paragraph.swift` is a 1028-line `struct` with 11+ stored properties (`runs`, `properties`, `hasPageBreak`, `bookmarks`, `hyperlinks`, deprecated `commentIds`, `footnoteIds`, `endnoteIds`, `revisions`, `semantic`, `paragraphFormatChangeRevisionId`, `previousProperties`, content controls). It is the core typed view used by che-word-mcp's 234 production MCP tools and 271 tests.

`word-aligned-state-sync` Phase 0 (archived as `ooxml-tree-io` capability, ooxml-swift v0.30.0) introduced the `XmlNode` tree foundation — a class-based, fully-preserving DOM with `attributes`, `children`, `attributeValue(prefix:localName:)`, `setAttribute(prefix:localName:value:)`, `markDirty()`, and `stableID` derivation. Phase 1 of that change (tasks 2.1-2.12) refactors the typed views (Paragraph, Run, Table family, SectionProperties, Settings) to read and write through this tree.

The RED scaffold at `packages/ooxml-swift/Tests/OOXMLSwiftTests/ParagraphTreeProjectionTests.swift` (committed as `c97de51` in ooxml-swift) pins 9 design decisions for the tree-backed Paragraph through failing tests. When committed, the tests caused a compile failure (referencing `Paragraph(xmlNode:)` and `paragraph.id` — neither existed). Commit `8d3dd49` gated the entire test class behind `#if false` so the test target builds; this change flips the gate to `#if true` (or removes it) once the API exists.

This change is the **production-code half** of `word-aligned-state-sync` Phase 1 task 2.1. The RED scaffold (the test half) and Package.swift's `Fixtures/mdocx` exclude already shipped. This change closes the loop.

Sibling type refactors (`Run`, `Table`, `TableRow`, `TableCell`, `SectionProperties`, `Settings`) are explicitly NOT in scope here. Each follows the pattern this change establishes but stays as `word-aligned-state-sync` Phase 1 tasks 2.2-2.5. Splitting the 5 type refactors into 5 changes adds ceremony; landing them all under `word-aligned-state-sync` keeps the phased plan intact. Paragraph is special-cased into its own change because (a) it is the largest single type, (b) its API surface is the entry point exercised by every fixture in the `mdocx-fixture-corpus`, and (c) its design choices (struct vs class, identity equality semantics, setter routing model) cascade to all sibling types.

## Goals / Non-Goals

**Goals:**

- Implement `Paragraph(xmlNode:)`, `paragraph.id`, tree-backed `paragraph.text` and `paragraph.runs` getters, tree-mutating `paragraph.text` setter (Phase 1 stub — direct tree mutation, no op log routing yet), identity-based `Equatable` conformance for tree-backed paragraphs.
- Coexist with the legacy `Paragraph(runs:, properties:, ...)` constructor and stored-property-backed mode. Detached paragraphs (legacy mode) keep their current behavior 100% byte-equivalent.
- Flip the `#if false` gate in `ParagraphTreeProjectionTests.swift` to `#if true` (or remove it). All 9 RED scaffold tests turn GREEN.
- Run `swift test` on ooxml-swift: every existing test passes (no regression on legacy paragraphs).
- Run che-word-mcp's 271 production tests against the new ooxml-swift: zero observable behavior change in MCP tool output.

**Non-Goals:**

- **Refactoring sibling typed views** (`Run`, `Table`, `TableRow`, `TableCell`, `SectionProperties`, `Settings`). Those stay as `word-aligned-state-sync` Phase 1 tasks 2.2-2.5. This change establishes the pattern; sibling refactors apply the same pattern.
- **Routing setters through the op log** (`OperationLog`). The op log infrastructure is `word-aligned-state-sync` Phase 2 (target ooxml-swift v0.32.0). Phase 1 stubs setter routing as direct tree mutation; Phase 2 swaps the stub for log-routing.
- **Removing the legacy `Paragraph(runs:, properties:, ...)` constructor**. That removal is `word-aligned-state-sync` Phase 5 (Migration cleanup, target v1.0.0). Phase 1 keeps both modes.
- **Implementing `WordDSLSwift` types or builders**. That is `word-aligned-state-sync` Phase 4 (Script transcoder, target v0.34.0). The fixture corpus's `.mdocx.swift` files keep using future DSL surface — they remain non-executable until Phase 4 lands.
- **Activating `mdocx-fixture-corpus` Phase B**. Phase B activation is the hand-off contract recorded in `mdocx-fixture-corpus` design.md Decision 5 §5 deferred tasks. This change does NOT flip `MdocxFixtureCorpusTests.activatePhaseB`.
- **Public API changes to `Paragraph`**. che-word-mcp's 271 tests are the regression gate; any public-API delta would break them. This change is internal-implementation only from the consumer's perspective.

## Decisions

### Decision 1: `Paragraph` stays a `struct`, not promoted to `class`

`Paragraph` keeps its existing `struct` declaration. The new `xmlNode: XmlNode?` stored property holds a reference to the underlying tree node (XmlNode is a `class`), so two value-copies of the same Paragraph share the same tree state — mutations via one copy are visible through the other.

**Why**: Promoting to `class` would break che-word-mcp's 271 tests (many depend on value-copy semantics, `Equatable`-by-content conformance via auto-synthesis, and `Hashable` membership). Keeping `struct` preserves the public API surface; the tree-state-sharing behavior is documented in the new `Paragraph(xmlNode:)` constructor's doc comment so callers know two copies share state.

**Alternatives considered**:

- *Promote to `class`*: Cleaner reference semantics. Rejected: 271-test regression risk is unacceptable in Phase 1.
- *Use copy-on-write*: Hide the tree-sharing behavior behind value-copy semantics. Rejected: forces the Paragraph layer to detect "I'm being mutated, time to clone the tree" — but tree mutation is the entire point of the refactor; CoW would defeat it.

### Decision 2: `id` is `String?` and reads `xmlNode?.stableID` with `lib:` UUID fallback

`paragraph.id` is a computed property:

```
public var id: String? {
    if let stable = xmlNode?.stableID { return stable }
    if let uuid = xmlNode?.libraryUUID { return "lib:\(uuid.uuidString)" }
    return nil
}
```

Detached Paragraphs (legacy `Paragraph(runs:)` constructor, no xmlNode) return `nil`. Tree-backed Paragraphs return `XmlNode.stableID` if present (which itself walks `w14:paraId` → `w:bookmarkId` → `w:id` → `r:id` → `w14:textId`), else `lib:<UUID>` from the reader-injected `libraryUUID`.

**Why**: Op log addresses paragraphs by `id`. Without identity, log entries cannot reliably target paragraphs. The `lib:` prefix differentiates library-generated UUIDs from native OOXML stable IDs so consumers can detect when a paragraph lacks a native ID (and may want to inject one for cross-document stability).

**Alternatives considered**:

- *Force every Paragraph to have a non-nil id (raise on detached)*: Rejected. Legacy `Paragraph(runs:)` callers don't have an xmlNode; raising would break 271 tests. Phase 5 removes legacy mode and at that point id can become non-optional.
- *Strip the prefix from stableID when returning*: Rejected. The `w14:paraId=ABC123` format is the XmlNode contract; preserving the prefix in `paragraph.id` keeps the round-trip unambiguous.

### Decision 3: Getter `text` and `runs` are computed, not cached

Both `paragraph.text` and `paragraph.runs` walk the wrapped xmlNode's `children` at every access. There is no internal cache.

**Why**: Caching introduces invalidation. Mutating the tree directly (e.g., `xmlNode.children.append(newRun)`) would not trigger a cache invalidation — but the test `testTreeBackedParagraph_runsCountReflectsTreeChildren` explicitly asserts that view changes are observable without reconstructing the Paragraph. Caching would fail that test. The walk cost is acceptable for typed-view access patterns (a paragraph rarely has more than 50 runs; the walk is O(n) over a small n).

**Alternatives considered**:

- *Cache + invalidate on `xmlNode.markDirty()`*: Rejected. `markDirty()` is set-only; XmlNode does not expose dirty events. Adding eventing is out of scope for this change.
- *Lazy-init on first access, never invalidate*: Rejected. Stale reads after tree mutation would be a silent bug class.

### Decision 4: Setter `text` mutates tree directly (Phase 1 stub)

`paragraph.text = "X"` does:

1. Replace `xmlNode.children` with one new `XmlNode.element(prefix: "w", localName: "r", children: [XmlNode.element(prefix: "w", localName: "t", children: [XmlNode.text("X")])])`.
2. Call `xmlNode.markDirty()` so the writer re-serializes the sub-tree from typed fields.

Run formatting is destroyed by this stub setter (consistent with the existing legacy setter's deprecation notice). Phase 2 routes through the op log to preserve formatting via `setText` ops.

**Why**: Phase 2 op log infrastructure is not yet built; Phase 1 cannot route through what does not exist. The stub matches the existing legacy setter's destructive behavior so consumer expectations don't change. The Phase 2 transition is internal-only — public API is unchanged.

**Alternatives considered**:

- *Defer setter implementation to Phase 2*: Rejected. The RED scaffold's `testTreeBackedParagraph_textSetterMutatesTree` requires setter behavior in Phase 1. Stubbing fulfills the contract; Phase 2 refines.
- *Preserve formatting by reading existing rPr from first run*: Rejected. Adds complexity that Phase 2 will replace anyway. Stub stays simple.

### Decision 5: Identity-based `Equatable`, not content-based

Tree-backed Paragraphs use identity-based equality (same `xmlNode` reference == equal; different xmlNode == unequal even with identical content). Detached Paragraphs (no xmlNode) keep auto-synthesized content equality on the legacy stored properties.

Equality is split-mode: when both sides have xmlNode, compare xmlNode references (`===`). When neither side has xmlNode, fall back to content equality. When mixed (one tree-backed, one detached), inequality.

**Why**: Op log addresses paragraphs by id (== identity). Two content-equal-but-different-id paragraphs MUST NOT be equal — content equality would silently merge log entries that target different elements.

**Risk**: che-word-mcp's 271 tests may have assertions of the form `XCTAssertEqual(paragraphA, paragraphB)` where both are reconstructed from the same source; if the reader produces tree-backed paragraphs with distinct xmlNode refs in such tests, identity inequality would break them. **Mitigation**: legacy code paths (Reader-produced paragraphs without explicit xmlNode wrap) keep stored-property-backed mode, where content equality applies. Reader is NOT modified to produce tree-backed paragraphs in this change — that is Phase 1 task 2.6 (Reader update) inside `word-aligned-state-sync`.

**Alternatives considered**:

- *Content equality for both modes*: Rejected. Op log address ambiguity (per Why above).
- *Make `Paragraph.contentEquals(other:)` a separate method, keep `==` content-based*: Rejected. The RED scaffold's `testTreeBackedParagraph_identityEqualityNotContentEquality` explicitly asserts `==` is identity-based. Adding a separate content-compare method is a follow-up if needed.

### Decision 6: Test gate flips, not removes

The `#if false ... #endif` block in `ParagraphTreeProjectionTests.swift` becomes `#if true ... #endif`. The block is NOT removed entirely.

**Why**: Future contributors reading the file should see the gate marker as a historical artifact — "this test class was once a RED scaffold awaiting implementation." Removing the gate erases that context. The `#if true` gate is a no-op at compile time; preserves the design history.

**Phase 1 task 2.1 closure note** (delete during Phase 5 cleanup once all sibling type refactors are GREEN): when all of `word-aligned-state-sync` Phase 1 tasks 2.1-2.12 land and the equivalent RED scaffolds for sibling types also flip to GREEN, the historical `#if true` gates can be removed in one cleanup pass. Until then, the gates document the cross-change handoff for each type.

**Alternatives considered**:

- *Remove the gate entirely*: Rejected per "preserve design history" reasoning above.
- *Use a Swift compiler condition like `#if PARAGRAPH_TREE_BACKED_AVAILABLE`*: Rejected. Adds Package.swift `swiftSettings` complexity for a one-line marker; no benefit over `#if true`.

## Risks / Trade-offs

- *che-word-mcp 271 tests fail on Equatable identity change* — Mitigation: Reader is NOT modified; existing test paragraphs go through the legacy stored-property-backed path where content equality still applies. If a test fails, investigate whether the test path actually exercises tree-backed mode (it shouldn't yet).
- *Tree-walking text getter cost* — Each `paragraph.text` access walks all `<w:r><w:t>` descendants. For a paragraph with N runs, this is O(N). For typical documents (median 5-20 runs per paragraph), the cost is negligible. For pathological cases (50+ runs), the cost is still under 1ms; che-word-mcp's MCP tool latency budget tolerates it.
- *Phase 2 setter migration breaks tree-backed callers if API surface shifts* — Mitigation: setter signatures are unchanged across Phase 1 → Phase 2. Only internal implementation swaps from "mutate tree directly" to "emit op". Public API stays identical.
- *Phase 1 task 2.1 progresses independently of word-aligned-state-sync's task list* — This change archives separately from `word-aligned-state-sync`. The `word-aligned-state-sync` task list still has 2.1 marked uncomplete; mark it done after this change archives via `spectra task done` on word-aligned-state-sync. Document this hand-off in the archive commit message.

## Migration Plan

This change does NOT require user-facing migration. Internal Paragraph storage shifts from stored-property-only to "stored-property-or-tree-backed" depending on which constructor was used. Existing callers using `Paragraph(runs:, properties:, ...)` see zero behavior change. New callers using `Paragraph(xmlNode:)` get the tree-backed mode.

ooxml-swift release: this change targets a minor version bump (e.g., v0.30.x → v0.31.0). che-word-mcp's existing pin (`from: 0.30.0`) automatically picks up the new minor version. No changes needed in che-word-mcp itself.

## Open Questions

(no open decisions — all six Decisions above are locked, ready for spec plus tasks)
