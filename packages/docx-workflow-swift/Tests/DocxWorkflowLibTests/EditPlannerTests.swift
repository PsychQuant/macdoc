// EditPlannerTests — PsychQuant/macdoc#232.
//
// Covers `EditPlanner.compile`'s `set_bold` case directly, at the
// planner-unit level (no baseline document, no Executor, no CLI):
// - a non-empty `substring` compiles to `OOXMLEdit.setBoldInRange` (not the
//   old paragraph-targeted `OOXMLEdit.setBold`, which the reducer always
//   rejected — see the issue's "target must be <w:r>" reproduction).
// - an empty `substring` is rejected at compile time (`.pending`), never
//   reaching the reducer.
//
// `@testable import` reaches `EditPlanner`, which is `internal` (§4.1 —
// the planner is implementation detail behind `Executor`'s public surface).

import XCTest
@testable import DocxWorkflowLib

final class EditPlannerTests: XCTestCase {

    private func makeRef() -> ParagraphRef {
        ParagraphRef(ElementID(libraryUUID: UUID()))
    }

    // MARK: - Non-empty substring → functional setBoldInRange

    func testSetBoldCompilesToSetBoldInRange() throws {
        let ref = makeRef()
        let step = Step.setBold(SetBoldStep(anchor: .afterText("intro"), substring: "TARGET"))

        let result = EditPlanner().compile(step, anchorRef: ref)

        guard case .functional(let edit) = result else {
            XCTFail("Expected .functional, got \(result)")
            return
        }
        guard let ooxmlEdit = edit as? OOXMLEdit,
              case .setBoldInRange(let target, let substring, let value, let instance) = ooxmlEdit
        else {
            XCTFail("Expected OOXMLEdit.setBoldInRange, got \(edit)")
            return
        }
        XCTAssertEqual(target, ref.elementID, "target is the anchor PARAGRAPH's ElementID, not a Run")
        XCTAssertEqual(substring, "TARGET")
        XCTAssertEqual(value, true)
        XCTAssertEqual(instance, 1, "manifest step shape has no instance field — defaults to the first occurrence")
    }

    func testSetBoldNoLongerCompilesToPlainSetBold() throws {
        // Regression guard for the exact macdoc#232 failure mode: the
        // paragraph-targeted `.setBold` case always threw `malformedOp`
        // ("setRunFormat target must be <w:r>") because it expects a Run,
        // not a paragraph.
        let ref = makeRef()
        let step = Step.setBold(SetBoldStep(anchor: .afterText("intro"), substring: "TARGET"))

        let result = EditPlanner().compile(step, anchorRef: ref)

        guard case .functional(let edit) = result, let ooxmlEdit = edit as? OOXMLEdit else {
            XCTFail("Expected .functional")
            return
        }
        if case .setBold = ooxmlEdit {
            XCTFail("set_bold must not compile to the plain paragraph-targeted OOXMLEdit.setBold")
        }
    }

    // MARK: - Empty substring → rejected at compile time (.pending)

    func testSetBoldWithEmptySubstringIsPending() throws {
        let ref = makeRef()
        let step = Step.setBold(SetBoldStep(anchor: .afterText("intro"), substring: ""))

        let result = EditPlanner().compile(step, anchorRef: ref)

        guard case .pending(let stepType, let tracker) = result else {
            XCTFail("Expected .pending for an empty substring, got \(result) — an empty substring can never match a text range and must not reach the reducer")
            return
        }
        XCTAssertEqual(stepType, "set_bold")
        XCTAssertFalse(tracker.isEmpty)
    }

    // MARK: - Missing anchor still reported the existing way (unchanged)

    func testSetBoldWithMissingAnchorIsPending() throws {
        let step = Step.setBold(SetBoldStep(anchor: .afterText("intro"), substring: "TARGET"))

        let result = EditPlanner().compile(step, anchorRef: nil)

        guard case .pending(let stepType, let tracker) = result else {
            XCTFail("Expected .pending when anchorRef is nil, got \(result)")
            return
        }
        XCTAssertEqual(stepType, "set_bold")
        XCTAssertTrue(tracker.contains("anchor missing"))
    }
}
