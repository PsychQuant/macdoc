// AnchorDecodingTests — §2.2 verify clause (decoder coverage for Anchor enum).
//
// Note: AnchorResolverTests in §6.2 covers RESOLUTION semantics; this file
// covers DECODING the JSON object shape for `before_text` / `after_text` /
// `paragraph_index` variants.

import XCTest
import DocxWorkflowLib

final class AnchorDecodingTests: XCTestCase {

    func testTaggedAnchorDecode() throws {
        // Spec: `Anchor` decodes from `{ "after_text": "前言" }` to `.afterText("前言")`
        let data = Data(#"{ "after_text": "前言" }"#.utf8)
        let anchor = try JSONDecoder().decode(Anchor.self, from: data)
        guard case .afterText(let text) = anchor else {
            XCTFail("Expected .afterText, got \(anchor)")
            return
        }
        XCTAssertEqual(text, "前言")
    }

    func testBeforeTextAnchorDecode() throws {
        let data = Data(#"{ "before_text": "Header" }"#.utf8)
        let anchor = try JSONDecoder().decode(Anchor.self, from: data)
        guard case .beforeText(let text) = anchor else {
            XCTFail("Expected .beforeText")
            return
        }
        XCTAssertEqual(text, "Header")
    }

    func testParagraphIndexAnchorDecode() throws {
        let data = Data(#"{ "paragraph_index": 3 }"#.utf8)
        let anchor = try JSONDecoder().decode(Anchor.self, from: data)
        guard case .paragraphIndex(let idx) = anchor else {
            XCTFail("Expected .paragraphIndex")
            return
        }
        XCTAssertEqual(idx, 3)
    }

    func testEmptyAnchorObjectFailsToDecode() {
        // An anchor object with no recognized key SHALL fail.
        let data = Data("{}".utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(Anchor.self, from: data))
    }
}
