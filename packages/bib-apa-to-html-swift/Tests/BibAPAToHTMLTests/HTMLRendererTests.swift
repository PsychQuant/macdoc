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

    // MARK: - Integration with real .bib

    func testEndToEndWithRealBibFile() throws {
        let bibPath = "/Users/che/Academic/che-cheng-website/vendor/cheng_che_cv/bibliography/Che.bib"
        let bibFile = try BibParser.parse(filePath: bibPath)
        let html = BibToAPAHTMLFormatter.formatReferenceList(bibFile.entries)
        XCTAssertFalse(html.isEmpty)
        XCTAssertTrue(html.contains("<em>"))
        XCTAssertTrue(html.contains("<a href="))
        print("\n=== HTML output (first 500 chars) ===\n")
        print(String(html.prefix(500)))
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

    func testReferenceListHasAnchorIDs() throws {
        let bibPath = "/Users/che/Academic/che-cheng-website/vendor/cheng_che_cv/bibliography/Che.bib"
        let bibFile = try BibParser.parse(filePath: bibPath)
        let html = BibToAPAHTMLFormatter.formatReferenceList(bibFile.entries)
        // Every entry should have a unique id
        XCTAssertTrue(html.contains("id=\"ref-cheng_likert_choices_2021\""))
        XCTAssertTrue(html.contains("id=\"ref-cheng_phd_dissertation_2025\""))
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
}
