## 1. Extract note-core-swift (Layer 1)

Implements Decision: Extract note-core-swift (Option C from diagnosis).

- [x] 1.1 [P] Create `packages/note-core-swift/Package.swift` with target `NoteCore`, platform macOS 14+, dependency on ZIPFoundation (same as note-to-html-swift)
- [x] 1.2 [P] Move `NoteParser.swift`, `StrokeDecoder.swift`, `TimelineDecoder.swift` from `packages/note-to-html-swift/Sources/NoteToHTML/` to `packages/note-core-swift/Sources/NoteCore/`. Update module name in source files (change any `internal` to `public` where needed for cross-module access).
- [x] 1.3 Verify all model types are public: `ParsedNote`, `StrokeData`, `Curve`, `StrokeBounds`, `NoteImage`, `RecordingInfo`, `HandwritingEntry`, `TimelineEvent` per **NoteParser extracts ParsedNote from .note ZIP bundle** and **StrokeDecoder produces Curve array with color and width** and **ParsedNote exposes page geometry** requirements
- [x] 1.4 `swift build` in `note-core-swift` to confirm compilation
- [x] 1.5 Commit `note-core-swift` package (local, no push yet — path dep)

## 2. Refactor note-to-html-swift

- [x] 2.1 Update `packages/note-to-html-swift/Package.swift` to depend on `note-core-swift` (path: dep for now)
- [x] 2.2 Remove the moved files from `note-to-html-swift/Sources/NoteToHTML/` (NoteParser, StrokeDecoder, TimelineDecoder). Add `import NoteCore` to `NoteConverter.swift` and `PlayerTemplate.swift`.
- [x] 2.3 `swift build` in `note-to-html-swift` to confirm compilation
- [x] 2.4 `swift test` in `note-to-html-swift` to confirm all existing tests pass (no behavioral change)
- [x] 2.5 Commit refactor (local)

## 3. Create note-to-pdf-swift (Layer 3) — tests (TDD red)

- [x] 3.1 [P] Create `packages/note-to-pdf-swift/Package.swift` with target `NoteToPDF`, dependency on `note-core-swift`, platform macOS 14+
- [x] 3.2 [P] Write test `testSinglePageNoteProducesOnePage` — parse a fixture `.note` file (reuse from note-to-html-swift if available, or create minimal), convert to PDF, assert PDF page count == 1 and data is non-empty per **NoteToPDFConverter renders strokes to multi-page PDF** requirement
- [x] 3.3 [P] Write test `testEmptyNoteProducesBlankPages` — create a `ParsedNote` with 2 pages but zero curves, convert, assert 2-page PDF (no crash)
- [x] 3.4 [P] Write test `testCoordinateTransformYFlip` per **Coordinate transform applies scale and Y-flip** requirement — stroke at Notability (10, 10) should map to high PDF Y value (near top of page)
- [x] 3.5 Run tests to confirm RED state

## 4. Implement note-to-pdf-swift (TDD green)

- [x] 4.1 Create `packages/note-to-pdf-swift/Sources/NoteToPDF/NoteToPDFConverter.swift` with `public func convert(note: ParsedNote) -> Data` method
- [x] 4.2 Per Decision: Coordinate Transform is Scale + Y-Flip — implement transform: `scale = 612.0 / note.pageWidth`, page size = `(612, note.pageHeight * scale)`, Y-flip per stroke point
- [x] 4.3 Per Decision: Multi-Page Split by pageHeight Boundaries — loop `0..<note.pageCount`, for each page: `CGContext.beginPDFPage()`, filter curves by Y-range, offset, transform, draw via `CGContext.addLines(between:)` + `CGContext.setStrokeColor()` + `CGContext.setLineWidth()` + `CGContext.strokePath()`
- [x] 4.4 Per Decision: Images Render as Background Layer and **Images render as background layer under strokes** requirement — for each `NoteImage` with non-nil position: convert `Data` → `CGImage` via `CGImageSource`, compute page + transformed rect, draw BEFORE strokes on that page. Per Decision: Audio Skipped Entirely — `RecordingInfo` and `TimelineDecoder` output are NOT consulted during PDF rendering (static format; audio requires HTML player)
- [x] 4.5 Run tests to confirm GREEN state
- [x] 4.6 Commit `note-to-pdf-swift` (local)

## 5. Wire CLI route

- [x] 5.1 Per **CLI route converts .note to PDF** requirement — add `case ("note", "pdf"):` in `Sources/MacDocCLI/MacDoc+Convert.swift` after the existing `("note", "html")` case. Call `NoteToPDFConverter`, write output `Data` to file. Default output: same dir as input with `.pdf` extension. Support `--output` flag.
- [x] 5.2 Update `Package.swift` to add `note-to-pdf-swift` + `note-core-swift` as dependencies of `MacDocCLI`
- [x] 5.3 `swift build` macdoc to confirm compilation
- [x] 5.4 Manual smoke test: `swift run macdoc convert --to pdf <test.note>` — verify PDF opens in Preview and shows strokes

## 6. Release + docs

- [x] 6.1 Commit + push `note-core-swift` (tag if using url: dep; path: if monorepo-only)
- [x] 6.2 Update `CLAUDE.md` project structure section: add `note-core-swift` (Layer 1) and `note-to-pdf-swift` (Layer 3) to the tree and dependency graph
- [x] 6.3 Post implementation-complete comment on macdoc#76 referencing the new `macdoc convert --to pdf` route
- [x] 6.4 Close macdoc#76 via `/idd-close`
