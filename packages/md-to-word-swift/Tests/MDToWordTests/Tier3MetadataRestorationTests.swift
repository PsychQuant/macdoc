import XCTest
@testable import MDToWord
import OOXMLSwift

/// Unit coverage for `MarkdownToWordConverter.convertMarkdown(_:metadata:...)`
/// (PsychQuant/macdoc#206). The end-to-end round-trip through a real
/// `.docx` + sidecar YAML lives in `E2ETests.testE2E_Tier3MetadataRestoration`;
/// this file isolates the restoration entry point itself against
/// directly-constructed `DocumentMetadata` values so each edge case is
/// independent of the forward converter / DocxWriter / DocxReader pipeline.
final class Tier3MetadataRestorationTests: XCTestCase {
    private let converter = MarkdownToWordConverter()

    // MARK: - metadata: nil behaves exactly like the base overload

    func testNilMetadataMatchesBaseOverload() throws {
        let markdown = "Plain paragraph, no formatting."

        let withoutMetadataParam = try converter.convertMarkdown(markdown)
        let withNilMetadata = try converter.convertMarkdown(markdown, metadata: nil)

        // Two independent `convertMarkdown` calls each mint a fresh random
        // `w14ParaId`/`w14TextId` (see RoundTripTests.stripVolatileIDs and
        // PsychQuant/macdoc#155) — that noise is expected and unrelated to
        // whether the `metadata:` overload changes behavior, so it is
        // stripped before comparing.
        XCTAssertEqual(
            stripVolatileIDs(withoutMetadataParam).body.children,
            stripVolatileIDs(withNilMetadata).body.children
        )
    }

    // MARK: - index out of bounds is skipped, not thrown

    func testOutOfBoundsIndexIsSilentlySkipped() throws {
        let markdown = "Only one paragraph here."

        var paragraphMeta = ParagraphMeta(index: 5) // document only has index 0
        paragraphMeta.alignment = "center"
        let metadata = DocumentMetadata(paragraphs: [paragraphMeta])

        // Must not throw despite the dangling index.
        let document = try converter.convertMarkdown(markdown, metadata: metadata)

        XCTAssertEqual(document.body.children.count, 1)
        guard case .paragraph(let paragraph) = document.body.children[0] else {
            return XCTFail("Expected the sole body child to be a paragraph")
        }
        XCTAssertNil(paragraph.properties.alignment, "Out-of-range metadata must not mutate any paragraph")
    }

    func testNegativeIndexIsSilentlySkipped() throws {
        let markdown = "Only one paragraph here."

        var paragraphMeta = ParagraphMeta(index: -1)
        paragraphMeta.alignment = "center"
        let metadata = DocumentMetadata(paragraphs: [paragraphMeta])

        let document = try converter.convertMarkdown(markdown, metadata: metadata)

        guard case .paragraph(let paragraph) = document.body.children[0] else {
            return XCTFail("Expected the sole body child to be a paragraph")
        }
        XCTAssertNil(paragraph.properties.alignment)
    }

    // MARK: - index landing on a non-paragraph body child is skipped

    func testIndexOnTableIsSilentlySkipped() throws {
        let markdown = """
        Intro paragraph.

        | A | B |
        | - | - |
        | 1 | 2 |
        """

        let document = try converter.convertMarkdown(markdown)
        // Sanity: confirm the fixture actually produced [paragraph, table]
        // before asserting anything about restoration behavior.
        guard document.body.children.count >= 2,
              case .table = document.body.children[1] else {
            return XCTFail("Fixture expected to produce a table at index 1, got: \(document.body.children)")
        }

        var tableIndexedMeta = ParagraphMeta(index: 1) // index 1 is the table, not a paragraph
        tableIndexedMeta.alignment = "center"
        let metadata = DocumentMetadata(paragraphs: [tableIndexedMeta])

        // Must not throw or crash despite the type mismatch at index 1.
        let restored = try converter.convertMarkdown(markdown, metadata: metadata)
        XCTAssertEqual(restored.body.children.count, document.body.children.count)
        guard case .table = restored.body.children[1] else {
            return XCTFail("Table at index 1 must remain a table, not be overwritten")
        }
    }

    // MARK: - partial fields: only the fields present in metadata are applied

    func testOnlyAlignmentIsAppliedWhenOtherFieldsAreNil() throws {
        let markdown = "Centered, otherwise default."

        var paragraphMeta = ParagraphMeta(index: 0)
        paragraphMeta.alignment = "center"
        // spacing / indentation / keepNext / keepLines / pageBreakBefore /
        // border / shading are all left nil.
        let metadata = DocumentMetadata(paragraphs: [paragraphMeta])

        let document = try converter.convertMarkdown(markdown, metadata: metadata)

        guard case .paragraph(let paragraph) = document.body.children[0] else {
            return XCTFail("Expected a paragraph at index 0")
        }
        XCTAssertEqual(paragraph.properties.alignment, .center)
        XCTAssertNil(paragraph.properties.indentation)
        XCTAssertFalse(paragraph.properties.keepNext)
        XCTAssertFalse(paragraph.properties.keepLines)
        XCTAssertFalse(paragraph.properties.pageBreakBefore)
        XCTAssertNil(paragraph.properties.border)
        XCTAssertNil(paragraph.properties.shading)
    }

    func testSpacingIndentationAndKeepFlagsAreRestoredTogether() throws {
        let markdown = "A paragraph with several Tier 3 formatting fields."

        var paragraphMeta = ParagraphMeta(index: 0)
        paragraphMeta.spacing = SpacingMeta(before: 240, after: 120, line: 360)
        paragraphMeta.indentation = IndentationMeta(left: 720, right: 0, firstLine: 240, hanging: nil)
        paragraphMeta.keepNext = true
        paragraphMeta.keepLines = true
        paragraphMeta.pageBreakBefore = true
        let metadata = DocumentMetadata(paragraphs: [paragraphMeta])

        let document = try converter.convertMarkdown(markdown, metadata: metadata)

        guard case .paragraph(let paragraph) = document.body.children[0] else {
            return XCTFail("Expected a paragraph at index 0")
        }
        XCTAssertEqual(paragraph.properties.spacing?.before, 240)
        XCTAssertEqual(paragraph.properties.spacing?.after, 120)
        XCTAssertEqual(paragraph.properties.spacing?.line, 360)
        XCTAssertEqual(paragraph.properties.indentation?.left, 720)
        XCTAssertEqual(paragraph.properties.indentation?.right, 0)
        XCTAssertEqual(paragraph.properties.indentation?.firstLine, 240)
        XCTAssertNil(paragraph.properties.indentation?.hanging)
        XCTAssertTrue(paragraph.properties.keepNext)
        XCTAssertTrue(paragraph.properties.keepLines)
        XCTAssertTrue(paragraph.properties.pageBreakBefore)
    }

    // MARK: - composite fields are whole-value snapshots, not sparse per-field patches

    func testSpacingSnapshotReplacesRatherThanMergesSubFields() {
        // Pins the semantics documented on Tier3MetadataRestorer: when
        // `ParagraphMeta.spacing` is non-nil it is a *complete* snapshot of
        // the original paragraph's spacing, not a sparse patch to overlay
        // onto whatever the target already has. A pre-existing `lineRule`
        // that this SpacingMeta instance does NOT carry (nil) must NOT
        // survive — that would silently turn this into field-level merge,
        // the behavior Tier3MetadataRestorer's doc-comment explicitly says
        // this is not. (`lineRule` itself is expressible since
        // PsychQuant/macdoc#220 item 1 — see
        // `testLineRuleIsRestoredWhenPresentInSidecar` below for the
        // positive case; this test is about the *absent* case.)
        // Uses `@testable import` to call the restorer directly, since the
        // public `convertMarkdown(_:metadata:)` entry point has no way to
        // inject a pre-existing composite value to overwrite.
        var paragraph = Paragraph(text: "Pre-existing spacing.")
        paragraph.properties.spacing = Spacing(before: 999, after: 999, line: 999, lineRule: .exact)
        var document = WordDocument()
        document.body.children = [.paragraph(paragraph)]

        // Sidecar snapshot only carries `before` — mirrors a source
        // paragraph whose Spacing had no explicit after/line/lineRule.
        var paragraphMeta = ParagraphMeta(index: 0)
        paragraphMeta.spacing = SpacingMeta(before: 50, after: nil, line: nil, lineRule: nil)
        let metadata = DocumentMetadata(paragraphs: [paragraphMeta])

        Tier3MetadataRestorer.restore(metadata, onto: &document)

        guard case .paragraph(let restored) = document.body.children[0] else {
            return XCTFail("Expected a paragraph at index 0")
        }
        XCTAssertEqual(restored.properties.spacing?.before, 50, "The captured sub-field must apply")
        XCTAssertNil(restored.properties.spacing?.after, "Un-captured sub-fields must be cleared, not inherited from the pre-existing value")
        XCTAssertNil(restored.properties.spacing?.line, "Un-captured sub-fields must be cleared, not inherited from the pre-existing value")
        XCTAssertNil(restored.properties.spacing?.lineRule, "A SpacingMeta entry with lineRule == nil must clear a pre-existing lineRule, not inherit it")
    }

    // MARK: - lineRule (PsychQuant/macdoc#220 item 1)

    func testLineRuleIsRestoredWhenPresentInSidecar() throws {
        let markdown = "A paragraph with an explicit line rule."

        var paragraphMeta = ParagraphMeta(index: 0)
        paragraphMeta.spacing = SpacingMeta(before: 240, after: 120, line: 360, lineRule: "exact")
        let metadata = DocumentMetadata(paragraphs: [paragraphMeta])

        let document = try converter.convertMarkdown(markdown, metadata: metadata)

        guard case .paragraph(let paragraph) = document.body.children[0] else {
            return XCTFail("Expected a paragraph at index 0")
        }
        XCTAssertEqual(paragraph.properties.spacing?.lineRule, .exact)
    }

    func testInvalidLineRuleRawValueIsIgnoredWithoutCrashing() throws {
        let markdown = "A paragraph with a bogus line rule value."

        var paragraphMeta = ParagraphMeta(index: 0)
        paragraphMeta.spacing = SpacingMeta(line: 360, lineRule: "wobbly") // not a real LineRule case
        let metadata = DocumentMetadata(paragraphs: [paragraphMeta])

        let document = try converter.convertMarkdown(markdown, metadata: metadata)

        guard case .paragraph(let paragraph) = document.body.children[0] else {
            return XCTFail("Expected a paragraph at index 0")
        }
        XCTAssertEqual(paragraph.properties.spacing?.line, 360, "The recognized sibling field must still apply")
        XCTAssertNil(paragraph.properties.spacing?.lineRule, "Unrecognized lineRule rawValue must not be force-applied")
    }

    func testSpacingIsPreservedWhenMetadataHasNoSpacingEntryAtAll() {
        // The complement of the above: when `ParagraphMeta.spacing` itself
        // is nil (the paragraph has no Tier 3 spacing entry in the
        // sidecar), the pre-existing value must be left completely alone —
        // "no entry" and "an entry with all-nil sub-fields" are different
        // things, and only the latter is a snapshot-replace.
        var paragraph = Paragraph(text: "Pre-existing spacing, no sidecar entry for it.")
        paragraph.properties.spacing = Spacing(before: 111, after: 222, line: 333, lineRule: .exact)
        var document = WordDocument()
        document.body.children = [.paragraph(paragraph)]

        var paragraphMeta = ParagraphMeta(index: 0)
        paragraphMeta.alignment = "center" // some other field IS present, spacing is not
        let metadata = DocumentMetadata(paragraphs: [paragraphMeta])

        Tier3MetadataRestorer.restore(metadata, onto: &document)

        guard case .paragraph(let restored) = document.body.children[0] else {
            return XCTFail("Expected a paragraph at index 0")
        }
        XCTAssertEqual(restored.properties.spacing?.before, 111)
        XCTAssertEqual(restored.properties.spacing?.after, 222)
        XCTAssertEqual(restored.properties.spacing?.line, 333)
        XCTAssertEqual(restored.properties.spacing?.lineRule, .exact)
    }

    func testBorderAndShadingAreRestored() throws {
        let markdown = "A paragraph with a border and shading."

        var paragraphMeta = ParagraphMeta(index: 0)
        paragraphMeta.border = ParagraphBorderMeta(
            top: nil,
            bottom: BorderStyleMeta(type: "single", color: "C8C8C8", size: 8),
            left: nil,
            right: nil
        )
        paragraphMeta.shading = ShadingMeta(fill: "F7F7F7", pattern: "clear")
        let metadata = DocumentMetadata(paragraphs: [paragraphMeta])

        let document = try converter.convertMarkdown(markdown, metadata: metadata)

        guard case .paragraph(let paragraph) = document.body.children[0] else {
            return XCTFail("Expected a paragraph at index 0")
        }
        XCTAssertNil(paragraph.properties.border?.top)
        // ParagraphBorderType / ShadingPattern are raw-value enums that do
        // not declare Equatable conformance, so compare via .rawValue.
        XCTAssertEqual(paragraph.properties.border?.bottom?.type.rawValue, "single")
        XCTAssertEqual(paragraph.properties.border?.bottom?.color, "C8C8C8")
        XCTAssertEqual(paragraph.properties.border?.bottom?.size, 8)
        XCTAssertEqual(paragraph.properties.shading?.fill, "F7F7F7")
        XCTAssertEqual(paragraph.properties.shading?.pattern?.rawValue, "clear")
    }

    // MARK: - commentIds / bookmarkNames are not restored in this release
    // (evaluated and declined for #220 items 2/3, not ruled out
    // permanently — see Tier3MetadataRestorer's doc comment for the
    // concrete blockers and the unblocking path)

    func testCommentIdsAndBookmarkNamesAreNotRestoredInThisRelease() throws {
        // Per Tier3MetadataRestorer's doc-comment: these two fields were
        // evaluated for #220 and declined for THIS release — not ruled out
        // permanently — because the sidecar does not capture the range
        // endpoints reconstruction would need (see PsychQuant/macdoc#220
        // items 2/3). Unlike `runs` (below), there is no fingerprint-gated
        // path that ever restores them today: this test pins that as
        // observable behavior regardless of whether a matching
        // textFingerprint is present, so a future change that silently
        // starts (or silently fails to) restore them is caught either way.
        let markdown = "A paragraph that used to carry a comment and bookmark."

        var paragraphMeta = ParagraphMeta(index: 0)
        paragraphMeta.textFingerprint = ParagraphFingerprint.compute(markdown)
        paragraphMeta.commentIds = [1]
        paragraphMeta.bookmarkNames = ["_Ref12345"]
        let metadata = DocumentMetadata(paragraphs: [paragraphMeta])

        let document = try converter.convertMarkdown(markdown, metadata: metadata)

        guard case .paragraph(let paragraph) = document.body.children[0] else {
            return XCTFail("Expected a paragraph at index 0")
        }
        XCTAssertTrue(paragraph.commentIds.isEmpty)
        XCTAssertTrue(paragraph.bookmarks.isEmpty)
    }

    // MARK: - runs are restored, but ONLY when a matching exactTextFingerprint
    // gates them — a byte-exact check, deliberately stricter than the loose
    // textFingerprint used for paragraph-level fields (PsychQuant/macdoc#220
    // items 4/5; the exact/loose split itself is a follow-up fix — see
    // ParagraphFingerprint's doc comment for why a loose match alone is NOT
    // safe for run-offset restoration)

    func testRunFormattingIsNotAppliedWithoutAnExactTextFingerprint() throws {
        // Old-sidecar backward compat: a `ParagraphMeta` with `runs`
        // populated but no `exactTextFingerprint` (as every sidecar written
        // before word-to-md-swift ≥ 1.1.0 looks) must NOT have its `runs`
        // applied — there is no way to verify the freshly-converted
        // paragraph's runs still line up with the offsets `RunMeta.range`
        // was captured against, so this restorer stays conservative and
        // leaves `runs` untouched, exactly as it did before #220.
        let markdown = "A paragraph that used to carry per-run formatting."

        var paragraphMeta = ParagraphMeta(index: 0)
        // exactTextFingerprint (and textFingerprint) deliberately left nil.
        var runMeta = RunMeta(range: [0, 1])
        runMeta.fontName = "Arial"
        paragraphMeta.runs = [runMeta]
        let metadata = DocumentMetadata(paragraphs: [paragraphMeta])

        let document = try converter.convertMarkdown(markdown, metadata: metadata)

        guard case .paragraph(let paragraph) = document.body.children[0] else {
            return XCTFail("Expected a paragraph at index 0")
        }
        XCTAssertNil(paragraph.runs.first?.properties.fontName)
    }

    func testRunFormattingIsAppliedWhenExactFingerprintMatches() throws {
        let markdown = "Bold middle word plain."
        // Runs text on the reverse side is exactly the markdown source here
        // (no escaping, no smart-punctuation substitution), so the exact
        // fingerprint over the original run text and over this string are
        // the same computation.

        var paragraphMeta = ParagraphMeta(index: 0)
        paragraphMeta.textFingerprint = ParagraphFingerprint.compute(markdown)
        paragraphMeta.exactTextFingerprint = ParagraphFingerprint.computeExact(markdown)
        // "middle" is characters [5, 11) in "Bold middle word plain."
        // ("Bold " is 5 chars: B-o-l-d-space).
        var runMeta = RunMeta(range: [5, 11])
        runMeta.fontName = "Georgia"
        runMeta.color = "FF0000"
        paragraphMeta.runs = [runMeta]
        let metadata = DocumentMetadata(paragraphs: [paragraphMeta])

        let document = try converter.convertMarkdown(markdown, metadata: metadata)

        guard case .paragraph(let paragraph) = document.body.children[0] else {
            return XCTFail("Expected a paragraph at index 0")
        }
        let fullText = paragraph.runs.map(\.text).joined()
        XCTAssertEqual(fullText, markdown, "Splitting runs must not change the paragraph's overall visible text")

        // Directly assert the formatted substring is exactly "middle", not
        // merely "some run inside a range" — pins the actual claim the test
        // name makes (a prior version of this test used the wrong range,
        // [11, 17) = " word " instead of [5, 11) = "middle", and passed
        // vacuously because its own assertion loop re-used the same wrong
        // bounds; caught by Codex cross-model review round 1).
        let formattedText = paragraph.runs
            .filter { $0.properties.fontName == "Georgia" }
            .map(\.text)
            .joined()
        XCTAssertEqual(formattedText, "middle")

        var cursor = 0
        for run in paragraph.runs {
            let range = cursor..<(cursor + run.text.count)
            cursor = range.upperBound
            if range.lowerBound >= 5 && range.upperBound <= 11 {
                XCTAssertEqual(run.properties.fontName, "Georgia", "Run '\(run.text)' at \(range) should be formatted")
                XCTAssertEqual(run.properties.color, "FF0000")
            } else {
                XCTAssertNotEqual(run.properties.fontName, "Georgia", "Run '\(run.text)' at \(range) should NOT be formatted")
            }
        }
    }

    func testRunFormattingSurvivesRunCoalescingAcrossACombiningCharacterBoundary() {
        // Reproduces Codex cross-model review round 2's NEW-1 finding
        // directly: a base letter ("e") and a combining acute accent
        // (U+0301) captured as TWO separately-formatted runs on the forward
        // side — "e" is 1 Character AND 1 scalar in isolation, "\u{0301}"
        // is likewise 1 Character and 1 scalar in isolation, so
        // `RunMeta.range` for the "bc" that follows is [2, 4) either way in
        // THIS forward-side fixture (the two coordinate systems don't yet
        // diverge on the forward side alone — see
        // word-to-md-swift's `testRunMetaRangeIsMeasuredInUnicodeScalarsNotCharacters`
        // for where they do). The divergence shows up HERE, on the reverse
        // side: once reconstructed into a SINGLE run "e\u{0301}bc", the
        // base+combining-mark pair merges into ONE Swift `Character`
        // ("é"), so a naive `Character`-based split would place "bc" at
        // [1, 3) instead of [2, 4) — silently formatting "́b" (accent +
        // "b") instead of "bc". Scalar-based splitting (this restorer's
        // actual implementation) is immune: the merge never happens at the
        // scalar level, so [2, 4) still lands on exactly "bc".
        let combined = "e\u{0301}bc" // 1 Character "é" + "b" + "c" = 3 Characters, but 4 scalars
        XCTAssertEqual(combined.count, 3, "Fixture assumption: base+combining-mark merges into ONE Character once combined")
        XCTAssertEqual(combined.unicodeScalars.count, 4, "Fixture assumption: still 4 scalars")

        var document = WordDocument()
        document.body.children = [.paragraph(Paragraph(text: combined))]

        var meta = ParagraphMeta(index: 0)
        meta.textFingerprint = ParagraphFingerprint.compute(combined)
        meta.exactTextFingerprint = ParagraphFingerprint.computeExact(combined)
        var runMeta = RunMeta(range: [2, 4]) // scalar offsets: targets "bc"
        runMeta.fontName = "Georgia"
        meta.runs = [runMeta]
        let metadata = DocumentMetadata(paragraphs: [meta])

        Tier3MetadataRestorer.restore(metadata, onto: &document)

        guard case .paragraph(let restored) = document.body.children[0] else {
            return XCTFail("Expected a paragraph at index 0")
        }
        let fullText = restored.runs.map(\.text).joined()
        XCTAssertEqual(fullText, combined, "Splitting must not change the paragraph's overall visible text")

        let formattedText = restored.runs
            .filter { $0.properties.fontName == "Georgia" }
            .map(\.text)
            .joined()
        XCTAssertEqual(formattedText, "bc", "Scalar-based offsets must land on exactly \"bc\", not \"é\"-adjacent text")

        let unformattedText = restored.runs
            .filter { $0.properties.fontName != "Georgia" }
            .map(\.text)
            .joined()
        XCTAssertEqual(unformattedText, "e\u{0301}", "The base+combining-mark pair must be left unformatted, intact")
    }

    func testRunFormattingIsNotAppliedWhenLooseFingerprintMatchesButRawTextChangedByWhitespaceCollapse() {
        // Reproduces the exact scenario a Codex cross-model review round 1
        // finding identified as unsafe: original text "A  B" (two spaces)
        // and current text "A B" (one space) share a LOOSE fingerprint
        // match (both normalize to "A B"), but they are different lengths —
        // a RunMeta.range captured against the 4-character original is not
        // safely appliable to the 3-character current text. This is why
        // `runs` restoration must gate on exactTextFingerprint, never on
        // textFingerprint alone.
        var document = WordDocument()
        document.body.children = [.paragraph(Paragraph(text: "A B"))]

        var meta = ParagraphMeta(index: 0)
        meta.textFingerprint = ParagraphFingerprint.compute("A  B") // loose: matches "A B" too
        meta.exactTextFingerprint = ParagraphFingerprint.computeExact("A  B") // exact: does NOT match "A B"
        meta.alignment = "center"
        var runMeta = RunMeta(range: [3, 4]) // targets "B" in the ORIGINAL "A  B"
        runMeta.fontName = "Arial"
        meta.runs = [runMeta]
        let metadata = DocumentMetadata(paragraphs: [meta])

        let report = Tier3MetadataRestorer.restore(metadata, onto: &document)

        guard case .paragraph(let restored) = document.body.children[0] else {
            return XCTFail("Expected a paragraph at index 0")
        }
        XCTAssertEqual(restored.properties.alignment, .center, "Paragraph-level fields still apply on a loose match")
        XCTAssertNil(restored.runs.first?.properties.fontName, "Run-level fields must NOT apply without an exact match")
        XCTAssertEqual(report.appliedCount, 1)
        XCTAssertEqual(report.runsSkipped, [
            Tier3RestorationReport.RunsSkippedEntry(index: 0, reason: .exactFingerprintMismatchOrAbsent),
        ])
    }

    func testRunFormattingIsNotAppliedWhenLooseFingerprintMatchesButRawTextChangedByTypographicSubstitution() throws {
        // Same fix, exercised through the real markdown parser: "a---bcdef"
        // round-trips through swift-markdown's default smart-punctuation
        // substitution to "a—bcdef" (em dash) with no actual edit. The loose
        // fingerprint of the ORIGINAL "a---bcdef" matches the ACTUAL parsed
        // text ("a—bcdef") — so paragraph-level fields still apply — but the
        // exact fingerprint does not, so `runs` must be withheld.
        //
        // Uses a longer suffix than a minimal "a---bc" fixture deliberately
        // (Codex cross-model review round 2 NEW-2): with only "bc" after the
        // dash, [4, 5) clamps to an empty, in-bounds-but-zero-width range
        // against the 4-character substituted text, so the test would pass
        // vacuously even if the implementation regressed to gating `runs` on
        // the LOOSE fingerprint (the clamped range would format nothing
        // either way). With "bcdef" after the dash, [4, 5) against the
        // 7-character substituted text is a real, non-empty, IN-BOUNDS
        // range that lands on "d" (a different character than the
        // originally-targeted "b") — so a regression to the unsafe gate
        // would visibly mis-format "d", not silently no-op.
        let markdown = "a---bcdef"

        var paragraphMeta = ParagraphMeta(index: 0)
        paragraphMeta.textFingerprint = ParagraphFingerprint.compute(markdown)
        paragraphMeta.exactTextFingerprint = ParagraphFingerprint.computeExact(markdown)
        paragraphMeta.alignment = "center"
        var runMeta = RunMeta(range: [4, 5]) // targets "b" in the ORIGINAL "a---bcdef"
        runMeta.fontName = "Arial"
        paragraphMeta.runs = [runMeta]
        let metadata = DocumentMetadata(paragraphs: [paragraphMeta])

        let (document, report) = try converter.convertMarkdownReportingTier3Restoration(markdown, metadata: metadata)

        guard case .paragraph(let paragraph) = document.body.children[0] else {
            return XCTFail("Expected a paragraph at index 0")
        }
        // Sanity: confirm the parser actually substituted the dash AND that
        // offset 4 is a real, in-bounds, non-"b" character in the
        // substituted text — i.e. this test is exercising the scenario
        // where an unsafe gate would mis-format something specific, not a
        // no-op.
        let actualText = paragraph.runs.map(\.text).joined()
        XCTAssertNotEqual(actualText, markdown, "Fixture assumption: swift-markdown must have substituted the ASCII dash sequence")
        XCTAssertEqual(actualText, "a\u{2014}bcdef")
        let scalars = Array(actualText.unicodeScalars)
        XCTAssertTrue(scalars.count > 5, "Fixture assumption: offset [4, 5) must be in-bounds against the substituted text")
        XCTAssertNotEqual(String(scalars[4]), "b", "Fixture assumption: offset 4 must NOT coincidentally still be \"b\"")

        XCTAssertEqual(paragraph.properties.alignment, .center, "Paragraph-level fields still apply on a loose match")
        XCTAssertTrue(paragraph.runs.allSatisfy { $0.properties.fontName != "Arial" }, "Run-level fields must NOT apply without an exact match")
        XCTAssertEqual(report.runsSkipped, [
            Tier3RestorationReport.RunsSkippedEntry(index: 0, reason: .exactFingerprintMismatchOrAbsent),
        ])
    }

    func testEntireEntryIsSkippedWhenFingerprintMismatches() throws {
        // The central scenario #220 exists to fix: a stale sidecar entry
        // (captured against different text than what is now at this index)
        // must not silently apply ANY of its fields — not just `runs`, but
        // also the paragraph-level fields #206 already restores
        // unconditionally for fingerprint-less (old) sidecars. A present
        // but WRONG fingerprint is positive evidence of misalignment, so
        // the whole entry is skipped.
        let markdown = "This paragraph's real text -- with a dash... and \"quotes\"."

        var paragraphMeta = ParagraphMeta(index: 0)
        paragraphMeta.textFingerprint = ParagraphFingerprint.compute("Completely different captured text.")
        paragraphMeta.alignment = "center"
        var runMeta = RunMeta(range: [0, 4])
        runMeta.fontName = "Arial"
        paragraphMeta.runs = [runMeta]
        let metadata = DocumentMetadata(paragraphs: [paragraphMeta])

        let document = try converter.convertMarkdown(markdown, metadata: metadata)

        guard case .paragraph(let paragraph) = document.body.children[0] else {
            return XCTFail("Expected a paragraph at index 0")
        }
        XCTAssertNil(paragraph.properties.alignment, "Paragraph-level fields must NOT apply when the fingerprint mismatches")
        XCTAssertNil(paragraph.runs.first?.properties.fontName, "Run-level fields must NOT apply when the fingerprint mismatches")
    }

    func testParagraphLevelFieldsStillApplyWhenFingerprintMatches() throws {
        // Complement of the mismatch case: a CORRECT fingerprint must not
        // regress the #206 behavior of restoring paragraph-level fields.
        let markdown = "This paragraph's real text -- with a dash... and \"quotes\"."

        var paragraphMeta = ParagraphMeta(index: 0)
        paragraphMeta.textFingerprint = ParagraphFingerprint.compute(markdown)
        paragraphMeta.alignment = "center"
        let metadata = DocumentMetadata(paragraphs: [paragraphMeta])

        let document = try converter.convertMarkdown(markdown, metadata: metadata)

        guard case .paragraph(let paragraph) = document.body.children[0] else {
            return XCTFail("Expected a paragraph at index 0")
        }
        XCTAssertEqual(paragraph.properties.alignment, .center)
    }

    // MARK: - Tier3RestorationReport (PsychQuant/macdoc#220 item 5 — "回報型別用封閉列舉")

    func testReportRecordsAppliedCount() {
        var document = WordDocument()
        document.body.children = [.paragraph(Paragraph(text: "Text.")), .paragraph(Paragraph(text: "More text."))]

        var metaA = ParagraphMeta(index: 0)
        metaA.alignment = "center"
        var metaB = ParagraphMeta(index: 1)
        metaB.alignment = "right"
        let metadata = DocumentMetadata(paragraphs: [metaA, metaB])

        let report = Tier3MetadataRestorer.restore(metadata, onto: &document)
        XCTAssertEqual(report.appliedCount, 2)
        XCTAssertTrue(report.skipped.isEmpty)
    }

    func testReportRecordsIndexOutOfRange() {
        var document = WordDocument()
        document.body.children = [.paragraph(Paragraph(text: "Only paragraph."))]

        var meta = ParagraphMeta(index: 5)
        meta.alignment = "center"
        let metadata = DocumentMetadata(paragraphs: [meta])

        let report = Tier3MetadataRestorer.restore(metadata, onto: &document)
        XCTAssertEqual(report.appliedCount, 0)
        XCTAssertEqual(report.skipped, [Tier3RestorationReport.SkippedEntry(index: 5, reason: .indexOutOfRange)])
    }

    func testReportRecordsIndexNotAParagraph() {
        var document = WordDocument()
        document.body.children = [.table(Table(rows: []))]

        var meta = ParagraphMeta(index: 0)
        meta.alignment = "center"
        let metadata = DocumentMetadata(paragraphs: [meta])

        let report = Tier3MetadataRestorer.restore(metadata, onto: &document)
        XCTAssertEqual(report.appliedCount, 0)
        XCTAssertEqual(report.skipped, [Tier3RestorationReport.SkippedEntry(index: 0, reason: .indexNotAParagraph)])
    }

    func testReportRecordsFingerprintMismatch() {
        var document = WordDocument()
        document.body.children = [.paragraph(Paragraph(text: "Actual text."))]

        var meta = ParagraphMeta(index: 0)
        meta.textFingerprint = ParagraphFingerprint.compute("Different captured text.")
        meta.alignment = "center"
        let metadata = DocumentMetadata(paragraphs: [meta])

        let report = Tier3MetadataRestorer.restore(metadata, onto: &document)
        XCTAssertEqual(report.appliedCount, 0)
        XCTAssertEqual(report.skipped, [Tier3RestorationReport.SkippedEntry(index: 0, reason: .fingerprintMismatch)])
    }

    func testReportMixesAppliedAndSkippedEntriesIndependently() {
        var document = WordDocument()
        document.body.children = [
            .paragraph(Paragraph(text: "First.")),
            .paragraph(Paragraph(text: "Second.")),
            .table(Table(rows: [])),
        ]

        var ok = ParagraphMeta(index: 0)
        ok.alignment = "center"
        var mismatched = ParagraphMeta(index: 1)
        mismatched.textFingerprint = ParagraphFingerprint.compute("Wrong text entirely.")
        mismatched.alignment = "right"
        var onTable = ParagraphMeta(index: 2)
        onTable.alignment = "center"
        var outOfRange = ParagraphMeta(index: 99)
        outOfRange.alignment = "center"

        let metadata = DocumentMetadata(paragraphs: [ok, mismatched, onTable, outOfRange])
        let report = Tier3MetadataRestorer.restore(metadata, onto: &document)

        XCTAssertEqual(report.appliedCount, 1)
        XCTAssertEqual(Set(report.skipped), Set([
            Tier3RestorationReport.SkippedEntry(index: 1, reason: .fingerprintMismatch),
            Tier3RestorationReport.SkippedEntry(index: 2, reason: .indexNotAParagraph),
            Tier3RestorationReport.SkippedEntry(index: 99, reason: .indexOutOfRange),
        ]))
    }

    // MARK: - convertMarkdownReportingTier3Restoration (public report-returning overload)

    func testConvertMarkdownReportingTier3RestorationReturnsSameDocumentAsBaseOverload() throws {
        let markdown = "Some paragraph."
        var meta = ParagraphMeta(index: 0)
        meta.alignment = "center"
        let metadata = DocumentMetadata(paragraphs: [meta])

        let plain = try converter.convertMarkdown(markdown, metadata: metadata)
        let (reported, report) = try converter.convertMarkdownReportingTier3Restoration(markdown, metadata: metadata)

        XCTAssertEqual(report.appliedCount, 1)
        guard case .paragraph(let plainPara) = plain.body.children[0],
              case .paragraph(let reportedPara) = reported.body.children[0] else {
            return XCTFail("Expected paragraphs")
        }
        XCTAssertEqual(plainPara.properties.alignment, reportedPara.properties.alignment)
    }

    func testConvertMarkdownReportingTier3RestorationWithNilMetadataReturnsEmptyReport() throws {
        let (_, report) = try converter.convertMarkdownReportingTier3Restoration("Plain text.", metadata: nil)
        XCTAssertEqual(report.appliedCount, 0)
        XCTAssertTrue(report.skipped.isEmpty)
    }

    // MARK: - metadata.paragraphs == [] is a no-op

    func testEmptyParagraphsArrayIsNoOp() throws {
        let markdown = "Untouched paragraph."
        let metadata = DocumentMetadata(paragraphs: [])

        let document = try converter.convertMarkdown(markdown, metadata: metadata)

        guard case .paragraph(let paragraph) = document.body.children[0] else {
            return XCTFail("Expected a paragraph at index 0")
        }
        XCTAssertNil(paragraph.properties.alignment)
    }

    // MARK: - index == children.count (one past the last valid index) is skipped

    func testIndexEqualToChildrenCountIsSkipped() throws {
        let markdown = "Only one paragraph here."

        var paragraphMeta = ParagraphMeta(index: 1) // count is 1; valid indices are just [0]
        paragraphMeta.alignment = "center"
        let metadata = DocumentMetadata(paragraphs: [paragraphMeta])

        let document = try converter.convertMarkdown(markdown, metadata: metadata)

        guard case .paragraph(let paragraph) = document.body.children[0] else {
            return XCTFail("Expected a paragraph at index 0")
        }
        XCTAssertNil(paragraph.properties.alignment)
    }

    // MARK: - one invalid entry does not block other valid entries in the same call

    func testInvalidEntryDoesNotBlockOtherValidEntries() throws {
        let markdown = """
        First paragraph.

        Second paragraph.
        """

        var outOfRange = ParagraphMeta(index: 99)
        outOfRange.alignment = "center"

        var valid = ParagraphMeta(index: 1)
        valid.alignment = "right"

        let metadata = DocumentMetadata(paragraphs: [outOfRange, valid])

        let document = try converter.convertMarkdown(markdown, metadata: metadata)

        guard case .paragraph(let first) = document.body.children[0],
              case .paragraph(let second) = document.body.children[1] else {
            return XCTFail("Expected two paragraphs")
        }
        XCTAssertNil(first.properties.alignment, "Untouched entry must stay untouched")
        XCTAssertEqual(second.properties.alignment, .right, "Valid entry after an invalid one must still apply")
    }

    // MARK: - index is a body-child position, not a paragraph-sequence number

    func testIndexTargetsBodyChildPositionNotParagraphSequenceNumber() throws {
        let markdown = """
        Intro paragraph.

        | A | B |
        | - | - |
        | 1 | 2 |

        Closing paragraph.
        """

        let baseline = try converter.convertMarkdown(markdown)
        guard baseline.body.children.count == 3,
              case .paragraph = baseline.body.children[0],
              case .table = baseline.body.children[1],
              case .paragraph = baseline.body.children[2] else {
            return XCTFail("Fixture expected [paragraph, table, paragraph], got: \(baseline.body.children)")
        }

        // index 2 is the body-child position of the *closing* paragraph
        // (not "the 2nd paragraph seen", which would be a paragraph-only
        // counter landing on index 1's table instead).
        var closingMeta = ParagraphMeta(index: 2)
        closingMeta.alignment = "right"
        let metadata = DocumentMetadata(paragraphs: [closingMeta])

        let restored = try converter.convertMarkdown(markdown, metadata: metadata)
        guard case .paragraph(let intro) = restored.body.children[0],
              case .paragraph(let closing) = restored.body.children[2] else {
            return XCTFail("Expected paragraphs at indices 0 and 2")
        }
        XCTAssertNil(intro.properties.alignment, "Only the body child at index 2 should be touched")
        XCTAssertEqual(closing.properties.alignment, .right)
    }

    // MARK: - invalid raw values are ignored gracefully, not crashed on

    func testInvalidRawValuesAreIgnoredWithoutCrashing() throws {
        let markdown = "A paragraph with some invalid sidecar values."

        var paragraphMeta = ParagraphMeta(index: 0)
        paragraphMeta.alignment = "diagonal" // not a real Alignment case
        paragraphMeta.border = ParagraphBorderMeta(
            top: BorderStyleMeta(type: "squiggly", color: "000000", size: 4), // not a real ParagraphBorderType case
            bottom: nil, left: nil, right: nil
        )
        paragraphMeta.shading = ShadingMeta(fill: "F7F7F7", pattern: "sparkle") // not a real ShadingPattern case
        // A valid field in the same call must still apply.
        paragraphMeta.keepNext = true
        let metadata = DocumentMetadata(paragraphs: [paragraphMeta])

        // Must not throw or crash.
        let document = try converter.convertMarkdown(markdown, metadata: metadata)

        guard case .paragraph(let paragraph) = document.body.children[0] else {
            return XCTFail("Expected a paragraph at index 0")
        }
        XCTAssertNil(paragraph.properties.alignment, "Unrecognized rawValue must not be force-applied")
        XCTAssertNil(paragraph.properties.border?.top, "Unrecognized border type must drop that side, not crash")
        XCTAssertEqual(paragraph.properties.shading?.fill, "F7F7F7", "fill still applies even though pattern is unrecognized")
        XCTAssertNil(paragraph.properties.shading?.pattern, "Unrecognized shading pattern must not be force-applied")
        XCTAssertTrue(paragraph.properties.keepNext, "A valid field in the same entry must still apply")
    }

    // MARK: - explicit false overrides a pre-existing true (isolated restorer call)

    func testExplicitFalseOverridesExistingTrueValue() throws {
        // The public `convertMarkdown(_:metadata:)` entry point always
        // starts from a fresh markdown-only conversion, which never
        // produces `keepNext == true` on its own — so this scenario can
        // only be exercised by calling `Tier3MetadataRestorer.restore`
        // directly against a manually-constructed document (hence
        // `@testable import` at the top of this file).
        var paragraph = Paragraph(text: "Pre-existing keepNext=true.")
        paragraph.properties.keepNext = true
        var document = WordDocument()
        document.body.children = [.paragraph(paragraph)]

        var paragraphMeta = ParagraphMeta(index: 0)
        paragraphMeta.keepNext = false
        let metadata = DocumentMetadata(paragraphs: [paragraphMeta])

        Tier3MetadataRestorer.restore(metadata, onto: &document)

        guard case .paragraph(let restored) = document.body.children[0] else {
            return XCTFail("Expected a paragraph at index 0")
        }
        XCTAssertFalse(restored.properties.keepNext, "An explicit false in metadata must overwrite a pre-existing true")
    }

    // MARK: - Helpers

    /// Minimal local counterpart to `RoundTripTests.stripVolatileIDs` (that
    /// one is a private instance method scoped to a different test class).
    /// Only handles the body-child shapes this file's fixtures produce
    /// (paragraphs; tables pass through untouched) — nested tables /
    /// content controls are out of scope here.
    private func stripVolatileIDs(_ document: WordDocument) -> WordDocument {
        var result = document
        result.body.children = document.body.children.map { child in
            guard case .paragraph(var paragraph) = child else { return child }
            paragraph.w14ParaId = nil
            paragraph.w14TextId = nil
            return .paragraph(paragraph)
        }
        result.properties.created = nil
        result.properties.modified = nil
        return result
    }
}

