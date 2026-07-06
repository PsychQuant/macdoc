## ADDED Requirements

### Requirement: Tree-backed sibling-type constructors

`Run`, `Table`, `TableRow`, `TableCell`, and `SectionProperties` SHALL each be constructable from an existing `XmlNode` representing a `<w:r>`, `<w:tbl>`, `<w:tr>`, `<w:tc>`, or `<w:sectPr>` element respectively, via a `Type(xmlNode: XmlNode)` constructor on each type.

The constructors SHALL accept any `XmlNode` whose `kind == .element` regardless of `localName`; semantic validation (asserting the element is a `<w:r>`, etc.) is a separate concern handled by callers.

Each constructor SHALL co-exist with the existing legacy constructors on its type:
- `Run(text:, properties:)`
- `Table(rows:, properties:)` and `Table(rowCount:, columnCount:, properties:)`
- `TableRow(cells:, properties:)`
- `TableCell()` and `TableCell(paragraphs:, properties:)`
- `SectionProperties(...)` (the existing 7-parameter convenience initializer)

Both constructor families SHALL produce values of the same type usable interchangeably across the public API surface.

#### Scenario: tree-backed Run constructor accepts any element xmlNode

- **WHEN** `Run(xmlNode: someWRElement)` is called with a `<w:r>` xmlNode
- **THEN** the call SHALL succeed and produce a tree-backed Run value
- **AND** the wrapped xmlNode SHALL be retained as the source of truth for getter accesses

#### Scenario: tree-backed Table constructor accepts a wtbl element

- **WHEN** `Table(xmlNode: someWTblElement)` is called with a `<w:tbl>` xmlNode
- **THEN** the call SHALL succeed and produce a tree-backed Table value

#### Scenario: tree-backed TableCell constructor accepts a wtc element

- **WHEN** `TableCell(xmlNode: someWTcElement)` is called with a `<w:tc>` xmlNode
- **THEN** the call SHALL succeed and produce a tree-backed TableCell value

#### Scenario: tree-backed SectionProperties constructor accepts a wsectPr element

- **WHEN** `SectionProperties(xmlNode: someWSectPrElement)` is called with a `<w:sectPr>` xmlNode
- **THEN** the call SHALL succeed and produce a tree-backed SectionProperties value

#### Scenario: legacy detached constructors still produce usable values

- **WHEN** `Run(text: "x", properties: RunProperties())` is called (legacy form)
- **THEN** the call SHALL succeed and produce a detached Run value with no associated xmlNode
- **AND** the resulting Run SHALL be usable everywhere `Run` is accepted in the public API

### Requirement: Sibling-type identity derived from XmlNode stableID with libraryUUID fallback

`run.id`, `table.id`, `tableRow.id`, `tableCell.id`, and `sectionProperties.id` SHALL each be a computed `String?` property that, when the value is tree-backed, returns `xmlNode.stableID` if present, else `"lib:\(xmlNode.libraryUUID.uuidString)"` if `libraryUUID` is set, else `nil`. When the value is detached (no xmlNode), `id` SHALL return `nil`.

The format of `xmlNode.stableID` SHALL be preserved verbatim. Library-generated UUIDs SHALL be prefixed `"lib:"` to differentiate them from native OOXML stable IDs at consumer level.

#### Scenario: Run id falls back to libraryUUID when no native stable ID exists

- **GIVEN** a `<w:r>` xmlNode with no stable-ID attributes but `libraryUUID = UUID(uuidString: "550E8400-E29B-41D4-A716-446655440000")`
- **WHEN** `run.id` is accessed on `Run(xmlNode: thatNode)`
- **THEN** the returned value SHALL equal `"lib:550E8400-E29B-41D4-A716-446655440000"`

#### Scenario: detached typed values return nil id

- **GIVEN** a detached value of any sibling type (`Run(text: "x")`, `Table()`, `TableRow()`, `TableCell()`, `SectionProperties()`)
- **WHEN** `id` is accessed
- **THEN** the returned value SHALL be `nil`

### Requirement: Tree-walking primary content getters

When the value is tree-backed, the **primary content accessor** of each sibling type SHALL be a computed property that walks the wrapped xmlNode's children at every access. Computed values SHALL NOT cache results.

The primary content accessor of each type:

- `Run.text` — concatenates `textContent` of every `<w:t>` direct child of the wrapped `<w:r>` xmlNode, in document order
- `Table.rows` — returns one `TableRow(xmlNode:)` per `<w:tr>` direct child of the wrapped `<w:tbl>` xmlNode, in document order
- `TableRow.cells` — returns one `TableCell(xmlNode:)` per `<w:tc>` direct child of the wrapped `<w:tr>` xmlNode, in document order
- `TableCell.paragraphs` — returns one `Paragraph(xmlNode:)` per `<w:p>` direct child of the wrapped `<w:tc>` xmlNode, in document order
- `TableCell.nestedTables` — returns one `Table(xmlNode:)` per `<w:tbl>` direct child of the wrapped `<w:tc>` xmlNode, in document order

Mutating the wrapped xmlNode's children directly (e.g., appending or removing a child) SHALL be observable through subsequent primary-content-accessor reads without reconstructing the value.

When the value is detached, the same accessors SHALL return the legacy stored property values.

#### Scenario: Run.text concatenates across multiple <w:t> direct children

- **GIVEN** a `<w:r>` xmlNode with three direct `<w:t>` children whose text content is `"Hello"`, `" "`, `"World"` respectively
- **WHEN** `run.text` is accessed on `Run(xmlNode: thatNode)`
- **THEN** the returned value SHALL equal `"Hello World"`

#### Scenario: Table.rows reflects current xmlNode children count

- **GIVEN** a `<w:tbl>` xmlNode with three `<w:tr>` children
- **WHEN** `table.rows.count` is accessed on `Table(xmlNode: thatNode)`
- **THEN** the returned value SHALL equal `3`
- **AND** when an additional `<w:tr>` child is appended directly to the xmlNode and `table.rows.count` is accessed again
- **THEN** the returned value SHALL equal `4` (live view, no caching)

#### Scenario: TableCell.paragraphs returns tree-backed Paragraphs

- **GIVEN** a `<w:tc>` xmlNode with two `<w:p>` children
- **WHEN** `cell.paragraphs` is accessed on `TableCell(xmlNode: thatNode)`
- **THEN** the returned array SHALL have count 2
- **AND** each returned `Paragraph` SHALL itself be tree-backed (`paragraph.id != nil` when the underlying `<w:p>` carries a stable ID)

### Requirement: SectionProperties Phase 1 stub for structured fields

A tree-backed `SectionProperties` value SHALL provide identity (via `id`), equality (via the identity-based `Equatable`), and the `xmlNode` reference. It SHALL NOT auto-populate the 12+ structured fields (`pageSize`, `pageMargins`, `orientation`, `columns`, `docGrid`, `headerReferences`, `footerReferences`, `lineNumbers`, `verticalAlignment`, `pageNumberFormat`, `pageNumberStartValue`, `titlePageDistinct`, `sectionBreakType`) from the wrapped `<w:sectPr>` xmlNode in this release.

When a caller reads any structured field on a tree-backed `SectionProperties`, the returned value SHALL be the default that `SectionProperties()` would return for that field.

This is a **Phase 1 stub**. A separate change (`section-properties-tree-walking-impl`, follow-up to `word-aligned-state-sync` Phase 1 task 2.4) will add full tree-walking parsers for the 12+ structured fields. Reader continues to produce detached `SectionProperties` values (with structured fields populated by the existing parser) in this release, so all existing call sites that go through Reader are unaffected.

#### Scenario: tree-backed SectionProperties returns default structured fields

- **GIVEN** a `<w:sectPr>` xmlNode with a `<w:pgSz w:w="12240" w:h="15840"/>` child
- **WHEN** `sectionProperties.pageSize` is accessed on `SectionProperties(xmlNode: thatNode)`
- **THEN** the returned value SHALL equal `PageSize.letter` (the `SectionProperties()` default), NOT a value parsed from the xmlNode child

#### Scenario: tree-backed SectionProperties still derives id

- **GIVEN** a `<w:sectPr>` xmlNode with `libraryUUID = UUID(uuidString: "AABBCCDD-1234-5678-9999-FFEEDDCCBBAA")`
- **WHEN** `sectionProperties.id` is accessed
- **THEN** the returned value SHALL equal `"lib:AABBCCDD-1234-5678-9999-FFEEDDCCBBAA"`

### Requirement: Tree-mutating Run text setter (Phase 1 stub)

When a `Run` is tree-backed, `run.text = "X"` SHALL replace the wrapped xmlNode's `<w:t>` children with a single new `<w:t>X</w:t>` element constructed via `XmlNode.element(...)` factories, then call `xmlNode.markDirty()`.

This setter is a Phase 1 stub. Phase 2 of `word-aligned-state-sync` (target ooxml-swift v0.32.0) replaces this implementation with op-log routing that preserves run formatting and `rawElements` siblings via `setText` operations. Phase 1 explicitly accepts the destructive behavior (any pre-existing `<w:t>` siblings are dropped).

When the `Run` is detached, `run.text = "X"` SHALL update the legacy stored `text` field directly (matches pre-v0.31.1 behavior).

#### Scenario: Run.text setter replaces wt children and marks dirty

- **GIVEN** a tree-backed Run wrapping `<w:r><w:t>Old</w:t></w:r>` whose `xmlNode.isDirty == false`
- **WHEN** `run.text = "New"` is assigned
- **THEN** the wrapped xmlNode's children SHALL contain exactly one `<w:t>New</w:t>` element among any non-`<w:t>` siblings preserved
- **AND** the wrapped xmlNode's `isDirty` SHALL be `true`
- **AND** subsequent `run.text` reads SHALL return `"New"`

### Requirement: Identity-based equality for tree-backed sibling types

When both sides of `==` are tree-backed values of the same sibling type (`Run`, `Table`, `TableRow`, `TableCell`, or `SectionProperties`), the comparison SHALL be identity-based: equal if and only if both wrap the same `xmlNode` reference (per `===` reference equality on the underlying class instance).

When both sides are detached values of the same type, the comparison SHALL fall back to content equality on the legacy stored properties.

When one side is tree-backed and the other detached, the comparison SHALL return `false`.

#### Scenario: same xmlNode reference yields equal tree-backed Runs

- **GIVEN** two `Run` values constructed via `Run(xmlNode: nodeA)` twice (same reference)
- **WHEN** they are compared with `==`
- **THEN** the comparison SHALL return `true`

#### Scenario: different xmlNodes with identical content are unequal

- **GIVEN** two `<w:r>` xmlNodes `nodeA` and `nodeB` with byte-identical content but distinct class instances
- **WHEN** the corresponding `Run(xmlNode: nodeA)` and `Run(xmlNode: nodeB)` are compared with `==`
- **THEN** the comparison SHALL return `false` (identity-based, not content-based)

#### Scenario: detached values use content equality

- **GIVEN** two detached `TableCell` values `TableCell(paragraphs: [p1])` and `TableCell(paragraphs: [p1])` with identical stored content
- **WHEN** they are compared with `==`
- **THEN** the comparison SHALL return `true` (content equality preserved for legacy mode)

### Requirement: Public sibling-type API surface preserved during refactor

The set of public methods, properties, initializers, and conformances exposed by `Run`, `Table`, `TableRow`, `TableCell`, and `SectionProperties` SHALL remain a strict superset after this change. Existing consumers (che-word-mcp 297 production tests, macdoc CLI consumers, downstream library users) SHALL compile unchanged and exhibit identical observable behavior on legacy detached values.

The refactor adds the new tree-backed constructors, `id` accessors, and the mode-aware `Equatable` implementations; it SHALL NOT remove, rename, or alter the signature of any pre-existing public API element on these types.

#### Scenario: legacy property accessors remain functional on detached values

- **GIVEN** a `Table` constructed via the legacy `Table(rowCount: 3, columnCount: 2)` constructor
- **WHEN** any pre-existing public accessor (`table.rows`, `table.properties`, `table.conditionalStyles`, `table.tableIndent`, `table.explicitLayout`) is accessed
- **THEN** the returned value SHALL match exactly what the same accessor returned before this refactor (byte-equivalent legacy behavior)

#### Scenario: che-word-mcp test suite passes against the refactored library

- **GIVEN** che-word-mcp's 297 production tests (covering the full MCP tool surface)
- **WHEN** the test suite runs against an ooxml-swift containing this change (with `Package.resolved` bumped to v0.31.1)
- **THEN** zero test SHALL fail

### Requirement: Sibling-type RED scaffolds land GREEN

Three new test files SHALL be added under `packages/ooxml-swift/Tests/OOXMLSwiftTests/`:

- `RunTreeProjectionTests.swift` — pins `Run(xmlNode:)`, `run.id`, tree-walking `text` getter, tree-mutating `text` setter, dirty-flag flip, identity equality
- `TableTreeProjectionTests.swift` — pins `Table(xmlNode:)`, `TableRow(xmlNode:)`, `TableCell(xmlNode:)`, the corresponding `id` accessors, tree-walking `rows`/`cells`/`paragraphs` getters, identity equality
- `SectionPropertiesTreeProjectionTests.swift` — pins `SectionProperties(xmlNode:)`, `id` derivation, identity equality, and the Phase 1 stub behavior (structured fields return defaults)

These tests SHALL pass GREEN against the new implementation when this change applies.

#### Scenario: all sibling-type tree projection tests pass GREEN

- **WHEN** `swift test --filter RunTreeProjectionTests` runs against this change
- **THEN** every test method SHALL pass
- **AND** the same SHALL hold for `TableTreeProjectionTests` and `SectionPropertiesTreeProjectionTests`
