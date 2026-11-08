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

    // MARK: - insert_paragraph `inherit_anchor_format` (PsychQuant/macdoc#251)

    private func decodeInsertStep(_ stepJSON: String) throws -> InsertParagraphStep {
        let json = #"{ "baseline": "a.docx", "output": "b.docx", "steps": [ "# + stepJSON + " ] }"
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(json.utf8))
        guard case .insertParagraph(let payload) = manifest.steps[0] else {
            throw XCTSkip("expected an insert_paragraph step, got \(manifest.steps[0])")
        }
        return payload
    }

    private func encodedObject(_ step: InsertParagraphStep) throws -> [String: Any] {
        let data = try JSONEncoder().encode(step)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testInheritAnchorFormatTrueDecodes() throws {
        let step = try decodeInsertStep(
            #"{ "type": "insert_paragraph", "anchor": { "after_text": "Name:" }, "content": "x", "inherit_anchor_format": true }"#)
        XCTAssertEqual(step.inheritAnchorFormat, true)
    }

    func testInheritAnchorFormatFalseDecodes() throws {
        let step = try decodeInsertStep(
            #"{ "type": "insert_paragraph", "anchor": { "after_text": "Name:" }, "content": "x", "inherit_anchor_format": false }"#)
        XCTAssertEqual(step.inheritAnchorFormat, false)
    }

    func testInheritAnchorFormatIsNilWhenAbsent() throws {
        let step = try decodeInsertStep(
            #"{ "type": "insert_paragraph", "anchor": { "after_text": "Name:" }, "content": "x" }"#)
        XCTAssertNil(step.inheritAnchorFormat, "a manifest written before #251 must decode exactly as before")
    }

    func testInheritAnchorFormatRejectsANonBooleanValue() {
        XCTAssertThrowsError(try decodeInsertStep(
            #"{ "type": "insert_paragraph", "anchor": { "after_text": "Name:" }, "content": "x", "inherit_anchor_format": "yes" }"#)
        ) { error in
            guard case DecodingError.typeMismatch = error else {
                XCTFail("expected DecodingError.typeMismatch for a string value, got \(error)")
                return
            }
        }
    }

    func testInheritAnchorFormatIsOmittedWhenEncodingNil() throws {
        let object = try encodedObject(InsertParagraphStep(anchor: .afterText("Name:"), content: "x"))
        XCTAssertNil(object["inherit_anchor_format"], "nil must not be written, so existing manifests round-trip unchanged")
        XCTAssertNil(object["inheritAnchorFormat"])
        XCTAssertEqual(Set(object.keys), ["type", "anchor", "content"])
    }

    func testInheritAnchorFormatEncodesUnderTheSnakeCaseKey() throws {
        let object = try encodedObject(
            InsertParagraphStep(anchor: .afterText("Name:"), content: "x", inheritAnchorFormat: true))
        XCTAssertEqual(object["inherit_anchor_format"] as? Bool, true)
        XCTAssertNil(object["inheritAnchorFormat"])
    }
}
