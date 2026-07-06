## ADDED Requirements

### Requirement: Tree-backed Paragraph constructor

A `Paragraph` SHALL be constructable from an existing `XmlNode` representing a `<w:p>` element via `Paragraph(xmlNode: XmlNode)`. The constructor SHALL accept any `XmlNode` whose `kind == .element` regardless of `localName`; semantic validation (asserting it is a `<w:p>` element) is a separate concern handled by callers.

The constructor SHALL co-exist with the existing legacy `Paragraph(runs:, properties:, ...)` constructor, which constructs detached paragraphs from stored properties without an underlying tree node. Both constructors SHALL produce values of the same `Paragraph` type usable interchangeably across the public API surface.

#### Scenario: tree-backed constructor accepts any element xmlNode

- **WHEN** `Paragraph(xmlNode: someWPElement)` is called with a `<w:p>` xmlNode
- **THEN** the call SHALL succeed and produce a tree-backed Paragraph value
- **AND** the wrapped xmlNode SHALL be retained as the source of truth for getter accesses

#### Scenario: legacy detached constructor still produces a usable Paragraph

- **WHEN** `Paragraph(runs: [], properties: ParagraphProperties())` is called (legacy form)
- **THEN** the call SHALL succeed and produce a detached Paragraph value with no associated xmlNode
- **AND** the resulting Paragraph SHALL be usable everywhere `Paragraph` is accepted in the public API

### Requirement: Paragraph identity derived from XmlNode stableID with libraryUUID fallback

`paragraph.id` SHALL be a computed `String?` property that, when the Paragraph is tree-backed, returns `xmlNode.stableID` if present, else `"lib:\(xmlNode.libraryUUID.uuidString)"` if `libraryUUID` is set, else `nil`. When the Paragraph is detached (no xmlNode), `paragraph.id` SHALL return `nil`.

The format of `xmlNode.stableID` (e.g., `"w14:paraId=0ABC1234"`) SHALL be preserved verbatim in `paragraph.id`. Library-generated UUIDs SHALL be prefixed `"lib:"` to differentiate them from native OOXML stable IDs at consumer level.

#### Scenario: id derives from w14:paraId attribute

- **GIVEN** an xmlNode with attribute `w14:paraId="0ABC1234"` and no other stable identifiers
- **WHEN** `paragraph.id` is accessed on a Paragraph wrapping that xmlNode
- **THEN** the returned value SHALL equal `"w14:paraId=0ABC1234"`

#### Scenario: id falls back to libraryUUID when no native stable ID exists

- **GIVEN** an xmlNode with no stable-ID attributes (no paraId, bookmarkId, w:id, r:id, textId) but `libraryUUID = UUID(uuidString: "550E8400-E29B-41D4-A716-446655440000")`
- **WHEN** `paragraph.id` is accessed
- **THEN** the returned value SHALL equal `"lib:550E8400-E29B-41D4-A716-446655440000"`

#### Scenario: detached Paragraph returns nil id

- **GIVEN** a Paragraph constructed via `Paragraph(runs: [], properties: ParagraphProperties())` (legacy detached form)
- **WHEN** `paragraph.id` is accessed
- **THEN** the returned value SHALL be `nil`

### Requirement: Tree-walking getters for text and runs

When a Paragraph is tree-backed, `paragraph.text` and `paragraph.runs` SHALL be computed properties that walk the wrapped xmlNode's `children` at every access. They SHALL NOT cache results.

`paragraph.text` SHALL concatenate the textContent of every `<w:t>` descendant in document order across all `<w:r>` children of the wrapped `<w:p>` xmlNode.

`paragraph.runs` SHALL return one `Run` value per `<w:r>` child of the wrapped xmlNode, in document order. Each returned `Run` SHALL itself be tree-backed (wrapping the corresponding `<w:r>` xmlNode) so further accessors propagate freshly.

Mutating the wrapped xmlNode's `children` directly (e.g., appending or removing a `<w:r>`) SHALL be observable through subsequent `paragraph.runs` and `paragraph.text` accesses without reconstructing the Paragraph value.

#### Scenario: text concatenates across multiple <w:r><w:t> children

- **GIVEN** an xmlNode `<w:p><w:r><w:t>Hello</w:t></w:r><w:r><w:t> </w:t></w:r><w:r><w:t>World</w:t></w:r></w:p>`
- **WHEN** `paragraph.text` is accessed
- **THEN** the returned value SHALL equal `"Hello World"`

#### Scenario: runs.count reflects current xmlNode children count

- **GIVEN** an xmlNode `<w:p>` with three `<w:r>` children
- **WHEN** `paragraph.runs.count` is accessed
- **THEN** the returned value SHALL equal `3`
- **AND** when an additional `<w:r>` child is appended directly to the xmlNode and `paragraph.runs.count` is accessed again
- **THEN** the returned value SHALL equal `4` (live view, no caching)

### Requirement: Tree-mutating setter for text (Phase 1 stub)

When a Paragraph is tree-backed, `paragraph.text = "X"` SHALL replace the wrapped xmlNode's `<w:r>` children with a single new `<w:r><w:t>X</w:t></w:r>` element constructed via `XmlNode.element(...)` factories, then call `xmlNode.markDirty()`.

This setter is a Phase 1 stub. Sibling change `word-aligned-state-sync` Phase 2 (target ooxml-swift v0.32.0) replaces this implementation with an op-log routing path that preserves run formatting via `setText` operations. Phase 1 explicitly accepts the destructive behavior (formatting on existing runs is lost) — this matches the deprecation notice on the legacy `Paragraph.text` setter.

#### Scenario: setter replaces runs with one unstyled <w:r><w:t>

- **GIVEN** a tree-backed Paragraph wrapping `<w:p><w:r><w:rPr><w:b/></w:rPr><w:t>Old</w:t></w:r></w:p>`
- **WHEN** `paragraph.text = "New"` is assigned
- **THEN** the wrapped xmlNode's children SHALL be exactly one `<w:r><w:t>New</w:t></w:r>` element
- **AND** the original bold formatting on the prior run SHALL be lost (Phase 1 stub destructive behavior)

#### Scenario: setter flips xmlNode.isDirty

- **GIVEN** a tree-backed Paragraph whose wrapped xmlNode has `isDirty == false` (clean read from disk)
- **WHEN** `paragraph.text = "X"` is assigned
- **THEN** the wrapped xmlNode's `isDirty` SHALL be `true` after the assignment

#### Scenario: subsequent text getter reflects the new value

- **GIVEN** a tree-backed Paragraph wrapping `<w:p><w:r><w:t>Old</w:t></w:r></w:p>`
- **WHEN** `paragraph.text = "New"` is assigned and then `paragraph.text` is accessed
- **THEN** the returned value SHALL equal `"New"` (the tree-walking getter sees the freshly mutated tree)

### Requirement: Identity-based equality for tree-backed Paragraphs

When both sides of `==` are tree-backed Paragraphs, the comparison SHALL be identity-based: equal if and only if both wrap the same `xmlNode` reference (per `===` reference equality on the underlying class instance).

When both sides are detached Paragraphs (no xmlNode), the comparison SHALL fall back to content equality on the legacy stored properties (auto-synthesized `Equatable` conformance applies).

When one side is tree-backed and the other detached, the comparison SHALL return `false` (mixed mode is unequal).

#### Scenario: same xmlNode reference yields equal Paragraphs

- **GIVEN** two `Paragraph` values constructed via `Paragraph(xmlNode: nodeA)` and `Paragraph(xmlNode: nodeA)` (same reference)
- **WHEN** they are compared with `==`
- **THEN** the comparison SHALL return `true`

#### Scenario: different xmlNodes with identical content are unequal

- **GIVEN** two xmlNodes `nodeA` and `nodeB` both representing `<w:p w14:paraId="X"><w:r><w:t>Hello</w:t></w:r></w:p>` (byte-identical content but distinct class instances)
- **WHEN** the corresponding Paragraphs `Paragraph(xmlNode: nodeA)` and `Paragraph(xmlNode: nodeB)` are compared with `==`
- **THEN** the comparison SHALL return `false` (identity-based, not content-based)

#### Scenario: detached Paragraphs use content equality

- **GIVEN** two detached Paragraphs `Paragraph(runs: [run1], properties: props)` and `Paragraph(runs: [run1], properties: props)` with identical stored content
- **WHEN** they are compared with `==`
- **THEN** the comparison SHALL return `true` (auto-synthesized content equality preserved for legacy mode)

### Requirement: Public Paragraph API surface preserved during refactor

The set of public methods, properties, initializers, and conformances exposed by `Paragraph` SHALL remain a strict superset after this change. Existing consumers (che-word-mcp 271 tests, macdoc CLI consumers, downstream library users) SHALL compile unchanged and exhibit identical observable behavior on legacy detached paragraphs.

The refactor adds the new tree-backed constructor and `id` accessor; it SHALL NOT remove, rename, or alter the signature of any pre-existing public API element.

#### Scenario: legacy property accessors remain functional on detached paragraphs

- **GIVEN** a Paragraph constructed via the legacy `Paragraph(runs: [...], properties: ...)` constructor
- **WHEN** any pre-existing public accessor (`paragraph.runs`, `paragraph.properties`, `paragraph.bookmarks`, `paragraph.hyperlinks`, `paragraph.semantic`, etc.) is accessed
- **THEN** the returned value SHALL match exactly what the same accessor returned before this refactor (byte-equivalent legacy behavior)

#### Scenario: che-word-mcp test suite passes against the refactored library

- **GIVEN** che-word-mcp's 271 production tests (covering the full MCP tool surface)
- **WHEN** the test suite runs against an ooxml-swift containing this change
- **THEN** zero test SHALL fail
- **AND** zero test SHALL exhibit observable output diff versus the pre-change baseline

### Requirement: ParagraphTreeProjectionTests gate flipped to enabled

The `#if false` compile gate at the top of `Tests/OOXMLSwiftTests/ParagraphTreeProjectionTests.swift` (introduced in commit `8d3dd49` to allow the test target to build before this implementation existed) SHALL be flipped to `#if true` (or the gate SHALL be removed entirely with the surrounding header comment retained as historical context).

All 9 tests inside `ParagraphTreeProjectionTests` SHALL run and pass GREEN against the new Paragraph implementation.

#### Scenario: gate flip enables compilation

- **WHEN** this change lands and the test target is built
- **THEN** `ParagraphTreeProjectionTests.swift` SHALL compile (`#if true` block reached) without the previous "extra argument 'xmlNode' in call" error
- **AND** `swift test --filter ParagraphTreeProjectionTests` SHALL discover all 9 test methods

#### Scenario: 9 RED scaffold tests transition to GREEN

- **WHEN** `swift test --filter ParagraphTreeProjectionTests` runs against this change
- **THEN** all 9 test methods (`testTreeBackedParagraph_constructorTakesXmlNode`, `testTreeBackedParagraph_idDerivesFromW14ParaId`, `testTreeBackedParagraph_idFallsBackToLibraryUUID`, `testTreeBackedParagraph_textGetterReadsFromTreeChildren`, `testTreeBackedParagraph_runsCountReflectsTreeChildren`, `testTreeBackedParagraph_textSetterMutatesTree`, `testTreeBackedParagraph_setterMarksNodeDirty`, `testLegacyParagraph_detachedConstructorStillCompiles`, `testTreeBackedParagraph_identityEqualityNotContentEquality`) SHALL pass
- **AND** the test runner SHALL report 9 passing tests with 0 failures
