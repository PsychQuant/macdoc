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

    // MARK: - SUBTITLE reaches every entry type (macdoc#183)

    /// `buildTitle` has always folded a standalone `SUBTITLE` field into the
    /// rendered title, but only `styleArticle` and `styleBook` called it. Four
    /// other per-type functions inlined `toSentenceCase(stripBraces(title))`
    /// and dropped the field silently — a real bibliography lost the subtitle
    /// of 8 `@PRESENTATION` entries. `styleChapter` is a fifth instance the
    /// issue's table did not list.
    func testSubtitleIsFoldedIntoTheTitleForEveryEntryType() {
        func title(_ type: String, extra: [String: String] = [:]) -> String {
            var fields = [
                "AUTHOR": "Cheng, Che",
                "TITLE": "Main Title",
                "SUBTITLE": "The Subtitle",
                "DATE": "2025",
            ]
            fields.merge(extra) { _, new in new }
            switch APAStyler.style(makeEntry(type: type, fields: fields)) {
            case .article(let r):      return r.title
            case .book(let r):         return r.title
            case .chapter(let r):      return r.chapterTitle
            case .thesis(let r):       return r.title
            case .report(let r):       return r.title
            case .presentation(let r): return r.title
            case .online(let r):       return r.title
            @unknown default:          return ""
            }
        }
        let cases: [(String, [String: String])] = [
            ("ARTICLE", ["JOURNALTITLE": "Psychometrika"]),
            ("BOOK", [:]),
            ("INCOLLECTION", ["BOOKTITLE": "A Handbook"]),
            ("THESIS", ["INSTITUTION": "NTU"]),
            ("REPORT", ["INSTITUTION": "Academia Sinica"]),
            ("PRESENTATION", ["EVENTTITLE": "A Conference"]),
            ("ONLINE", ["URL": "https://example.com"]),
            ("MISC", ["URL": "https://example.com"]),
        ]
        for (type, extra) in cases {
            XCTAssertEqual(title(type, extra: extra), "Main title: The subtitle", "\(type) must fold SUBTITLE into the title")
        }
    }

    /// An entry without `SUBTITLE` renders exactly as before — the fix must not
    /// append a stray colon.
    func testATitleWithoutASubtitleIsUnchanged() {
        let entry = makeEntry(type: "PRESENTATION", fields: [
            "AUTHOR": "Cheng, Che", "TITLE": "Main Title", "EVENTTITLE": "A Conference", "DATE": "2025",
        ])
        guard case .presentation(let pres) = APAStyler.style(entry) else { XCTFail("Expected .presentation"); return }
        XCTAssertEqual(pres.title, "Main title")
    }
}
