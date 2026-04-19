import XCTest
import BiblatexAPA
@testable import BibAPAToMD

final class IntegrationTests: XCTestCase {

    func testEndToEndWithRealBibFile() throws {
        let bibPath = "/Users/che/Academic/che-cheng-website/vendor/cheng_che_cv/bibliography/Che.bib"
        let bibFile = try BibParser.parse(filePath: bibPath)

        XCTAssertGreaterThan(bibFile.entries.count, 0, "Should have entries")

        let markdown = BibToAPAFormatter.formatReferenceList(bibFile.entries)
        XCTAssertFalse(markdown.isEmpty)

        // Print for manual inspection
        print("\n=== \(bibFile.entries.count) entries converted ===\n")
        print(markdown)
    }
}
