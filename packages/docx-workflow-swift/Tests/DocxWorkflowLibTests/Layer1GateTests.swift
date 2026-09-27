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

    // MARK: - R2 review LOW items (review-c137.md L2, L3, L4)

    /// L2: OPC (ECMA-376 Part 2, the Content Types stream's `Default` element) content-type extension matching is
    /// case-insensitive. Only the `Default`'s own `Extension` attribute
    /// case changes here — the two `.rels` parts on disk are unaffected
    /// and rely entirely on this one `Default` (no per-part `Override`).
    func testContentTypeDefaultExtensionMatchIsCaseInsensitive() throws {
        let baseline = try makeBaseline(texts: ["intro"])
        let candidate = try makeCandidate(from: baseline) { dir in
            try self.replace(
                #"<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>"#,
                with: #"<Default Extension="RELS" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>"#,
                in: dir.appendingPathComponent("[Content_Types].xml"))
        }
        defer { cleanup(baseline, candidate) }

        let intent = MutationIntent(allowedParts: ["word/document.xml", "[Content_Types].xml"], stepSummary: ["insert_paragraph"])
        let result = Layer1Gate.evaluate(baseline: baseline, candidate: candidate, intent: intent)

        XCTAssertFalse(result.violations.contains { violation in
            if case .missingContentType = violation { return true }
            return false
        }, "\(result.violations)")
    }

    /// L3: a relationship `Target` may be percent-encoded (e.g. a space as
    /// `%20`); it must be decoded before resolving against the package's
    /// actual part names.
    func testRelationshipTargetIsPercentDecodedBeforeResolution() throws {
        let baseline = try makeBaseline(texts: ["intro"])
        let candidate = try makeCandidate(from: baseline) { dir in
            let media = dir.appendingPathComponent("word/media/my file.png")
            try FileManager.default.createDirectory(at: media.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("not a real png, just bytes".utf8).write(to: media)
            try self.insert(
                #"<Relationship Id="rIdSpace" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/my%20file.png"/>"#,
                before: "</Relationships>", in: dir.appendingPathComponent("word/_rels/document.xml.rels"))
        }
        defer { cleanup(baseline, candidate) }

        let intent = MutationIntent(
            allowedParts: ["word/document.xml", "word/_rels/document.xml.rels", "word/media/my file.png"],
            stepSummary: ["insert_paragraph"]
        )
        let result = Layer1Gate.evaluate(baseline: baseline, candidate: candidate, intent: intent)

        XCTAssertFalse(result.violations.contains { violation in
            if case .danglingRelationship(_, let target) = violation { return target == "media/my%20file.png" }
            return false
        }, "\(result.violations)")
    }

    /// L4: a relative `Target` using `..` must resolve against the owner
    /// part's directory, not just its own — a chart's rels (owner
    /// directory `word/charts`) referencing shared media one level up
    /// (`word/media/`) is the common real-world shape for this.
    func testDotDotRelativeTargetResolvesToSiblingDirectory() throws {
        let baseline = try makeBaseline(texts: ["intro"])
        let candidate = try makeCandidate(from: baseline) { dir in
            let media = dir.appendingPathComponent("word/media/image1.png")
            try FileManager.default.createDirectory(at: media.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("fake image bytes".utf8).write(to: media)

            let chartRels = dir.appendingPathComponent("word/charts/_rels/chart1.xml.rels")
            try FileManager.default.createDirectory(at: chartRels.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(Self.chartRelsXML.utf8).write(to: chartRels)
        }
        defer { cleanup(baseline, candidate) }

        let intent = MutationIntent(allowedParts: ["word/document.xml"], stepSummary: ["insert_paragraph"])
        let result = Layer1Gate.evaluate(baseline: baseline, candidate: candidate, intent: intent)

        XCTAssertFalse(result.violations.contains { violation in
            if case .danglingRelationship(let source, _) = violation { return source == "word/charts/_rels/chart1.xml.rels" }
            return false
        }, "\(result.violations)")
    }

    /// L4 negative companion: proves the `..` traversal in the test above
    /// is actually exercised — remove the sibling file and the SAME
    /// relationship must now be reported dangling, naming the raw
    /// (un-resolved) `Target` string.
    func testDotDotRelativeTargetIsDanglingWhenTheSiblingFileIsAbsent() throws {
        let baseline = try makeBaseline(texts: ["intro"])
        let candidate = try makeCandidate(from: baseline) { dir in
            // No word/media/image1.png this time.
            let chartRels = dir.appendingPathComponent("word/charts/_rels/chart1.xml.rels")
            try FileManager.default.createDirectory(at: chartRels.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(Self.chartRelsXML.utf8).write(to: chartRels)
        }
        defer { cleanup(baseline, candidate) }

        let intent = MutationIntent(allowedParts: ["word/document.xml"], stepSummary: ["insert_paragraph"])
        let result = Layer1Gate.evaluate(baseline: baseline, candidate: candidate, intent: intent)

        XCTAssertTrue(
            result.violations.contains(.danglingRelationship(source: "word/charts/_rels/chart1.xml.rels", target: "../media/image1.png")),
            "\(result.violations)"
        )
    }

    private static let chartRelsXML = #"""
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rIdChartImage" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/image1.png"/></Relationships>
    """#

    // MARK: - R3 review LOW items (review-c137-r2.md Finding C, Finding D)

    /// Finding C: R2 made the Content Types stream's `Default` element's
    /// `Extension` attribute comparison case-insensitive but left the
    /// `Override` element's `PartName` attribute comparison (a different
    /// lookup in the same function) case-sensitive, even though OPC's part
    /// name comparison is the same ASCII case-insensitive rule either way.
    /// The generic `Default Extension="xml"` fallback masks this in every
    /// fixture that carries one, so this test removes it first — exactly
    /// how the review's own probe exposed the gap.
    func testContentTypeOverridePartNameMatchIsCaseInsensitive() throws {
        let baseline = try makeBaseline(texts: ["intro"])
        let candidate = try makeCandidate(from: baseline) { dir in
            try self.replace(
                #"<Default Extension="xml" ContentType="application/xml"/>"#,
                with: "",
                in: dir.appendingPathComponent("[Content_Types].xml"))
            try self.replace(
                #"<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>"#,
                with: #"<Override PartName="/Word/Styles.XML" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>"#,
                in: dir.appendingPathComponent("[Content_Types].xml"))
        }
        defer { cleanup(baseline, candidate) }

        let intent = MutationIntent(allowedParts: ["word/document.xml", "[Content_Types].xml"], stepSummary: ["insert_paragraph"])
        let result = Layer1Gate.evaluate(baseline: baseline, candidate: candidate, intent: intent)

        XCTAssertFalse(result.violations.contains { violation in
            if case .missingContentType(let part) = violation { return part == "word/styles.xml" }
            return false
        }, "\(result.violations)")
    }

    /// Finding D: `testContentTypeDefaultExtensionMatchIsCaseInsensitive`
    /// only changed the `Default` element's own `Extension` attribute's
    /// case — every fixture part's actual on-disk extension is already
    /// lowercase, so the READ side's `.lowercased()` call in
    /// `hasContentType` was never actually exercised by it (removing that
    /// one line left all 72 tests passing). This test adds a part whose
    /// own extension is uppercase, so the query side's case must be folded
    /// too, not just the stored `Default`'s.
    func testContentTypeDefaultExtensionMatchIsCaseInsensitiveOnTheQuerySide() throws {
        let baseline = try makeBaseline(texts: ["intro"])
        let candidate = try makeCandidate(from: baseline) { dir in
            let extra = dir.appendingPathComponent("word/extra.XML")
            try Data(#"<?xml version="1.0" encoding="UTF-8"?><root/>"#.utf8).write(to: extra)
        }
        defer { cleanup(baseline, candidate) }

        let intent = MutationIntent(allowedParts: ["word/document.xml"], stepSummary: ["insert_paragraph"])
        let result = Layer1Gate.evaluate(baseline: baseline, candidate: candidate, intent: intent)

        XCTAssertFalse(result.violations.contains { violation in
            if case .missingContentType(let part) = violation { return part == "word/extra.XML" }
            return false
        }, "\(result.violations)")
    }

    /// R4 review Finding G (LOW, test-gap): `testContentTypeOverridePartNameMatchIsCaseInsensitive`
    /// only changed the `Override` element's own `PartName` attribute case
    /// (`/Word/Styles.XML`) — the actual on-disk part it was matched
    /// against (`word/styles.xml`, from the real ZIP entry) is already
    /// lowercase, so `hasContentType`'s READ-side `.lowercased()` call on
    /// the Override branch was never actually exercised by it (removing
    /// just that line left all 15 `Layer1GateTests` cases passing — the
    /// review's own mutation probe). This is the Override-branch
    /// counterpart to `testContentTypeDefaultExtensionMatchIsCaseInsensitiveOnTheQuerySide`
    /// above: the part added here has an uppercase on-disk name
    /// (`word/Extra.XML`), so the query side's case must be folded too, not
    /// just the stored `Override`'s. The generic `Default Extension="xml"`
    /// fallback is removed so only the `Override` branch can satisfy the
    /// lookup — otherwise the Default branch (already covered by the test
    /// above) would silently rescue a broken Override branch and this test
    /// would pass for the wrong reason.
    func testContentTypeOverridePartNameMatchIsCaseInsensitiveOnTheQuerySide() throws {
        let baseline = try makeBaseline(texts: ["intro"])
        let candidate = try makeCandidate(from: baseline) { dir in
            try self.replace(
                #"<Default Extension="xml" ContentType="application/xml"/>"#,
                with: "",
                in: dir.appendingPathComponent("[Content_Types].xml"))
            let extra = dir.appendingPathComponent("word/Extra.XML")
            try Data(#"<?xml version="1.0" encoding="UTF-8"?><root/>"#.utf8).write(to: extra)
            try self.insert(
                #"<Override PartName="/word/extra.xml" ContentType="application/xml"/>"#,
                before: "</Types>", in: dir.appendingPathComponent("[Content_Types].xml"))
        }
        defer { cleanup(baseline, candidate) }

        let intent = MutationIntent(allowedParts: ["word/document.xml"], stepSummary: ["insert_paragraph"])
        let result = Layer1Gate.evaluate(baseline: baseline, candidate: candidate, intent: intent)

        XCTAssertFalse(result.violations.contains { violation in
            if case .missingContentType(let part) = violation { return part == "word/Extra.XML" }
            return false
        }, "\(result.violations)")
    }
}
