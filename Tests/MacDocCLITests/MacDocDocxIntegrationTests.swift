// MacDocDocxIntegrationTests — §7.5 of macdoc-docx-workflow-cli.
//
// End-to-end tests that exercise the built `macdoc` binary via Process
// against fixture manifests + baselines. Per the test-files/ convention
// (gitignored — local fixtures only), tests XCTSkip cleanly when fixtures
// are absent, matching the precedent from NoteHTMLConvertTests.

import XCTest
import Foundation

final class MacDocDocxIntegrationTests: XCTestCase {

    // MARK: - Binary resolution

    private var macdocBinary: URL? {
        // Locate the built `macdoc` binary in the standard SPM debug output.
        // Tests run from the repo root; the binary lives at .build/debug/macdoc.
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let candidate = cwd.appendingPathComponent(".build/debug/macdoc")
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
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
