// VerifierTests — §6.4 of macdoc-docx-workflow-cli.
//
// Covers spec.md Requirement "Verify post-condition modes assert document
// invariants" scenarios for all 5 Phase 1 verify modes.

import XCTest
import DocxWorkflowLib

final class VerifierTests: XCTestCase {

    // MARK: - Fixture helpers

    private func makeTempURL(prefix: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString).docx")
    }

    private func makeBaseline(texts: [String]) throws -> URL {
        var doc = WordDocument()
        for text in texts {
            doc.appendParagraph(Paragraph(text: text))
        }
        let url = makeTempURL(prefix: "baseline")
        try DocxWriter.writeData(doc).write(to: url)
        return url
    }

    // MARK: - expected_paragraphs_min

    func testParagraphCountSucceedsWhenAboveMin() throws {
        let url = try makeBaseline(texts: ["a", "b", "c", "d"])
        defer { try? FileManager.default.removeItem(at: url) }

        let assertions = VerifyAssertions(expectedParagraphsMin: 3)
        XCTAssertNoThrow(try Verifier().verify(assertions, baselineURL: url, outputURL: url))
    }

    func testParagraphCountFailsWhenBelowMin() throws {
        let url = try makeBaseline(texts: ["only"])
        defer { try? FileManager.default.removeItem(at: url) }

        let assertions = VerifyAssertions(expectedParagraphsMin: 5)
        XCTAssertThrowsError(try Verifier().verify(assertions, baselineURL: url, outputURL: url)) { error in
            guard case VerifyError.paragraphCountBelowMin(let expected, let observed) = error else {
                XCTFail("Expected .paragraphCountBelowMin, got \(error)")
                return
            }
            XCTAssertEqual(expected, 5)
            XCTAssertEqual(observed, 1)
        }
    }

    // MARK: - expected_images

    func testExpectedImagesSucceedsWhenZero() throws {
        // Spec scenario: baseline with 0 images, manifest verify {expected_images: 0}.
        let url = try makeBaseline(texts: ["text"])
        defer { try? FileManager.default.removeItem(at: url) }

        let assertions = VerifyAssertions(expectedImages: 0)
        XCTAssertNoThrow(try Verifier().verify(assertions, baselineURL: url, outputURL: url))
    }

    func testExpectedImagesFailsWhenMismatch() throws {
        // Baseline has 0 images, but verify expects 5 → mismatch.
        let url = try makeBaseline(texts: ["text"])
        defer { try? FileManager.default.removeItem(at: url) }

        let assertions = VerifyAssertions(expectedImages: 5)
        XCTAssertThrowsError(try Verifier().verify(assertions, baselineURL: url, outputURL: url)) { error in
            guard case VerifyError.imageCountMismatch(let expected, let observed) = error else {
                XCTFail("Expected .imageCountMismatch, got \(error)")
                return
            }
            XCTAssertEqual(expected, 5)
            XCTAssertEqual(observed, 0)
        }
    }

    // MARK: - libxml2_valid

    func testLibxml2ValidPassesForCleanDocx() throws {
        let url = try makeBaseline(texts: ["a"])
        defer { try? FileManager.default.removeItem(at: url) }

        let assertions = VerifyAssertions(libxml2Valid: true)
        XCTAssertNoThrow(try Verifier().verify(assertions, baselineURL: url, outputURL: url))
    }

    func testLibxml2ValidSkippedWhenFlagFalse() throws {
        let url = try makeBaseline(texts: ["a"])
        defer { try? FileManager.default.removeItem(at: url) }

        // libxml2Valid: false means "don't run the check"; should always pass.
        let assertions = VerifyAssertions(libxml2Valid: false)
        XCTAssertNoThrow(try Verifier().verify(assertions, baselineURL: url, outputURL: url))
    }

    // MARK: - byte_preserved_parts

    func testBytePreservedPartsPassesWhenIdentical() throws {
        let url = try makeBaseline(texts: ["a", "b"])
        defer { try? FileManager.default.removeItem(at: url) }

        let assertions = VerifyAssertions(bytePreservedParts: ["word/styles.xml"])
        // Baseline == output (same URL) → all parts match byte-for-byte.
        XCTAssertNoThrow(try Verifier().verify(assertions, baselineURL: url, outputURL: url))
    }

    func testBytePreservedPartsFailsWhenPartDiffers() throws {
        let baseline = try makeBaseline(texts: ["a"])
        let output = try makeBaseline(texts: ["a", "b"])  // different content → different word/document.xml
        defer {
            try? FileManager.default.removeItem(at: baseline)
            try? FileManager.default.removeItem(at: output)
        }

        let assertions = VerifyAssertions(bytePreservedParts: ["word/document.xml"])
        XCTAssertThrowsError(try Verifier().verify(assertions, baselineURL: baseline, outputURL: output)) { error in
            guard case VerifyError.bytePreservedPartChanged(let partName, _, _, _) = error else {
                XCTFail("Expected .bytePreservedPartChanged, got \(error)")
                return
            }
            XCTAssertTrue(partName.hasSuffix("document.xml"))
        }
    }

    func testBytePreservedPartsGlobMatching() throws {
        let url = try makeBaseline(texts: ["a"])
        defer { try? FileManager.default.removeItem(at: url) }

        // Glob pattern matching multiple files.
        let assertions = VerifyAssertions(bytePreservedParts: ["word/*.xml"])
        XCTAssertNoThrow(try Verifier().verify(assertions, baselineURL: url, outputURL: url))
    }

    // MARK: - All-nil verify is a no-op

    func testEmptyVerifyAssertionsPassesTrivially() throws {
        let url = try makeBaseline(texts: ["a"])
        defer { try? FileManager.default.removeItem(at: url) }

        let assertions = VerifyAssertions()
        XCTAssertNoThrow(try Verifier().verify(assertions, baselineURL: url, outputURL: url))
    }
}
