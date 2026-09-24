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

    func testEndToEndWithBundledBibFixtureHasExplicitJSONFields() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "portable-references", withExtension: "bib"))
        let bibFile = try BibParser.parse(filePath: url.path)
        let json = try BibToAPAJSONFormatter.formatJSON(bibFile.entries)
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode([APAJSONEntry].self, from: data)

        // Count, order and dedup — asserted against the rendered *output*,
        // not just the parsed input (macdoc#189 Expected item 1). Order
        // matches the HTML/MD packages' `formatReferenceList` (same sort key:
        // lowercased rendered text), verified by actually running the
        // formatter (macdoc#189 Step 0).
        let expectedKeyOrder = [
            "fixture-article", "fixture-book", "fixture-chapter", "fixture-thesis",
            "fixture-report", "fixture-presentation", "fixture-online", "fixture-fallback",
            "fixture-nodate", "fixture-manyauthors",
        ]
        XCTAssertEqual(decoded.count, expectedKeyOrder.count)
        XCTAssertEqual(decoded.map(\.key), expectedKeyOrder,
            "Reference list order does not match the fixture's expected APA sort")

        // Duplicate-key trap (macdoc#189 Expected item 5): `Dictionary(uniqueKeysWithValues:)`
        // crashes (precondition failure) on a duplicate key instead of failing
        // with a readable assertion. Check uniqueness explicitly, first, so a
        // future duplicate fixture key fails loud here rather than fatal-erroring
        // the whole test binary on the line below.
        XCTAssertEqual(Set(decoded.map(\.key)).count, decoded.count,
            "Fixture has a duplicate key; byKey lookup below would crash instead of failing readably")
        let byKey = Dictionary(uniqueKeysWithValues: decoded.map { ($0.key, $0) })

        XCTAssertEqual(byKey["fixture-article"]?.type, "ARTICLE")
        XCTAssertEqual(byKey["fixture-book"]?.type, "BOOK")
        XCTAssertEqual(byKey["fixture-chapter"]?.type, "INCOLLECTION")
        XCTAssertEqual(byKey["fixture-thesis"]?.type, "THESIS")
        XCTAssertEqual(byKey["fixture-report"]?.type, "REPORT")
        XCTAssertEqual(byKey["fixture-presentation"]?.type, "PRESENTATION")
        XCTAssertEqual(byKey["fixture-online"]?.type, "ONLINE")
        XCTAssertEqual(byKey["fixture-fallback"]?.type, "UNPUBLISHED")
        XCTAssertEqual(byKey["fixture-nodate"]?.type, "ARTICLE")
        XCTAssertEqual(byKey["fixture-manyauthors"]?.type, "ARTICLE")
        XCTAssertEqual(byKey["fixture-article"]?.year, "2020")
        // Boundary case: missing DATE field yields year "n.d." rather than
        // crashing or an empty string (macdoc#189 Expected item 5).
        XCTAssertEqual(byKey["fixture-nodate"]?.year, "n.d.")
        XCTAssertEqual(byKey["fixture-manyauthors"]?.year, "2028")

        // Thesis and presentation subtitles were already covered precisely
        // here (unlike the HTML/MD suites before this change — macdoc#189
        // Expected item 3), so these stay exact-equal rather than `.contains`.
        XCTAssertEqual(byKey["fixture-article"]?.rendered,
            "Tester, A. (2020). Article title: Article subtitle. <em>Journal of Fixtures</em>, <em>12</em>(3), 10–20. <a href=\"https://doi.org/10.1234/article\">https://doi.org/10.1234/article</a>")
        XCTAssertEqual(byKey["fixture-book"]?.rendered,
            "Tester, A. (2021). <em>Book title: Book subtitle</em>. Fixture Press.")
        XCTAssertEqual(byKey["fixture-chapter"]?.rendered,
            "Tester, A. (2022). Chapter title: Chapter subtitle. In E. Editor (Ed.), <em>Fixture handbook</em> (pp. 21–30). Fixture Press.")
        XCTAssertEqual(byKey["fixture-thesis"]?.rendered,
            "Tester, A. (2023). <em>Thesis title: Thesis subtitle</em> [Doctoral dissertation, Test University].")
        XCTAssertEqual(byKey["fixture-report"]?.rendered,
            "Tester, A. (2024). <em>Report title: Report subtitle</em> (Technical Report 42). Fixture Institute.")
        XCTAssertEqual(byKey["fixture-presentation"]?.rendered,
            "Tester, A. (2025). <em>Presentation title: Presentation subtitle</em> [Conference presentation]. Fixture Conference, Taipei, Taiwan.")
        XCTAssertEqual(byKey["fixture-online"]?.rendered,
            "Tester, A. (2026). <em>Online title: Online subtitle</em>. Fixture Web. <a href=\"https://example.test/online\">https://example.test/online</a>")
        XCTAssertEqual(byKey["fixture-fallback"]?.rendered,
            "Tester, A. (2027). <em>Fallback title: Fallback subtitle</em>. Fallback Publisher. <a href=\"https://example.test/fallback\">https://example.test/fallback</a>")
        XCTAssertEqual(byKey["fixture-nodate"]?.rendered,
            "Tester, A. (n.d.). No date title: No date subtitle. <em>Journal of Fixtures</em>.")
        XCTAssertEqual(byKey["fixture-manyauthors"]?.rendered,
            "Tester, A., Coauthor, B., &amp; Thirdauthor, C. (2028). Many authors title: Many authors subtitle. <em>Journal of Fixtures</em>.")

        XCTAssertEqual(byKey["fixture-article"]?.citation, "<a href=\"#ref-fixture-article\">(Tester, 2020)</a>")
        XCTAssertEqual(byKey["fixture-article"]?.narrativeCitation, "<a href=\"#ref-fixture-article\">Tester (2020)</a>")
        // Boundary case: 3+ authors alias to "et al." in citations even
        // though the reference list itself spells all of them out.
        XCTAssertEqual(byKey["fixture-manyauthors"]?.citation, "<a href=\"#ref-fixture-manyauthors\">(Tester et al., 2028)</a>")
        XCTAssertEqual(byKey["fixture-manyauthors"]?.narrativeCitation, "<a href=\"#ref-fixture-manyauthors\">Tester et al. (2028)</a>")
        XCTAssertEqual(byKey["fixture-nodate"]?.citation, "<a href=\"#ref-fixture-nodate\">(Tester, n.d.)</a>")
        XCTAssertEqual(byKey["fixture-nodate"]?.narrativeCitation, "<a href=\"#ref-fixture-nodate\">Tester (n.d.)</a>")
    }

    // MARK: - Helpers

    func makeEntry(type: String, key: String = "test", fields: [String: String]) -> BibEntry {
        var dict = OrderedDict()
        for (k, v) in fields { dict[k] = v }
        return BibEntry(entryType: type, key: key, fields: dict, rawText: "", lineNumber: 1)
    }
}
