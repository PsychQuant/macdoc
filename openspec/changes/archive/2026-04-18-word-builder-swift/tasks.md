## 1. Blocker — OOXMLSwift.DocxWriter writeData for in-memory output

- [x] 1.1 In `packages/ooxml-swift/Tests`, write a failing test that calls `DocxWriter.writeData(doc)` on a minimal `WordDocument` and asserts the returned `Data` begins with ZIP magic `0x50 0x4B 0x03 0x04` (**Decision: OOXMLSwift.DocxWriter gains writeData**).
- [x] 1.2 Refactor `DocxWriter.write(_:to:)` into two internal phases: `buildArchiveData(_:) throws -> Data` and `writeToURL(_:to:)`; keep `write(_:to:)` as a facade that composes them so existing callers see identical behavior.
- [x] 1.3 Add public static `writeData(_ document: WordDocument) throws -> Data` that calls the new `buildArchiveData`; confirm the test from 1.1 passes.
- [x] 1.4 [P] Add a second test that round-trips through both APIs (`writeData` vs `write` + re-read) and asserts byte equality, fulfilling **OOXMLSwift.DocxWriter exposes writeData for in-memory output** scenario "writeData and write produce identical bytes".
- [x] 1.5 [P] Add a third test that asserts no files persist under `FileManager.default.temporaryDirectory` with the OOXMLSwift tempdir prefix after `writeData` returns, fulfilling the scenario "writeData performs no disk I/O in its hot path".
- [x] 1.6 Push ooxml-swift commits, tag a new patch version, and update the version constraint in `packages/ooxml-swift/Package.swift` README if version badges exist. (Tagged **v0.7.0**, pushed to `PsychQuant/ooxml-swift`.)

## 2. Bootstrap word-builder-swift package

- [x] 2.1 Create new local directory `packages/word-builder-swift` with `Package.swift` declaring Swift 5.9+, platforms macOS 13+, product `WordBuilderSwift`, dependency on `OOXMLSwift` at the version from task 1.6.
- [x] 2.2 [P] Add `README.md` explaining the package is a **1:1 mirror of docx.js 9.6.x** and documenting the **Version number mirrors docx.js minor version** policy; include a note warning against simultaneous import with OOXMLSwift.
- [x] 2.3 [P] Add MIT `LICENSE` attributing the reference `docx.js` project for API shape inspiration per **reference/docx-js/ is read-only, no code copying**.
- [x] 2.4 [P] Create `Tests/WordBuilderSwiftTests/WordBuilderSwiftTests.swift` with a placeholder test that imports `WordBuilderSwift` and asserts the module loads; confirm `swift test` runs (zero test cases initially is fine).

## 3. Core types — Document, Section, Paragraph, TextRun, Run

- [x] 3.1 Write failing test `DocumentSectionsTests` with three cases covering **Document accepts a sections array and Phase 1 emits only the first section**: single-section renders, multi-section emits only section zero, empty sections throws `WordBuilderError.emptyDocument`.
- [x] 3.2 Implement `Section` struct with public `children: [ParagraphChild]` (or equivalent) and defaulted init, per **Decision: Options use Swift struct init parameters with defaults**.
- [x] 3.3 Implement `Document` struct with public `sections: [Section]` init parameter and `WordBuilderError` enum including `emptyDocument`, per **Decision: Phase 1 accepts [Section] but only emits sections[0]**.
- [x] 3.4 [P] Write failing test `TextRunTests` covering **TextRun accepts a bare String and an options-style init**: `TextRun("x")` compiles, `TextRun(text:bold:)` applies formatting.
- [x] 3.5 Implement `Run` struct (options init only) and `TextRun` convenience struct forwarding to `Run`, per **Decision: TextRun is a String-overload convenience wrapper over Run**.
- [x] 3.6 [P] Write failing test `ParagraphInitTests` covering **Paragraph accepts heading, alignment, and children as init parameters with defaults**: heading renders with style, empty `Paragraph()` is valid.
- [x] 3.7 Implement `Paragraph` struct with defaulted `heading`, `alignment`, `children` parameters; define the `ParagraphChild` type to admit `Run` and `TextRun`.

## 4. Table types

- [x] 4.1 Write failing test `TableRenderingTests` covering **Table accepts rows of cells and renders to OOXML table**: 2×2 table with text `A`/`B`/`C`/`D` emits correct `<w:tbl>` / `<w:tr>` / `<w:tc>` structure.
- [x] 4.2 Implement `TableCell` struct with `children: [Paragraph]` init parameter.
- [x] 4.3 Implement `TableRow` struct with `children: [TableCell]` init parameter.
- [x] 4.4 Implement `Table` struct with `rows: [TableRow]` init parameter and any minimum table properties (width, borders) needed for the scenario to render.

## 5. Enums — HeadingLevel and AlignmentType

- [x] 5.1 Write failing test `HeadingLevelEnumTests` covering **HeadingLevel and AlignmentType enums mirror docx.js values**: `.heading1` outputs `<w:pStyle w:val="Heading1"/>`.
- [x] 5.2 Implement `HeadingLevel` enum with cases `heading1` through `heading6` and an internal `oxmlStyleId` property returning `"Heading1"` … `"Heading6"`.
- [x] 5.3 [P] Write failing test `AlignmentTypeEnumTests`: `.center` outputs `<w:jc w:val="center"/>`.
- [x] 5.4 [P] Implement `AlignmentType` enum with cases `start`, `center`, `end`, `both` and an internal `oxmlValue` property returning the matching OOXML string.

## 6. Internal converter — WordBuilderSwift → OOXMLSwift.WordDocument

- [x] 6.1 Write failing integration test `PackerToDataTests` covering **Packer provides toData, toFile, and toBase64String static methods** scenario "Packer.toData returns a valid .docx zip archive": builds a non-empty Document and asserts the `Data` is accepted by `OOXMLSwift.DocxReader.read`.
- [x] 6.2 Implement internal `DocumentConverter` type that walks `Document` → `Section` → `Paragraph` / `Table` → `OOXMLSwift.WordDocument`, respecting **Decision: Phase 1 accepts [Section] but only emits sections[0]** by taking `sections.first`.
- [x] 6.3 [P] Implement paragraph mapping: `Paragraph.heading` maps via `HeadingLevel.oxmlStyleId` to `ParagraphProperties.style`; `Paragraph.alignment` maps via `AlignmentType.oxmlValue` to `ParagraphProperties.alignment`.
- [x] 6.4 [P] Implement run mapping: `Run` and `TextRun` both produce `OOXMLSwift.Run` with matching `RunProperties`.
- [x] 6.5 [P] Implement table mapping: `Table` / `TableRow` / `TableCell` produce `OOXMLSwift.Table` / `TableRow` / `TableCell` with cell-to-paragraph content preserved.

## 7. Packer facade

- [x] 7.1 Write failing test `PackerInstantiationTests` covering scenario "Packer cannot be instantiated" — `Packer()` fails to compile (compile-time test via `#if` guard is acceptable).
- [x] 7.2 Implement `Packer` as uninhabited `enum` with static `toData(_:)` calling `DocumentConverter` then `OOXMLSwift.DocxWriter.writeData` (**Decision: Packer is a static-method facade over DocxWriter.writeData**).
- [x] 7.3 [P] Implement static `toFile(_:url:)` that calls `toData` then writes `Data` to `url`; write test asserting byte equality with `toData` output (scenario "Packer.toFile writes equivalent bytes to disk").
- [x] 7.4 [P] Implement static `toBase64String(_:)` that calls `toData` then returns `.base64EncodedString()`; add a test that decoding the result equals `toData` bytes.

## 8. Public-surface audit for docx.js mirror

- [x] 8.1 [P] Write a compile-test file in `Tests/` that literally translates the `docx.js` README Hello-World snippet using only `Document`, `Section`, `Paragraph`, `TextRun`, `Packer` and confirms it compiles, proving **Public API mirrors docx.js top-level types** scenario "Translating a docx.js snippet to Swift preserves type names".
- [x] 8.2 [P] Grep the public types in `Sources/WordBuilderSwift/` and assert none of `WordDocument`, `TextBlock`, `WordParagraph` appear as public types, covering scenario "Public API surface does not include Swift-specific renames" and enforcing **Decision: API mirrors docx.js naming 1:1**.

## 9. Examples directory

- [x] 9.1 Under `packages/word-builder-swift/examples/`, create five runnable Swift scripts, each covering **Phase 1 ships five worked examples translated from docx.js README**: (a) hello-world paragraph, (b) heading + two paragraphs, (c) 3×3 table with headers, (d) paragraph with mixed bold/italic runs, (e) centered heading plus left-aligned paragraph.
- [x] 9.2 [P] Each example file SHALL begin with a header comment citing the docx.js README section URL it translates from.
- [x] 9.3 [P] Add an `examples/README.md` that lists all five examples with one-line descriptions and the exact `swift run` command to produce each `.docx`.
- [x] 9.4 Add a CI-style integration test `ExamplesIntegrationTests` that runs each example and asserts the produced `.docx` opens via `DocxReader.read(...)` without error.

## 10. Release + macdoc wiring

- [x] 10.1 Create GitHub repo `PsychQuant/word-builder-swift`; push local `packages/word-builder-swift/` to `main`. (Repo live at https://github.com/PsychQuant/word-builder-swift)
- [x] 10.2 Tag release `0.9.0` per **Decision: Version 0.9.x tracks docx.js 9.6.x**. (v0.9.0 pushed)
- [x] 10.3 [P] In `Users/che/Developer/macdoc/Package.swift`, add `.package(url: "https://github.com/PsychQuant/word-builder-swift.git", from: "0.9.0")` as a dependency; confirm `swift build` on macdoc succeeds without regressions. (103.47s build clean)
- [x] 10.4 [P] Update top-level `CLAUDE.md` Package Dependencies section to list `word-builder-swift` under Layer 4 consumers.

## 11. Housekeeping

- [x] 11.1 Confirm `reference/docx-js/` stays in `.gitignore` and no file under `packages/word-builder-swift/Sources/` duplicates 5+ contiguous lines from `reference/docx-js/src/`, per **reference docx-js is read-only, no code copying**. (scanned 577 TS vs 8 Swift files, zero hits)
- [x] 11.2 [P] Post a closing comment on issue #71 that links the `0.9.0` release, lists the five example files, and explicitly flags which Phase 2 items (Header/Footer/Numbering/Hyperlink/Image/etc.) are deferred. (comment #4271540942)
