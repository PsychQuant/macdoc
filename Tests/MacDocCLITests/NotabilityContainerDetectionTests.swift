import Foundation
import XCTest
@testable import MacDocCLI

final class NotabilityContainerDetectionTests: XCTestCase {
    private static let modernContainerDiagnostic =
        "偵測到新版 Notability .ntb 容器（noteBundle／FlatBuffers）；目前僅支援舊版 plist-based .note（Session.plist）"

    func testEntryClassificationGivesLegacyMarkerPrecedence() {
        XCTAssertEqual(
            NotabilityContainerDetector.classify(
                regularEntryPaths: ["export/noteBundle", "export/Session.plist"]
            ),
            .legacy
        )
    }

    func testEntryClassificationRecognizesWrappedModernMarker() {
        XCTAssertEqual(
            NotabilityContainerDetector.classify(
                regularEntryPaths: ["./export\\noteBundle", "manifest.json"]
            ),
            .modernFlatBuffers
        )
    }

    func testEntryClassificationPreservesUnknownFallback() {
        XCTAssertEqual(
            NotabilityContainerDetector.classify(
                regularEntryPaths: ["manifest.json", "thumbnail.png"]
            ),
            .unknown
        )
    }

    func testUnreadableArchiveIsUnknown() {
        let missing = temporaryURL(pathExtension: "ntb")
        XCTAssertEqual(NotabilityContainerDetector.classify(at: missing), .unknown)
    }

    func testDocumentationStatesNotabilityGenerationBoundary() throws {
        let documents = ["README.md", "CONVERSIONS.md"]

        for document in documents {
            let content = try String(
                contentsOf: CLITestHelper.repoRoot.appendingPathComponent(document),
                encoding: .utf8
            )
            XCTAssertTrue(
                content.contains("舊版 plist-based `.note`（`Session.plist`）"),
                "\(document) SHALL identify the supported legacy container"
            )
            XCTAssertTrue(
                content.contains("現代 `.ntb`（FlatBuffers `noteBundle`）會被辨識，但尚不支援轉換"),
                "\(document) SHALL distinguish detected modern containers"
            )
            XCTAssertTrue(
                content.contains("尚未實作 FlatBuffers 的手寫／時間軸重播"),
                "\(document) SHALL not overstate FlatBuffers replay support"
            )
        }
    }

    func testModernNTBHTMLFailsBeforeCreatingOutput() throws {
        let fixture = try makeModernArchive(pathExtension: "ntb")
        let output = temporaryURL(pathExtension: "html")
        defer {
            removeIfPresent(output)
            removeIfPresent(fixture.deletingLastPathComponent())
        }

        let result = try CLITestHelper.convert(
            to: "html",
            input: fixture.path,
            flags: ["--output", output.path, "--css", "dark"]
        )

        assertModernContainerRejection(result, output: output)
    }

    func testModernNTBPDFFailsBeforeCreatingOutput() throws {
        let fixture = try makeModernArchive(pathExtension: "ntb")
        let output = temporaryURL(pathExtension: "pdf")
        defer {
            removeIfPresent(output)
            removeIfPresent(fixture.deletingLastPathComponent())
        }

        let result = try CLITestHelper.convert(
            to: "pdf",
            input: fixture.path,
            flags: ["--output", output.path]
        )

        assertModernContainerRejection(result, output: output)
    }

    func testModernContainerRenamedNoteUsesGenerationDiagnostic() throws {
        let fixture = try makeModernArchive(pathExtension: "note")
        let output = temporaryURL(pathExtension: "html")
        defer {
            removeIfPresent(output)
            removeIfPresent(fixture.deletingLastPathComponent())
        }

        let result = try CLITestHelper.convert(
            to: "html",
            input: fixture.path,
            flags: ["--output", output.path, "--css", "dark"]
        )

        assertModernContainerRejection(result, output: output)
    }

    private func assertModernContainerRejection(
        _ result: CLIResult,
        output: URL,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertNotEqual(result.exitCode, 0, file: file, line: line)
        XCTAssertEqual(result.stdout, "", file: file, line: line)
        let diagnosticLine = result.stderr.split(separator: "\n", omittingEmptySubsequences: false).first
        XCTAssertEqual(
            diagnosticLine,
            "Error: \(Self.modernContainerDiagnostic)",
            "the first stderr line SHALL be the exact generation diagnostic",
            file: file,
            line: line
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: output.path),
            "modern container rejection SHALL leave the destination absent",
            file: file,
            line: line
        )
    }

    private func makeModernArchive(pathExtension: String) throws -> URL {
        let root = temporaryURL(pathExtension: nil)
        let staging = root.appendingPathComponent("payload", isDirectory: true)
        let archive = root
            .appendingPathComponent("modern")
            .appendingPathExtension(pathExtension)
        try FileManager.default.createDirectory(
            at: staging,
            withIntermediateDirectories: true
        )

        // Central-directory entry names are the only fixture signal. Contents
        // are fixed synthetic bytes and contain no real Notability payload.
        try Data().write(to: staging.appendingPathComponent("noteBundle"))
        try Data("synthetic\n".utf8).write(to: staging.appendingPathComponent("version"))
        try Data("{}\n".utf8).write(to: staging.appendingPathComponent("manifest.json"))

        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.arguments = [
            "-0", "-q", archive.path,
            "noteBundle", "version", "manifest.json",
        ]
        zip.currentDirectoryURL = staging
        let stderr = Pipe()
        zip.standardError = stderr
        try zip.run()
        zip.waitUntilExit()

        let errorText = String(
            data: stderr.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        XCTAssertEqual(zip.terminationStatus, 0, "zip failed: \(errorText)")
        return archive
    }

    private func temporaryURL(pathExtension: String?) -> URL {
        var url = FileManager.default.temporaryDirectory
            .appendingPathComponent("macdoc-modern-note-\(UUID().uuidString)")
        if let pathExtension {
            url.appendPathExtension(pathExtension)
        }
        return url
    }

    private func removeIfPresent(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
