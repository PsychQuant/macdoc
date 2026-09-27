// Layer1GateTests — macdoc#137 Layer 1 (docx-mutation-certification-layer1).
//
// Covers spec.md Requirement "Layer 1 gate proves package and byte
// preservation": tasks 2.1 (part-set + byte checks) and 2.2
// (package-integrity checks), each against a synthetic package built by
// mutating a fresh scratch-mode .docx.

import XCTest
import DocxWorkflowLib

final class Layer1GateTests: XCTestCase {

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
        let url = makeTempURL(prefix: "l1-baseline")
        try DocxWriter.writeData(doc).write(to: url)
        return url
    }

    /// A baseline that also carries a theme part reached through a
    /// relationship — scratch mode never emits theme itself, so the fixture
    /// injects one directly into the archive, mirroring
    /// `ExecutorTests.makeBaselineWithUnmodeledParts` (macdoc#231).
    private func makeBaselineWithTheme(texts: [String]) throws -> URL {
        let plain = try makeBaseline(texts: texts)
        defer { try? FileManager.default.removeItem(at: plain) }
        let dir = try ZipHelper.unzip(plain)
        defer { ZipHelper.cleanup(dir) }

        let theme = dir.appendingPathComponent("word/theme/theme1.xml")
        try FileManager.default.createDirectory(
            at: theme.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?><a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="Layer1"><a:themeElements/></a:theme>"#.utf8)
            .write(to: theme)

        try insert(
            #"<Relationship Id="rIdLayer1Theme" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="theme/theme1.xml"/>"#,
            before: "</Relationships>", in: dir.appendingPathComponent("word/_rels/document.xml.rels"))
        try insert(
            #"<Override PartName="/word/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>"#,
            before: "</Types>", in: dir.appendingPathComponent("[Content_Types].xml"))

        let url = makeTempURL(prefix: "l1-baseline-theme")
        try ZipHelper.zip(dir, to: url)
        return url
    }

    private func insert(_ snippet: String, before closing: String, in url: URL) throws {
        let text = try String(contentsOf: url, encoding: .utf8)
        guard let range = text.range(of: closing, options: .backwards) else {
            throw NSError(domain: "Layer1GateTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "'\(closing)' not found in \(url.lastPathComponent)"])
        }
        try Data(text.replacingCharacters(in: range, with: snippet + closing).utf8).write(to: url)
    }

    private func replace(_ old: String, with new: String, in url: URL) throws {
        let text = try String(contentsOf: url, encoding: .utf8)
        guard text.contains(old) else {
            throw NSError(domain: "Layer1GateTests", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "'\(old)' not found in \(url.lastPathComponent)"])
        }
        try Data(text.replacingOccurrences(of: old, with: new).utf8).write(to: url)
    }

    /// Unzips `baseline`, lets `mutate` edit the extracted tree, then
    /// re-zips into a fresh candidate URL. The baseline file is untouched.
    private func makeCandidate(from baseline: URL, prefix: String = "l1-candidate", mutate: (URL) throws -> Void) throws -> URL {
        let dir = try ZipHelper.unzip(baseline)
        defer { ZipHelper.cleanup(dir) }
        try mutate(dir)
        let url = makeTempURL(prefix: prefix)
        try ZipHelper.zip(dir, to: url)
        return url
    }

    private func cleanup(_ urls: URL...) {
        for url in urls { try? FileManager.default.removeItem(at: url) }
    }

    // MARK: - 2.1 Part-set and byte checks

    /// Scenario: Step touches only its allowed part.
    func testCleanPassReportsOnlyDocumentXMLChanged() throws {
        let baseline = try makeBaselineWithTheme(texts: ["intro", "body"])
        let candidate = try makeCandidate(from: baseline) { dir in
            try self.replace("intro", with: "intro-changed", in: dir.appendingPathComponent("word/document.xml"))
        }
        defer { cleanup(baseline, candidate) }

        let intent = MutationIntent(allowedParts: ["word/document.xml"], stepSummary: ["insert_paragraph"])
        let result = Layer1Gate.evaluate(baseline: baseline, candidate: candidate, intent: intent)

        XCTAssertTrue(result.passed, "violations: \(result.violations)")
        XCTAssertEqual(result.changedParts, ["word/document.xml"])
        XCTAssertTrue(result.violations.isEmpty)
    }

    /// Scenario: A dropped part is reported.
    func testDroppedThemePartReportsPartRemoved() throws {
        let baseline = try makeBaselineWithTheme(texts: ["intro"])
        let candidate = try makeCandidate(from: baseline) { dir in
            try FileManager.default.removeItem(at: dir.appendingPathComponent("word/theme/theme1.xml"))
        }
        defer { cleanup(baseline, candidate) }

        let intent = MutationIntent(allowedParts: ["word/document.xml"], stepSummary: ["insert_paragraph"])
        let result = Layer1Gate.evaluate(baseline: baseline, candidate: candidate, intent: intent)

        XCTAssertFalse(result.passed)
        XCTAssertTrue(result.violations.contains(.partRemoved("word/theme/theme1.xml")), "\(result.violations)")
    }

    /// Companion coverage for the same Requirement's "part set equality"
    /// clause: an extra part is reported as `partAdded`.
    func testExtraPartReportsPartAdded() throws {
        let baseline = try makeBaseline(texts: ["intro"])
        let candidate = try makeCandidate(from: baseline) { dir in
            try Data("not an OOXML part".utf8).write(to: dir.appendingPathComponent("word/extra.bin"))
        }
        defer { cleanup(baseline, candidate) }

        let intent = MutationIntent(allowedParts: ["word/document.xml"], stepSummary: ["insert_paragraph"])
        let result = Layer1Gate.evaluate(baseline: baseline, candidate: candidate, intent: intent)

        XCTAssertFalse(result.passed)
        XCTAssertTrue(result.violations.contains(.partAdded("word/extra.bin")), "\(result.violations)")
    }

    /// Scenario: An unallowed change is reported with its offset.
    func testUnallowedStylesChangeReportsUnexpectedChangeWithOffset() throws {
        let baseline = try makeBaseline(texts: ["intro"])
        let stylesPath = baseline // placeholder to keep types explicit below
        _ = stylesPath
        let baselineStylesBytes = try Data(contentsOf: try ZipHelper.unzip(baseline).appendingPathComponent("word/styles.xml"))

        let candidate = try makeCandidate(from: baseline) { dir in
            try self.replace("</w:styles>", with: "<!-- l1 --></w:styles>", in: dir.appendingPathComponent("word/styles.xml"))
        }
        defer { cleanup(baseline, candidate) }

        let intent = MutationIntent(allowedParts: ["word/document.xml"], stepSummary: ["insert_paragraph"])
        let result = Layer1Gate.evaluate(baseline: baseline, candidate: candidate, intent: intent)

        XCTAssertFalse(result.passed)
        guard let violation = result.violations.first(where: {
            if case .unexpectedChange(let part, _, _, _) = $0 { return part == "word/styles.xml" }
            return false
        }) else {
            XCTFail("Expected unexpectedChange for word/styles.xml, got \(result.violations)")
            return
        }
        guard case .unexpectedChange(_, let baselineSize, let candidateSize, let offset) = violation else {
            XCTFail("unreachable")
            return
        }
        XCTAssertEqual(baselineSize, baselineStylesBytes.count)
        XCTAssertGreaterThan(candidateSize, baselineSize)
        XCTAssertGreaterThan(offset, 0)
        XCTAssertLessThanOrEqual(offset, baselineSize)
        XCTAssertTrue(result.changedParts.contains("word/styles.xml"))
    }

    // MARK: - 2.2 Package-integrity checks

    /// The candidate must re-open through `DocxReader`.
    func testMissingDocumentXMLReportsUnreadablePackage() throws {
        let baseline = try makeBaseline(texts: ["intro"])
        let candidate = try makeCandidate(from: baseline) { dir in
            try FileManager.default.removeItem(at: dir.appendingPathComponent("word/document.xml"))
        }
        defer { cleanup(baseline, candidate) }

        let intent = MutationIntent(allowedParts: ["word/document.xml"], stepSummary: ["insert_paragraph"])
        let result = Layer1Gate.evaluate(baseline: baseline, candidate: candidate, intent: intent)

        XCTAssertFalse(result.passed)
        let sawUnreadable = result.violations.contains { violation in
            if case .unreadablePackage = violation { return true }
            return false
        }
        XCTAssertTrue(sawUnreadable, "\(result.violations)")
    }

    /// Every `.xml`/`.rels` part must be well-formed. `word/fontTable.xml`
    /// is not parsed by `DocxReader` at all, so corrupting it isolates this
    /// check from `unreadablePackage`.
    func testCorruptFontTableReportsMalformedXML() throws {
        let baseline = try makeBaseline(texts: ["intro"])
        let candidate = try makeCandidate(from: baseline) { dir in
            try self.replace("</w:fonts>", with: "", in: dir.appendingPathComponent("word/fontTable.xml"))
        }
        defer { cleanup(baseline, candidate) }

        let intent = MutationIntent(allowedParts: ["word/document.xml"], stepSummary: ["insert_paragraph"])
        let result = Layer1Gate.evaluate(baseline: baseline, candidate: candidate, intent: intent)

        XCTAssertFalse(result.passed)
        XCTAssertTrue(result.violations.contains { violation in
            if case .malformedXML(let part, _) = violation { return part == "word/fontTable.xml" }
            return false
        }, "\(result.violations)")
        // Isolation: DocxReader itself tolerates the corrupted fontTable.
        XCTAssertFalse(result.violations.contains { violation in
            if case .unreadablePackage = violation { return true }
            return false
        })
    }

    /// `[Content_Types].xml` must assign a content type to every part.
    /// Removing the `rels` `Default` leaves both `.rels` parts uncovered
    /// (they carry no `Override`).
    func testMissingRelsDefaultReportsMissingContentType() throws {
        let baseline = try makeBaseline(texts: ["intro"])
        let candidate = try makeCandidate(from: baseline) { dir in
            try self.replace(
                #"<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>"#,
                with: "",
                in: dir.appendingPathComponent("[Content_Types].xml"))
        }
        defer { cleanup(baseline, candidate) }

        let intent = MutationIntent(allowedParts: ["word/document.xml", "[Content_Types].xml"], stepSummary: ["insert_paragraph"])
        let result = Layer1Gate.evaluate(baseline: baseline, candidate: candidate, intent: intent)

        XCTAssertFalse(result.passed)
        XCTAssertTrue(result.violations.contains(.missingContentType(part: "word/_rels/document.xml.rels")), "\(result.violations)")
    }

    /// Every internal relationship target must resolve to an existing part.
    func testGhostRelationshipReportsDanglingRelationship() throws {
        let baseline = try makeBaseline(texts: ["intro"])
        let candidate = try makeCandidate(from: baseline) { dir in
            try self.insert(
                #"<Relationship Id="rIdGhost" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="theme/nonexistent.xml"/>"#,
                before: "</Relationships>", in: dir.appendingPathComponent("word/_rels/document.xml.rels"))
        }
        defer { cleanup(baseline, candidate) }

        let intent = MutationIntent(allowedParts: ["word/document.xml", "word/_rels/document.xml.rels"], stepSummary: ["wrap_link"])
        let result = Layer1Gate.evaluate(baseline: baseline, candidate: candidate, intent: intent)

        XCTAssertFalse(result.passed)
        XCTAssertTrue(result.violations.contains(.danglingRelationship(source: "word/_rels/document.xml.rels", target: "theme/nonexistent.xml")), "\(result.violations)")
    }

    /// An external relationship target (e.g. a hyperlink URL) must NOT be
    /// treated as dangling — `wrap_link` produces exactly this shape.
    func testExternalRelationshipTargetIsNotDangling() throws {
        let baseline = try makeBaseline(texts: ["intro"])
        let candidate = try makeCandidate(from: baseline) { dir in
            try self.insert(
                #"<Relationship Id="rIdHyperlink" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink" Target="https://example.com" TargetMode="External"/>"#,
                before: "</Relationships>", in: dir.appendingPathComponent("word/_rels/document.xml.rels"))
        }
        defer { cleanup(baseline, candidate) }

        let intent = MutationIntent(allowedParts: ["word/document.xml", "word/_rels/document.xml.rels"], stepSummary: ["wrap_link"])
        let result = Layer1Gate.evaluate(baseline: baseline, candidate: candidate, intent: intent)

        XCTAssertFalse(result.violations.contains { violation in
            if case .danglingRelationship = violation { return true }
            return false
        }, "\(result.violations)")
    }
}
