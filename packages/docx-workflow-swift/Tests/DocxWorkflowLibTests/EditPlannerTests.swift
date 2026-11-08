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

    // MARK: - insert_paragraph `inherit_anchor_format` (PsychQuant/macdoc#251)

    /// Compiles one insert_paragraph step and returns the OOXMLEdit it became.
    private func compileInsert(anchor: Anchor, inherit: Bool?, ref: ParagraphRef) throws -> OOXMLEdit {
        let step = Step.insertParagraph(
            InsertParagraphStep(anchor: anchor, content: "new", inheritAnchorFormat: inherit))
        guard case .functional(let edit) = EditPlanner().compile(step, anchorRef: ref),
              let ooxmlEdit = edit as? OOXMLEdit
        else {
            XCTFail("expected a functional OOXMLEdit for \(anchor)")
            throw XCTSkip("compile did not produce an OOXMLEdit")
        }
        return ooxmlEdit
    }

    func testInsertAfterTextPassesInheritAnchorFormat() throws {
        let ref = makeRef()
        let edit = try compileInsert(anchor: .afterText("intro"), inherit: true, ref: ref)
        guard case .insertParagraph(let after, let content, let styleId, let inherit) = edit else {
            return XCTFail("after_text must compile to OOXMLEdit.insertParagraph, got \(edit)")
        }
        XCTAssertEqual(after, ref.elementID)
        XCTAssertEqual(content, "new")
        XCTAssertNil(styleId, "the manifest shape exposes no style id")
        XCTAssertTrue(inherit, "inherit_anchor_format: true must reach the reducer")
    }

    func testInsertAfterParagraphIndexPassesInheritAnchorFormat() throws {
        let ref = makeRef()
        let edit = try compileInsert(anchor: .paragraphIndex(0), inherit: true, ref: ref)
        guard case .insertParagraph(_, _, _, let inherit) = edit else {
            return XCTFail("paragraph_index must compile to OOXMLEdit.insertParagraph, got \(edit)")
        }
        XCTAssertTrue(inherit)
    }

    func testInsertBeforeTextPassesInheritAnchorFormat() throws {
        let ref = makeRef()
        let edit = try compileInsert(anchor: .beforeText("intro"), inherit: true, ref: ref)
        guard case .insertParagraphBefore(let before, let content, let styleId, let inherit) = edit else {
            return XCTFail("before_text must compile to OOXMLEdit.insertParagraphBefore, got \(edit)")
        }
        XCTAssertEqual(before, ref.elementID)
        XCTAssertEqual(content, "new")
        XCTAssertNil(styleId)
        XCTAssertTrue(inherit, "inherit_anchor_format: true must reach the reducer")
    }

    func testInsertWithoutTheFieldOrWithFalseDoesNotInherit() throws {
        let ref = makeRef()
        for inherit in [nil, false] as [Bool?] {
            let after = try compileInsert(anchor: .afterText("intro"), inherit: inherit, ref: ref)
            guard case .insertParagraph(_, _, _, let afterFlag) = after else {
                return XCTFail("expected insertParagraph, got \(after)")
            }
            XCTAssertFalse(afterFlag, "inherit_anchor_format \(String(describing: inherit)) must keep the old output")

            let before = try compileInsert(anchor: .beforeText("intro"), inherit: inherit, ref: ref)
            guard case .insertParagraphBefore(_, _, _, let beforeFlag) = before else {
                return XCTFail("expected insertParagraphBefore, got \(before)")
            }
            XCTAssertFalse(beforeFlag, "inherit_anchor_format \(String(describing: inherit)) must keep the old output")
        }
    }
}
