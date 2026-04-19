import XCTest
import BiblatexAPA
@testable import BibAPAToJSON

final class JSONFormatterTests: XCTestCase {

    // MARK: - Single Entry

    func testSingleEntryHasAllFields() {
        let entry = makeEntry(type: "ARTICLE", key: "cheng_test_2025", fields: [
            "AUTHOR": "Cheng, Che and Hsu, Yung-Fong",
            "TITLE": "Test Article Title",
            "JOURNALTITLE": "Test Journal",
            "VOLUME": "1",
            "PAGES": "1--10",
            "DOI": "10.1234/test",
            "DATE": "2025",
        ])
        let result = BibToAPAJSONFormatter.formatEntry(entry)

        XCTAssertEqual(result.key, "cheng_test_2025")
        XCTAssertEqual(result.type, "ARTICLE")
        XCTAssertEqual(result.year, "2025")
        XCTAssertTrue(result.rendered.contains("Test article title"))
        XCTAssertTrue(result.citation.contains("href=\"#ref-cheng_test_2025\""))
        XCTAssertTrue(result.citation.contains("Cheng"))
        XCTAssertTrue(result.narrativeCitation.contains("href=\"#ref-cheng_test_2025\""))
    }

    // MARK: - Multiple Entries

    func testMultipleEntriesSortedAlphabetically() {
        let entry1 = makeEntry(type: "ARTICLE", key: "zeta_2025", fields: [
            "AUTHOR": "Zeta, A.", "TITLE": "First", "JOURNALTITLE": "J", "DATE": "2025",
        ])
        let entry2 = makeEntry(type: "ARTICLE", key: "alpha_2025", fields: [
            "AUTHOR": "Alpha, B.", "TITLE": "Second", "JOURNALTITLE": "J", "DATE": "2025",
        ])
        let results = BibToAPAJSONFormatter.formatEntries([entry1, entry2])

        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].key, "alpha_2025")
        XCTAssertEqual(results[1].key, "zeta_2025")
    }

    // MARK: - JSON Output

    func testJSONOutputIsValid() throws {
        let entry = makeEntry(type: "THESIS", key: "cheng_phd_2025", fields: [
            "AUTHOR": "Cheng, Che",
            "TITLE": "My Dissertation",
            "INSTITUTION": "National Taiwan University",
            "TYPE": "phdthesis",
            "DATE": "2025",
        ])
        let json = try BibToAPAJSONFormatter.formatJSON([entry])
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode([APAJSONEntry].self, from: data)

        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].key, "cheng_phd_2025")
        XCTAssertEqual(decoded[0].type, "THESIS")
        XCTAssertTrue(decoded[0].rendered.contains("Doctoral dissertation"))
    }

    // MARK: - Integration

    func testEndToEndWithRealBibFile() throws {
        let bibPath = "/Users/che/Academic/che-cheng-website/vendor/cheng_che_cv/bibliography/Che.bib"
        let bibFile = try BibParser.parse(filePath: bibPath)
        let json = try BibToAPAJSONFormatter.formatJSON(bibFile.entries)

        XCTAssertFalse(json.isEmpty)

        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode([APAJSONEntry].self, from: data)

        XCTAssertEqual(decoded.count, bibFile.entries.count)
        // Every entry should have a non-empty rendered field
        for entry in decoded {
            XCTAssertFalse(entry.rendered.isEmpty, "Entry \(entry.key) has empty rendered HTML")
            XCTAssertFalse(entry.citation.isEmpty, "Entry \(entry.key) has empty citation")
        }

        print("\n=== JSON output (first entry) ===")
        if let first = decoded.first {
            print("key: \(first.key)")
            print("type: \(first.type)")
            print("year: \(first.year)")
            print("rendered: \(String(first.rendered.prefix(100)))...")
            print("citation: \(first.citation)")
        }
    }

    // MARK: - Helpers

    func makeEntry(type: String, key: String = "test", fields: [String: String]) -> BibEntry {
        var dict = OrderedDict()
        for (k, v) in fields { dict[k] = v }
        return BibEntry(entryType: type, key: key, fields: dict, rawText: "", lineNumber: 1)
    }
}
