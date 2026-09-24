import Foundation
import XCTest
import BiblatexAPA
@testable import BibAPAToHTML

final class HTMLRendererTests: XCTestCase {

    // MARK: - Article

    func testArticleHTML() {
        let entry = makeEntry(type: "ARTICLE", fields: [
            "AUTHOR": "Cheng, Che and Yang, Hau-Hung and Hsu, Yung-Fong",
            "TITLE": "Some Article Title Here",
            "JOURNALTITLE": "Psychometrika",
            "VOLUME": "90",
            "NUMBER": "2",
            "PAGES": "757--778",
            "DOI": "10.1007/s11336-025-10029-2",
            "DATE": "2025",
        ])
        let result = BibToAPAHTMLFormatter.formatReference(entry)
        XCTAssertTrue(result.contains("<em>Psychometrika</em>"))
        XCTAssertTrue(result.contains("<em>90</em>(2)"))
        XCTAssertTrue(result.contains("<a href=\"https://doi.org/10.1007/s11336-025-10029-2\">"))
        XCTAssertFalse(result.contains("*"), "Should not contain markdown italics")
    }

    // MARK: - Presentation

    func testPresentationHTML() {
        let entry = makeEntry(type: "PRESENTATION", fields: [
            "AUTHOR": "Cheng, Che",
            "TITLE": "Test Talk",
            "TITLEADDON": "Oral presentation",
            "EVENTTITLE": "Conference Name",
            "VENUE": "Taipei, Taiwan",
            "EVENTDATE": "2025-05-01/2025-05-03",
            "DATE": "2025",
        ])
        let result = BibToAPAHTMLFormatter.formatReference(entry)
        XCTAssertTrue(result.contains("<em>Test talk</em>"))
        XCTAssertTrue(result.contains("[Oral presentation]"))
        XCTAssertTrue(result.contains("Taipei, Taiwan"))
    }

    // MARK: - Thesis

    func testThesisHTML() {
        let entry = makeEntry(type: "THESIS", fields: [
            "AUTHOR": "Cheng, Che",
            "TITLE": "My Thesis Title",
            "INSTITUTION": "National Taiwan University",
            "TYPE": "mathesis",
            "DATE": "2020",
        ])
        let result = BibToAPAHTMLFormatter.formatReference(entry)
        XCTAssertTrue(result.contains("<em>My thesis title</em>"))
        XCTAssertTrue(result.contains("[Master&apos;s thesis" ) || result.contains("[Master&#x27;s thesis") || result.contains("[Master's thesis"))
        XCTAssertTrue(result.contains("National Taiwan University"))
    }

    // MARK: - HTML Escaping

    func testHTMLEscaping() {
        let entry = makeEntry(type: "ARTICLE", fields: [
            "AUTHOR": "O'Brien, James",
            "TITLE": "A <bold> claim & its consequences",
            "JOURNALTITLE": "Test Journal",
            "DATE": "2025",
        ])
        let result = BibToAPAHTMLFormatter.formatReference(entry)
        XCTAssertTrue(result.contains("&amp;"))
        XCTAssertTrue(result.contains("&lt;bold&gt;"))
        XCTAssertFalse(result.contains("<bold>"), "Raw HTML tags should be escaped")
    }

    // MARK: - Reference List

    func testReferenceListWrapsInParagraphs() {
        let entry1 = makeEntry(type: "ARTICLE", fields: [
            "AUTHOR": "Zeta, A.", "TITLE": "First", "JOURNALTITLE": "J", "DATE": "2025",
        ])
        let entry2 = makeEntry(type: "ARTICLE", fields: [
            "AUTHOR": "Alpha, B.", "TITLE": "Second", "JOURNALTITLE": "J", "DATE": "2025",
        ])
        let result = BibToAPAHTMLFormatter.formatReferenceList([entry1, entry2])
        let lines = result.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].contains("<p class=\"apa-reference\""))
        XCTAssertTrue(lines[0].contains("id=\"ref-test\""))
        XCTAssertTrue(lines[0].hasSuffix("</p>"))
        // Alphabetically sorted: Alpha before Zeta
        XCTAssertTrue(lines[0].contains("Alpha"))
    }

    // MARK: - Portable integration

    /// Key order the fixture is expected to render in. `formatReferenceList`
    /// sorts by the lowercased *rendered* text (not by key or date field), but
    /// because every fixture entry shares the author "Tester, Ada", that sort
    /// key collapses to "tester, a. (" + year for the eight dated entries
    /// (ascending 2020→2027), with "n.d." sorting after all four-digit years
    /// (the character 'n' > any digit) and the three-author entry sorting
    /// last of all (a "," right after "Tester, A" sorts after the space that
    /// begins every single-author entry's "(year)"). Verified by actually
    /// running the formatter (macdoc#189 Step 0) rather than derived by hand.
    private let expectedFixtureKeyOrder = [
        "fixture-article", "fixture-book", "fixture-chapter", "fixture-thesis",
        "fixture-report", "fixture-presentation", "fixture-online", "fixture-fallback",
        "fixture-nodate", "fixture-manyauthors",
    ]

    func testEndToEndWithBundledBibFixtureCoversEveryReferenceType() throws {
        let bibFile = try parseBundledFixture()
        let html = BibToAPAHTMLFormatter.formatReferenceList(bibFile.entries)
        let anchored = try parseAnchoredEntries(html)

        // Count, dedup and order — asserted against the rendered *output*,
        // not just the parsed input (macdoc#189 Expected item 1).
        XCTAssertEqual(bibFile.entries.count, expectedFixtureKeyOrder.count)
        XCTAssertEqual(anchored.map(\.key), expectedFixtureKeyOrder,
            "Reference list order does not match the fixture's expected APA sort")
        XCTAssertEqual(Set(anchored.map(\.key)).count, anchored.count,
            "Duplicate anchor key in rendered output")

        func content(for key: String) throws -> String {
            try XCTUnwrap(anchored.first { $0.key == key }?.content, "No rendered line for \(key)")
        }

        XCTAssertEqual(try content(for: "fixture-article"),
            "Tester, A. (2020). Article title: Article subtitle. <em>Journal of Fixtures</em>, <em>12</em>(3), 10–20. <a href=\"https://doi.org/10.1234/article\">https://doi.org/10.1234/article</a>")
        XCTAssertEqual(try content(for: "fixture-book"),
            "Tester, A. (2021). <em>Book title: Book subtitle</em>. Fixture Press.")
        XCTAssertEqual(try content(for: "fixture-chapter"),
            "Tester, A. (2022). Chapter title: Chapter subtitle. In E. Editor (Ed.), <em>Fixture handbook</em> (pp. 21–30). Fixture Press.")
        // Thesis and presentation subtitles were the two types with no
        // precise assertion anywhere in the HTML/MD suites (macdoc#189
        // Expected item 3) — only the JSON suite covered them.
        XCTAssertEqual(try content(for: "fixture-thesis"),
            "Tester, A. (2023). <em>Thesis title: Thesis subtitle</em> [Doctoral dissertation, Test University].")
        XCTAssertEqual(try content(for: "fixture-report"),
            "Tester, A. (2024). <em>Report title: Report subtitle</em> (Technical Report 42). Fixture Institute.")
        XCTAssertEqual(try content(for: "fixture-presentation"),
            "Tester, A. (2025). <em>Presentation title: Presentation subtitle</em> [Conference presentation]. Fixture Conference, Taipei, Taiwan.")
        XCTAssertEqual(try content(for: "fixture-online"),
            "Tester, A. (2026). <em>Online title: Online subtitle</em>. Fixture Web. <a href=\"https://example.test/online\">https://example.test/online</a>")
        XCTAssertEqual(try content(for: "fixture-fallback"),
            "Tester, A. (2027). <em>Fallback title: Fallback subtitle</em>. Fallback Publisher. <a href=\"https://example.test/fallback\">https://example.test/fallback</a>")
        // Boundary case: missing DATE field renders "(n.d.)" (macdoc#189 Expected item 5).
        XCTAssertEqual(try content(for: "fixture-nodate"),
            "Tester, A. (n.d.). No date title: No date subtitle. <em>Journal of Fixtures</em>.")
        // Boundary case: 3+ authors are listed in full in the reference list
        // (APA 7 lists up to 20), unlike in-text citations which alias to "et al.".
        XCTAssertEqual(try content(for: "fixture-manyauthors"),
            "Tester, A., Coauthor, B., &amp; Thirdauthor, C. (2028). Many authors title: Many authors subtitle. <em>Journal of Fixtures</em>.")
    }

    // MARK: - In-Text Citations

    func testParentheticalInTextCitation() {
        let entry = makeEntry(type: "ARTICLE", key: "cheng_psychometrika_2025", fields: [
            "AUTHOR": "Cheng, Che and Yang, Hau-Hung and Hsu, Yung-Fong",
            "TITLE": "Some Title",
            "JOURNALTITLE": "Psychometrika",
            "DATE": "2025",
        ])
        let result = BibToAPAHTMLFormatter.formatInTextCitation(entry)
        XCTAssertTrue(result.contains("<a href=\"#ref-cheng_psychometrika_2025\">"))
        XCTAssertTrue(result.contains("Cheng"))
        XCTAssertTrue(result.contains("2025"))
        XCTAssertTrue(result.contains("</a>"))
    }

    func testNarrativeInTextCitation() {
        let entry = makeEntry(type: "THESIS", key: "cheng_phd_2025", fields: [
            "AUTHOR": "Cheng, Che",
            "TITLE": "My Dissertation",
            "INSTITUTION": "National Taiwan University",
            "TYPE": "phdthesis",
            "DATE": "2025",
        ])
        let result = BibToAPAHTMLFormatter.formatNarrativeInTextCitation(entry)
        XCTAssertTrue(result.contains("<a href=\"#ref-cheng_phd_2025\">"))
        XCTAssertTrue(result.contains("Cheng"))
        XCTAssertTrue(result.contains("(2025)"))
        XCTAssertTrue(result.contains("</a>"))
    }

    func testBundledFixtureInTextCitationsLinkToTheirOwnAnchor() throws {
        let bibFile = try parseBundledFixture()

        for entry in bibFile.entries {
            XCTAssertTrue(BibToAPAHTMLFormatter.formatReferenceList(bibFile.entries).contains("id=\"ref-\(entry.key)\""),
                "Missing anchor for \(entry.key)")

            // `entry.date` is nil for fixture-nodate — use `try XCTUnwrap` semantics
            // via `?? "n.d."` (matching APAStyler's own missing-date fallback)
            // instead of force-unwrapping, so a genuinely missing date fails with
            // a readable assertion instead of crashing the whole test run
            // (macdoc#189 Expected item 5 — force unwrap masking assertions).
            let year = entry.date ?? "n.d."
            // Every fixture entry is authored by "Tester, Ada" alone, except
            // fixture-manyauthors (3 authors), which APA 7 aliases to "et al."
            // in in-text citations (but lists all authors in the reference itself).
            let citationAuthor = entry.key == "fixture-manyauthors" ? "Tester et al." : "Tester"

            XCTAssertEqual(
                BibToAPAHTMLFormatter.formatInTextCitation(entry),
                "<a href=\"#ref-\(entry.key)\">(\(citationAuthor), \(year))</a>"
            )
            XCTAssertEqual(
                BibToAPAHTMLFormatter.formatNarrativeInTextCitation(entry),
                "<a href=\"#ref-\(entry.key)\">\(citationAuthor) (\(year))</a>"
            )
        }
    }

    /// Each anchor's `id="ref-KEY"` must wrap that same entry's own rendered
    /// content — not merely appear somewhere in the document. A
    /// `.contains("id=\"ref-KEY\"")` style assertion cannot tell the
    /// difference between "present" and "present but attached to the wrong
    /// entry" (macdoc#189 Expected item 2; see `testAnchorRotationMutationIsDetected`
    /// below for a demonstration that this distinction matters).
    func testBundledFixtureAnchorsWrapTheirOwnContent() throws {
        let bibFile = try parseBundledFixture()
        let html = BibToAPAHTMLFormatter.formatReferenceList(bibFile.entries)
        let byKey = Dictionary(uniqueKeysWithValues: try parseAnchoredEntries(html).map { ($0.key, $0.content) })

        for entry in bibFile.entries {
            XCTAssertEqual(byKey[entry.key], BibToAPAHTMLFormatter.formatReference(entry),
                "Anchor id=\"ref-\(entry.key)\" does not wrap that entry's own rendered content")
        }
    }

    /// Demonstrates that the key-paired assertion above actually has
    /// detection power: manually rotate two anchors' `id` attributes (the
    /// mutation the #186 review named — "anchor 旋轉突變仍能通過現有斷言") and
    /// confirm the pairing now reports a mismatch. A `.contains(...)` style
    /// assertion would still pass here, because every id substring is still
    /// present somewhere in the document — just attached to the wrong `<p>`.
    func testAnchorRotationMutationIsDetected() throws {
        let bibFile = try parseBundledFixture()
        let html = BibToAPAHTMLFormatter.formatReferenceList(bibFile.entries)

        let mutated = html
            .replacingOccurrences(of: "id=\"ref-fixture-thesis\"", with: "id=\"ref-ROTATE-PLACEHOLDER\"")
            .replacingOccurrences(of: "id=\"ref-fixture-presentation\"", with: "id=\"ref-fixture-thesis\"")
            .replacingOccurrences(of: "id=\"ref-ROTATE-PLACEHOLDER\"", with: "id=\"ref-fixture-presentation\"")

        let byKey = Dictionary(uniqueKeysWithValues: try parseAnchoredEntries(mutated).map { ($0.key, $0.content) })
        let thesisEntry = try XCTUnwrap(bibFile.entries.first { $0.key == "fixture-thesis" })
        let presentationEntry = try XCTUnwrap(bibFile.entries.first { $0.key == "fixture-presentation" })

        XCTAssertNotEqual(byKey["fixture-thesis"], BibToAPAHTMLFormatter.formatReference(thesisEntry),
            "Rotation mutation should break the anchor-to-content pairing, but it still matched")
        XCTAssertNotEqual(byKey["fixture-presentation"], BibToAPAHTMLFormatter.formatReference(presentationEntry),
            "Rotation mutation should break the anchor-to-content pairing, but it still matched")

        // The OLD assertion style (macdoc#186's contains-only check) would still
        // pass on this exact mutated document — this is the regression #189 exists to close.
        for entry in bibFile.entries {
            XCTAssertTrue(mutated.contains("id=\"ref-\(entry.key)\""))
        }
    }

    func testCSSContainsTargetHighlight() {
        XCTAssertTrue(APACSS.minimal.contains(":target"))
        XCTAssertTrue(APACSS.web.contains(":target"))
    }

    // MARK: - Helpers

    func makeEntry(type: String, key: String = "test", fields: [String: String]) -> BibEntry {
        var dict = OrderedDict()
        for (k, v) in fields { dict[k] = v }
        return BibEntry(entryType: type, key: key, fields: dict, rawText: "", lineNumber: 1)
    }

    private func parseBundledFixture() throws -> BibFile {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "portable-references", withExtension: "bib"))
        return try BibParser.parse(filePath: url.path)
    }

    /// One rendered reference, as it appears wrapped in `formatReferenceList`'s output.
    private struct AnchoredEntry {
        let key: String
        let content: String
    }

    /// Parses the output of `formatReferenceList` into one `AnchoredEntry`
    /// per `<p class="apa-reference" id="ref-KEY">content</p>` line,
    /// preserving output order (`formatReferenceList` joins with `\n`, never
    /// emitting a literal newline inside a single entry's content — see
    /// `BibToAPAHTMLFormatter.swift`). Fails the calling test (rather than
    /// silently dropping the line) if a non-empty line doesn't match that
    /// shape, so a malformed line can't hide behind an incomplete result.
    private func parseAnchoredEntries(_ html: String, file: StaticString = #filePath, line: UInt = #line) throws -> [AnchoredEntry] {
        let regex = try NSRegularExpression(pattern: #"^<p class="apa-reference" id="ref-([^"]+)">(.*)</p>$"#)
        var result: [AnchoredEntry] = []
        for htmlLine in html.components(separatedBy: "\n") where !htmlLine.isEmpty {
            let range = NSRange(htmlLine.startIndex..., in: htmlLine)
            guard let match = regex.firstMatch(in: htmlLine, range: range),
                  let keyRange = Range(match.range(at: 1), in: htmlLine),
                  let contentRange = Range(match.range(at: 2), in: htmlLine) else {
                XCTFail("Line does not match <p class=\"apa-reference\" id=\"ref-KEY\">content</p>: \(htmlLine)", file: file, line: line)
                continue
            }
            result.append(AnchoredEntry(key: String(htmlLine[keyRange]), content: String(htmlLine[contentRange])))
        }
        return result
    }
}
