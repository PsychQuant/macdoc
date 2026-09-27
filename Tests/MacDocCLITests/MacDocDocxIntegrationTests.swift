// MacDocDocxIntegrationTests — §7.5 of macdoc-docx-workflow-cli.
//
// End-to-end tests that exercise the built `macdoc` binary via Process
// against fixture manifests + baselines. Per the test-files/ convention
// (gitignored — local fixtures only), tests XCTSkip cleanly when fixtures
// are absent, matching the precedent from NoteHTMLConvertTests.

import XCTest
import Darwin
import Foundation
import OOXMLSwift

final class MacDocDocxIntegrationTests: XCTestCase {

    /// A synthetic baseline built directly through the authoring API — no
    /// `test-files/` fixture needed, so the two `--certificate` tests below
    /// run in any clone/CI, not only where a local `.docx` happens to sit.
    private func makeSyntheticBaseline(texts: [String]) throws -> URL {
        var doc = WordDocument()
        for text in texts {
            doc.appendParagraph(Paragraph(text: text))
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("docx-cli-baseline-\(UUID().uuidString).docx")
        try DocxWriter.writeData(doc).write(to: url)
        return url
    }

    // MARK: - Binary resolution

    private var macdocBinary: URL? {
        // Locate the built `macdoc` binary in the standard SPM debug output.
        // Tests run from the repo root; the binary lives at .build/debug/macdoc.
        //
        // Resolution logic lives in `DocxIntegrationBinaryResolver`
        // (PsychQuant/macdoc#192) so it has its own dedicated unit test
        // coverage; see that type's doc comment for why it deliberately does
        // NOT read `MACDOC_TEST_BINARY`.
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        return DocxIntegrationBinaryResolver.resolve(
            cwd: cwd,
            environment: ProcessInfo.processInfo.environment,
            fileExists: FileManager.default.fileExists(atPath:)
        )
    }

    /// Optional baseline fixture under test-files/ (gitignored). Tests that
    /// need a `.docx` baseline XCTSkip when no fixture is available.
    private func fixtureBaseline() -> URL? {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let testFiles = cwd.appendingPathComponent("test-files")
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: testFiles.path) else {
            return nil
        }
        if let docx = entries.first(where: { $0.hasSuffix(".docx") }) {
            return testFiles.appendingPathComponent(docx)
        }
        return nil
    }

    // MARK: - Help integration

    func testHelpListsFourSubcommands() throws {
        // Spec: "macdoc docx --help lists four inner subcommands"
        guard let binary = macdocBinary else {
            throw XCTSkip("Built macdoc binary not found at .build/debug/macdoc")
        }
        let output = try runProcess(binary: binary, args: ["docx", "--help"])
        XCTAssertTrue(output.contains("apply"), "Expected `apply` in docx --help")
        XCTAssertTrue(output.contains("plan"), "Expected `plan` in docx --help")
        XCTAssertTrue(output.contains("verify"), "Expected `verify` in docx --help")
        XCTAssertTrue(output.contains("diff"), "Expected `diff` in docx --help")
    }

    // MARK: - apply integration (fixture-dependent)

    func testApplyWritesOutputAndExitsZero() throws {
        // Spec: "apply with valid manifest writes output and exits 0"
        guard let binary = macdocBinary else {
            throw XCTSkip("Built macdoc binary not found")
        }
        guard let baseline = fixtureBaseline() else {
            throw XCTSkip("No .docx fixture under test-files/")
        }

        let temp = FileManager.default.temporaryDirectory
        let manifestURL = temp.appendingPathComponent("manifest-\(UUID().uuidString).json")
        let outputURL = temp.appendingPathComponent("out-\(UUID().uuidString).docx")
        defer {
            try? FileManager.default.removeItem(at: manifestURL)
            try? FileManager.default.removeItem(at: outputURL)
        }

        // Minimal manifest: one pending insert_image step (warns + skips,
        // produces a valid output bytes-equivalent to baseline).
        let json = #"""
        {
          "baseline": "\#(baseline.path)",
          "output": "\#(outputURL.path)",
          "steps": [
            { "type": "insert_image", "anchor": { "paragraph_index": 0 }, "path": "ignored.png" }
          ]
        }
        """#
        try Data(json.utf8).write(to: manifestURL)

        let (stdout, stderr, exitCode) = try runProcessFull(
            binary: binary,
            args: ["docx", "apply", manifestURL.path, "--input", baseline.path, "--output", outputURL.path]
        )

        XCTAssertEqual(exitCode, 0, "Expected exit 0, got \(exitCode). stdout: \(stdout) stderr: \(stderr)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path),
            "Output file should exist after apply")

        // Output should be a valid OOXML container (ZIP signature).
        let bytes = try Data(contentsOf: outputURL)
        XCTAssertGreaterThan(bytes.count, 0)
        XCTAssertEqual(Array(bytes.prefix(4)), [0x50, 0x4B, 0x03, 0x04],
            "Output should start with the ZIP/OOXML signature")
    }

    // MARK: - Certified transaction integration (docx-mutation-certification-layer1)

    func testCertificateFlagWritesLayer1VerifiedJSONOnSuccess() throws {
        // Spec: "Certificate flag writes the JSON on success"
        guard let binary = macdocBinary else {
            throw XCTSkip("Built macdoc binary not found")
        }
        let baseline = try makeSyntheticBaseline(texts: ["intro"])
        let temp = FileManager.default.temporaryDirectory
        let manifestURL = temp.appendingPathComponent("manifest-\(UUID().uuidString).json")
        let outputURL = temp.appendingPathComponent("out-\(UUID().uuidString).docx")
        let certificateURL = temp.appendingPathComponent("cert-\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: baseline)
            try? FileManager.default.removeItem(at: manifestURL)
            try? FileManager.default.removeItem(at: outputURL)
            try? FileManager.default.removeItem(at: certificateURL)
        }

        let json = #"""
        {
          "baseline": "\#(baseline.path)",
          "output": "\#(outputURL.path)",
          "steps": [
            { "type": "insert_paragraph", "anchor": { "after_text": "intro" }, "content": "inserted" }
          ]
        }
        """#
        try Data(json.utf8).write(to: manifestURL)

        let (stdout, stderr, exitCode) = try runProcessFull(
            binary: binary,
            args: ["docx", "apply", manifestURL.path, "--input", baseline.path, "--output", outputURL.path,
                   "--certificate", certificateURL.path]
        )

        XCTAssertEqual(exitCode, 0, "stdout: \(stdout) stderr: \(stderr)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: certificateURL.path))

        let certificateData = try Data(contentsOf: certificateURL)
        let certificate = try XCTUnwrap(JSONSerialization.jsonObject(with: certificateData) as? [String: Any])
        XCTAssertEqual(certificate["status"] as? String, "layer1Verified")
        XCTAssertEqual(certificate["schemaVersion"] as? Int, 1)
        XCTAssertEqual(certificate["changedParts"] as? [String], ["word/document.xml"])
    }

    // MARK: - set_bold integration (PsychQuant/macdoc#232)

    func testSetBoldOnlyBoldsMatchedSubstringAndSucceeds() throws {
        // Spec: `macdoc docx apply` with a `set_bold` step whose `anchor`
        // resolves to a paragraph and whose `substring` names a range
        // inside that paragraph's text bolds only that range and exits 0
        // with a `.layer1Verified` certificate — the issue's reproduction
        // ("EditPlanner compiled set_bold into a paragraph-targeted edit,
        // which the reducer always rejected with `target must be <w:r>`,
        // and `substring` was never used") no longer applies.
        guard let binary = macdocBinary else {
            throw XCTSkip("Built macdoc binary not found")
        }
        let baseline = try makeSyntheticBaseline(texts: ["intro alpha TARGET beta gamma"])
        let temp = FileManager.default.temporaryDirectory
        let manifestURL = temp.appendingPathComponent("manifest-\(UUID().uuidString).json")
        let outputURL = temp.appendingPathComponent("out-\(UUID().uuidString).docx")
        let certificateURL = temp.appendingPathComponent("cert-\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: baseline)
            try? FileManager.default.removeItem(at: manifestURL)
            try? FileManager.default.removeItem(at: outputURL)
            try? FileManager.default.removeItem(at: certificateURL)
        }

        let json = #"""
        {
          "baseline": "\#(baseline.path)",
          "output": "\#(outputURL.path)",
          "steps": [
            { "type": "set_bold", "anchor": { "after_text": "intro" }, "substring": "TARGET" }
          ]
        }
        """#
        try Data(json.utf8).write(to: manifestURL)

        let (stdout, stderr, exitCode) = try runProcessFull(
            binary: binary,
            args: ["docx", "apply", manifestURL.path, "--input", baseline.path, "--output", outputURL.path,
                   "--certificate", certificateURL.path]
        )

        // `guard` + `return` (rather than a plain `XCTAssertEqual` that lets
        // execution fall through) so a non-zero exit — no candidate, no
        // certificate — reports exactly the assertion below and nothing
        // else: the unguarded `Data(contentsOf: certificateURL)` further
        // down would otherwise throw its own unrelated Cocoa "file does not
        // exist" error and mask the real failure.
        guard exitCode == 0 else {
            XCTFail("Expected exit 0, got \(exitCode). stdout: \(stdout) stderr: \(stderr)")
            return
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))

        let certificateData = try Data(contentsOf: certificateURL)
        let certificate = try XCTUnwrap(JSONSerialization.jsonObject(with: certificateData) as? [String: Any])
        XCTAssertEqual(certificate["status"] as? String, "layer1Verified")
        XCTAssertEqual(certificate["changedParts"] as? [String], ["word/document.xml"])

        let outputDoc = try DocxReader.read(from: outputURL, wireTreeBackedViews: true)
        var found = false
        for child in outputDoc.body.children {
            guard case .paragraph(let paragraph) = child, paragraph.text.contains("intro") else { continue }
            found = true
            XCTAssertEqual(paragraph.text, "intro alpha TARGET beta gamma",
                           "set_bold must not change any character of the paragraph's text")
            guard let node = paragraph.xmlNode else {
                XCTFail("expected a tree-backed paragraph")
                continue
            }
            let runs = node.children.filter { $0.kind == .element && $0.localName == "r" }
            func text(_ run: XmlNode) -> String {
                run.children
                    .filter { $0.kind == .element && $0.localName == "t" }
                    .flatMap { $0.children.filter { $0.kind == .text }.map(\.textContent) }
                    .joined()
            }
            func isBold(_ run: XmlNode) -> Bool {
                guard let rPr = run.children.first(where: { $0.kind == .element && $0.localName == "rPr" })
                else { return false }
                return rPr.children.contains { $0.kind == .element && $0.localName == "b" }
            }
            for run in runs {
                if text(run) == "TARGET" {
                    XCTAssertTrue(isBold(run), "the matched substring must be bold")
                } else {
                    XCTAssertFalse(isBold(run), "\(String(reflecting: text(run))) must not be bold")
                }
            }
        }
        XCTAssertTrue(found, "expected to find the 'intro' paragraph in the output")
    }

    func testSetBoldSubstringNotFoundFailsWithReasonAndLeavesOutputAbsent() throws {
        // Spec: a `substring` that does not occur in the anchor paragraph
        // surfaces ooxml-swift's specific reason (not the issue's "error
        // 1"), exits non-zero, and never writes the output — #137's
        // transactional semantics.
        guard let binary = macdocBinary else {
            throw XCTSkip("Built macdoc binary not found")
        }
        let baseline = try makeSyntheticBaseline(texts: ["intro alpha beta gamma"])
        let temp = FileManager.default.temporaryDirectory
        let manifestURL = temp.appendingPathComponent("manifest-\(UUID().uuidString).json")
        let outputURL = temp.appendingPathComponent("out-\(UUID().uuidString).docx")
        defer {
            try? FileManager.default.removeItem(at: baseline)
            try? FileManager.default.removeItem(at: manifestURL)
            try? FileManager.default.removeItem(at: outputURL)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))

        let json = #"""
        {
          "baseline": "\#(baseline.path)",
          "output": "\#(outputURL.path)",
          "steps": [
            { "type": "set_bold", "anchor": { "after_text": "intro" }, "substring": "NOPE" }
          ]
        }
        """#
        try Data(json.utf8).write(to: manifestURL)

        let (stdout, stderr, exitCode) = try runProcessFull(
            binary: binary,
            args: ["docx", "apply", manifestURL.path, "--input", baseline.path, "--output", outputURL.path]
        )

        XCTAssertNotEqual(exitCode, 0, "stdout: \(stdout) stderr: \(stderr)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
        XCTAssertTrue(stderr.contains("NOPE"), "stderr should name the substring that was not found: \(stderr)")
        XCTAssertTrue(stderr.contains("not found"), "stderr should carry ooxml-swift's specific reason: \(stderr)")
        XCTAssertFalse(stderr.contains("ReducerError error"),
                       "must not regress to the generic NSError-bridged \"error N\" message the issue reported: \(stderr)")
    }

    func testFailingVerifyLeavesOutputAbsent() throws {
        // Spec: "Failing verify leaves no output"
        guard let binary = macdocBinary else {
            throw XCTSkip("Built macdoc binary not found")
        }
        let baseline = try makeSyntheticBaseline(texts: ["intro"])
        let temp = FileManager.default.temporaryDirectory
        let manifestURL = temp.appendingPathComponent("manifest-\(UUID().uuidString).json")
        let outputURL = temp.appendingPathComponent("out-\(UUID().uuidString).docx")
        let rejectedURL = temp.appendingPathComponent("\(outputURL.deletingPathExtension().lastPathComponent).rejected.docx")
        defer {
            try? FileManager.default.removeItem(at: baseline)
            try? FileManager.default.removeItem(at: manifestURL)
            try? FileManager.default.removeItem(at: outputURL)
            try? FileManager.default.removeItem(at: rejectedURL)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))

        let json = #"""
        {
          "baseline": "\#(baseline.path)",
          "output": "\#(outputURL.path)",
          "steps": [
            { "type": "insert_paragraph", "anchor": { "after_text": "intro" }, "content": "inserted" }
          ],
          "verify": { "expected_paragraphs_min": 5 }
        }
        """#
        try Data(json.utf8).write(to: manifestURL)

        let (stdout, stderr, exitCode) = try runProcessFull(
            binary: binary,
            args: ["docx", "apply", manifestURL.path, "--input", baseline.path, "--output", outputURL.path]
        )

        XCTAssertNotEqual(exitCode, 0, "stdout: \(stdout) stderr: \(stderr)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
        XCTAssertTrue(stderr.contains("verify") || stderr.contains("驗證") || stderr.contains("驗"),
                       "stderr should name the verify failure: \(stderr)")
    }

    // MARK: - R2 adversarial-review fixes (review-c137.md Findings 1 CRITICAL, 2 MEDIUM, L5)

    func testCertificateDestinationInvalidFailsBeforeAnyWrite() throws {
        // Review Finding 1 (CRITICAL) reproduction: a `--certificate`
        // parent directory that does not exist must no longer corrupt an
        // otherwise-successful apply into "output written but exit 1 with
        // an English Cocoa error". It must fail before any write, in
        // Traditional Chinese, exit non-zero.
        guard let binary = macdocBinary else {
            throw XCTSkip("Built macdoc binary not found")
        }
        let baseline = try makeSyntheticBaseline(texts: ["intro"])
        let temp = FileManager.default.temporaryDirectory
        let manifestURL = temp.appendingPathComponent("manifest-\(UUID().uuidString).json")
        let outputURL = temp.appendingPathComponent("out-\(UUID().uuidString).docx")
        let certificateURL = temp.appendingPathComponent("nonexistent-dir-\(UUID().uuidString)")
            .appendingPathComponent("cert.json")
        defer {
            try? FileManager.default.removeItem(at: baseline)
            try? FileManager.default.removeItem(at: manifestURL)
            try? FileManager.default.removeItem(at: outputURL)
        }

        let json = #"""
        {
          "baseline": "\#(baseline.path)",
          "output": "\#(outputURL.path)",
          "steps": [
            { "type": "insert_paragraph", "anchor": { "after_text": "intro" }, "content": "inserted" }
          ]
        }
        """#
        try Data(json.utf8).write(to: manifestURL)

        let (stdout, stderr, exitCode) = try runProcessFull(
            binary: binary,
            args: ["docx", "apply", manifestURL.path, "--input", baseline.path, "--output", outputURL.path,
                   "--certificate", certificateURL.path]
        )

        XCTAssertNotEqual(exitCode, 0, "stdout: \(stdout) stderr: \(stderr)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path),
                        "the output must not exist — pre-flight must fail before any write")
        XCTAssertFalse(FileManager.default.fileExists(atPath: certificateURL.path))
        XCTAssertTrue(stderr.contains("錯誤"), "stderr should use the Traditional Chinese error convention: \(stderr)")
        XCTAssertFalse(stderr.contains("已寫入"), "the success message must not appear when pre-flight rejected the certificate destination")
    }

    func testCertificateDestinationInvalidWinsOverAnUnderlyingVerifyFailure() throws {
        // Pre-flight runs before the transaction is attempted, so the
        // reported reason names the certificate problem, not the verify
        // failure that would otherwise have occurred.
        guard let binary = macdocBinary else {
            throw XCTSkip("Built macdoc binary not found")
        }
        let baseline = try makeSyntheticBaseline(texts: ["intro"])
        let temp = FileManager.default.temporaryDirectory
        let manifestURL = temp.appendingPathComponent("manifest-\(UUID().uuidString).json")
        let outputURL = temp.appendingPathComponent("out-\(UUID().uuidString).docx")
        let certificateURL = temp.appendingPathComponent("nonexistent-dir-\(UUID().uuidString)")
            .appendingPathComponent("cert.json")
        defer {
            try? FileManager.default.removeItem(at: baseline)
            try? FileManager.default.removeItem(at: manifestURL)
            try? FileManager.default.removeItem(at: outputURL)
        }

        let json = #"""
        {
          "baseline": "\#(baseline.path)",
          "output": "\#(outputURL.path)",
          "steps": [
            { "type": "insert_paragraph", "anchor": { "after_text": "intro" }, "content": "inserted" }
          ],
          "verify": { "expected_paragraphs_min": 99999 }
        }
        """#
        try Data(json.utf8).write(to: manifestURL)

        let (stdout, stderr, exitCode) = try runProcessFull(
            binary: binary,
            args: ["docx", "apply", manifestURL.path, "--input", baseline.path, "--output", outputURL.path,
                   "--certificate", certificateURL.path]
        )

        XCTAssertNotEqual(exitCode, 0, "stdout: \(stdout) stderr: \(stderr)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
        XCTAssertFalse(stderr.contains("verify"), "pre-flight should win before verify is ever evaluated: \(stderr)")
    }

    func testOutputPathAsExistingDirectoryIsRejectedWithoutDeletingIt() throws {
        // Review Finding 2 (MEDIUM) reproduction.
        guard let binary = macdocBinary else {
            throw XCTSkip("Built macdoc binary not found")
        }
        let baseline = try makeSyntheticBaseline(texts: ["intro"])
        let temp = FileManager.default.temporaryDirectory
        let manifestURL = temp.appendingPathComponent("manifest-\(UUID().uuidString).json")
        let outputDir = temp.appendingPathComponent("outdir-\(UUID().uuidString).docx")
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let importantFile = outputDir.appendingPathComponent("important-file.txt")
        try Data("important data".utf8).write(to: importantFile)
        defer {
            try? FileManager.default.removeItem(at: baseline)
            try? FileManager.default.removeItem(at: manifestURL)
            try? FileManager.default.removeItem(at: outputDir)
        }

        let json = #"""
        {
          "baseline": "\#(baseline.path)",
          "output": "\#(outputDir.path)",
          "steps": [
            { "type": "insert_paragraph", "anchor": { "after_text": "intro" }, "content": "inserted" }
          ]
        }
        """#
        try Data(json.utf8).write(to: manifestURL)

        let (stdout, stderr, exitCode) = try runProcessFull(
            binary: binary,
            args: ["docx", "apply", manifestURL.path, "--input", baseline.path, "--output", outputDir.path]
        )

        XCTAssertNotEqual(exitCode, 0, "stdout: \(stdout) stderr: \(stderr)")
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputDir.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue, "the output path must still be a directory, not replaced by a .docx")
        XCTAssertEqual(try String(contentsOf: importantFile, encoding: .utf8), "important data")
    }

    func testNonCertificationErrorIsWrappedWithChinesePrefix() throws {
        // Review Finding L5: a thrown error that is not a
        // `CertificationError` (here: a missing manifest file, decoded
        // before the transaction even starts) must still surface through
        // the CLI's Traditional Chinese "錯誤：" convention, not swift-
        // argument-parser's default English top-level printer.
        guard let binary = macdocBinary else {
            throw XCTSkip("Built macdoc binary not found")
        }
        let temp = FileManager.default.temporaryDirectory
        let missingManifest = temp.appendingPathComponent("missing-manifest-\(UUID().uuidString).json")
        let baseline = try makeSyntheticBaseline(texts: ["intro"])
        let outputURL = temp.appendingPathComponent("out-\(UUID().uuidString).docx")
        defer {
            try? FileManager.default.removeItem(at: baseline)
            try? FileManager.default.removeItem(at: outputURL)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: missingManifest.path))

        let (stdout, stderr, exitCode) = try runProcessFull(
            binary: binary,
            args: ["docx", "apply", missingManifest.path, "--input", baseline.path, "--output", outputURL.path]
        )

        XCTAssertNotEqual(exitCode, 0, "stdout: \(stdout) stderr: \(stderr)")
        XCTAssertTrue(stderr.contains("錯誤："), "non-CertificationError failures should still use the Chinese error prefix: \(stderr)")
    }

    // MARK: - R3 adversarial-review fixes (review-c137-r2.md Finding A CRITICAL, Finding D(b))

    func testCertificateEqualToOutputPathFailsBeforeAnyWrite() throws {
        // review-c137-r2.md Finding A, repro #E: --certificate pointed at
        // the same path as --output used to succeed (exit 0, "已寫入"
        // printed) while silently overwriting the just-verified .docx
        // with the certificate JSON.
        guard let binary = macdocBinary else {
            throw XCTSkip("Built macdoc binary not found")
        }
        let baseline = try makeSyntheticBaseline(texts: ["intro"])
        let temp = FileManager.default.temporaryDirectory
        let manifestURL = temp.appendingPathComponent("manifest-\(UUID().uuidString).json")
        let outputURL = temp.appendingPathComponent("out-\(UUID().uuidString).docx")
        defer {
            try? FileManager.default.removeItem(at: baseline)
            try? FileManager.default.removeItem(at: manifestURL)
            try? FileManager.default.removeItem(at: outputURL)
        }

        let json = #"""
        {
          "baseline": "\#(baseline.path)",
          "output": "\#(outputURL.path)",
          "steps": [
            { "type": "insert_paragraph", "anchor": { "after_text": "intro" }, "content": "inserted" }
          ]
        }
        """#
        try Data(json.utf8).write(to: manifestURL)

        let (stdout, stderr, exitCode) = try runProcessFull(
            binary: binary,
            args: ["docx", "apply", manifestURL.path, "--input", baseline.path, "--output", outputURL.path,
                   "--certificate", outputURL.path]
        )

        XCTAssertNotEqual(exitCode, 0, "stdout: \(stdout) stderr: \(stderr)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path),
                        "nothing must be written — the output must not exist, not exist-as-JSON")
        XCTAssertTrue(stderr.contains("錯誤"), "stderr should use the Chinese error convention: \(stderr)")
        XCTAssertFalse(stderr.contains("已寫入"), "success must not be reported when the destinations conflict: \(stderr)")
    }

    func testCertificateEqualToBaselinePathPreservesBaselineBytes() throws {
        // review-c137-r2.md Finding A, repro #F: the user's own source
        // file was silently overwritten with certificate JSON, no warning.
        guard let binary = macdocBinary else {
            throw XCTSkip("Built macdoc binary not found")
        }
        let baseline = try makeSyntheticBaseline(texts: ["intro"])
        let originalBaselineBytes = try Data(contentsOf: baseline)
        let temp = FileManager.default.temporaryDirectory
        let manifestURL = temp.appendingPathComponent("manifest-\(UUID().uuidString).json")
        let outputURL = temp.appendingPathComponent("out-\(UUID().uuidString).docx")
        defer {
            try? FileManager.default.removeItem(at: baseline)
            try? FileManager.default.removeItem(at: manifestURL)
            try? FileManager.default.removeItem(at: outputURL)
        }

        let json = #"""
        {
          "baseline": "\#(baseline.path)",
          "output": "\#(outputURL.path)",
          "steps": [
            { "type": "insert_paragraph", "anchor": { "after_text": "intro" }, "content": "inserted" }
          ]
        }
        """#
        try Data(json.utf8).write(to: manifestURL)

        let (stdout, stderr, exitCode) = try runProcessFull(
            binary: binary,
            args: ["docx", "apply", manifestURL.path, "--input", baseline.path, "--output", outputURL.path,
                   "--certificate", baseline.path]
        )

        XCTAssertNotEqual(exitCode, 0, "stdout: \(stdout) stderr: \(stderr)")
        XCTAssertEqual(try Data(contentsOf: baseline), originalBaselineBytes,
                        "the user's own source file must survive byte-for-byte")
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
    }

    func testCertificateEqualToManifestPathPreservesManifestBytes() throws {
        // The manifest's own file path is the one conflict
        // `CertifiedTransaction` itself never sees — checked by the CLI
        // layer only.
        guard let binary = macdocBinary else {
            throw XCTSkip("Built macdoc binary not found")
        }
        let baseline = try makeSyntheticBaseline(texts: ["intro"])
        let temp = FileManager.default.temporaryDirectory
        let manifestURL = temp.appendingPathComponent("manifest-\(UUID().uuidString).json")
        let outputURL = temp.appendingPathComponent("out-\(UUID().uuidString).docx")
        defer {
            try? FileManager.default.removeItem(at: baseline)
            try? FileManager.default.removeItem(at: manifestURL)
            try? FileManager.default.removeItem(at: outputURL)
        }

        let json = #"""
        {
          "baseline": "\#(baseline.path)",
          "output": "\#(outputURL.path)",
          "steps": [
            { "type": "insert_paragraph", "anchor": { "after_text": "intro" }, "content": "inserted" }
          ]
        }
        """#
        try Data(json.utf8).write(to: manifestURL)
        let originalManifestBytes = try Data(contentsOf: manifestURL)

        let (stdout, stderr, exitCode) = try runProcessFull(
            binary: binary,
            args: ["docx", "apply", manifestURL.path, "--input", baseline.path, "--output", outputURL.path,
                   "--certificate", manifestURL.path]
        )

        XCTAssertNotEqual(exitCode, 0, "stdout: \(stdout) stderr: \(stderr)")
        XCTAssertEqual(try Data(contentsOf: manifestURL), originalManifestBytes,
                        "the manifest file itself must survive byte-for-byte")
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
        XCTAssertTrue(stderr.contains("manifest"), "stderr should name the manifest-path conflict: \(stderr)")
    }

    func testCertificateWriteFailureAfterSuccessfulCommitStillExitsNonZero() throws {
        // Finding D: spec.md's docx-workflow-cli Scenario "Certificate
        // write failing after a successful commit still exits non-zero"
        // had no CLI-level automated coverage (mutation M6 survived).
        // A directory with rw------- (0600, no execute/search bit) passes
        // `FileManager.isWritableFile` (pre-flight's own check — verified
        // empirically: `access(2)`'s W_OK bit is satisfied) but any actual
        // attempt to create a file inside it fails with EACCES — a
        // deterministic, non-racy way to reproduce "pre-flight passed, the
        // real write still failed" without timing-dependent concurrency.
        guard let binary = macdocBinary else {
            throw XCTSkip("Built macdoc binary not found")
        }
        let baseline = try makeSyntheticBaseline(texts: ["intro"])
        let temp = FileManager.default.temporaryDirectory
        let manifestURL = temp.appendingPathComponent("manifest-\(UUID().uuidString).json")
        let outputURL = temp.appendingPathComponent("out-\(UUID().uuidString).docx")
        let certDir = temp.appendingPathComponent("cert-noexec-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: certDir, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: certDir.path)
        let certificateURL = certDir.appendingPathComponent("cert.json")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: certDir.path)
            try? FileManager.default.removeItem(at: baseline)
            try? FileManager.default.removeItem(at: manifestURL)
            try? FileManager.default.removeItem(at: outputURL)
            try? FileManager.default.removeItem(at: certDir)
        }
        XCTAssertTrue(FileManager.default.isWritableFile(atPath: certDir.path),
                       "the point of this fixture is that pre-flight's own writability check passes")

        let json = #"""
        {
          "baseline": "\#(baseline.path)",
          "output": "\#(outputURL.path)",
          "steps": [
            { "type": "insert_paragraph", "anchor": { "after_text": "intro" }, "content": "inserted" }
          ]
        }
        """#
        try Data(json.utf8).write(to: manifestURL)

        let (stdout, stderr, exitCode) = try runProcessFull(
            binary: binary,
            args: ["docx", "apply", manifestURL.path, "--input", baseline.path, "--output", outputURL.path,
                   "--certificate", certificateURL.path]
        )

        XCTAssertNotEqual(exitCode, 0, "stdout: \(stdout) stderr: \(stderr)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path),
                       "the transaction itself succeeded and must still be committed")
        XCTAssertTrue(stderr.contains("已寫入"), "the success must still be reported: \(stderr)")
        XCTAssertFalse(FileManager.default.fileExists(atPath: certificateURL.path))
    }

    // MARK: - R3b (review-c137-r2.md follow-up): a same-file collision
    // pre-flight cannot see, because neither --output nor --certificate
    // existed yet and they differ only by case.

    /// True when `directory`'s filesystem folds case for lookups (APFS's
    /// default). Probes empirically rather than querying volume
    /// attributes, per the coordinator's explicit instruction that this
    /// follow-up should not need to.
    private func directoryIsCaseInsensitive(_ directory: URL) -> Bool {
        let name = "CASEPROBE-\(UUID().uuidString)"
        let mixedCase = directory.appendingPathComponent(name)
        let lowered = directory.appendingPathComponent(name.lowercased())
        FileManager.default.createFile(atPath: mixedCase.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: mixedCase) }
        return FileManager.default.fileExists(atPath: lowered.path)
    }

    func testCertificateDestinationCollidingWithOutputOnlyByCaseIsCaughtAfterCommit() throws {
        guard let binary = macdocBinary else {
            throw XCTSkip("Built macdoc binary not found")
        }
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("cli-case-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        guard directoryIsCaseInsensitive(temp) else {
            throw XCTSkip("this filesystem is case-sensitive — the R3b collision needs a case-insensitive volume (APFS's default)")
        }

        let baseline = try makeSyntheticBaseline(texts: ["intro"])
        let manifestURL = temp.appendingPathComponent("manifest.json")
        let outputURL = temp.appendingPathComponent("Out.docx")
        let certificateURL = temp.appendingPathComponent("out.docx")   // same file once created, different case
        defer { try? FileManager.default.removeItem(at: baseline) }

        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path), "the point of this test is that neither path exists before the call")
        XCTAssertFalse(FileManager.default.fileExists(atPath: certificateURL.path))

        let json = #"""
        {
          "baseline": "\#(baseline.path)",
          "output": "\#(outputURL.path)",
          "steps": [
            { "type": "insert_paragraph", "anchor": { "after_text": "intro" }, "content": "inserted" }
          ]
        }
        """#
        try Data(json.utf8).write(to: manifestURL)

        let (stdout, stderr, exitCode) = try runProcessFull(
            binary: binary,
            args: ["docx", "apply", manifestURL.path, "--input", baseline.path, "--output", outputURL.path,
                   "--certificate", certificateURL.path]
        )

        XCTAssertNotEqual(exitCode, 0, "stdout: \(stdout) stderr: \(stderr)")
        XCTAssertTrue(stderr.contains("已寫入"), "the transaction itself succeeded and must still be reported: \(stderr)")

        // The output must still be a valid ZIP/OOXML container — not
        // overwritten by certificate JSON that the case-insensitive
        // collision would otherwise have routed to the exact same
        // directory entry.
        let data = try Data(contentsOf: outputURL)
        XCTAssertEqual(Array(data.prefix(4)), [0x50, 0x4B, 0x03, 0x04],
                       "output must still be a ZIP/OOXML container, not certificate JSON")
    }

    // MARK: - R4 (review-c137-r3.md Finding E HIGH, Finding F HIGH)

    func testOutputPathThatIsASymlinkIsRejectedAtCliAndTargetSurvivesUntouched() throws {
        // Finding E: `commit`'s switch to POSIX `rename(2)` (R3) means a
        // symlink named by `--output` gets its OWN directory entry
        // replaced by the new file — the target the symlink used to point
        // to is left completely alone, and the alias relationship between
        // them is severed without any warning. Before that switch,
        // `FileManager.replaceItemAt` threw for this same case and
        // touched neither.
        guard let binary = macdocBinary else {
            throw XCTSkip("Built macdoc binary not found")
        }
        let baseline = try makeSyntheticBaseline(texts: ["intro"])
        let temp = FileManager.default.temporaryDirectory
        let manifestURL = temp.appendingPathComponent("manifest-\(UUID().uuidString).json")
        let realTarget = temp.appendingPathComponent("real-target-\(UUID().uuidString).docx")
        try Data("original target content".utf8).write(to: realTarget)
        let outputLink = temp.appendingPathComponent("out-symlink-\(UUID().uuidString).docx")
        try FileManager.default.createSymbolicLink(at: outputLink, withDestinationURL: realTarget)
        defer {
            try? FileManager.default.removeItem(at: baseline)
            try? FileManager.default.removeItem(at: manifestURL)
            try? FileManager.default.removeItem(at: realTarget)
            try? FileManager.default.removeItem(at: outputLink)
        }

        let json = #"""
        {
          "baseline": "\#(baseline.path)",
          "output": "\#(outputLink.path)",
          "steps": [
            { "type": "insert_paragraph", "anchor": { "after_text": "intro" }, "content": "inserted" }
          ]
        }
        """#
        try Data(json.utf8).write(to: manifestURL)

        let (stdout, stderr, exitCode) = try runProcessFull(
            binary: binary,
            args: ["docx", "apply", manifestURL.path, "--input", baseline.path, "--output", outputLink.path]
        )

        XCTAssertNotEqual(exitCode, 0, "stdout: \(stdout) stderr: \(stderr)")
        XCTAssertTrue(stderr.contains("符號連結"), "stderr must name the symlink case: \(stderr)")
        XCTAssertFalse(stderr.contains("已寫入"), "the transaction must not report success: \(stderr)")

        let resolvedDestination = try FileManager.default.destinationOfSymbolicLink(atPath: outputLink.path)
        XCTAssertEqual(resolvedDestination, realTarget.path, "the symlink itself must survive, still pointing at the same target")
        XCTAssertEqual(try String(contentsOf: realTarget, encoding: .utf8), "original target content")
    }

    func testOverwritingExistingOutputAtCliPreservesPermissionsXattrAndCreationDate() throws {
        // Finding F: plain `rename(2)` does not preserve a replaced
        // file's permissions/ACL/xattrs the way `FileManager
        // .replaceItemAt` used to. Re-running `apply` against an output
        // the caller had deliberately locked down (e.g. `chmod 640`)
        // must not silently widen it back to the default umask.
        guard let binary = macdocBinary else {
            throw XCTSkip("Built macdoc binary not found")
        }
        let baseline = try makeSyntheticBaseline(texts: ["intro"])
        let output = try makeSyntheticBaseline(texts: ["old content"])
        let temp = FileManager.default.temporaryDirectory
        let manifestURL = temp.appendingPathComponent("manifest-\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: baseline)
            try? FileManager.default.removeItem(at: output)
            try? FileManager.default.removeItem(at: manifestURL)
        }

        let fm = FileManager.default
        try fm.setAttributes([.posixPermissions: 0o640], ofItemAtPath: output.path)
        let oldCreationDate = Date(timeIntervalSince1970: 1_000_000_000)
        try fm.setAttributes([.creationDate: oldCreationDate], ofItemAtPath: output.path)
        let xattrName = "com.example.macdoc137.cli-marker"
        let xattrValue = "r4-finding-f-cli"
        let xattrResult = xattrValue.withCString { value in
            setxattr(output.path, xattrName, value, strlen(value), 0, 0)
        }
        XCTAssertEqual(xattrResult, 0, "test setup: setxattr itself must succeed")

        let json = #"""
        {
          "baseline": "\#(baseline.path)",
          "output": "\#(output.path)",
          "steps": [
            { "type": "insert_paragraph", "anchor": { "after_text": "intro" }, "content": "inserted" }
          ]
        }
        """#
        try Data(json.utf8).write(to: manifestURL)

        let (stdout, stderr, exitCode) = try runProcessFull(
            binary: binary,
            args: ["docx", "apply", manifestURL.path, "--input", baseline.path, "--output", output.path]
        )
        XCTAssertEqual(exitCode, 0, "stdout: \(stdout) stderr: \(stderr)")

        let newAttributes = try fm.attributesOfItem(atPath: output.path)
        XCTAssertEqual((newAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o640, "permissions must survive the overwrite")
        XCTAssertEqual(newAttributes[.creationDate] as? Date, oldCreationDate, "creation date must survive the overwrite")

        var buffer = [UInt8](repeating: 0, count: 64)
        let length = getxattr(output.path, xattrName, &buffer, buffer.count, 0, 0)
        XCTAssertGreaterThan(length, 0, "custom extended attribute must survive the overwrite")
        XCTAssertEqual(String(bytes: buffer.prefix(max(length, 0)), encoding: .utf8), xattrValue)
    }

    func testMetadataPreservationFailureAtCliRejectsCommitAndReportsError() throws {
        guard let binary = macdocBinary else {
            throw XCTSkip("Built macdoc binary not found")
        }
        let baseline = try makeSyntheticBaseline(texts: ["intro"])
        let output = try makeSyntheticBaseline(texts: ["old content"])
        let temp = FileManager.default.temporaryDirectory
        let manifestURL = temp.appendingPathComponent("manifest-\(UUID().uuidString).json")
        let originalOutputBytes = try Data(contentsOf: output)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: output.path)
            try? FileManager.default.removeItem(at: baseline)
            try? FileManager.default.removeItem(at: output)
            try? FileManager.default.removeItem(at: manifestURL)
        }

        // Deterministic, non-racy reproduction of "copyfile(3) itself
        // fails": mode 0 still lets `stat` see the file but blocks
        // `copyfile`'s own `open()` of it (see the library-level test's
        // comment for why `fileExists`/`attributesOfItem` still succeed).
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: output.path)

        let json = #"""
        {
          "baseline": "\#(baseline.path)",
          "output": "\#(output.path)",
          "steps": [
            { "type": "insert_paragraph", "anchor": { "after_text": "intro" }, "content": "inserted" }
          ]
        }
        """#
        try Data(json.utf8).write(to: manifestURL)

        let (stdout, stderr, exitCode) = try runProcessFull(
            binary: binary,
            args: ["docx", "apply", manifestURL.path, "--input", baseline.path, "--output", output.path]
        )

        XCTAssertNotEqual(exitCode, 0, "stdout: \(stdout) stderr: \(stderr)")
        XCTAssertFalse(stderr.contains("已寫入"), "the transaction must not report success: \(stderr)")

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: output.path)
        XCTAssertEqual(try Data(contentsOf: output), originalOutputBytes, "the old output must be byte-for-byte unchanged")
    }

    func testPlanDoesNotWriteOutput() throws {
        // Spec: "plan does not write output"
        guard let binary = macdocBinary else {
            throw XCTSkip("Built macdoc binary not found")
        }
        guard let baseline = fixtureBaseline() else {
            throw XCTSkip("No .docx fixture under test-files/")
        }

        let temp = FileManager.default.temporaryDirectory
        let manifestURL = temp.appendingPathComponent("manifest-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: manifestURL) }

        let json = #"""
        {
          "baseline": "\#(baseline.path)",
          "output": "should-not-be-created.docx",
          "steps": [
            { "type": "insert_image", "anchor": { "paragraph_index": 0 }, "path": "x.png" }
          ]
        }
        """#
        try Data(json.utf8).write(to: manifestURL)

        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let mustNotExist = cwd.appendingPathComponent("should-not-be-created.docx")

        let (stdout, _, exitCode) = try runProcessFull(
            binary: binary,
            args: ["docx", "plan", manifestURL.path, "--input", baseline.path]
        )

        XCTAssertEqual(exitCode, 0)
        XCTAssertTrue(stdout.contains("Steps:"), "plan output should describe the planned steps")
        XCTAssertFalse(FileManager.default.fileExists(atPath: mustNotExist.path),
            "plan should not write any output file")
    }

    // MARK: - Process helpers

    private func runProcess(binary: URL, args: [String]) throws -> String {
        let (out, _, _) = try runProcessFull(binary: binary, args: args)
        return out
    }

    private func runProcessFull(binary: URL, args: [String]) throws -> (stdout: String, stderr: String, exit: Int32) {
        let process = Process()
        process.executableURL = binary
        process.arguments = args
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        try process.run()
        process.waitUntilExit()
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        return (
            String(data: outData, encoding: .utf8) ?? "",
            String(data: errData, encoding: .utf8) ?? "",
            process.terminationStatus
        )
    }
}
