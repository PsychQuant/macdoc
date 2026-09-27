// MutationIntentTests — macdoc#137 Layer 1 (docx-mutation-certification-layer1).
//
// Covers spec.md Requirement "Mutation intent is derived from a closed
// step-type table": every row of the "Allowed-part derivation" example,
// the "Link step allows the relationships part" scenario, and the
// "Unknown functional step type fails closed" scenario.
//
// The unknown-type scenario is unreachable through the public
// `Manifest`/`Step` surface — `Step` is a closed 12-case enum and every
// case EditPlanner currently compiles to a functional edit already has a
// row in `MutationIntent.allowedPartsTable`. This file uses
// `@testable import` to reach the internal
// `derive(functionalStepTypeIDs:)` seam, which lets the test exercise the
// fail-closed path the table's forward-compatibility promise depends on
// (a future runtime-functional step type shipped without a table row)
// without waiting for that gap to exist for real.

import XCTest
@testable import DocxWorkflowLib

final class MutationIntentTests: XCTestCase {

    // MARK: - Allowed-part derivation example (spec.md table)

    func testInsertParagraphAloneAllowsDocumentXML() throws {
        let manifest = Manifest(
            baseline: "baseline.docx",
            output: "output.docx",
            steps: [.insertParagraph(InsertParagraphStep(anchor: .afterText("x"), content: "new"))]
        )
        let intent = try MutationIntent.derive(from: manifest)
        XCTAssertEqual(intent.allowedParts, ["word/document.xml"])
    }

    func testRemoveParagraphAndSetBoldAllowDocumentXML() throws {
        let manifest = Manifest(
            baseline: "baseline.docx",
            output: "output.docx",
            steps: [
                .removeParagraph(RemoveParagraphStep(anchor: .afterText("x"))),
                .setBold(SetBoldStep(anchor: .afterText("y"), substring: "y")),
            ]
        )
        let intent = try MutationIntent.derive(from: manifest)
        XCTAssertEqual(intent.allowedParts, ["word/document.xml"])
    }

    func testInsertParagraphAndWrapLinkAllowRelationshipsPart() throws {
        let manifest = Manifest(
            baseline: "baseline.docx",
            output: "output.docx",
            steps: [
                .insertParagraph(InsertParagraphStep(anchor: .afterText("x"), content: "new")),
                .wrapLink(WrapLinkStep(anchor: .afterText("y"), url: "https://example.com")),
            ]
        )
        let intent = try MutationIntent.derive(from: manifest)
        XCTAssertEqual(intent.allowedParts, ["word/document.xml", "word/_rels/document.xml.rels"])
    }

    func testOnlyPendingStepsYieldEmptyAllowedParts() throws {
        let manifest = Manifest(
            baseline: "baseline.docx",
            output: "output.docx",
            steps: [
                .insertImage(InsertImageStep(anchor: .afterText("x"), path: "f.png")),
                .insertTable(InsertTableStep(anchor: .afterText("y"), rows: 1, columns: 1)),
            ]
        )
        let intent = try MutationIntent.derive(from: manifest)
        XCTAssertEqual(intent.allowedParts, [])
    }

    // MARK: - Scenario: Link step allows the relationships part

    func testWrapLinkScenarioDerivedAllowedPartsAreExactlyTwo() throws {
        let manifest = Manifest(
            baseline: "baseline.docx",
            output: "output.docx",
            steps: [
                .insertParagraph(InsertParagraphStep(anchor: .afterText("x"), content: "new")),
                .wrapLink(WrapLinkStep(anchor: .afterText("y"), url: "https://example.com")),
            ]
        )
        let intent = try MutationIntent.derive(from: manifest)
        XCTAssertEqual(intent.allowedParts.count, 2)
        XCTAssertTrue(intent.allowedParts.contains("word/document.xml"))
        XCTAssertTrue(intent.allowedParts.contains("word/_rels/document.xml.rels"))
    }

    // MARK: - Scenario: Unknown functional step type fails closed

    func testUnknownFunctionalStepTypeThrowsIntentUnavailable() {
        XCTAssertThrowsError(
            try MutationIntent.derive(functionalStepTypeIDs: ["insert_table"])
        ) { error in
            guard let certError = error as? CertificationError else {
                XCTFail("Expected CertificationError, got \(error)")
                return
            }
            guard case .intentUnavailable(let stepType) = certError else {
                XCTFail("Expected .intentUnavailable, got \(certError)")
                return
            }
            XCTAssertEqual(stepType, "insert_table")
        }
    }

    func testPendingStepTypesContributeNoParts() throws {
        // Sanity: a manifest containing every currently-pending step type
        // (Phase 2c) derives an empty allowed-parts set, never a thrown
        // error — "pending steps contribute no parts", not "unknown type".
        let manifest = Manifest(
            baseline: "baseline.docx",
            output: "output.docx",
            steps: [
                .replaceText(ReplaceTextStep(find: "a", replace: "b")),
                .setParagraphStyle(SetParagraphStyleStep(anchor: .afterText("x"), styleId: "Heading1")),
                .setItalic(SetItalicStep(anchor: .afterText("x"), substring: "x")),
                .setUnderline(SetUnderlineStep(anchor: .afterText("x"), substring: "x")),
                .insertImage(InsertImageStep(anchor: .afterText("x"), path: "f.png")),
                .insertTable(InsertTableStep(anchor: .afterText("x"), rows: 1, columns: 1)),
                .setCellText(SetCellTextStep(anchor: .afterText("x"), row: 0, col: 0, text: "t")),
                .insertEquation(InsertEquationStep(anchor: .afterText("x"), omml: "<m:e/>")),
            ]
        )
        let intent = try MutationIntent.derive(from: manifest)
        XCTAssertEqual(intent.allowedParts, [])
    }
}
