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

    func testEndToEndWithBundledBibFixtureCoversEveryReferenceType() throws {
        let bibFile = try parseBundledFixture()
        let html = BibToAPAHTMLFormatter.formatReferenceList(bibFile.entries)

        XCTAssertEqual(bibFile.entries.count, 8)
        XCTAssertTrue(html.contains("Article title: Article subtitle"))
        XCTAssertTrue(html.contains("<em>Journal of Fixtures</em>"))
        XCTAssertTrue(html.contains("<em>Book title: Book subtitle</em>"))
        XCTAssertTrue(html.contains("Chapter title: Chapter subtitle"))
        XCTAssertTrue(html.contains("<em>Fixture handbook</em>"))
        XCTAssertTrue(html.contains("[Doctoral dissertation, Test University]"))
        XCTAssertTrue(html.contains("Report title: Report subtitle"))
        XCTAssertTrue(html.contains("(Technical Report 42)"))
        XCTAssertTrue(html.contains("[Conference presentation]"))
        XCTAssertTrue(html.contains("Fixture Conference"))
        XCTAssertTrue(html.contains("<em>Online title: Online subtitle</em>"))
        XCTAssertTrue(html.contains("<em>Fallback title: Fallback subtitle</em>"))
        XCTAssertTrue(html.contains("<a href=\"https://doi.org/10.1234/article\">https://doi.org/10.1234/article</a>"))
        XCTAssertTrue(html.contains("<a href=\"https://example.test/online\">https://example.test/online</a>"))
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

    func testBundledFixtureReferenceLinksMatchAnchorIDs() throws {
        let bibFile = try parseBundledFixture()
        let html = BibToAPAHTMLFormatter.formatReferenceList(bibFile.entries)

        for entry in bibFile.entries {
            XCTAssertTrue(html.contains("id=\"ref-\(entry.key)\""), "Missing anchor for \(entry.key)")
            XCTAssertEqual(
                BibToAPAHTMLFormatter.formatInTextCitation(entry),
                "<a href=\"#ref-\(entry.key)\">(Tester, \(entry.date!))</a>"
            )
            XCTAssertEqual(
                BibToAPAHTMLFormatter.formatNarrativeInTextCitation(entry),
                "<a href=\"#ref-\(entry.key)\">Tester (\(entry.date!))</a>"
            )
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
}
