## 1. Testability + RED tests

- [x] 1.1 Per Decision: Testability via Internal Visibility (not Word-built Fixture) — change `parseParagraph` visibility from `private static` to `internal static` in `DocxReader.swift:353`. Update its doc-comment to note it is internal for `@testable import` access. No behavioral change.
- [x] 1.2 [P] Create new test file `packages/ooxml-swift/Tests/OOXMLSwiftTests/RevisionParsingTests.swift` with `@testable import OOXMLSwift`. Add a test helper `paragraphElement(xml:)` that wraps `<w:p xmlns:w="...">\(body)</w:p>` around an inner XML string and returns an `XMLElement` via `XMLDocument(xmlString:).rootElement()`. Add a second helper `parseParagraph(_:)` that calls `DocxReader.parseParagraph(from:styles:numbering:relationships:)` with default empty arrays.
- [x] 1.3 [P] Write RED test `testParsesMoveFromRevision` — per **DocxReader parses w:moveFrom revisions** requirement, constructs an `XMLElement` representing `<w:p><w:moveFrom w:id="3" w:author="Alice" w:date="2026-04-16T12:00:00Z"><w:r><w:t>moved source</w:t></w:r></w:moveFrom></w:p>`, calls the helper, asserts the returned `Paragraph.revisions` contains exactly one `Revision` with `id == 3`, `type == .moveFrom`, `author == "Alice"`, `originalText == "moved source"`, `newText == nil`.
- [x] 1.4 [P] Write RED test `testParsesMoveToRevision` — per **DocxReader parses w:moveTo revisions** requirement, constructs an `XMLElement` with `<w:moveTo>...</w:moveTo>` and asserts the returned revision has `type == .moveTo`, `newText == "moved destination"`, `originalText == nil`.
- [x] 1.5 [P] Write RED test `testMoveFromConcatenatesMultipleRuns` — per the second scenario of **DocxReader parses w:moveFrom revisions**, constructs `<w:moveFrom><w:r><w:t>first </w:t></w:r><w:r><w:t>second</w:t></w:r></w:moveFrom>` and asserts `originalText == "first second"`.
- [x] 1.6 [P] Write RED test `testDebugLoggingDisabledProducesNoOutput` — per the **DocxReader surfaces unknown paragraph elements via debug logging** requirement, captures stderr via a dup2-based `Pipe` redirect, sets `DocxReader.debugLoggingEnabled = false`, parses a paragraph with `<w:p><w:customElement/></w:p>`, asserts the captured bytes are empty.
- [x] 1.7 [P] Write RED test `testDebugLoggingEnabledEmitsOneLinePerUnknownElement` — same capture approach, sets the flag to `true`, parses a paragraph with one `<w:customElement/>`, asserts captured stderr contains exactly `"DocxReader.parseParagraph: skipped unknown element customElement\n"`.
- [x] 1.8 [P] Write RED test `testExistingInsDelStillParsed` per the **DocxReader parses w:ins insertion revisions** and **DocxReader parses w:del deletion revisions** requirements — constructs a paragraph with both `<w:ins>` and `<w:del>` elements and asserts the returned revisions contain both `.insertion` and `.deletion` types with correct text fields. Guards against the switch expansion accidentally breaking the existing two cases.
- [x] 1.9a [P] Write RED test `testRevisionAggregationPreservesOrderWithinParagraph` per the **Revision aggregation preserves revision order** requirement — constructs a single `<w:p>` containing `<w:ins>` followed by `<w:moveTo>`, asserts the returned `Paragraph.revisions` lists the insertion first and the moveTo second (child order preserved). This test covers the within-paragraph scenario at the parseParagraph level; the cross-paragraph scenario is covered by `DocxReaderIntegrationTests` via round-trip with ins/del in separate paragraphs (documented by a code comment in this test).
- [x] 1.9 Run `swift test --filter RevisionParsingTests` to confirm RED state — moveFrom/moveTo tests fail with "expected 1 revision, got 0"; debug-logging tests fail because `DocxReader.debugLoggingEnabled` does not exist. (Initial run crashed with index-out-of-range from `revisions[0]` force-unwrap and a stderr-capture deadlock; fixed the captureStderr helper's fd ordering; re-ran → 4 failures reported for the correct reasons before GREEN phase.)

## 2. Top-level switch expansion (Part A)

Implements Decision: Two-Element Scope for Top-Level Switch Expansion and Decision: moveFrom and moveTo Mirror ins and del Structure and Decision: Author and Date Extraction Reuses ins/del Helper Pattern.

- [x] 2.1 In `DocxReader.swift` at the top-level paragraph switch (around line 371-428), add `case "moveFrom":` between the `del` case and `commentRangeStart`. Extract `w:id`, `w:author`, `w:date` attributes using the ISO8601 formatter already declared for ins/del. Iterate nested `w:r` children, append each parsed run to `paragraph.runs`, and collect their concatenated `text` into a local `movedText` variable.
- [x] 2.2 If `movedText` is non-empty, append a `Revision(id: revId, type: .moveFrom, author: author, paragraphIndex: 0, originalText: movedText, newText: nil, date: date)` to `paragraph.revisions`. The `paragraphIndex: 0` is a placeholder; the aggregation step at `DocxReader.swift:87-107` overwrites it with the actual enumerated index.
- [x] 2.3 Add `case "moveTo":` mirror-image of the moveFrom case — same attribute extraction, same `w:r` iteration, but store the concatenated text into `newText` (not `originalText`) and emit `Revision(id: revId, type: .moveTo, ..., originalText: nil, newText: movedText, date: date)`.
- [x] 2.4 Run `swift test --filter testParsesMoveFromRevision --filter testParsesMoveToRevision --filter testMoveFromConcatenatesMultipleRuns --filter testExistingInsDelStillParsed` to confirm these four tests pass GREEN.

## 3. Defensive logging (Part D)

Implements Decision: Debug Logging Via Static Flag, Not Swift-log Dependency.

- [x] 3.1 Add `public static var debugLoggingEnabled: Bool = false` to the `DocxReader` type declaration with a doc-comment stating "Toggle at test setup time; not thread-safe for concurrent toggles during parallel parses." (Pulled forward to unblock RED test compilation.)
- [x] 3.2 Replace the existing `default: break` at `DocxReader.swift:426-427` with a guard pattern: `if DocxReader.debugLoggingEnabled { let name = childElement.localName ?? "<nil>"; FileHandle.standardError.write("DocxReader.parseParagraph: skipped unknown element \(name)\n".data(using: .utf8) ?? Data()) }`. Ensure the guard runs before any string interpolation so production parses pay zero cost when the flag is `false`.
- [x] 3.3 Run `swift test --filter testDebugLoggingDisabledProducesNoOutput --filter testDebugLoggingEnabledEmitsOneLinePerUnknownElement` to confirm debug-logging tests pass GREEN.

## 4. Regression + full suite verification

- [x] 4.1 Run `swift test` against the full `ooxml-swift` suite and confirm the previous 183 tests + ~8 new tests all pass. Investigate and fix any regressions before proceeding. (190/190 pass — 183 pre-existing + 7 new.)
- [x] 4.2 Manually verify by reading an existing `DocxReaderIntegrationTests.swift` fixture with ins/del revisions that the counts and types remain unchanged (the switch expansion is strictly additive to unrelated cases, but sanity-check). (Covered by `testExistingInsDelStillParsed` + full suite regression — no existing test broke.)

## 5. CHANGELOG and release

Implements Decision: Patch Bump (v0.5.7), Not Minor Bump.

- [x] 5.1 Update `packages/ooxml-swift/CHANGELOG.md` — add an `[Unreleased]` entry or convert to `[0.5.7] - 2026-04-16` describing: parser now emits `moveFrom` and `moveTo` revisions (previously silently dropped); new opt-in `DocxReader.debugLoggingEnabled` flag for surfacing unknown elements during development. Link back to [`PsychQuant/ooxml-swift#1`](https://github.com/PsychQuant/ooxml-swift/issues/1).
- [x] 5.2 Commit the change with conventional-commit message referencing `ooxml-swift#1` Part A + D. Commit message enumerates the new revision types covered and notes the debug flag's default. (Committed as `b02fe4f`.)
- [x] 5.3 Tag `v0.5.7` on the committed SHA and `git push origin main v0.5.7` to `github.com/PsychQuant/ooxml-swift`. (Tag and main pushed cleanly.)
- [x] 5.4 Optional verification: in `mcp/che-word-mcp`, run `swift package update` and confirm `Package.resolved` picks up ooxml-swift v0.5.7 cleanly; run `swift test` in che-word-mcp and confirm 30/30 still pass. (Resolved to 0.5.7; 30/30 pass; Package.resolved committed as che-word-mcp `db0e75e`.)

## 6. Issue update

- [x] 6.1 Add a comment on [PsychQuant/ooxml-swift#1](https://github.com/PsychQuant/ooxml-swift/issues/1) noting that Part A + D shipped in v0.5.7 and Parts B + C remain for the follow-up change `docx-reader-nested-revisions-and-containers`. Do NOT close the issue — it stays open until Parts B + C ship too.
- [x] 6.2 Update `PsychQuant/macdoc#75` umbrella tracking issue body: under Layer 1, annotate `ooxml-swift#1` with "partial: Parts A+D shipped in v0.5.7; B+C pending".
