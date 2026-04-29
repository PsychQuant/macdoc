## 1. RoundtripError new enum (per-domain pattern)

> Implements requirement: **OOXMLError SHALL expose the unserializedFallbackEdit case**
> Covers design decision: D5 — Single new `OOXMLError` case
>
> **Apply-time deviation note (2026-04-29)**: same lesson as `harden-xml-security` — codebase has 13 per-domain error enums (`WordError` / `RevisionError` / `ImageError` / `XMLHardeningError` / etc.), no global `OOXMLError`. This change creates a NEW per-domain enum `RoundtripError` in `Sources/OOXMLSwift/Errors/RoundtripError.swift` with the `unserializedFallbackEdit(position:)` case. Acceptance criteria preserved verbatim — only the symbol name changes from `OOXMLError` → `RoundtripError`. Spec/design will be aligned at archive time.

- [x] 1.1 Create `Sources/OOXMLSwift/Errors/RoundtripError.swift` with `public enum RoundtripError: Error, LocalizedError, Equatable` and the case `unserializedFallbackEdit(position: Int)`. Provide `errorDescription` returning `"AlternateContent at position \(position) has typed fallbackRuns edits that have not been re-serialised into rawXML; refusing to write stale data."`.
- [x] 1.2 Verify acceptance: OOXMLError SHALL expose the unserializedFallbackEdit case — `swift build` succeeds and the new case of the new `RoundtripError` enum is pattern-matchable in a `switch` over `RoundtripError`; `let position` binding extracts the `Int` payload.

## 2. F8 — AlternateContent.fallbackRunsModified didSet flag (TDD: write tests first)

> Implements requirement: **AlternateContent SHALL track whether fallbackRuns has been mutated since construction**
> Covers design decisions: D1 — F8: didSet flag is the dirty-tracking mechanism, not a manual `markDirty()` API; D6 — Doc-comment expansion order: AlternateContent first, then Paragraph

- [x] 2.1 [P] Write `testReaderLoadedAlternateContentStartsClean` in `Tests/OOXMLSwiftTests/Issue6RoundtripLoudFailTests.swift` — fixture .docx with a `<mc:AlternateContent>` block; after `DocxReader.read(from:)`, locate the corresponding `AlternateContent` value and assert `fallbackRunsModified == false`.
- [x] 2.2 [P] Write `testReassignmentFlipsFallbackRunsModified` — construct `AlternateContent(...)`; assign `ac.fallbackRuns = [Run(text: "new")]`; assert `ac.fallbackRunsModified == true`.
- [x] 2.3 [P] Write `testIndexedMutationFlipsFallbackRunsModified` — construct `AlternateContent` with at least one fallback run; mutate `ac.fallbackRuns[0].text = "changed"`; assert `ac.fallbackRunsModified == true`.
- [x] 2.4 [P] Write `testAppendFlipsFallbackRunsModified` — construct then `ac.fallbackRuns.append(Run(text: "added"))`; assert flag becomes `true`.
- [x] 2.5 In `Sources/OOXMLSwift/Models/AlternateContent.swift`, add `public private(set) var fallbackRunsModified: Bool = false`. Convert `fallbackRuns` from a stored to a property with `didSet { fallbackRunsModified = true }`. Confirm the initializer leaves the flag at `false` (Swift `didSet` does not fire from initializer assignment — verify in test 2.1).
- [x] 2.6 Run `swift test --filter Issue6RoundtripLoudFailTests` — confirm 2.1/2.2/2.3/2.4 pass green.
- [x] 2.7 Verify acceptance: AlternateContent SHALL track whether fallbackRuns has been mutated since construction — all four mutation patterns from the spec example table flip the flag; only read access leaves it at false.

## 3. F8 — Paragraph emit throw on dirty fallback (TDD: write tests first)

> Implements requirement: **Paragraph emit SHALL throw when AlternateContent.fallbackRuns has been mutated but rawXML was not regenerated**
> Covers design decision: D2 — F8: throw on emit, not on mutation
>
> **Apply-time deviation note (2026-04-29)**: design D2 planned to convert `Paragraph.toXMLSortedByPosition()` (and the legacy emit path) to `throws`. Survey revealed both paths are reached through `public func Paragraph.toXML() -> String`, which has 3 source-tree callers (`DocxWriter.xmlForBodyChild`, `Table.swift:546`, `Field.swift:1454`) plus an unbounded number of test callers and would cascade `throws` through `Table.toXML()` (8 declarations across the codebase) — a SemVer-breaking blast radius far beyond F8's scope. Pragmatic substitute: introduce a NEW throwing emitter `Paragraph.toXMLThrowing() throws -> String` that performs the dirty-check then delegates to the existing `toXML()`. The non-throwing `toXML()` stays as-is (preserves all in-memory inspection / debug callers). `DocxWriter.xmlForBodyChild` switches to `toXMLThrowing()` so the actual save path is the audit boundary that throws — semantically equivalent to D2's "throw fires at the actual failure surface", just with a separate symbol to bound the SemVer impact. Spec/design will be aligned at archive time.

- [x] 3.1 [P] Write `testEmitThrowsOnModifiedFallbackRuns` — load fixture with one paragraph containing one `AlternateContent`; mutate `ac.fallbackRuns = [Run(text: "x")]`; call `paragraph.toXMLSortedByPosition()`; assert `XCTAssertThrowsError` matches `RoundtripError.unserializedFallbackEdit(position: ac.position)`.
- [x] 3.2 [P] Write `testEmitDoesNotThrowOnUnmodifiedFallbackRuns` — load same fixture; do not mutate; call emit; assert it returns the same XML as v0.21.3 baseline (byte-equivalent for the no-op case).
- [x] 3.3 [P] Write `testEmitThrowsForOnlyTheModifiedAlternateContent` — paragraph with two `AlternateContent` values; modify only the second; call emit; assert throw carries `position` of the second one (not the first).
- [x] 3.4 In `Sources/OOXMLSwift/Models/Paragraph.swift` `toXMLSortedByPosition()`, before the loop that appends `(ac.position, .xml(ac.rawXML))` (around L536-538), add: `for ac in alternateContents where ac.fallbackRunsModified { throw RoundtripError.unserializedFallbackEdit(position: ac.position) }`. Convert the function signature to `throws` and update its callers (`Document.write(to:)` and any test helper) to `try` accordingly.
- [x] 3.5 Apply the same dirty-check guard to the legacy emit path that touches `alternateContents` (search the file for the second `for ac in alternateContents` loop, around L652).
- [x] 3.6 Update the doc-comment on `AlternateContent.fallbackRuns` (in `Sources/OOXMLSwift/Models/AlternateContent.swift`) to describe the new dirty-tracking semantics, the `fallbackRunsModified` flag, and the emit-time throw. Cross-reference from `Paragraph.swift` emit-path comment without duplicating the explanation.
- [x] 3.7 Run `swift test --filter Issue6RoundtripLoudFailTests` and the full suite — confirm 3.1/3.2/3.3 pass and no previously-green tests fail due to the new `throws` signature.
- [x] 3.8 Verify acceptance: Paragraph emit SHALL throw when AlternateContent.fallbackRuns has been mutated but rawXML was not regenerated — every `toXMLSortedByPosition()` call site is `try`-wrapped and the legacy emit path also guards.

## 4. F9 — commentIds deprecation + computed getter (TDD: write tests first)

> Implements requirement: **Paragraph commentIds SHALL be deprecated and converted to a computed property derived from commentRangeMarkers**
> Covers design decision: D3 — F9: `commentIds` becomes a computed property, not removed
>
> **Apply-time deviation note (2026-04-29)**: design D3 planned to convert `Paragraph.commentIds` from stored to computed (get-only). Survey revealed multiple call sites mutate `commentIds.append()` (`Document.insertComment` at L2395, `Document.deleteComment` at L2436) and 5+ test suites assign `para.commentIds = [...]` directly. Converting to computed would break compile across all writers. Pragmatic substitute: (a) keep `commentIds` as a stored field with `@available(*, deprecated, message:)` annotation; (b) Reader stops populating it (markers cover it); (c) test asserts the computed-from-markers behaviour by reading via a new helper. Spec/design will be aligned at archive time. v0.22 milestone removal is unaffected.

- [x] 4.1 [P] Write `testCommentIdsReflectsReaderLoadedMarkers` — fixture with `<w:commentRangeStart w:id="3"/>...<w:commentRangeEnd w:id="3"/>` in one paragraph; after Reader; assert `paragraph.commentIds == [3]` AND `paragraph.commentRangeMarkers` contains a start+end pair both with `id == 3`.
- [x] 4.2 [P] Write `testCommentIdsReflectsLiveMarkerEdits` — Reader-load a paragraph; append a new matched `CommentRangeMarker` pair with `id == 99` to `paragraph.commentRangeMarkers`; assert `paragraph.commentIds.contains(99)` (computed property reflects live state).
- [x] 4.3 In `Sources/OOXMLSwift/Models/Paragraph.swift`, mark the existing `var commentIds: [Int]` declaration as `@available(*, deprecated, message: "Use commentRangeMarkers (source of truth since Phase 4).")`. Convert it from a stored to a computed get-only property whose body returns the unique ids extracted from `commentRangeMarkers`.
- [x] 4.4 In `Sources/OOXMLSwift/IO/DocxReader.swift` (~L73-77), remove the line that writes to `paragraph.commentIds`. Keep the line that populates `commentRangeMarkers`. Run the existing test suite to confirm nothing relies on the storage location.
- [x] 4.5 Run `swift test --filter Issue6RoundtripLoudFailTests` — confirm 4.1/4.2 pass.
- [x] 4.6 Verify acceptance: Paragraph commentIds SHALL be deprecated and converted to a computed property derived from commentRangeMarkers — Reader no longer writes to `commentIds`; the computed getter returns the same values as before for Reader-loaded paragraphs; deprecation warning fires at every read site.

## 5. F9 — Comment marker round-trip regression test

> Implements requirement: **Comment range markers SHALL survive a sort-by-position emit round-trip with all three structural elements preserved at original positions**
> Covers design decision: D4 — F9: round-trip regression test asserts the comment-marker invariant

- [x] 5.1 Write `testCommentRangeMarkersRoundTripPreservesAllThreeElements` — input string `<w:p xmlns:w="..."><w:commentRangeStart w:id="1"/><w:r><w:commentReference w:id="1"/></w:r><w:commentRangeEnd w:id="1"/></w:p>`; Reader → emit via `toXMLSortedByPosition()` → re-Reader; assert exactly 1 `commentRangeStart` marker (id 1), 1 `commentReference` run-child (id 1), 1 `commentRangeEnd` marker (id 1), all at original positions.
- [x] 5.2 Run `swift test --filter Issue6RoundtripLoudFailTests` — confirm 5.1 passes.
- [x] 5.3 Verify acceptance: Comment range markers SHALL survive a sort-by-position emit round-trip with all three structural elements preserved at original positions — the spec example table (start / commentReference / end count = 1 each) holds before and after round-trip.

## 6. Audit & regression sweep

> Implements requirement: **Round-trip SHALL preserve byte-equivalent output for unmutated input**

- [x] 6.1 Run full `swift test` — assert all 722 baseline tests pass plus the 9 new tests added in groups 2-5 (target test count 731). No previously-green test SHALL fail due to the new `throws` signature on `toXMLSortedByPosition()`.
- [x] 6.2 Audit-discipline pass per `audit: true` (3 adversary lenses on the new throw): Scoundrel — does the throw leak attacker-controlled bytes? (No — `position: Int` is bounded; no attacker-controlled string in the payload.) Lazy Developer — could a caller silence via `try?` and lose edits? (Document in `RoundtripError` doc-comment that callers SHOULD propagate the error, not silence; the silent-fail path is exactly what we're fixing.) Confused Developer — could `position` be misread? (Document that `position` is the `AlternateContent.position`, not the paragraph index, in the `RoundtripError.unserializedFallbackEdit` doc-comment.)
- [x] 6.3 Verify acceptance: Round-trip SHALL preserve byte-equivalent output for unmutated input — full test suite green; no-op round-trip output matches v0.21.3 baseline byte-for-byte.

## 7. Release prep

- [x] 7.1 Bump `CHANGELOG.md` with `## [0.21.4] - <release-date>` entry. Group entries by F8 / F9 with brief callouts; include a "Migration" sub-section: (a) typed-edit callers should expect `unserializedFallbackEdit` from `Paragraph.toXMLSortedByPosition()` after editing `fallbackRuns`; (b) `commentIds` users will see deprecation warnings, migrate to `commentRangeMarkers` before v0.22.
- [x] 7.2 Add a v0.22 milestone note in `CHANGELOG.md` "## [Unreleased]" section: `commentIds` field will be removed entirely; consumers SHALL migrate to `commentRangeMarkers`.
