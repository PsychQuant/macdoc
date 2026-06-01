# word-builder-swift Specification

## Purpose

Fluent Swift API in the `word-builder-swift` package for programmatically constructing `.docx` files, whose public surface is a 1:1 mirror of `npm docx` (dolanmiu/docx) 9.6.x. Developers familiar with `docx.js` in Node.js can translate code line-by-line to Swift using the same class names (`Document`, `Section`, `Paragraph`, `TextRun`, `Table`, `Packer`, `HeadingLevel`, `AlignmentType`) and option shapes. `word-builder-swift` is the docx-writing sibling of the `markdown-builder` capability; it delegates zip/XML emission to `OOXMLSwift.DocxWriter.writeData` but does not itself read existing `.docx` files.

## Requirements

### Requirement: WordBuilderSwift module re-exports the OOXMLSwift Edit-algebra surface

The `WordBuilderSwift` module SHALL re-export `OOXMLSwift` via `@_exported import` so that callers writing `import WordBuilderSwift` have access to `Edit`, `OOXMLEdit`, `WordEdit`, `EditError`, `WordRange`, `ParagraphRef`, and related Edit-algebra types without a second import statement.

This re-export aligns with `ooxml-edit-isomorphism-foundation` ADR-009's "downstream-rerouting" framing: word-builder-swift is a Layer 3 front-end to the foundation, not a parallel algebra. The Edit protocol is the single source of truth.

#### Scenario: Importing WordBuilderSwift surfaces the Edit protocol

- **WHEN** a Swift file writes `import WordBuilderSwift` and references `Edit`, `OOXMLEdit.insertParagraph`, `WordEdit.applyBold`, or `EditError`
- **THEN** the symbols MUST resolve without a separate `import OOXMLSwift` statement

#### Scenario: WordBuilderSwift does NOT define a separate WordBuilderEdit protocol

- **WHEN** a caller searches the `WordBuilderSwift` module for a protocol named `WordBuilderEdit`, `WordBuilderEditAlgebra`, or similar
- **THEN** no such protocol MUST exist; the only Edit-algebra surface is the re-exported `OOXMLSwift.Edit` protocol


<!-- @trace
source: word-builder-swift-lens-migration
updated: 2026-06-01
code:
  - Package.resolved
  - Package.swift
-->

---
### Requirement: LensDocument is the top-level document handle

The `WordBuilderSwift` module SHALL provide a `public struct LensDocument` that wraps a private `OOXMLSwift.WordDocument` field. LensDocument SHALL be the only public top-level type used to construct, mutate, and emit `.docx` files via word-builder-swift.

LensDocument SHALL be a value type (`struct`, not `class`). Apply operations SHALL be immutable: each `apply(_:)` call returns a new `LensDocument` instance; the input LensDocument is not mutated.

#### Scenario: LensDocument is a value type

- **WHEN** a caller assigns `let a = LensDocument(); let b = a` and then calls `try b.apply(someEdit)`
- **THEN** `a` MUST be unchanged; the apply mutates only the copy stored in `b`'s next binding

#### Scenario: LensDocument has no public access to its inner WordDocument

- **WHEN** a caller writes `LensDocument().inner` from outside the WordBuilderSwift module
- **THEN** the access MUST fail at compile time (`inner` is `private`)


<!-- @trace
source: word-builder-swift-lens-migration
updated: 2026-06-01
code:
  - Package.resolved
  - Package.swift
-->

---
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


<!-- @trace
source: word-builder-swift-lens-migration
updated: 2026-06-01
code:
  - Package.resolved
  - Package.swift
-->

---
### Requirement: Edit-protocol failure modes propagate unchanged

When LensDocument's `apply(_:)` invokes `OOXMLSwift.WordDocument.apply(_:)` and the underlying Edit fails (e.g., target ElementID doesn't resolve, Reducer Phase 2c case not yet implemented), the resulting error SHALL propagate up unchanged. word-builder-swift SHALL NOT wrap, swallow, or rebrand errors from the Edit-algebra runtime.

#### Scenario: notImplemented error surfaces to caller

- **WHEN** a caller writes `try doc.apply(someEdit)` and the lowered Operation hits an unimplemented Phase 2c Reducer case
- **THEN** the call MUST throw `EditError.operationLogFailure(underlying:)` (or `EditError.notImplemented` if the OOXMLEdit's `operations()` itself stubs) with the underlying message intact

#### Scenario: pathNotFound surfaces to caller

- **WHEN** a caller writes `try doc.apply(OOXMLEdit.removeParagraph(target: badID))` where `badID` doesn't resolve in `doc.inner`
- **THEN** the call MUST throw the error per the Edit protocol's documented PHASED behavior (currently `EditError.operationLogFailure(underlying:)` wrapping the Reducer's elementNotFound; in a later phase, `EditError.pathNotFound(badID)`)


<!-- @trace
source: word-builder-swift-lens-migration
updated: 2026-06-01
code:
  - Package.resolved
  - Package.swift
-->

---
### Requirement: Examples demonstrate the lens-model authoring flow

The `packages/word-builder-swift/examples/` directory SHALL contain at least five example Swift files (numbered 01–05, preserving file numbering from v0.9.0 for git-history continuity) that demonstrate the LensDocument + Edit authoring flow.

Each example SHALL be a self-contained Swift program that constructs a LensDocument, applies one or more Edits, and emits to a URL.

#### Scenario: Hello-world example uses LensDocument

- **WHEN** a reader opens `examples/01-hello-world.swift`
- **THEN** the file MUST construct a LensDocument via `LensDocument()`, apply at least one Edit (e.g., `WordEdit.applyInsertParagraph`), and call `emit(to:)`

#### Scenario: Examples that exercise Phase-2c-pending Edits document the gap

- **WHEN** an example (e.g., `examples/03-table-3x3.swift`) uses an Edit whose Reducer support hasn't shipped yet (e.g., table-mutation cases tracked in ooxml-swift#71 Phase 2c)
- **THEN** the example MUST include an explanatory comment naming the issue/tracker AND the example MAY include a `try?` to demonstrate the call shape without compiling a runtime failure into a published example program


<!-- @trace
source: word-builder-swift-lens-migration
updated: 2026-06-01
code:
  - Package.resolved
  - Package.swift
-->

---
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

<!-- @trace
source: word-builder-swift-lens-migration
updated: 2026-06-01
code:
  - Package.resolved
  - Package.swift
-->

---
### Requirement: Layer 3 consumers compose multi-step authoring flows via the re-exported Edit surface

`word-builder-swift` SHALL support the Layer 3 consumer pattern (per `ooxml-edit-isomorphism-foundation` ADR-009) wherein a consumer package depends on `WordBuilderSwift`, uses a single `import WordBuilderSwift` to access `LensDocument`, `Edit`, `OOXMLEdit`, `WordEdit`, `WordRange`, `ParagraphRef`, `EditError`, plus the foundation types (`WordDocument`, `DocxReader`, `DocxWriter`), and composes multi-step authoring workflows by chaining `LensDocument.apply([Edit])` calls. The `word-builder-swift` capability SHALL NOT add any new public API to support this pattern; the existing five-method `LensDocument` surface plus the `@_exported import OOXMLSwift` re-export already cover it. This requirement codifies the contract so that downstream Layer 3/4 capabilities (e.g., `docx-workflow-cli`, future R-emitter capabilities) can cite a normative anchor when describing their dependency.

#### Scenario: Layer 3 consumer reads, applies a sequence, and emits

- **GIVEN** a third-party Swift package that depends on `word-builder-swift` v1.0.0 and writes `import WordBuilderSwift`
- **WHEN** the consumer code constructs a sequence of `WordEdit` / `OOXMLEdit` cases and calls `try LensDocument(reading: url).apply(edits as [any Edit]).emit(to: outURL)` where `edits` is a `[any Edit]`
- **THEN** the call MUST type-check and execute against the v1.0.0 surface without requiring `import OOXMLSwift` separately, AND the resulting `.docx` MUST contain the cumulative effect of all runtime-functional Edits applied in order

#### Scenario: Layer 3 consumer surfaces Phase 2c gaps via the same try? idiom as the v1.0.0 examples

- **GIVEN** a Layer 3 consumer (e.g., `DocxWorkflowLib`) that needs to apply an Edit case whose Reducer is not yet shipped (per ooxml-swift#71 Phase 2c follow-up)
- **WHEN** the consumer wraps that Edit in `try?` with a comment naming the tracker (per the `examples/03-table-3x3.swift` precedent in v1.0.0)
- **THEN** the consumer code MUST compile against the v1.0.0 surface and MUST NOT require any new API from `word-builder-swift`; the gap-handling pattern is consumer-side, not library-side

##### Example: Layer 3 try? idiom for pending Reducer cases

- **GIVEN** a consumer that wants to apply a hypothetical `OOXMLEdit.insertTable(at: anchor, rows: 3, columns: 3)` whose Reducer is pending
- **WHEN** the consumer writes
  ```swift
  let withTable = try? doc.apply(OOXMLEdit.insertTable(at: anchor, rows: 3, columns: 3))
  let final = withTable ?? doc
  ```
- **THEN** the code MUST type-check against v1.0.0, MUST execute without throwing at the `try?` site even when the Reducer case is unimplemented, and the consumer's downstream code MUST receive a non-nil document via the nil-coalescing operator

<!-- @trace
source: macdoc-docx-workflow-cli
updated: 2026-06-01
code:
  - packages/word-to-html-swift/Sources/WordToHTML/WordHTMLConverter.swift
  - Package.swift
  - .remember/logs/autonomous/save-133659.log
  - Tests/MacDocCLITests/MacDocDocxIntegrationTests.swift
  - .remember/logs/autonomous/save-132859.log
  - packages/marker-word-converter-swift/Sources/MarkerWordConverter/MarkerWordConverter.swift
  - CLAUDE.md
  - packages/pdf-to-docx-swift/Sources/PDFToDOCX/PDFToDOCXConverter.swift
  - Sources/MacDocCLI/MacDoc+Docx.swift
  - packages/md-to-word-swift/Sources/MDToWord/MarkdownToWordConverter.swift
  - Package.resolved
  - Sources/MacDocCLI/MacDoc.swift
-->