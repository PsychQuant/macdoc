// CertifiedTransactionTests — macdoc#137 Layer 1 (docx-mutation-certification-layer1).
//
// Covers spec.md Requirement "Certified transaction commits only after
// every gate passes": tasks 4.1 (success + gate failure), 4.2 (verify
// failure) and 4.3 (baseline changed before commit).
//
// The gate-failure and baseline-changed scenarios need to reach into the
// window between candidate-write and commit — a real, honest failure
// through the actual `Executor` + `Layer1Gate` pipeline, not a
// hand-assembled `Layer1Result`. `@testable import` reaches the two
// internal test hooks that open that window (`testHookAfterCandidateWritten`
// / `testHookBeforeBaselineRecheck`), mirroring the precedent in
// `OOXMLSwift.DocxWriter.write`'s `immediatelyBeforeGenerationCheck`.

import XCTest
@testable import DocxWorkflowLib

final class CertifiedTransactionTests: XCTestCase {

    // MARK: - Fixtures

    private func makeTempURL(prefix: String, ext: String = "docx") -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString).\(ext)")
    }

    private func makeBaseline(texts: [String]) throws -> URL {
        var doc = WordDocument()
        for text in texts {
            doc.appendParagraph(Paragraph(text: text))
        }
        let url = makeTempURL(prefix: "ct-baseline")
        try DocxWriter.writeData(doc).write(to: url)
        return url
    }

    private func cleanup(_ urls: URL...) {
        for url in urls { try? FileManager.default.removeItem(at: url) }
    }

    private func rejectedURL(for outputURL: URL) -> URL {
        let dir = outputURL.deletingLastPathComponent()
        let stem = outputURL.deletingPathExtension().lastPathComponent
        return dir.appendingPathComponent("\(stem).rejected.\(outputURL.pathExtension)")
    }

    // MARK: - 4.1 Success

    func testSuccessWritesOutputAndLeavesNoLeftovers() throws {
        let baseline = try makeBaseline(texts: ["intro"])
        let output = makeTempURL(prefix: "ct-out")
        defer { cleanup(baseline, output) }

        let manifest = Manifest(
            baseline: baseline.path, output: output.path,
            steps: [.insertParagraph(InsertParagraphStep(anchor: .afterText("intro"), content: "inserted"))]
        )

        let certificate = try CertifiedTransaction().apply(manifest: manifest, baselineURL: baseline, outputURL: output)

        XCTAssertEqual(certificate.status, .layer1Verified)
        XCTAssertTrue(certificate.layer1.passed)
        XCTAssertEqual(certificate.changedParts, ["word/document.xml"])
        XCTAssertNil(certificate.rejectedCandidateURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.path))

        // No candidate-<uuid> or rejected file remains beside the output.
        let dirEntries = try FileManager.default.contentsOfDirectory(atPath: output.deletingLastPathComponent().path)
        let stem = output.deletingPathExtension().lastPathComponent
        let leftovers = dirEntries.filter { $0.hasPrefix(stem) && $0 != output.lastPathComponent }
        XCTAssertTrue(leftovers.isEmpty, "leftover files: \(leftovers)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: rejectedURL(for: output).path))
    }

    func testSuccessRemovesAPreExistingRejectedFile() throws {
        // "no candidate or rejected file remains in the directory" — even
        // one left over from an earlier failed run.
        let baseline = try makeBaseline(texts: ["intro"])
        let output = makeTempURL(prefix: "ct-out")
        let rejected = rejectedURL(for: output)
        try Data("stale rejected candidate".utf8).write(to: rejected)
        defer { cleanup(baseline, output, rejected) }

        let manifest = Manifest(
            baseline: baseline.path, output: output.path,
            steps: [.insertParagraph(InsertParagraphStep(anchor: .afterText("intro"), content: "inserted"))]
        )
        _ = try CertifiedTransaction().apply(manifest: manifest, baselineURL: baseline, outputURL: output)

        XCTAssertFalse(FileManager.default.fileExists(atPath: rejected.path))
    }

    // MARK: - 4.1 Gate failure

    func testGateFailureLeavesPreExistingOutputUnchanged() throws {
        let baseline = try makeBaseline(texts: ["intro"])
        let output = makeTempURL(prefix: "ct-out")
        let originalOutputBytes = Data("this is the pre-existing output — must survive".utf8)
        try originalOutputBytes.write(to: output)
        defer { cleanup(baseline, output, rejectedURL(for: output)) }

        let manifest = Manifest(
            baseline: baseline.path, output: output.path,
            steps: [.insertParagraph(InsertParagraphStep(anchor: .afterText("intro"), content: "inserted"))]
        )

        // Simulates design.md's named risk: "The writer changes something
        // outside the allowed set in a case not yet seen" — corrupt
        // word/styles.xml directly in the freshly-written candidate.
        XCTAssertThrowsError(
            try CertifiedTransaction().apply(
                manifest: manifest, baselineURL: baseline, outputURL: output,
                certificateURL: nil, warnHandler: { _ in },
                testHookAfterCandidateWritten: { candidateURL in
                    let dir = try ZipHelper.unzip(candidateURL)
                    defer { ZipHelper.cleanup(dir) }
                    let stylesURL = dir.appendingPathComponent("word/styles.xml")
                    let text = try String(contentsOf: stylesURL, encoding: .utf8)
                    try Data(text.replacingOccurrences(of: "</w:styles>", with: "<!-- ct-gate-failure --></w:styles>").utf8)
                        .write(to: stylesURL)
                    try ZipHelper.zip(dir, to: candidateURL)
                },
                testHookBeforeBaselineRecheck: nil
            )
        ) { error in
            guard let certError = error as? CertificationError, case .gateFailed(let certificate) = certError else {
                XCTFail("Expected .gateFailed, got \(error)")
                return
            }
            XCTAssertEqual(certificate.status, .rejected)
            XCTAssertFalse(certificate.layer1.passed)
            XCTAssertTrue(certificate.layer1.violations.contains { violation in
                if case .unexpectedChange(let part, _, _, _) = violation { return part == "word/styles.xml" }
                return false
            }, "\(certificate.layer1.violations)")
            XCTAssertNotNil(certificate.rejectedCandidateURL)
        }

        // The pre-existing output must be byte-identical to what it was.
        XCTAssertEqual(try Data(contentsOf: output), originalOutputBytes)

        // The rejected candidate carries the corruption.
        let rejected = rejectedURL(for: output)
        XCTAssertTrue(FileManager.default.fileExists(atPath: rejected.path))
        let rejectedDir = try ZipHelper.unzip(rejected)
        defer { ZipHelper.cleanup(rejectedDir) }
        let rejectedStyles = try String(contentsOf: rejectedDir.appendingPathComponent("word/styles.xml"), encoding: .utf8)
        XCTAssertTrue(rejectedStyles.contains("ct-gate-failure"))
    }

    // MARK: - 4.2 Verify failure

    func testVerifyFailureDoesNotCreateOutput() throws {
        let baseline = try makeBaseline(texts: ["intro"])
        let output = makeTempURL(prefix: "ct-out")
        defer { cleanup(baseline, output, rejectedURL(for: output)) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))

        let manifest = Manifest(
            baseline: baseline.path, output: output.path,
            steps: [.insertParagraph(InsertParagraphStep(anchor: .afterText("intro"), content: "inserted"))],
            verify: VerifyAssertions(expectedParagraphsMin: 5)
        )

        XCTAssertThrowsError(
            try CertifiedTransaction().apply(manifest: manifest, baselineURL: baseline, outputURL: output)
        ) { error in
            guard let certError = error as? CertificationError, case .verifyFailed(let verifyError, let certificate) = certError else {
                XCTFail("Expected .verifyFailed, got \(error)")
                return
            }
            guard case .paragraphCountBelowMin(let expected, let observed) = verifyError else {
                XCTFail("Expected .paragraphCountBelowMin, got \(verifyError)")
                return
            }
            XCTAssertEqual(expected, 5)
            XCTAssertEqual(observed, 2)   // "intro" + the inserted paragraph
            XCTAssertEqual(certificate.status, .rejected)
            XCTAssertTrue(certificate.layer1.passed, "Layer 1 itself should still pass")
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    // MARK: - 4.3 Baseline changed before commit

    func testBaselineChangedBeforeCommitThrowsAndLeavesOutputUntouched() throws {
        let baseline = try makeBaseline(texts: ["intro"])
        let output = makeTempURL(prefix: "ct-out")
        defer { cleanup(baseline, output, rejectedURL(for: output)) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))

        let manifest = Manifest(
            baseline: baseline.path, output: output.path,
            steps: [.insertParagraph(InsertParagraphStep(anchor: .afterText("intro"), content: "inserted"))]
        )

        XCTAssertThrowsError(
            try CertifiedTransaction().apply(
                manifest: manifest, baselineURL: baseline, outputURL: output,
                certificateURL: nil, warnHandler: { _ in },
                testHookAfterCandidateWritten: nil,
                testHookBeforeBaselineRecheck: {
                    // Rewrite the baseline's bytes in place, after the gate
                    // already ran against the original bytes.
                    try Data("baseline changed underneath the transaction".utf8).write(to: baseline)
                }
            )
        ) { error in
            guard let certError = error as? CertificationError, case .baselineChanged(let certificate) = certError else {
                XCTFail("Expected .baselineChanged, got \(error)")
                return
            }
            XCTAssertEqual(certificate.status, .rejected)
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }

    // MARK: - Intent unavailable (no candidate exists)

    func testIntentUnavailableCreatesNoCandidateOrOutput() throws {
        // `MutationIntent.derive(from:)` cannot actually throw
        // `.intentUnavailable` through the real 12-case `Step` enum today
        // (every case it treats as runtime-functional already has a table
        // row — see MutationIntentTests). The `deriveIntent` seam injects a
        // failing derivation so this test can check the surrounding
        // contract for real: when intent derivation fails, `Executor` is
        // never invoked, so no candidate file is ever created, and the
        // output path — which did not exist beforehand — stays absent.
        let baseline = try makeBaseline(texts: ["intro"])
        let output = makeTempURL(prefix: "ct-out")
        defer { cleanup(baseline, output, rejectedURL(for: output)) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))

        let manifest = Manifest(
            baseline: baseline.path, output: output.path,
            steps: [.insertParagraph(InsertParagraphStep(anchor: .afterText("intro"), content: "inserted"))]
        )

        XCTAssertThrowsError(
            try CertifiedTransaction().apply(
                manifest: manifest, baselineURL: baseline, outputURL: output,
                certificateURL: nil, warnHandler: { _ in },
                testHookAfterCandidateWritten: nil, testHookBeforeBaselineRecheck: nil,
                deriveIntent: { _ in throw CertificationError.intentUnavailable(stepType: "insert_table") }
            )
        ) { error in
            guard let certError = error as? CertificationError, case .intentUnavailable(let stepType) = certError else {
                XCTFail("Expected .intentUnavailable, got \(error)")
                return
            }
            XCTAssertEqual(stepType, "insert_table")
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        // No stray candidate-<uuid>.docx either.
        let dirEntries = try FileManager.default.contentsOfDirectory(atPath: output.deletingLastPathComponent().path)
        let stem = output.deletingPathExtension().lastPathComponent
        XCTAssertTrue(dirEntries.filter { $0.hasPrefix(stem) }.isEmpty)
    }
}
