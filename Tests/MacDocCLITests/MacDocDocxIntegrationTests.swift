// MacDocDocxIntegrationTests — §7.5 of macdoc-docx-workflow-cli.
//
// End-to-end tests that exercise the built `macdoc` binary via Process
// against fixture manifests + baselines. Per the test-files/ convention
// (gitignored — local fixtures only), tests XCTSkip cleanly when fixtures
// are absent, matching the precedent from NoteHTMLConvertTests.

import XCTest
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
