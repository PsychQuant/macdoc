## 1. F5 — Hyperlink.text setter deprecation (TDD: write tests first)

> Implements requirement: **Hyperlink.text setter SHALL be marked deprecated and emit a compile-time warning at every call site**
> Covers design decision: D1 — F5: Deprecate via `@available(*, deprecated, message:)`, keep behaviour identical for one minor

- [x] 1.1 [P] Write `testHyperlinkTextSetterRuntimeBehaviorUnchanged` in `Tests/OOXMLSwiftTests/Issue5MutationSurfaceTests.swift` — construct `Hyperlink` with two runs (different `RunProperties.bold` values); assign `hyperlink.text = "replaced"`; assert `hyperlink.runs.count == 1` and `hyperlink.runs[0].text == "replaced"` (matches v0.21.4 baseline behavior; the deprecation does not change runtime semantics).
- [x] 1.2 In `Sources/OOXMLSwift/Models/Hyperlink.swift` (line 61-64), annotate the setter only of `text` with `@available(*, deprecated, message: "Mutates runs destructively (loses formatting / rawElements). Use .runs directly to preserve formatting; assign a single Run to replace, append/insert Runs to extend.")`. The getter SHALL remain non-deprecated.
- [x] 1.3 Run `swift test --filter Issue5MutationSurfaceTests` — confirm 1.1 passes (runtime unchanged).
- [x] 1.4 Run `swift build` and confirm any internal call sites that set `hyperlink.text = ...` produce the deprecation warning. Fix any internal code that triggers the warning (use `.runs = [Run(text: ...)]` directly).
- [x] 1.5 Verify acceptance: Hyperlink.text setter SHALL be marked deprecated and emit a compile-time warning at every call site — the deprecation message contains the substring "Use .runs directly"; getter is unaffected.

## 2. F6 — Position type cascade across thirteen sites (TDD: write tests first)

> Implements requirement: **All thirteen typed-child position fields SHALL change from non-optional Int to optional Int defaulting to nil**
> Covers design decisions: D2 — F6: `Int? = nil` over `Int = 0`, partition at emit time; D6 — Position type cascade affects 13 sites; cascade is mechanical

- [x] 2.1 [P] Write `testDefaultConstructedHyperlinkHasNilPosition` in `Tests/OOXMLSwiftTests/Issue5MutationSurfaceTests.swift` — `let h = Hyperlink(...)` with no position arg; assert `h.position == nil`.
- [x] 2.2 [P] Write `testDefaultConstructedRunHasNilPosition` — `let r = Run(text: "x")`; assert `r.position == nil`.
- [x] 2.3 [P] Write `testReaderLoadedTypedChildHasExplicitPosition` — fixture .docx with one paragraph and three runs; after Reader, assert all `paragraph.runs[i].position != nil`.
- [x] 2.4 In `Sources/OOXMLSwift/Models/Hyperlink.swift` line 55, change `public var position: Int = 0` to `public var position: Int? = nil`. Update the initializer signature to accept `position: Int? = nil`.
- [x] 2.5 In `Sources/OOXMLSwift/Models/Run.swift` line 55, change `public var position: Int = 0` to `public var position: Int? = nil`. Update the initializer signature.
- [x] 2.6 In `Sources/OOXMLSwift/Models/AlternateContent.swift` line 47, change `public var position: Int` to `public var position: Int? = nil`. Update the initializer signature; default the new parameter to `nil`.
- [x] 2.7 In `Sources/OOXMLSwift/Models/FieldSimple.swift` line 39, change `public var position: Int` to `public var position: Int? = nil`. Update the initializer signature.
- [x] 2.8 In `Sources/OOXMLSwift/Models/Field.swift` line 1499 (`StructuredDocumentTag.position`), change `public var position: Int` to `public var position: Int? = nil`. Update the initializer signature. Do NOT touch `Field.swift:466` (already `Int?` for unrelated purpose).
- [x] 2.9 In `Sources/OOXMLSwift/Models/ParagraphChildMarkers.swift` for the eight marker types at lines 40, 72, 96, 123, 140, 156, 179, 198, change each `public var position: Int` to `public var position: Int? = nil`. Update each marker's initializer.
- [x] 2.10 Run `grep -nE 'public var position: Int(\s*=\s*0)?$' Sources/OOXMLSwift/Models/*.swift | wc -l` — expect 0 (all 13 sites converted; only `Field.swift:466` remains as the unrelated `Int?` site).
- [x] 2.11 Update `DocxReader` Reader-side construction sites for these 13 typed children — wherever Reader currently passes `position: somePos`, the call signature is unchanged because `Int` widens to `Int?` automatically. No Reader behaviour change required.
- [x] 2.12 Run `swift test --filter Issue5MutationSurfaceTests` — confirm 2.1/2.2/2.3 pass.
- [x] 2.13 Verify acceptance: All thirteen typed-child position fields SHALL change from non-optional Int to optional Int defaulting to nil — `grep` returns 0 matches; the 13 sites listed in the spec example table all show `Int? = nil`.

## 3. F6 — Paragraph emit partition + max-plus-one heuristic (TDD: write tests first)

> Implements requirement: **Paragraph sort-by-position emit SHALL partition typed children into explicit and append cohorts**
> Covers design decision: D2 — F6: `Int? = nil` over `Int = 0`, partition at emit time

- [x] 3.1 [P] Write `testAppendRunLandsAfterSourceChildrenInSourceLoadedParagraph` — load fixture with three source runs at positions 1/2/3; call `paragraph.runs.append(Run(text: "z"))`; call `paragraph.toXMLSortedByPosition()`; parse output XML; assert the new run's effective emit position is 4 (after the three source runs).
- [x] 3.2 [P] Write `testAllNilCollectionEmitsInArrayOrder` — construct paragraph entirely API-side with three runs all `position == nil`; emit; assert positions 1/2/3 in array order.
- [x] 3.3 [P] Write `testSparseExplicitPositionsAppendCorrectly` — paragraph with runs at explicit positions 1 and 100, plus one append-mode run; emit; assert appendee lands at effective position 101, not 2.
- [x] 3.4 In `Sources/OOXMLSwift/Models/Paragraph.swift` `toXMLSortedByPosition()`, refactor the loops that iterate `runs`, `hyperlinks`, `fieldSimples`, `alternateContents`, and the marker collections. For each collection: separate into `explicit` (`position != nil`) and `appendees` (`position == nil`); compute `let nextPos = (explicit.compactMap(\.position).max() ?? 0) + 1`; emit explicit at their positions; emit appendees at `nextPos`, `nextPos + 1`, etc.
- [x] 3.5 Apply the same partition logic to the legacy `toXML()` emit path that touches the same collections — preserve the legacy ordering for any collection that doesn't reach the sort path.
- [x] 3.6 Run full `swift test` — assert no previously-green tests fail (legacy partition produces same observable behaviour for Reader-loaded typed children that all carry explicit positions).
- [x] 3.7 Run `swift test --filter Issue5MutationSurfaceTests` — confirm 3.1/3.2/3.3 pass.
- [x] 3.8 Verify acceptance: Paragraph sort-by-position emit SHALL partition typed children into explicit and append cohorts — the example table outcomes (empty + one → 1; [1,2] + one → 3; [1,100] + one → 101; [1,2] + two → 3,4) all hold via the new tests.

## 4. F13 — Run.toXML xml:space autosense (TDD: write tests first)

> Implements requirement: **Run.toXML SHALL auto-emit xml:space="preserve" when text contains semantically significant whitespace**
> Covers design decision: D3 — F13: `xml:space="preserve"` autosense in `Run.toXML()`, owner-correct fix

- [x] 4.1 [P] Write `testRunWithLeadingWhitespaceEmitsPreserveFlag` in `Tests/OOXMLSwiftTests/Issue5MutationSurfaceTests.swift` — `Run(text: " leading").toXML()` SHALL contain the substring `xml:space="preserve"`.
- [x] 4.2 [P] Write `testRunWithTrailingWhitespaceEmitsPreserveFlag` — `Run(text: "trailing ").toXML()` contains preserve flag.
- [x] 4.3 [P] Write `testRunWithConsecutiveInternalWhitespaceEmitsPreserveFlag` — `Run(text: "two  spaces").toXML()` contains preserve flag.
- [x] 4.4 [P] Write `testRunWithSingleInternalWhitespaceDoesNotEmitPreserveFlag` — `Run(text: "hello world").toXML()` does NOT contain `xml:space="preserve"` (single internal space is XML-normalised).
- [x] 4.5 [P] Write `testRunWithEmptyTextDoesNotEmitPreserveFlag` — `Run(text: "").toXML()` does NOT contain `xml:space="preserve"`.
- [x] 4.6 [P] Write `testRunWithTabAndNewlineWhitespacePatterns` — covers `"a\tb"` (no flag), `"a\t\tb"` (flag), `"\nleading-newline"` (flag) per the spec example table.
- [x] 4.7 In `Sources/OOXMLSwift/Models/Run.swift` `toXML()`, before composing the `<w:t>` element, compute `let needsPreserve = text.first?.isWhitespace == true || text.last?.isWhitespace == true || text.range(of: #"\s\s"#, options: .regularExpression) != nil`. If `needsPreserve`, emit `<w:t xml:space="preserve">` instead of `<w:t>`. Empty text SHALL fall through the cheap leading/trailing checks (both nil) and the regex SHALL also miss, so empty text emits `<w:t>` without the flag.
- [x] 4.8 Run `swift test --filter Issue5MutationSurfaceTests` — confirm 4.1 through 4.6 pass.
- [x] 4.9 Verify acceptance: Run.toXML SHALL auto-emit xml:space="preserve" when text contains semantically significant whitespace — every row of the spec example table (10 cases including tab/newline variants) is covered by tests 4.1-4.6.

## 5. Audit & regression sweep

> Implements requirement: **Round-trip SHALL preserve byte-equivalent output for unmutated input across all three fixes**

- [x] 5.1 Run full `swift test` — assert all 722 baseline tests pass plus the new tests added in groups 1-4 (target test count ~736-740 depending on parameterization). No previously-green test SHALL fail due to the deprecation, the position type cascade, or the xml:space autosense.
- [x] 5.2 Audit-discipline pass per `audit: true` (3 adversary lenses): Scoundrel — does the deprecation message leak any sensitive information? (No — it is a static string with no runtime data interpolation.) Lazy Developer — could a caller `// swiftlint:disable deprecated` to silence the F5 warning across the codebase? (Possible but visible in code review; the v0.22 removal forces eventual migration.) Confused Developer — could `position: Int? = nil` be misread as `position: Int = 0` in caller code? (No — Swift type system surfaces the difference at compile time; nil-coalescing is the migration path.)
- [x] 5.3 Write `testNoOpRoundTripMatchesV0214Baseline` — load a corpus document, write it back, re-read, and assert byte-equivalent output (or content-equivalent if file-system metadata makes byte equivalence brittle). Also assert pre-existing `xml:space="preserve"` flags survive the round-trip.
- [x] 5.4 Verify acceptance: Round-trip SHALL preserve byte-equivalent output for unmutated input across all three fixes — full test suite green; no-op round-trip output matches v0.21.4 baseline; pre-existing xml:space flags preserved.

## 6. Release prep

> Covers design decisions: D4 — Two-step deprecation timeline (v0.21.5 → v0.22); D5 — No new `OOXMLError` cases

- [x] 6.1 Bump `CHANGELOG.md` with `## [0.21.5] - <release-date>` entry. Group entries by F5 / F6 / F13 with brief callouts. Include "Migration" sub-section: (a) `hyperlink.text = "x"` callers see deprecation warning, migrate to `hyperlink.runs = [Run(text: "x")]` before v0.22; (b) `position: Int` reads need `pos ?? defaultValue` upgrade; (c) F13 autosense is transparent — no caller action needed.
- [x] 6.2 Add a v0.22 milestone note in `CHANGELOG.md` "Unreleased" section: `Hyperlink.text` setter will be removed entirely; consumers SHALL migrate to `.runs` direct assignment before v0.22.
