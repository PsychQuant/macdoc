import XCTest
import BiblatexAPA
@testable import BibAPAToMD

final class IntegrationTests: XCTestCase {

    func testEndToEndWithBundledBibFixtureCoversEveryReferenceType() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "portable-references", withExtension: "bib"))
        let bibFile = try BibParser.parse(filePath: url.path)

        XCTAssertEqual(bibFile.entries.count, 8)
        let markdown = BibToAPAFormatter.formatReferenceList(bibFile.entries)
        XCTAssertTrue(markdown.contains("Article title: Article subtitle"))
        XCTAssertTrue(markdown.contains("*Journal of Fixtures*"))
        XCTAssertTrue(markdown.contains("*Book title: Book subtitle*"))
        XCTAssertTrue(markdown.contains("Chapter title: Chapter subtitle"))
        XCTAssertTrue(markdown.contains("*Fixture handbook*"))
        XCTAssertTrue(markdown.contains("[Doctoral dissertation, Test University]"))
        XCTAssertTrue(markdown.contains("Report title: Report subtitle"))
        XCTAssertTrue(markdown.contains("(Technical Report 42)"))
        XCTAssertTrue(markdown.contains("[Conference presentation]"))
        XCTAssertTrue(markdown.contains("Fixture Conference"))
        XCTAssertTrue(markdown.contains("*Online title: Online subtitle*"))
        XCTAssertTrue(markdown.contains("*Fallback title: Fallback subtitle*"))
        XCTAssertTrue(markdown.contains("https://doi.org/10.1234/article"))
        XCTAssertTrue(markdown.contains("https://example.test/online"))
    }
}
