## Context

This is Change 1 of a two-change sequence resolving [`PsychQuant/ooxml-swift#1`](https://github.com/PsychQuant/ooxml-swift/issues/1) ("DocxReader.parseParagraph silently drops 5 of 7 RevisionTypes + skips 6 containers").

The issue diagnosis identified four parts:

- **Part A** — top-level switch expansion for `w:moveFrom` / `w:moveTo`
- **Part B** — nested `w:rPrChange` / `w:pPrChange` inside `w:rPr` / `w:pPr` property parsers
- **Part C** — container iteration for headers, footers, footnotes, endnotes
- **Part D** — defensive logging at `default: break`

Per the `spectra-discuss` conclusion, scope split is Option 2: this change ships A+D as a quick win; a follow-up change `docx-reader-nested-revisions-and-containers` ships B+C.

Current parser state (at ooxml-swift v0.5.6, commit `e5b3e78`):

- `DocxReader.swift:371-428` top-level switch handles only `r`, `ins`, `del`, `commentRangeStart`. Everything else hits `default: break` silently.
- `Revision` model in `Revision.swift` already declares all 7 `RevisionType` cases; only the parser is incomplete.
- Tests use `DocxReaderIntegrationTests.swift` for parser round-trips; no fixtures currently exercise moveFrom/moveTo.

## Goals / Non-Goals

**Goals:**

- Close the parser gap for the two top-level revision elements that can be added with no architectural change (`w:moveFrom`, `w:moveTo`).
- Establish a developer-visible signal for future parser gaps so that "we silently drop this element" is an observable state rather than a hidden failure.
- Ship this portion of #1 independently of the larger Parts B+C refactor so che-word-mcp users see incremental accuracy improvement quickly.
- Create the first formal spec capability `docx-revision-parsing` so follow-up changes have a spec surface to MODIFY rather than creating one anew.

**Non-Goals:**

- Not parsing `w:rPrChange`, `w:rPrChange2`, or `w:pPrChange`. These are nested inside `w:rPr` / `w:pPr` and require a deeper refactor that's part of Change 2.
- Not adding `Revision.source` field. The follow-up change introduces `source` when it adds container parsing (headers/footers/footnotes/endnotes) where the field becomes load-bearing. Adding it early would be a no-op struct growth.
- Not reading `word/header*.xml`, `word/footer*.xml`, `word/footnotes.xml`, or `word/endnotes.xml`. Deferred to Change 2.
- Not adding a formal logger framework or `swift-log` dependency. This change uses plain `print(...)` to stderr gated behind a static flag — minimal surface until the broader project decides on a logging strategy.
- Not rendering `moveFrom` / `moveTo` specially in `che-word-mcp` output formatters. The new revisions flow through the existing `getRevisions()` tuple return unchanged; display is handled by callers that already format `RevisionType.rawValue`.
- Not changing `Revision` / `RevisionType` public types. This change is purely parser coverage; no model or API surface change.

## Decisions

### Decision: Two-Element Scope for Top-Level Switch Expansion

Only `w:moveFrom` and `w:moveTo` are added to the top-level `switch childElement.localName` at `DocxReader.swift:371-428`. `w:rPrChange`, `w:rPrChange2`, `w:pPrChange` are NOT added here.

**Rationale**: `rPrChange` and `pPrChange` are structurally NESTED inside `w:rPr` and `w:pPr` elements in the OOXML spec. They are never direct children of `w:p`. Adding a top-level `case "rPrChange":` would not catch real-world documents because parse never sees `rPrChange` at that level. Parsing them requires descent into the property parsers — that's Change 2.

**Alternatives**:
- _Add all 5 missing cases to the top-level switch anyway_ — rejected because 3 of them would never match real input, creating dead code that implies broken coverage without fixing it.
- _Refactor property parsers first_ — rejected because Change 2 does exactly that; bundling them collapses the scope split back into one change.

### Decision: moveFrom and moveTo Mirror ins and del Structure

`w:moveFrom` parsing mirrors `w:del`: iterate nested `w:r` children, collect text as `originalText`, emit `Revision(type: .moveFrom, originalText: <text>, newText: nil, ...)`.

`w:moveTo` parsing mirrors `w:ins`: iterate nested `w:r` children, collect text as `newText`, emit `Revision(type: .moveTo, originalText: nil, newText: <text>, ...)`.

**Rationale**: The OOXML spec treats moveFrom as "this text was moved out of here" (semantically like deletion at the source) and moveTo as "this text was moved in to here" (semantically like insertion at the destination). Using the parallel text-field assignment matches callers' mental model without requiring any new abstractions.

**Alternatives**:
- _New struct `MoveRevision(sourceText, destinationText)`_ — rejected; `Revision` already has `originalText?` and `newText?` optional fields specifically to cover this one-sided shape.
- _Emit a single paired revision for moveFrom+moveTo_ — rejected because the parser sees the two elements in separate paragraph scans; pairing would require cross-paragraph state. If a caller needs pairing, it can correlate on `revId` which is preserved.

### Decision: Author and Date Extraction Reuses ins/del Helper Pattern

moveFrom and moveTo read `w:id`, `w:author`, `w:date` attributes the same way ins/del already do (explicit `childElement.attribute(forName:)` calls with the same ISO8601 formatter).

**Rationale**: This is the pattern currently at `DocxReader.swift:378-382` for `ins` and `400-403` for `del`. Repeating it for `moveFrom`/`moveTo` keeps the code symmetric. A future refactor could extract a helper function that takes the element and returns `(id, author, date)`, but that refactor is out of scope — the priority is closing the parser gap with minimal surface change.

**Alternatives**:
- _Extract helper function `parseRevisionAttributes(_:)`_ — rejected as scope creep; can be done later as a pure refactor without blocking this fix.

### Decision: Debug Logging Via Static Flag, Not Swift-log Dependency

`DocxReader.debugLoggingEnabled: Bool = false` static flag. When `true`, the `default:` branch of the paragraph switch emits `FileHandle.standardError.write(...)` with `"DocxReader.parseParagraph: skipped unknown element \(childElement.localName ?? "<nil>")\n"`.

**Rationale**:
- Adding a logging framework dependency (e.g., `swift-log`) is broader than this change's scope and should be a project-wide decision.
- `print(..., to: &FileHandle.standardError)` style writes have Foundation-only dependency, work on every supported platform, and carry zero performance cost when the flag is `false` (guarded early).
- The flag is static because there is one `DocxReader` per process in practice; tests that want to enable logging for a single test can `defer { DocxReader.debugLoggingEnabled = false }` to reset.

**Alternatives**:
- _Add `swift-log`_ — rejected as scope creep.
- _Throw on unknown elements_ — rejected as a BREAKING change for any real-world docx that contains unrecognized OOXML extensions (common — vendors add custom markup).
- _Accumulate unknown elements in a `parseWarnings: [String]` collection on the returned `WordDocument`_ — rejected as a public API expansion that Change 2 may or may not want to keep; simpler to start with opt-in print logging.

### Decision: Testability via Internal Visibility (not Word-built Fixture)

Test `parseParagraph` directly by relaxing its visibility from `private static` to `internal static`, then exercising it with hand-constructed `XMLElement` instances from tests using `@testable import OOXMLSwift`. No `.docx` file fixture is required.

**Rationale**:
- `parseParagraph` is a pure function of `(element, styles, numbering, relationships) -> Paragraph`. Tests that care about revision element recognition need only supply a synthetic `XMLElement` with the exact markup under test (e.g., `<w:p><w:moveFrom w:id="1" .../></w:p>`). They do not need a full `.docx` ZIP, `[Content_Types].xml`, or relationships scaffolding.
- The previous rationale (rejecting programmatic fixtures) focused on Word-vintage correctness (correlated paraIds across `commentsExtended.xml`). `parseParagraph` does not read `commentsExtended.xml` and does not correlate paraIds — those are separate read-path concerns. The decision was over-cautious relative to the function under test.
- Swift idiom: `@testable import` with `internal` visibility is the standard pattern for unit-testing otherwise-internal parser functions. `private` → `internal` is a small encapsulation give-back; no new public API surface.
- No new test helper / fixture pipeline to maintain; tests are a few lines of direct XMLElement construction each.

**Alternatives**:
- _Hand-build fixture.docx in Microsoft Word_ — rejected; blocks implementation on manual user action (which this automated apply flow cannot perform), and spec requirements describe parser behavior not fixture construction.
- _Programmatic minimal-docx helper zipping hand-crafted XML_ — rejected as scope creep; a ZIP helper makes sense as a future shared utility when multiple parser test suites need it, but for this change the internal-visibility path is simpler and sufficient.
- _Programmatic fixture via DocxWriter_ — rejected; `DocxWriter` does not currently emit move tracking markup, and extending the writer just to test the reader would conflate concerns.

### Decision: Patch Bump (v0.5.7), Not Minor Bump

Release ooxml-swift as v0.5.7, not v0.6.0.

**Rationale**:
- The change is strictly additive. `Revision` / `RevisionType` unchanged. `DocxReader.debugLoggingEnabled` is a new public property but defaults to `false` (invisible to callers that don't set it).
- `getRevisions()` tuple API unchanged — callers simply see MORE revisions on documents that use move tracking. This is a strict superset; no existing assertion about returned revisions becomes invalid.
- Following semver strictly: no breaking change + no new API surface that changes type signatures → patch bump is correct.

**Alternatives**:
- _v0.6.0 (minor)_ — rejected; reserved for Change 2 which introduces `Revision.source` and `getRevisionsFull()`.

## Risks / Trade-offs

- **Risk**: the fixture may not exercise `w:moveFrom` exactly as Word writes it in 2026-vintage docx files. OOXML move markup has evolved (there's `w:move` + `commentsExtended.xml` paraIds in newer versions).
  - **Mitigation**: Record the fixture with current Microsoft Word (not an older copy). After committing, verify the fixture's XML by `unzip -p fixture.docx word/document.xml | xmllint --format -` and confirm `w:moveFrom` / `w:moveTo` elements are present at the expected nesting level.

- **Risk**: downstream che-word-mcp tests that assert on specific revision counts may fail once this ships, if any test document happens to use move tracking.
  - **Mitigation**: che-word-mcp's test suite was just exercised at v1.19.0 (30 tests green) with ooxml-swift v0.5.6. No test fixture there uses move tracking (only a small fixture with one appended paragraph in `WordMCPServerTests`). Verified no regression risk for the current che-word-mcp corpus.

- **Trade-off**: shipping Parts A+D separately from B+C means two `git tag` + `git push` + CHANGELOG cycles for ooxml-swift. One release would be less administrative overhead.
  - **Mitigation**: The administrative cost is small (~5 min per release). The value of shipping the quick fix immediately — making che-word-mcp manuscript-review tools report accurately on move-tracked documents — exceeds the cost. Parts B+C require test fixtures and a deeper property-parser refactor that would hold the A+D fix hostage if bundled.

- **Trade-off**: `DocxReader.debugLoggingEnabled` is a static mutable flag — not thread-safe if multiple threads toggle it concurrently during parsing.
  - **Mitigation**: Toggles happen at test setup / teardown, not during parallel document parsing. Document this in the property's doc-comment ("toggle at setup time, not during concurrent parses"). If the project later adopts actor-based concurrency, the flag migrates to an actor-isolated property.

## Migration Plan

1. **Within this change**:
   1. Add moveFrom and moveTo cases to the switch (`DocxReader.swift:428` area).
   2. Add `public static var debugLoggingEnabled = false` to `DocxReader` type.
   3. Replace `default: break` with conditional logging.
   4. Commit hand-built `revisions-moves.docx` fixture under Tests/.../Fixtures/.
   5. Write `RevisionParsingTests.swift` or add test methods to `DocxReaderIntegrationTests.swift`.
   6. Run `swift test` — confirm all 183 existing tests + ~4 new tests pass.
   7. Update `CHANGELOG.md` with [Unreleased] entry.

2. **Release sequence**:
   1. Commit all changes to `packages/ooxml-swift/` with message linking this change and issue #1.
   2. Tag `v0.5.7`, push main + tag to `github.com/PsychQuant/ooxml-swift`.
   3. Optional: run `swift package update` in `mcp/che-word-mcp` to verify the new version resolves cleanly (not mandatory — next che-word-mcp build picks it up automatically).

3. **Rollback**: revert the single commit in `packages/ooxml-swift/`, push a new tag v0.5.8 reverting. The additive nature means rollback is safe — consumers that already saw the new revisions will just see fewer on their next build.

## Open Questions

- _(none open as of proposal — all key decisions resolved during `/spectra-discuss` phase)_
