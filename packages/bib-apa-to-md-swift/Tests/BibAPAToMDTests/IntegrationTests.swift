import XCTest
import BiblatexAPA
@testable import BibAPAToMD

final class IntegrationTests: XCTestCase {

    /// Key order the fixture is expected to render in, keyed to the exact
    /// paragraph at that index (paragraphs have no anchor id in Markdown, so
    /// order is the only handle available — see `testEndToEndWithBundledBibFixtureCoversEveryReferenceType`).
    /// `formatReferenceList` sorts by the lowercased *rendered* text; every
    /// fixture entry shares author "Tester, Ada", so the eight dated entries
    /// sort ascending by year (2020→2027), "n.d." sorts after all four-digit
    /// years ('n' > any digit), and the three-author entry sorts last of all
    /// (a "," right after "Tester, A" sorts after the space that begins
    /// every single-author entry's "(year)"). Verified by actually running
    /// the formatter (macdoc#189 Step 0), not derived by hand — see the HTML
    /// package's `expectedFixtureKeyOrder`, which is rendered from the same
    /// (semantically identical) fixture content.
    private let expectedParagraphOrder = [
        "Tester, A. (2020). Article title: Article subtitle. *Journal of Fixtures*, *12*(3), 10–20. https://doi.org/10.1234/article",
        "Tester, A. (2021). *Book title: Book subtitle*. Fixture Press.",
        "Tester, A. (2022). Chapter title: Chapter subtitle. In E. Editor (Ed.), *Fixture handbook* (pp. 21–30). Fixture Press.",
        "Tester, A. (2023). *Thesis title: Thesis subtitle* [Doctoral dissertation, Test University].",
        "Tester, A. (2024). *Report title: Report subtitle* (Technical Report 42). Fixture Institute.",
        "Tester, A. (2025). *Presentation title: Presentation subtitle* [Conference presentation]. Fixture Conference, Taipei, Taiwan.",
        "Tester, A. (2026). *Online title: Online subtitle*. Fixture Web. https://example.test/online",
        "Tester, A. (2027). *Fallback title: Fallback subtitle*. Fallback Publisher. https://example.test/fallback",
        "Tester, A. (n.d.). No date title: No date subtitle. *Journal of Fixtures*.",
        "Tester, A., Coauthor, B., & Thirdauthor, C. (2028). Many authors title: Many authors subtitle. *Journal of Fixtures*.",
    ]

    func testEndToEndWithBundledBibFixtureCoversEveryReferenceType() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "portable-references", withExtension: "bib"))
        let bibFile = try BibParser.parse(filePath: url.path)

        let markdown = BibToAPAFormatter.formatReferenceList(bibFile.entries)
        let paragraphs = markdown.components(separatedBy: "\n\n")

        // Count, dedup and order — asserted against the rendered *output*,
        // not just the parsed input (macdoc#189 Expected item 1).
        XCTAssertEqual(bibFile.entries.count, expectedParagraphOrder.count)
        XCTAssertEqual(paragraphs, expectedParagraphOrder,
            "Reference list order/content does not match the fixture's expected APA sort")
        XCTAssertEqual(Set(paragraphs).count, paragraphs.count, "Duplicate paragraph in rendered output")
    }

    /// Boundary cases for in-text citations (macdoc#189 Expected item 5):
    /// a missing DATE field renders "n.d." rather than crashing or producing
    /// an empty year, and 3+ authors alias to "et al." in citations even
    /// though the reference list itself spells all of them out.
    func testBundledFixtureInTextCitationsHandleMissingDateAndManyAuthors() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "portable-references", withExtension: "bib"))
        let bibFile = try BibParser.parse(filePath: url.path)

        let nodateEntry = try XCTUnwrap(bibFile.entries.first { $0.key == "fixture-nodate" })
        XCTAssertEqual(BibToAPAFormatter.formatCitation(nodateEntry), "(Tester, n.d.)")
        XCTAssertEqual(BibToAPAFormatter.formatNarrativeCitation(nodateEntry), "Tester (n.d.)")

        let manyAuthorsEntry = try XCTUnwrap(bibFile.entries.first { $0.key == "fixture-manyauthors" })
        XCTAssertEqual(BibToAPAFormatter.formatCitation(manyAuthorsEntry), "(Tester et al., 2028)")
        XCTAssertEqual(BibToAPAFormatter.formatNarrativeCitation(manyAuthorsEntry), "Tester et al. (2028)")
    }
}
