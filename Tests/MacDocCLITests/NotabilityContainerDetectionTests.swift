import Foundation
import XCTest
@testable import NotabilityContainerDetection

final class NotabilityContainerDetectionTests: XCTestCase {
    private static let modernContainerDiagnostic =
        "偵測到新版 Notability .ntb 容器（noteBundle／FlatBuffers）；目前僅支援舊版 plist-based .note（Session.plist）"
    private static let unrecognizedNTBContainerDiagnostic =
        "無法安全辨識 Notability .ntb 容器；目前僅支援舊版 plist-based .note（Session.plist）"

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

    func testEntryClassificationStopsBeforeMarkerBeyondSafetyLimit() {
        let paths = Array(repeating: "assets/thumbnail.png", count: 4_096) + ["noteBundle"]

        XCTAssertEqual(
            NotabilityContainerDetector.classify(regularEntryPaths: paths),
            .unknown
        )
    }

    func testEntryClassificationRejectsOversizedEntryName() {
        XCTAssertEqual(
            NotabilityContainerDetector.classify(
                regularEntryPaths: [String(repeating: "a", count: 4_097) + "/noteBundle"]
            ),
            .unknown
        )
    }

    func testUnreadableArchiveIsUnknown() {
        let missing = temporaryURL(pathExtension: "ntb")
        XCTAssertEqual(NotabilityContainerDetector.classify(at: missing), .unknown)
    }

    func testLargeSparseFileWithoutEOCDIsUnknown() throws {
        let file = temporaryURL(pathExtension: "ntb")
        defer { removeIfPresent(file) }

        FileManager.default.createFile(atPath: file.path, contents: Data("not-a-zip".utf8))
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: 256 * 1_024 * 1_024)
        try handle.close()

        let clock = ContinuousClock()
        let elapsed = clock.measure {
            XCTAssertEqual(NotabilityContainerDetector.classify(at: file), .unknown)
        }
        XCTAssertLessThan(elapsed, .seconds(1))
    }

    func testTruncatedArchiveEnumerationIsUnknown() throws {
        let archive = try makeArchive(
            pathExtension: "ntb",
            entries: ["noteBundle", "Session.plist"]
        )
        defer { removeIfPresent(archive.deletingLastPathComponent()) }

        var bytes = try Data(contentsOf: archive)
        let localHeader = Data([0x50, 0x4b, 0x03, 0x04])
        let first = try XCTUnwrap(bytes.range(of: localHeader))
        let second = try XCTUnwrap(
            bytes.range(of: localHeader, in: first.upperBound..<bytes.endIndex)
        )
        bytes[second.lowerBound] = 0x00
        try bytes.write(to: archive)

        XCTAssertEqual(NotabilityContainerDetector.classify(at: archive), .unknown)
    }

    func testEOCDInZIPCommentCannotHideLegacyMarker() throws {
        let archive = try makeArchive(
            pathExtension: "ntb",
            entries: ["noteBundle", "Session.plist"]
        )
        defer { removeIfPresent(archive.deletingLastPathComponent()) }

        var bytes = try Data(contentsOf: archive)
        let eocdSignature = Data([0x50, 0x4b, 0x05, 0x06])
        let realEOCDRange = try XCTUnwrap(
            bytes.range(of: eocdSignature, options: .backwards)
        )
        let realEOCDOffset = realEOCDRange.lowerBound
        var fakeEOCD = bytes.subdata(in: realEOCDOffset..<(realEOCDOffset + 22))

        // The real record owns a 22-byte comment. That comment is itself a
        // syntactically valid EOCD claiming only the first central entry.
        bytes[realEOCDOffset + 20] = 22
        bytes[realEOCDOffset + 21] = 0
        fakeEOCD[8] = 1
        fakeEOCD[9] = 0
        fakeEOCD[10] = 1
        fakeEOCD[11] = 0
        fakeEOCD[20] = 0
        fakeEOCD[21] = 0
        bytes.append(fakeEOCD)
        try bytes.write(to: archive)

        XCTAssertEqual(NotabilityContainerDetector.classify(at: archive), .unknown)
    }

    func testNonCanonicalEOCDCannotRedirectZIPFoundationToShadowDirectory() throws {
        let archive = try makeArchive(
            pathExtension: "ntb",
            entries: ["noteBundle", "Session.plist"]
        )
        defer { removeIfPresent(archive.deletingLastPathComponent()) }

        var bytes = try Data(contentsOf: archive)
        let eocdSignature = Data([0x50, 0x4b, 0x05, 0x06])
        let realEOCDOffset = try XCTUnwrap(
            bytes.range(of: eocdSignature, options: .backwards)
        ).lowerBound
        let directorySize = Int(testReadUInt32(bytes, at: realEOCDOffset + 12))
        let directoryOffset = Int(testReadUInt32(bytes, at: realEOCDOffset + 16))
        var shadowDirectory = bytes.subdata(
            in: directoryOffset..<(directoryOffset + directorySize)
        )
        let legacyName = Data("Session.plist".utf8)
        let legacyRange = try XCTUnwrap(shadowDirectory.range(of: legacyName))
        shadowDirectory.replaceSubrange(
            legacyRange,
            with: Data(String(repeating: "x", count: legacyName.count).utf8)
        )

        let shadowOffset = bytes.count
        var fakeEOCD = bytes.subdata(in: realEOCDOffset..<(realEOCDOffset + 22))
        testWriteUInt32(UInt32(shadowDirectory.count), to: &fakeEOCD, at: 12)
        testWriteUInt32(UInt32(shadowOffset), to: &fakeEOCD, at: 16)
        // ZIPFoundation ignores comment length and selects this later record.
        // The bounded parser sees two trailing bytes, so length 1 is non-canonical.
        fakeEOCD[20] = 1
        fakeEOCD[21] = 0

        let appendedByteCount = shadowDirectory.count + fakeEOCD.count + 2
        XCTAssertLessThanOrEqual(appendedByteCount, Int(UInt16.max))
        testWriteUInt16(UInt16(appendedByteCount), to: &bytes, at: realEOCDOffset + 20)
        bytes.append(shadowDirectory)
        bytes.append(fakeEOCD)
        bytes.append(contentsOf: [0, 0])
        try bytes.write(to: archive)

        XCTAssertEqual(NotabilityContainerDetector.classify(at: archive), .unknown)
    }

    func testCentralDirectoryEntryOnAnotherDiskIsUnknown() throws {
        let archive = try makeModernArchive(pathExtension: "ntb")
        defer { removeIfPresent(archive.deletingLastPathComponent()) }

        var bytes = try Data(contentsOf: archive)
        let centralSignature = Data([0x50, 0x4b, 0x01, 0x02])
        let centralOffset = try XCTUnwrap(bytes.range(of: centralSignature)).lowerBound
        // diskNumberStart lives at byte 34 of each central-directory header.
        bytes[centralOffset + 34] = 1
        bytes[centralOffset + 35] = 0
        try bytes.write(to: archive)

        XCTAssertEqual(NotabilityContainerDetector.classify(at: archive), .unknown)
    }

    func testZIP64VersionWithoutClassicSentinelsIsUnknown() throws {
        let archive = try makeModernArchive(pathExtension: "ntb")
        defer { removeIfPresent(archive.deletingLastPathComponent()) }

        var bytes = try Data(contentsOf: archive)
        let centralSignature = Data([0x50, 0x4b, 0x01, 0x02])
        let centralOffset = try XCTUnwrap(bytes.range(of: centralSignature)).lowerBound
        // ZIPFoundation treats version-needed 45 as ZIP64 even when the
        // classic EOCD fields do not use ZIP64 sentinels.
        bytes[centralOffset + 6] = 45
        bytes[centralOffset + 7] = 0
        try bytes.write(to: archive)

        XCTAssertEqual(NotabilityContainerDetector.classify(at: archive), .unknown)
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

    func testUnrecognizedNTBFailsLocallyWithoutLeakingPath() throws {
        let root = temporaryURL(pathExtension: nil)
        let fixture = root.appendingPathComponent("private-title.ntb")
        let output = root.appendingPathComponent("out.html")
        defer { removeIfPresent(root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("not-a-zip".utf8).write(to: fixture)

        let result = try CLITestHelper.convert(
            to: "html",
            input: fixture.path,
            flags: ["--output", output.path, "--css", "dark"]
        )

        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout, "")
        XCTAssertEqual(
            result.stderr.split(separator: "\n", omittingEmptySubsequences: false).first,
            "Error: \(Self.unrecognizedNTBContainerDiagnostic)"
        )
        XCTAssertFalse(result.stderr.contains("private-title"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
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
        try makeArchive(
            pathExtension: pathExtension,
            entries: ["noteBundle", "version", "manifest.json"]
        )
    }

    private func makeArchive(pathExtension: String, entries: [String]) throws -> URL {
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
        for entry in entries {
            try Data("synthetic\n".utf8).write(to: staging.appendingPathComponent(entry))
        }

        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.arguments = [
            "-0", "-q", archive.path,
        ] + entries
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

    private func testReadUInt32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    private func testWriteUInt16(_ value: UInt16, to data: inout Data, at offset: Int) {
        data[offset] = UInt8(truncatingIfNeeded: value)
        data[offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
    }

    private func testWriteUInt32(_ value: UInt32, to data: inout Data, at offset: Int) {
        data[offset] = UInt8(truncatingIfNeeded: value)
        data[offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
        data[offset + 2] = UInt8(truncatingIfNeeded: value >> 16)
        data[offset + 3] = UInt8(truncatingIfNeeded: value >> 24)
    }
}
