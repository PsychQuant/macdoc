## Why

Developers who want to generate `.docx` files programmatically from Swift have to manually import `OOXMLSwift` and hand-construct `WordDocument` / `ParagraphProperties` / `RunProperties` value types. There is no fluent builder API that mirrors what Node.js developers already have with `docx.js` (dolanmiu/docx@9.6.1). This change introduces `word-builder-swift` — a Swift package whose public API is a 1:1 mirror of `docx.js` — so a developer who knows `docx.js` can translate code line-by-line to Swift. `word-builder-swift` is the docx-writing sibling of the existing `markdown-builder` capability (programmatic markdown generation in `markdown-swift`).

The npm `docx` package has been cloned to `reference/docx-js/` (MIT, shallow) as the single source of truth for API naming and shape.

## What Changes

- Add new package `word-builder-swift` (new repo `PsychQuant/word-builder-swift`, same layout as `common-converter-swift` / `word-to-md-swift`).
- Phase 1 ships these public types: `Document`, `Section`, `Paragraph`, `TextRun`, `Table`, `TableRow`, `TableCell`, `HeadingLevel`, `AlignmentType`, `Packer`.
- `Packer` exposes `toData()`, `toFile(url:)`, `toBase64String()` — corresponding to `docx.js` `Packer.toBuffer` / `writeFile` / `.toBase64String`.
- Extend `ooxml-swift` `DocxWriter` with `writeData(_:) throws -> Data` so `Packer.toData()` can return in-memory bytes (today `DocxWriter.write` only accepts a `URL`).
- Ship five worked examples under `word-builder-swift/examples/` translated directly from `docx.js` README.
- Version the package as `0.9.x` to mirror `docx.js` `9.6.x` major/minor; patch number is independent.
- `word-builder-swift` becomes a Swift Package Manager remote dependency of `macdoc`, but **does not replace** `md-to-word-swift`, `html-to-word-swift`, or `tex-to-docx-swift` — those keep using the low-level `OOXMLSwift` model. `word-builder-swift` is the outward-facing builder for end users, `OOXMLSwift` stays the converter-internal layer.

## Non-Goals

- **Multi-section documents**: Phase 1 only generates single-section documents. `Document(sections:)` accepts an array but only `sections[0]` is emitted; multi-section delivery deferred to Phase 2. Rationale: `ooxml-swift` `SectionProperties` uses paragraph-break markers rather than section objects, so mapping multiple sections with independent headers/footers is a significant effort that would blow Phase 1 scope.
- **Headers, footers, numbering, hyperlinks, bookmarks, footnotes, images, checkboxes, textboxes, table of contents, core properties, global style definitions**: All deferred to Phase 2+. Phase 1 only covers the top-10 most common `docx.js` types needed for "write a body of text with tables" use cases.
- **Refactor existing converters**: `md-to-word-swift` / `html-to-word-swift` / `tex-to-docx-swift` will **not** be ported to use `word-builder-swift`. They keep direct `OOXMLSwift` usage. Rationale: those converters work with parsed AST nodes, not author-facing builder syntax, and introducing a dependency on `word-builder-swift` would force the high-level layer to cover every low-level construct.
- **`docx.js` `@resultBuilder` DSL**: Options are passed as Swift `struct` init parameters with defaults — not a Swift result builder. Rationale: `docx.js` users are familiar with options objects, and result builders would diverge from the mirror.
- **Dynamic Swift-file compilation (`macdoc convert --to docx file.swift`)**: Requires a Swift compiler at runtime; out of scope for this change.
- **`Packer.toStream`**: Streaming output is not required for typical document sizes and would complicate the `DocxWriter` refactor. `toData()` is sufficient.

## Capabilities

### New Capabilities

- `word-builder-swift`: Fluent Swift API for constructing `.docx` documents programmatically, whose public surface mirrors `npm docx` 1:1. Exposes `Document` / `Section` / `Paragraph` / `TextRun` / `Table` / `Packer` so callers can translate `docx.js` code to Swift with minimal friction.

### Modified Capabilities

(none. The OOXMLSwift DocxWriter writeData addition is an internal helper with no spec-level requirement change. The docx-container-parsing spec covers reading, not writing, and is unaffected.)

## Impact

- **Affected specs**: New `specs/word-builder-swift/spec.md`.
- **New repo**: `PsychQuant/word-builder-swift` — full `Package.swift`, `Sources/WordBuilderSwift/`, `Tests/WordBuilderSwiftTests/`, `examples/`, `README.md`, `LICENSE` (MIT).
- **Modified repo**: `PsychQuant/ooxml-swift` — extend `Sources/OOXMLSwift/IO/DocxWriter.swift` with a `writeData(_:) throws -> Data` method (internal refactor of the existing tempDir + ZipHelper pipeline to emit bytes instead of writing to disk).
- **Modified repo**: `PsychQuant/macdoc` — `Package.swift` adds `.package(url: "https://github.com/PsychQuant/word-builder-swift.git", from: "0.9.0")` as a dependency so CLI users can import it; no CLI subcommand change in Phase 1.
- **Reference-only**: `reference/docx-js/` is already cloned and gitignored. It is read for API shape reference only; no code is copied.
