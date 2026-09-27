// SetBoldEndToEndTests — PsychQuant/macdoc#232.
//
// End-to-end coverage through the real stack a `macdoc docx apply` run goes
// through: Manifest → Executor → CertifiedTransaction, against a document
// with an "intro" paragraph whose text carries the target substring in the
// middle (matching the issue's reproduction shape) plus an untouched second
// paragraph.
//
// Covers spec.md/design.md's "Certified transaction commits only after
// every gate passes" for the specific `set_bold` case the issue reported as
// broken end to end:
// - success: only the matched substring's run becomes bold, the rest of
//   the paragraph's text is untouched, every OTHER document part is
//   byte-identical to the baseline, and the certificate reports
//   `.layer1Verified`.
// - failure (substring not present in the anchor paragraph): the error
//   surfaces ooxml-swift's specific reason (not the generic
//   "ReducerError error 1" the issue reported), and the output path is
//   left exactly as it was — no candidate is ever committed (#137's
//   transactional semantics).

import XCTest
@testable import DocxWorkflowLib

final class SetBoldEndToEndTests: XCTestCase {

    // MARK: - Fixtures

    private func makeTempURL(prefix: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString).docx")
    }

    private func makeBaseline(texts: [String]) throws -> URL {
        var doc = WordDocument()
        for text in texts {
            doc.appendParagraph(Paragraph(text: text))
        }
        let url = makeTempURL(prefix: "setbold-baseline")
        try DocxWriter.writeData(doc).write(to: url)
        return url
    }

    private func partBytes(of docx: URL) throws -> [String: Data] {
        let dir = try ZipHelper.unzip(docx)
        defer { ZipHelper.cleanup(dir) }
        var parts: [String: Data] = [:]
        let files = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey])
        while let file = files?.nextObject() as? URL {
            guard (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            let name = file.standardizedFileURL.path
                .replacingOccurrences(of: dir.standardizedFileURL.path + "/", with: "")
            parts[name] = try Data(contentsOf: file)
        }
        return parts
    }

    /// Finds the first top-level body paragraph whose flattened text
    /// contains `needle`, and returns its raw `<w:r>` children so the test
    /// can inspect run-level bold state directly — the tree-backed
    /// `Paragraph.runs` accessor is a Phase 1 stub that does not carry
    /// `<w:rPr>` through (see `Paragraph.swift`'s "Phase 1 stub" note), so
    /// bold state has to be read from the XML node tree, the same way
    /// ooxml-swift's own `SetBoldInRangeTests` does.
    private func runs(inParagraphContaining needle: String, of doc: WordDocument) throws -> [XmlNode] {
        for child in doc.body.children {
            guard case .paragraph(let paragraph) = child, paragraph.text.contains(needle) else { continue }
            guard let node = paragraph.xmlNode else {
                throw XCTSkip("paragraph is not tree-backed")
            }
            return node.children.filter { $0.kind == .element && $0.localName == "r" }
        }
        XCTFail("no paragraph containing \(needle) found")
        return []
    }

    private func runText(_ run: XmlNode) -> String {
        run.children
            .filter { $0.kind == .element && $0.localName == "t" }
            .flatMap { $0.children.filter { $0.kind == .text }.map(\.textContent) }
            .joined()
    }

    private func isBold(_ run: XmlNode) -> Bool {
        guard let rPr = run.children.first(where: { $0.kind == .element && $0.localName == "rPr" })
        else { return false }
        return rPr.children.contains { $0.kind == .element && $0.localName == "b" }
    }

    // MARK: - Success

    func testSetBoldBoldsOnlyMatchedSubstringAndPreservesEverythingElse() throws {
        let baseline = try makeBaseline(texts: [
            "intro alpha TARGET beta gamma", "second paragraph untouched",
        ])
        let output = makeTempURL(prefix: "setbold-out")
        defer {
            try? FileManager.default.removeItem(at: baseline)
            try? FileManager.default.removeItem(at: output)
        }

        let manifest = Manifest(
            baseline: baseline.path,
            output: output.path,
            steps: [.setBold(SetBoldStep(anchor: .afterText("intro"), substring: "TARGET"))]
        )

        // Explicit do/catch (rather than a plain `try`) so a failure here
        // reports the real thrown error's description — swift-corelibs-xctest
        // does not reliably surface a `throws` test function's propagated
        // error for non-NSError Swift error types.
        let certificate: CertificationCertificate
        do {
            certificate = try CertifiedTransaction().apply(
                manifest: manifest, baselineURL: baseline, outputURL: output)
        } catch {
            XCTFail("CertifiedTransaction().apply threw unexpectedly: \(error)")
            return
        }

        XCTAssertEqual(certificate.status, .layer1Verified)
        XCTAssertTrue(certificate.layer1.passed)
        XCTAssertEqual(certificate.changedParts, ["word/document.xml"])

        // Every other part is byte-identical — only word/document.xml changed.
        let before = try partBytes(of: baseline)
        let after = try partBytes(of: output)
        XCTAssertEqual(Set(after.keys), Set(before.keys))
        for (name, bytes) in before where name != "word/document.xml" {
            XCTAssertEqual(after[name], bytes, "\(name) changed although set_bold only edits word/document.xml")
        }

        let outputDoc = try DocxReader.read(from: output, wireTreeBackedViews: true)

        // The anchor paragraph's text is unchanged — only formatting moved.
        let introRuns = try runs(inParagraphContaining: "intro", of: outputDoc)
        XCTAssertEqual(introRuns.map(runText).joined(), "intro alpha TARGET beta gamma",
                       "set_bold must not change any character of the paragraph's text")
        // Exactly the "TARGET" run fragment is bold; everything around it is not.
        for run in introRuns {
            let text = runText(run)
            if text == "TARGET" {
                XCTAssertTrue(isBold(run), "the matched substring's run must be bold")
            } else {
                XCTAssertFalse(isBold(run), "\(String(reflecting: text)) must NOT be bold")
            }
        }
        XCTAssertTrue(introRuns.contains { runText($0) == "TARGET" }, "run split must isolate the substring into its own run")

        // The split leaves "intro alpha " and " beta gamma" with edge
        // whitespace; without xml:space="preserve" Word drops it and the
        // words run together ("alphaTARGETbeta").
        for run in introRuns {
            let text = runText(run)
            guard text.first == " " || text.last == " " else { continue }
            let t = run.children.first { $0.kind == .element && $0.localName == "t" }
            XCTAssertEqual(t?.attributeValue(prefix: "xml", localName: "space"), "preserve",
                           "\(String(reflecting: text)) has edge whitespace but no xml:space=\"preserve\"")
        }

        // The untouched second paragraph is untouched.
        let secondRuns = try runs(inParagraphContaining: "second paragraph", of: outputDoc)
        XCTAssertEqual(secondRuns.map(runText).joined(), "second paragraph untouched")
        XCTAssertTrue(secondRuns.allSatisfy { !isBold($0) })
    }

    // MARK: - Failure: substring not found

    func testSetBoldSubstringNotFoundSurfacesReasonAndLeavesOutputUnwritten() throws {
        let baseline = try makeBaseline(texts: ["intro alpha beta gamma"])
        let output = makeTempURL(prefix: "setbold-notfound-out")
        defer {
            try? FileManager.default.removeItem(at: baseline)
            try? FileManager.default.removeItem(at: output)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))

        let manifest = Manifest(
            baseline: baseline.path,
            output: output.path,
            steps: [.setBold(SetBoldStep(anchor: .afterText("intro"), substring: "NOPE"))]
        )

        XCTAssertThrowsError(
            try CertifiedTransaction().apply(manifest: manifest, baselineURL: baseline, outputURL: output)
        ) { error in
            guard case EditError.operationLogFailure(let underlying) = error else {
                XCTFail("Expected EditError.operationLogFailure, got \(error)")
                return
            }
            // The issue's own reproduction: the reason used to collapse to
            // "OOXMLSwift.ReducerError error 1." (generic NSError bridging,
            // no case payload). ooxml-swift 3.16.0's `ReducerError:
            // LocalizedError` conformance means the real reason survives.
            XCTAssertFalse(underlying.contains("ReducerError error"),
                           "must not regress to the generic NSError bridging message: \(underlying)")
            XCTAssertTrue(underlying.contains("NOPE"), "reason should name the substring that was not found: \(underlying)")
            XCTAssertTrue(underlying.contains("not found"), "reason should say why: \(underlying)")
        }

        // #137 transactional semantics: no candidate ever reached the point
        // of being committed, so the output path was never created.
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        // No leftover candidate/rejected file beside the (nonexistent) output.
        let dirEntries = try FileManager.default.contentsOfDirectory(
            atPath: output.deletingLastPathComponent().path)
        let stem = output.deletingPathExtension().lastPathComponent
        let leftovers = dirEntries.filter { $0.hasPrefix(stem) }
        XCTAssertTrue(leftovers.isEmpty, "leftover files: \(leftovers)")
    }
}
