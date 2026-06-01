// VerifyAssertionsDecodingTests — §2.3 verify clause.
//
// Covers spec.md Requirement "Verify post-condition modes assert document
// invariants" decoder side: decoding a `verify` object with any subset of
// fields succeeds; missing fields decode to nil.

import XCTest
import DocxWorkflowLib

final class VerifyAssertionsDecodingTests: XCTestCase {

    func testEmptyVerifyDecodesToAllNil() throws {
        let data = Data("{}".utf8)
        let verify = try JSONDecoder().decode(VerifyAssertions.self, from: data)
        XCTAssertNil(verify.expectedImages)
        XCTAssertNil(verify.expectedParagraphsMin)
        XCTAssertNil(verify.expectedBookmarksMin)
        XCTAssertNil(verify.libxml2Valid)
        XCTAssertNil(verify.bytePreservedParts)
    }

    func testPartialVerifyDecodesWithMissingNil() throws {
        let data = Data(#"{ "expected_images": 5, "libxml2_valid": true }"#.utf8)
        let verify = try JSONDecoder().decode(VerifyAssertions.self, from: data)
        XCTAssertEqual(verify.expectedImages, 5)
        XCTAssertEqual(verify.libxml2Valid, true)
        XCTAssertNil(verify.expectedParagraphsMin)
        XCTAssertNil(verify.expectedBookmarksMin)
        XCTAssertNil(verify.bytePreservedParts)
    }

    func testFullVerifyDecodesAllFields() throws {
        let json = #"""
        {
          "expected_images": 3,
          "expected_paragraphs_min": 10,
          "expected_bookmarks_min": 2,
          "libxml2_valid": true,
          "byte_preserved_parts": ["word/header*.xml", "word/footer*.xml"]
        }
        """#
        let verify = try JSONDecoder().decode(VerifyAssertions.self, from: Data(json.utf8))
        XCTAssertEqual(verify.expectedImages, 3)
        XCTAssertEqual(verify.expectedParagraphsMin, 10)
        XCTAssertEqual(verify.expectedBookmarksMin, 2)
        XCTAssertEqual(verify.libxml2Valid, true)
        XCTAssertEqual(verify.bytePreservedParts, ["word/header*.xml", "word/footer*.xml"])
    }
}
