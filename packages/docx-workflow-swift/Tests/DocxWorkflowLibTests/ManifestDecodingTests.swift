// ManifestDecodingTests — §6.1 of macdoc-docx-workflow-cli.
//
// Covers spec.md Requirement "Manifest is JSON-Codable in Phase 1" scenarios:
// - Decoding a minimal JSON manifest (uses the exact JSON from
//   `##### Example: Minimal manifest`)
// - Decoding fails for missing required fields
// - UTF-8 CJK anchor text decodes intact

import XCTest
import DocxWorkflowLib

final class ManifestDecodingTests: XCTestCase {

    func testMinimalManifestDecode() throws {
        // Spec example: `##### Example: Minimal manifest`
        let json = #"""
        {
          "baseline": "archived/baseline.docx",
          "output": "docs/output.docx",
          "steps": [
            { "type": "insert_paragraph", "anchor": { "after_text": "Introduction" }, "content": "New paragraph body." }
          ]
        }
        """#
        let data = Data(json.utf8)

        let manifest = try JSONDecoder().decode(Manifest.self, from: data)

        XCTAssertEqual(manifest.baseline, "archived/baseline.docx")
        XCTAssertEqual(manifest.output, "docs/output.docx")
        XCTAssertEqual(manifest.steps.count, 1)
        XCTAssertNil(manifest.verify)

        // Verify the step shape
        guard case .insertParagraph(let payload) = manifest.steps[0] else {
            XCTFail("Expected insertParagraph step")
            return
        }
        XCTAssertEqual(payload.content, "New paragraph body.")
        guard case .afterText(let anchorText) = payload.anchor else {
            XCTFail("Expected afterText anchor")
            return
        }
        XCTAssertEqual(anchorText, "Introduction")
    }

    func testMissingRequiredFieldThrowsKeyNotFound() {
        // Spec scenario: "Decoding fails for missing required fields"
        let missingSteps = Data(#"{ "baseline": "a", "output": "b" }"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(Manifest.self, from: missingSteps)) { error in
            guard case DecodingError.keyNotFound(let key, _) = error else {
                XCTFail("Expected DecodingError.keyNotFound, got \(error)")
                return
            }
            XCTAssertEqual(key.stringValue, "steps")
        }
    }

    func testCJKAnchorTextRoundTripsByteForByte() throws {
        // Spec scenario: "UTF-8 CJK anchor text decodes intact"
        let json = #"""
        {
          "baseline": "a.docx",
          "output": "b.docx",
          "steps": [
            { "type": "insert_paragraph", "anchor": { "after_text": "前言" }, "content": "段落" }
          ]
        }
        """#
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(json.utf8))
        guard case .insertParagraph(let payload) = manifest.steps[0],
              case .afterText(let anchorText) = payload.anchor else {
            XCTFail("Unexpected step shape")
            return
        }
        XCTAssertEqual(anchorText, "前言")
        XCTAssertEqual(payload.content, "段落")
    }
}
