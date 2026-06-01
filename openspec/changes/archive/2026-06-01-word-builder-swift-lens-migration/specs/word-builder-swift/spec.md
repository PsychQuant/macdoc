## REMOVED Requirements

### Requirement: Public API mirrors docx.js top-level types

**Reason**: v1.0.0 abandons the docx.js parallel. The lens-model surface (LensDocument + ooxml-swift's Edit protocol) is a fundamentally different abstraction from docx.js's struct serialization. Pretending to mirror docx.js when the underlying semantics are event-sourced lens transformations would mislead callers.

**Migration**: Callers of the docx.js-style API (`Document(sections: [Section(children: [Paragraph(...)])])`) replace top-level construction with `LensDocument()` and apply `WordEdit.applyInsertParagraph` (and related cases). See the new "LensDocument exposes a five-method authoring surface" Requirement below. Examples in `examples/*.swift` are rewritten in the same change.

### Requirement: TextRun accepts a bare String and an options-style init

**Reason**: TextRun is removed in v1.0.0. The lens-model surface uses ooxml-swift's `OOXMLEdit.setText` / `WordEdit.applyInsertParagraph` Edit cases, which take String arguments directly. No options-style init survives.

**Migration**: `TextRun("Hello")` → embed the text in the relevant Edit case (`WordEdit.applyInsertParagraph(after: ref, content: "Hello")`). Inline formatting via `TextRun(bold: true)` migrates to chained Edits like `WordEdit.applyBold(range:)` after the run is inserted.

### Requirement: Paragraph accepts heading, alignment, and children as init parameters with defaults

**Reason**: The Paragraph type is removed in v1.0.0. Paragraphs are constructed via `WordEdit.applyInsertParagraph` (which produces a paragraph) and styled via subsequent Edits.

**Migration**: `Paragraph(children: [...], heading: .heading1)` → `apply(WordEdit.applyInsertParagraph(after: ref, content: text))` then `apply(OOXMLEdit.setParagraphStyle(target: id, styleId: "Heading1"))`. Alignment migrates via the same chained-apply pattern (Reducer support for setParagraphStyle ships per ooxml-swift#71 Phase 2c; alignment-specific Reducer cases are tracked there).

### Requirement: Table accepts rows of cells and renders to OOXML table

**Reason**: The Table type is removed in v1.0.0. Table mutations migrate to `OOXMLEdit` table cases (insertTable, removeTable, setCellText) which are tracked in ooxml-swift#71 Phase 2c. v1.0.0 ships with the table-mutation Edits visible at the protocol level but currently surfacing `EditError.notImplemented` when applied — documented in `examples/03-table-3x3.swift` and README's Architecture section.

**Migration**: `Table(rows: [TableRow(...)])` callers (currently zero) would, when Phase 2c table cases ship, use `apply(OOXMLEdit.insertTable(at:, table:))` followed by per-cell `setCellText` Edits. Until Phase 2c table support ships, table authoring is not supported in v1.0.0.

### Requirement: Document accepts a sections array and Phase 1 emits only the first section

**Reason**: The Document type and Section type are removed in v1.0.0. The top-level handle is `LensDocument`, and sections are managed via the underlying `OOXMLSwift.WordDocument.sectionProperties` (accessible through the wrapper) or through future section-management Edit cases.

**Migration**: `Document(sections: [Section(children: [...])])` → `LensDocument()` + chained `apply(...)` calls. Multi-section authoring is deferred to future Edit cases tracked in ooxml-swift Phase 2c follow-ups.

### Requirement: Packer provides toData, toFile, and toBase64String static methods

**Reason**: The `Packer` enum and all its static methods are removed in v1.0.0. Serialization is a property of `LensDocument` (via `emit(to:)`), not a separate utility namespace. Removing Packer enforces the lens-model invariant that the document handle owns its lifecycle (read → mutate → emit).

**Migration**: `Packer.toFile(doc, url:)` → `doc.emit(to: url)`. `Packer.toData(doc)` (raw bytes) is intentionally NOT provided as a public API in v1.0.0; if needed in v1.1.x, expose via `LensDocument.emitData()` or similar. `Packer.toBase64String(doc)` is similarly not exposed; callers can `emit(to: tempURL)` and base64-encode the file contents externally.

### Requirement: HeadingLevel and AlignmentType enums mirror docx.js values

**Reason**: The standalone HeadingLevel and AlignmentType enums in word-builder-swift's Enums.swift are removed. Style and alignment are now expressed via OOXMLEdit / WordEdit cases (e.g., `OOXMLEdit.setParagraphStyle(target:, styleId: "Heading1")`).

**Migration**: `Paragraph(heading: .heading1)` → `apply(OOXMLEdit.setParagraphStyle(target: paragraphID, styleId: "Heading1"))`. `Paragraph(alignment: .center)` migrates to whatever alignment Edit case ships in ooxml-swift Phase 2c (currently tracked).

### Requirement: Version number mirrors docx.js minor version

**Reason**: v1.0.0 abandons the docx.js parallel; the version number no longer mirrors docx.js. word-builder-swift's versioning follows standard semver from v1.0.0 onward, decoupled from docx.js release cadence.

**Migration**: Consumers pinning `word-builder-swift` via `.upToNextMinor(from: "0.9.x")` see clear semver-major-bump alerts at next `swift package update`. The 0.9 → 1.0 jump IS the breaking signal.

### Requirement: reference docx-js is read-only, no code copying

**Reason**: The reference/docx-js submodule's role as the spec source-of-truth is removed. word-builder-swift v1.0.0's spec is sourced from this Spectra change + the ooxml-swift Edit-algebra contract. `reference/docx-js/` may still exist in the repo for historical context but is no longer normative.

**Migration**: No caller action; this Requirement was a meta-requirement about spec governance, not a runtime contract.

### Requirement: OOXMLSwift.DocxWriter exposes writeData for in-memory output

**Reason**: This is an OOXMLSwift requirement, not a word-builder-swift requirement; it was included in v0.9.0's spec because Packer.toData depended on it. With Packer removed in v1.0.0, the cross-reference is no longer this spec's concern. OOXMLSwift's spec independently guarantees DocxWriter.writeData.

**Migration**: No caller action. `LensDocument.emit(to:)` continues to use `OOXMLSwift.DocxWriter.writeData(...)` internally, but that's an implementation detail not exposed in word-builder-swift's spec.

### Requirement: Phase 1 ships five worked examples translated from docx.js README

**Reason**: Examples are rewritten in this change to use LensDocument + Edit. The new examples no longer translate docx.js README snippets; instead they demonstrate the lens-model authoring flow. File numbering is preserved (01–05) for git-history continuity, but content is rewritten.

**Migration**: See the new "Examples demonstrate the lens-model authoring flow" Requirement below.

## ADDED Requirements

### Requirement: WordBuilderSwift module re-exports the OOXMLSwift Edit-algebra surface

The `WordBuilderSwift` module SHALL re-export `OOXMLSwift` via `@_exported import` so that callers writing `import WordBuilderSwift` have access to `Edit`, `OOXMLEdit`, `WordEdit`, `EditError`, `WordRange`, `ParagraphRef`, and related Edit-algebra types without a second import statement.

This re-export aligns with `ooxml-edit-isomorphism-foundation` ADR-009's "downstream-rerouting" framing: word-builder-swift is a Layer 3 front-end to the foundation, not a parallel algebra. The Edit protocol is the single source of truth.

#### Scenario: Importing WordBuilderSwift surfaces the Edit protocol

- **WHEN** a Swift file writes `import WordBuilderSwift` and references `Edit`, `OOXMLEdit.insertParagraph`, `WordEdit.applyBold`, or `EditError`
- **THEN** the symbols MUST resolve without a separate `import OOXMLSwift` statement

#### Scenario: WordBuilderSwift does NOT define a separate WordBuilderEdit protocol

- **WHEN** a caller searches the `WordBuilderSwift` module for a protocol named `WordBuilderEdit`, `WordBuilderEditAlgebra`, or similar
- **THEN** no such protocol MUST exist; the only Edit-algebra surface is the re-exported `OOXMLSwift.Edit` protocol

### Requirement: LensDocument is the top-level document handle

The `WordBuilderSwift` module SHALL provide a `public struct LensDocument` that wraps a private `OOXMLSwift.WordDocument` field. LensDocument SHALL be the only public top-level type used to construct, mutate, and emit `.docx` files via word-builder-swift.

LensDocument SHALL be a value type (`struct`, not `class`). Apply operations SHALL be immutable: each `apply(_:)` call returns a new `LensDocument` instance; the input LensDocument is not mutated.

#### Scenario: LensDocument is a value type

- **WHEN** a caller assigns `let a = LensDocument(); let b = a` and then calls `try b.apply(someEdit)`
- **THEN** `a` MUST be unchanged; the apply mutates only the copy stored in `b`'s next binding

#### Scenario: LensDocument has no public access to its inner WordDocument

- **WHEN** a caller writes `LensDocument().inner` from outside the WordBuilderSwift module
- **THEN** the access MUST fail at compile time (`inner` is `private`)

### Requirement: LensDocument exposes a five-method authoring surface

`LensDocument` SHALL expose the following public methods and no others:

```swift
public init()
public init(reading url: URL) throws
public func apply(_ edit: any Edit) throws -> LensDocument
public func apply<S: Sequence>(_ edits: S) throws -> LensDocument where S.Element == any Edit
public func emit(to url: URL) throws
```

No other public methods (e.g., `bold(range:)`, `insertParagraph(after:content:)`, `Packer`-style conveniences) SHALL be added in v1.0.0. The Edit protocol IS the authoring vocabulary.

#### Scenario: Empty document construction

- **WHEN** a caller writes `let doc = LensDocument()`
- **THEN** `doc` MUST be a valid LensDocument whose underlying `OOXMLSwift.WordDocument` is initialized via `OOXMLSwift.WordDocument()` (empty doc)

#### Scenario: Reading an existing .docx

- **WHEN** a caller writes `let doc = try LensDocument(reading: url)` and `url` points to a valid `.docx` file
- **THEN** the construction MUST succeed and `doc`'s underlying WordDocument MUST contain the parsed xmlTrees from that file (delegated to `OOXMLSwift.DocxReader.read(from:)`)

#### Scenario: Reading a missing or invalid file throws

- **WHEN** a caller writes `let doc = try LensDocument(reading: badURL)` and `badURL` is missing or not a valid `.docx` archive
- **THEN** the call MUST throw the error propagated from `OOXMLSwift.DocxReader.read(from:)` (no swallowing or wrapping with a new error type in word-builder-swift)

#### Scenario: Applying a single Edit returns a new LensDocument

- **WHEN** a caller writes `let after = try doc.apply(WordEdit.applyInsertParagraph(after: ref, content: "Hi"))` against a valid `ref`
- **THEN** the call MUST return a new LensDocument whose xmlTrees reflect the inserted paragraph

#### Scenario: Applying a sequence of Edits chains them in order

- **WHEN** a caller writes `let final = try doc.apply([edit1, edit2, edit3] as [any Edit])`
- **THEN** the call MUST apply `edit1`, then `edit2`, then `edit3`, returning a single new LensDocument equivalent to `try doc.apply(edit1).apply(edit2).apply(edit3)`

#### Scenario: Emitting to disk writes a .docx file

- **WHEN** a caller writes `try doc.emit(to: outURL)` against an empty or non-existent file path with writable parent directory
- **THEN** the call MUST write a valid `.docx` archive to `outURL` via `OOXMLSwift.DocxWriter.writeData(...)` followed by a file write

#### Scenario: Emit overwrites an existing file at the URL

- **WHEN** a caller writes `try doc.emit(to: existingURL)` and `existingURL` already has a file
- **THEN** the existing file MUST be removed first; the new `.docx` bytes MUST be written in its place

### Requirement: Edit-protocol failure modes propagate unchanged

When LensDocument's `apply(_:)` invokes `OOXMLSwift.WordDocument.apply(_:)` and the underlying Edit fails (e.g., target ElementID doesn't resolve, Reducer Phase 2c case not yet implemented), the resulting error SHALL propagate up unchanged. word-builder-swift SHALL NOT wrap, swallow, or rebrand errors from the Edit-algebra runtime.

#### Scenario: notImplemented error surfaces to caller

- **WHEN** a caller writes `try doc.apply(someEdit)` and the lowered Operation hits an unimplemented Phase 2c Reducer case
- **THEN** the call MUST throw `EditError.operationLogFailure(underlying:)` (or `EditError.notImplemented` if the OOXMLEdit's `operations()` itself stubs) with the underlying message intact

#### Scenario: pathNotFound surfaces to caller

- **WHEN** a caller writes `try doc.apply(OOXMLEdit.removeParagraph(target: badID))` where `badID` doesn't resolve in `doc.inner`
- **THEN** the call MUST throw the error per the Edit protocol's documented PHASED behavior (currently `EditError.operationLogFailure(underlying:)` wrapping the Reducer's elementNotFound; in a later phase, `EditError.pathNotFound(badID)`)

### Requirement: Examples demonstrate the lens-model authoring flow

The `packages/word-builder-swift/examples/` directory SHALL contain at least five example Swift files (numbered 01–05, preserving file numbering from v0.9.0 for git-history continuity) that demonstrate the LensDocument + Edit authoring flow.

Each example SHALL be a self-contained Swift program that constructs a LensDocument, applies one or more Edits, and emits to a URL.

#### Scenario: Hello-world example uses LensDocument

- **WHEN** a reader opens `examples/01-hello-world.swift`
- **THEN** the file MUST construct a LensDocument via `LensDocument()`, apply at least one Edit (e.g., `WordEdit.applyInsertParagraph`), and call `emit(to:)`

#### Scenario: Examples that exercise Phase-2c-pending Edits document the gap

- **WHEN** an example (e.g., `examples/03-table-3x3.swift`) uses an Edit whose Reducer support hasn't shipped yet (e.g., table-mutation cases tracked in ooxml-swift#71 Phase 2c)
- **THEN** the example MUST include an explanatory comment naming the issue/tracker AND the example MAY include a `try?` to demonstrate the call shape without compiling a runtime failure into a published example program

### Requirement: README documents the migration and architecture

The `packages/word-builder-swift/README.md` SHALL contain:

1. A "Migration from 0.9.0" section with a table mapping at least three v0.9.0 idioms (`Document(sections:)`, `Packer.toFile(doc, url:)`, `Packer.toData(doc)`) to v1.0.0 equivalents (`LensDocument()`, `doc.emit(to:)`, "follow-up").
2. An "Architecture" section explaining that LensDocument wraps `OOXMLSwift.WordDocument`, the Edit protocol is reused from `ooxml-swift`, and Phase 2c Reducer coverage gaps surface as runtime errors.

#### Scenario: Migration table contains all three core mappings

- **WHEN** a reader opens README.md and finds the "Migration from 0.9.0" section
- **THEN** the table MUST contain rows for `Document(sections:)` → `LensDocument()`-pattern, `Packer.toFile(...)` → `emit(to:)`, and `Packer.toData(_)` → "see follow-up" or explicit note that raw-bytes access is not exposed in v1.0.0

#### Scenario: Architecture section cites ooxml-swift dependency

- **WHEN** a reader opens README.md and finds the "Architecture" section
- **THEN** the section MUST name `OOXMLSwift.WordDocument` as the wrapped type, name the Edit protocol as the authoring vocabulary, and reference where Phase 2c Reducer gaps are tracked (ooxml-swift#71)
