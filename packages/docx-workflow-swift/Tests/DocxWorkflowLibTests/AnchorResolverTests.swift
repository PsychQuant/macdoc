// AnchorResolverTests — §6.2 of macdoc-docx-workflow-cli.
//
// Covers spec.md Requirement "Anchor resolution semantics are deterministic"
// scenarios: exact-one match, multi-match, zero-match, paragraph_index
// in-range + out-of-range.

import XCTest
import DocxWorkflowLib

final class AnchorResolverTests: XCTestCase {

    // MARK: - Test fixtures

    /// Builds a synthetic snapshot with deterministic ParagraphRefs derived
    /// from a UUID string seed (libraryUUID variant). The actual ElementID
    /// content doesn't matter for resolution logic — only that .ref values
    /// differ between paragraphs so the test can verify the right one is
    /// returned.
    private func makeSnapshot(_ texts: [String]) -> [ParagraphSnapshotEntry] {
        return texts.map { text in
            ParagraphSnapshotEntry(
                ref: ParagraphRef(ElementID(libraryUUID: UUID())),
                text: text
            )
        }
    }

    // MARK: - Spec scenarios

    func testExactOneMatchResolves() throws {
        // Spec: "GIVEN a baseline with paragraphs ['Introduction', 'Background', 'Methods']
        // WHEN anchor is { after_text: 'Background' } THEN resolver returns
        // the ParagraphRef for 'Background'."
        let snapshot = makeSnapshot(["Introduction", "Background", "Methods"])
        let resolver = AnchorResolver()
        let ref = try resolver.resolve(.afterText("Background"), snapshot: snapshot, stepIndex: 0)
        XCTAssertEqual(ref, snapshot[1].ref)
    }

    func testMultiMatchThrowsAmbiguous() {
        // Spec example: "GIVEN baseline paragraphs at indices [0]='Section A',
        // [2]='Section A' WHEN anchor is { after_text: 'Section A' } THEN
        // throws AnchorError.ambiguous(matches: [0, 2])"
        let snapshot = makeSnapshot(["Section A", "Section B", "Section A"])
        let resolver = AnchorResolver()
        XCTAssertThrowsError(try resolver.resolve(.afterText("Section A"), snapshot: snapshot, stepIndex: 0)) { error in
            guard case AnchorError.ambiguous(let anchor, let stepIdx, let matches) = error else {
                XCTFail("Expected .ambiguous, got \(error)")
                return
            }
            XCTAssertEqual(anchor, "Section A")
            XCTAssertEqual(stepIdx, 0)
            XCTAssertEqual(matches, [0, 2])
        }
    }

    func testZeroMatchThrowsNotFound() {
        // Spec: "WHEN anchor is { after_text: 'NonExistent' } THEN throws
        // AnchorError.notFound(scanned: <paragraph count>)"
        let snapshot = makeSnapshot(["one", "two", "three"])
        let resolver = AnchorResolver()
        XCTAssertThrowsError(try resolver.resolve(.afterText("NonExistent"), snapshot: snapshot, stepIndex: 3)) { error in
            guard case AnchorError.notFound(let anchor, let stepIdx, let count) = error else {
                XCTFail("Expected .notFound, got \(error)")
                return
            }
            XCTAssertEqual(anchor, "NonExistent")
            XCTAssertEqual(stepIdx, 3)
            XCTAssertEqual(count, 3)
        }
    }

    func testParagraphIndexResolvesDirectly() throws {
        // Spec: "GIVEN baseline with 5 paragraphs WHEN anchor is
        // { paragraph_index: 2 } THEN returns ParagraphRef for the 3rd
        // paragraph (zero-based) without scanning any paragraph text"
        let snapshot = makeSnapshot(["p0", "p1", "p2", "p3", "p4"])
        let resolver = AnchorResolver()
        let ref = try resolver.resolve(.paragraphIndex(2), snapshot: snapshot, stepIndex: 0)
        XCTAssertEqual(ref, snapshot[2].ref)
    }

    func testParagraphIndexOutOfRange() {
        // Spec: "GIVEN baseline with 3 paragraphs WHEN anchor is
        // { paragraph_index: 5 } THEN throws .indexOutOfRange"
        let snapshot = makeSnapshot(["p0", "p1", "p2"])
        let resolver = AnchorResolver()
        XCTAssertThrowsError(try resolver.resolve(.paragraphIndex(5), snapshot: snapshot, stepIndex: 0)) { error in
            guard case AnchorError.indexOutOfRange(let requested, let available) = error else {
                XCTFail("Expected .indexOutOfRange, got \(error)")
                return
            }
            XCTAssertEqual(requested, 5)
            XCTAssertEqual(available, 3)
        }
    }

    func testBeforeTextMatchesSameWayAsAfterText() throws {
        // before_text uses the same text-matching path as after_text;
        // they differ only at the EditPlanner stage (which Edit case to emit).
        let snapshot = makeSnapshot(["alpha", "beta", "gamma"])
        let resolver = AnchorResolver()
        let ref = try resolver.resolve(.beforeText("beta"), snapshot: snapshot, stepIndex: 0)
        XCTAssertEqual(ref, snapshot[1].ref)
    }

    func testNegativeParagraphIndexThrows() {
        // Audit-honest: negative indices are out-of-range, not a separate error case.
        let snapshot = makeSnapshot(["only"])
        let resolver = AnchorResolver()
        XCTAssertThrowsError(try resolver.resolve(.paragraphIndex(-1), snapshot: snapshot, stepIndex: 0))
    }
}
