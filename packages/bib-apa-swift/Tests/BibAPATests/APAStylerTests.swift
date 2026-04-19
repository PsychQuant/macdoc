import XCTest
import BiblatexAPA
@testable import BibAPA

final class APAStylerTests: XCTestCase {

    // MARK: - Style produces correct case

    func testStyleArticle() {
        let entry = makeEntry(type: "ARTICLE", fields: [
            "AUTHOR": "Cheng, Che",
            "TITLE": "Some Article Title",
            "JOURNALTITLE": "Psychometrika",
            "DATE": "2025",
        ])
        let ref = APAStyler.style(entry)
        guard case .article(let article) = ref else {
            XCTFail("Expected .article"); return
        }
        XCTAssertEqual(article.journal, "Psychometrika")
        XCTAssertEqual(article.date, "2025")
    }

    func testStylePresentation() {
        let entry = makeEntry(type: "PRESENTATION", fields: [
            "AUTHOR": "Cheng, Che",
            "TITLE": "Test Talk",
            "TITLEADDON": "Oral presentation",
            "EVENTTITLE": "Conference Name",
            "VENUE": "Taipei, Taiwan",
            "EVENTDATE": "2025-05-01/2025-05-03",
            "DATE": "2025",
        ])
        let ref = APAStyler.style(entry)
        guard case .presentation(let pres) = ref else {
            XCTFail("Expected .presentation"); return
        }
        XCTAssertEqual(pres.presentationType, "Oral presentation")
        XCTAssertEqual(pres.conference, "Conference Name")
        XCTAssertEqual(pres.venue, "Taipei, Taiwan")
        XCTAssertEqual(pres.date, "2025, May 1–3")
    }

    func testStyleThesis() {
        let entry = makeEntry(type: "THESIS", fields: [
            "AUTHOR": "Cheng, Che",
            "TITLE": "My Thesis Title",
            "INSTITUTION": "National Taiwan University",
            "TYPE": "mathesis",
            "DATE": "2020",
        ])
        let ref = APAStyler.style(entry)
        guard case .thesis(let thesis) = ref else {
            XCTFail("Expected .thesis"); return
        }
        XCTAssertEqual(thesis.thesisType, "Master's thesis")
        XCTAssertEqual(thesis.institution, "National Taiwan University")
    }

    // MARK: - Helpers

    func makeEntry(type: String, fields: [String: String]) -> BibEntry {
        var dict = OrderedDict()
        for (k, v) in fields { dict[k] = v }
        return BibEntry(entryType: type, key: "test", fields: dict, rawText: "", lineNumber: 1)
    }
}
