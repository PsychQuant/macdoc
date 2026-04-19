import XCTest
import BiblatexAPA
@testable import BibAPAToMD

final class BibToAPAFormatterTests: XCTestCase {

    // MARK: - Author Parsing

    func testParseSingleAuthor() {
        let author = BibToAPAFormatter.parseSingleAuthor("Cheng, Che")
        XCTAssertEqual(author.lastName, "Cheng")
        XCTAssertEqual(author.firstName, "Che")
    }

    func testParseHyphenatedFirstName() {
        let author = BibToAPAFormatter.parseSingleAuthor("Yang, Hau-Hung")
        XCTAssertEqual(author.lastName, "Yang")
        XCTAssertEqual(author.firstName, "Hau-Hung")
    }

    func testParseCorporateAuthor() {
        let author = BibToAPAFormatter.parseSingleAuthor("{American Psychological Association}")
        XCTAssertEqual(author.lastName, "American Psychological Association")
        XCTAssertTrue(author.isCorporate)
    }

    func testParseSingleName() {
        let author = BibToAPAFormatter.parseSingleAuthor("Plato")
        XCTAssertEqual(author.lastName, "Plato")
        XCTAssertTrue(author.firstName.isEmpty)
    }

    // MARK: - Initials

    func testInitials() {
        XCTAssertEqual(BibToAPAFormatter.formatInitials("Che"), "C.")
        XCTAssertEqual(BibToAPAFormatter.formatInitials("Hau-Hung"), "H.-H.")
        XCTAssertEqual(BibToAPAFormatter.formatInitials("Sarah Michelle"), "S. M.")
        XCTAssertEqual(BibToAPAFormatter.formatInitials("A. A."), "A. A.")
    }

    // MARK: - Author Formatting (Reference List)

    func testSingleAuthorRef() {
        let entry = makeEntry(type: "ARTICLE", fields: [
            "AUTHOR": "Cheng, Che",
            "TITLE": "Test",
            "DATE": "2025",
        ])
        let result = BibToAPAFormatter.formatAuthors(entry)
        XCTAssertEqual(result, "Cheng, C.")
    }

    func testTwoAuthorsRef() {
        let entry = makeEntry(type: "ARTICLE", fields: [
            "AUTHOR": "Cheng, Che and Yang, Hau-Hung",
            "TITLE": "Test",
            "DATE": "2025",
        ])
        let result = BibToAPAFormatter.formatAuthors(entry)
        XCTAssertEqual(result, "Cheng, C., & Yang, H.-H.")
    }

    func testThreeAuthorsRef() {
        let entry = makeEntry(type: "ARTICLE", fields: [
            "AUTHOR": "Cheng, Che and Yang, Hau-Hung and Hsu, Yung-Fong",
            "TITLE": "Test",
            "DATE": "2025",
        ])
        let result = BibToAPAFormatter.formatAuthors(entry)
        XCTAssertEqual(result, "Cheng, C., Yang, H.-H., & Hsu, Y.-F.")
    }

    // MARK: - Citation Authors

    func testCitationThreeAuthors() {
        let entry = makeEntry(type: "ARTICLE", fields: [
            "AUTHOR": "Cheng, Che and Yang, Hau-Hung and Hsu, Yung-Fong",
        ])
        let result = BibToAPAFormatter.formatCitationAuthors(entry)
        XCTAssertEqual(result, "Cheng et al.")
    }

    // MARK: - Date Formatting

    func testYearOnly() {
        let entry = makeEntry(type: "ARTICLE", fields: ["DATE": "2025"])
        XCTAssertEqual(BibToAPAFormatter.formatDate(entry), "2025")
    }

    func testEventDateRange() {
        XCTAssertEqual(
            BibToAPAFormatter.formatEventDate("2025-05-01/2025-05-03"),
            "2025, May 1–3"
        )
    }

    func testEventDateCrossMonth() {
        XCTAssertEqual(
            BibToAPAFormatter.formatEventDate("2025-08-29/2025-09-01"),
            "2025, August 29–September 1"
        )
    }

    // MARK: - Full Reference: Journal Article

    func testArticleReference() {
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
        let result = BibToAPAFormatter.formatReference(entry)
        XCTAssertTrue(result.hasPrefix("Cheng, C., Yang, H.-H., & Hsu, Y.-F. (2025)."))
        XCTAssertTrue(result.contains("*Psychometrika*, *90*(2), 757–778."))
        XCTAssertTrue(result.contains("https://doi.org/10.1007/s11336-025-10029-2"))
    }

    // MARK: - Full Reference: Presentation

    func testPresentationReference() {
        let entry = makeEntry(type: "PRESENTATION", fields: [
            "AUTHOR": "Cheng, Che and Yang, Hau-Hung and Hsu, Yung-Fong",
            "TITLE": "The universal Cramér-Rao lower bound",
            "TITLEADDON": "Oral presentation",
            "EVENTTITLE": "The 64th Annual Convention of the Taiwanese Psychology Association",
            "VENUE": "Tainan, Taiwan",
            "EVENTDATE": "2025-10-18/2025-10-19",
            "DATE": "2025",
        ])
        let result = BibToAPAFormatter.formatReference(entry)
        XCTAssertTrue(result.contains("(2025, October 18–19)."))
        XCTAssertTrue(result.contains("[Oral presentation]."))
        XCTAssertTrue(result.contains("The 64th Annual Convention"))
        XCTAssertTrue(result.contains("Tainan, Taiwan"))
    }

    // MARK: - Full Reference: Thesis

    func testThesisReference() {
        let entry = makeEntry(type: "THESIS", fields: [
            "AUTHOR": "Cheng, Che",
            "TITLE": "Analysis of Growth Curves Based on the Semiparametric Latent Curve Model",
            "INSTITUTION": "National Taiwan University",
            "TYPE": "mathesis",
            "DATE": "2020",
        ])
        let result = BibToAPAFormatter.formatReference(entry)
        XCTAssertTrue(result.hasPrefix("Cheng, C. (2020)."))
        XCTAssertTrue(result.contains("National Taiwan University"))
    }

    // MARK: - Sentence Case

    func testSentenceCaseBasic() {
        let result = BibToAPAFormatter.toSentenceCase("Language Learning as Language Use")
        XCTAssertEqual(result, "Language learning as language use")
    }

    func testSentenceCaseWithBraceProtection() {
        let result = BibToAPAFormatter.toSentenceCase("Identifiability of Ordinal {SEM} and Item Factor Analysis")
        XCTAssertTrue(result.contains("SEM"))
        XCTAssertTrue(result.hasPrefix("Identifiability"))
    }

    func testSentenceCaseWithColon() {
        let result = BibToAPAFormatter.toSentenceCase("two are better than one: incorporating data")
        XCTAssertTrue(result.hasPrefix("Two"))
        XCTAssertTrue(result.contains(": Incorporating") || result.contains(": incorporating"))
    }

    // MARK: - Pages Normalization

    func testPagesNormalization() {
        XCTAssertEqual(BibToAPAFormatter.normalizePages("757--778"), "757–778")
        XCTAssertEqual(BibToAPAFormatter.normalizePages("1-51"), "1–51")
    }

    // MARK: - Strip Braces

    func testStripBraces() {
        XCTAssertEqual(BibToAPAFormatter.stripBraces("{ADHD}"), "ADHD")
        XCTAssertEqual(BibToAPAFormatter.stripBraces("Normal text"), "Normal text")
        XCTAssertEqual(BibToAPAFormatter.stripBraces("{Nested {braces}}"), "Nested {braces}")
    }

    // MARK: - Helpers

    func makeEntry(type: String, fields: [String: String]) -> BibEntry {
        var dict = OrderedDict()
        for (k, v) in fields {
            dict[k] = v
        }
        return BibEntry(
            entryType: type,
            key: "test_key",
            fields: dict,
            rawText: "",
            lineNumber: 1
        )
    }
}
