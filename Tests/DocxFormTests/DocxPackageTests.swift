// DocxPackageTests.swift — "Parts other than the main part are unchanged" and
// the output handling of `word form apply` (#249).

import XCTest
import ZIPFoundation
@testable import DocxForm

final class DocxPackageTests: XCTestCase {
    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("docxform-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    private func samplePackage(at url: URL) throws -> [DocxPackage.Entry] {
        let entries = [
            DocxPackage.Entry(path: "[Content_Types].xml", data: Data("<Types/>".utf8)),
            DocxPackage.Entry(path: "_rels/.rels", data: Data("<Relationships/>".utf8)),
            DocxPackage.Entry(path: "word/document.xml",
                              data: Data(TestXML.document(TestXML.paragraph("0000R001", TestXML.run("刪"))
                                  + TestXML.paragraph("0000R002", TestXML.run("留"))))),
            DocxPackage.Entry(path: "word/styles.xml", data: Data("<w:styles xmlns:w=\"x\"><w:style/></w:styles>".utf8)),
            DocxPackage.Entry(path: "word/media/image1.png", data: Data((0..<4096).map { UInt8($0 % 251) })),
        ]
        try DocxPackage.write(entries, to: url)
        return entries
    }

    func testRewriteChangesOnlyTheMainPartAndKeepsOrder() throws {
        let dir = try tempDir()
        let input = dir.appendingPathComponent("in.docx")
        let output = dir.appendingPathComponent("out.docx")
        let original = try samplePackage(at: input)
        try DocxPackage.rewriteDocument(input: input, output: output, force: false) { document, _ in
            Data(try FormPlan(removals: ["0000R001"]).apply(toDocumentXML: Array(document)).documentXML)
        }
        let rewritten = try DocxPackage.read(from: output)
        XCTAssertEqual(rewritten.map(\.path), original.map(\.path))
        for (before, after) in zip(original, rewritten) where before.path != DocxPackage.documentPart {
            XCTAssertEqual(before.data, after.data, before.path)
        }
        let document = rewritten.first { $0.path == DocxPackage.documentPart }!
        XCTAssertFalse(String(decoding: document.data, as: UTF8.self).contains("0000R001"))
    }

    func testExistingOutputWithoutForceIsRefusedAndUnchanged() throws {
        let dir = try tempDir()
        let input = dir.appendingPathComponent("in.docx")
        let output = dir.appendingPathComponent("out.docx")
        _ = try samplePackage(at: input)
        try Data("keep me".utf8).write(to: output)
        XCTAssertThrowsError(try DocxPackage.rewriteDocument(input: input, output: output, force: false) { d, _ in d }) {
            XCTAssertEqual($0 as? DocxPackageError, .outputExists(output.path))
        }
        XCTAssertEqual(try Data(contentsOf: output), Data("keep me".utf8))
    }

    /// A file that appears at the output path after the first existence
    /// check is still not replaced without --force (exclusive rename).
    func testOutputCreatedDuringTheRunIsNotReplaced() throws {
        let dir = try tempDir()
        let input = dir.appendingPathComponent("in.docx")
        let output = dir.appendingPathComponent("out.docx")
        _ = try samplePackage(at: input)
        XCTAssertThrowsError(try DocxPackage.rewriteDocument(input: input, output: output, force: false) { document, _ in
            try Data("someone else".utf8).write(to: output)
            return document
        }) {
            XCTAssertEqual($0 as? DocxPackageError, .outputExists(output.path))
        }
        XCTAssertEqual(try Data(contentsOf: output), Data("someone else".utf8))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted(), ["in.docx", "out.docx"])
    }

    /// Filesystems without exclusive rename (exFAT, FAT) return ENOTSUP; the
    /// write falls back to an existence check plus a plain rename.
    func testRenameFallsBackWhenExclusiveRenameIsUnsupported() throws {
        let dir = try tempDir()
        let input = dir.appendingPathComponent("in.docx")
        let output = dir.appendingPathComponent("out.docx")
        _ = try samplePackage(at: input)
        let saved = DocxPackage.exclusiveRename
        DocxPackage.exclusiveRename = { _, _ in errno = ENOTSUP; return -1 }
        defer { DocxPackage.exclusiveRename = saved }
        try DocxPackage.rewriteDocument(input: input, output: output, force: false) { d, _ in d }
        XCTAssertEqual(try DocxPackage.read(from: output).count, 5)
        let second = dir.appendingPathComponent("out2.docx")
        XCTAssertThrowsError(try DocxPackage.rewriteDocument(input: input, output: second, force: false) { d, _ in
            try Data("someone else".utf8).write(to: second)
            return d
        }) {
            XCTAssertEqual($0 as? DocxPackageError, .outputExists(second.path))
        }
        XCTAssertEqual(try Data(contentsOf: second), Data("someone else".utf8))
    }

    func testFallbackWritesTheOutputUnderEINVAL() throws {
        let dir = try tempDir()
        let input = dir.appendingPathComponent("in.docx")
        let output = dir.appendingPathComponent("out.docx")
        _ = try samplePackage(at: input)
        let saved = DocxPackage.exclusiveRename
        DocxPackage.exclusiveRename = { _, _ in errno = EINVAL; return -1 }
        defer { DocxPackage.exclusiveRename = saved }
        try DocxPackage.rewriteDocument(input: input, output: output, force: false) { d, _ in d }
        XCTAssertEqual(try DocxPackage.read(from: output).count, 5)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted(), ["in.docx", "out.docx"])
    }

    /// A dangling symbolic link at the output is an existing output: the
    /// fallback checks the link itself, not its (missing) target.
    func testFallbackRefusesADanglingSymbolicLinkAtTheOutput() throws {
        for code in [ENOTSUP, EINVAL] {
            let dir = try tempDir()
            let input = dir.appendingPathComponent("in.docx")
            let output = dir.appendingPathComponent("out.docx")
            let target = dir.appendingPathComponent("missing.docx").path
            _ = try samplePackage(at: input)
            let saved = DocxPackage.exclusiveRename
            DocxPackage.exclusiveRename = { _, _ in errno = code; return -1 }
            defer { DocxPackage.exclusiveRename = saved }
            XCTAssertThrowsError(try DocxPackage.rewriteDocument(input: input, output: output, force: false) { d, _ in
                try FileManager.default.createSymbolicLink(atPath: output.path, withDestinationPath: target)
                return d
            }) {
                XCTAssertEqual($0 as? DocxPackageError, .outputExists(output.path), "errno \(code)")
            }
            XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: output.path), target)
        }
    }

    func testADanglingSymbolicLinkOutputIsRefusedBeforeAnyWork() throws {
        let dir = try tempDir()
        let input = dir.appendingPathComponent("in.docx")
        let output = dir.appendingPathComponent("out.docx")
        _ = try samplePackage(at: input)
        try FileManager.default.createSymbolicLink(atPath: output.path, withDestinationPath: dir.appendingPathComponent("missing").path)
        var transformed = false
        XCTAssertThrowsError(try DocxPackage.rewriteDocument(input: input, output: output, force: false) { d, _ in
            transformed = true
            return d
        }) {
            XCTAssertEqual($0 as? DocxPackageError, .outputExists(output.path))
        }
        XCTAssertFalse(transformed)
    }

    /// The temporary file lives in a private (0700) directory under a short
    /// fixed name: its content is never readable by others while it is
    /// written, and a long output name cannot push it past the name limit.
    func testTemporaryFileIsPrivateAndShortAndLeavesNothingBehind() throws {
        let dir = try tempDir()
        let input = dir.appendingPathComponent("in.docx")
        let name = String(repeating: "表", count: 80) + ".docx"   // 245 bytes, a legal name
        let output = dir.appendingPathComponent(name)
        _ = try samplePackage(at: input)
        var observed: (mode: Int, name: String)?
        let saved = DocxPackage.exclusiveRename
        DocxPackage.exclusiveRename = { from, to in
            let parent = (from as NSString).deletingLastPathComponent
            let mode = (try? FileManager.default.attributesOfItem(atPath: parent)[.posixPermissions] as? NSNumber)?.intValue
            observed = (mode ?? -1, (from as NSString).lastPathComponent)
            return saved(from, to)
        }
        defer { DocxPackage.exclusiveRename = saved }
        try DocxPackage.rewriteDocument(input: input, output: output, force: false) { d, _ in d }
        XCTAssertEqual(observed?.mode, 0o700)
        XCTAssertLessThanOrEqual(observed?.name.utf8.count ?? .max, 16)
        XCTAssertEqual(try DocxPackage.read(from: output).count, 5)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted(), ["in.docx", name].sorted())
    }

    func testFailedRenameLeavesNoTemporaryDirectory() throws {
        let dir = try tempDir()
        let input = dir.appendingPathComponent("in.docx")
        let output = dir.appendingPathComponent("out.docx")
        _ = try samplePackage(at: input)
        let saved = DocxPackage.exclusiveRename
        DocxPackage.exclusiveRename = { _, _ in errno = EIO; return -1 }
        defer { DocxPackage.exclusiveRename = saved }
        XCTAssertThrowsError(try DocxPackage.rewriteDocument(input: input, output: output, force: false) { d, _ in d }) {
            guard case .writeFailed = $0 as? DocxPackageError else { return XCTFail("\($0)") }
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), ["in.docx"])
    }

    /// Only the permission bits are copied: setuid/setgid/sticky are not.
    func testOutputDoesNotCopySpecialModeBits() throws {
        let dir = try tempDir()
        let input = dir.appendingPathComponent("in.docx")
        let output = dir.appendingPathComponent("out.docx")
        _ = try samplePackage(at: input)
        try FileManager.default.setAttributes([.posixPermissions: 0o4750], ofItemAtPath: input.path)
        try DocxPackage.rewriteDocument(input: input, output: output, force: false) { d, _ in d }
        let mode = try FileManager.default.attributesOfItem(atPath: output.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(mode?.intValue, 0o750)
    }

    func testOutputKeepsTheInputPermissions() throws {
        let dir = try tempDir()
        let input = dir.appendingPathComponent("in.docx")
        let output = dir.appendingPathComponent("out.docx")
        _ = try samplePackage(at: input)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: input.path)
        try DocxPackage.rewriteDocument(input: input, output: output, force: false) { d, _ in d }
        let mode = try FileManager.default.attributesOfItem(atPath: output.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(mode?.intValue, 0o600)
    }

    func testSymbolicLinkEntryIsRefused() throws {
        let dir = try tempDir()
        let input = dir.appendingPathComponent("in.docx")
        let archive = try Archive(url: input, accessMode: .create)
        try archive.addEntry(with: "word/document.xml", type: .file, uncompressedSize: Int64(4),
                             provider: { _, _ in Data("<a/>".utf8) })
        try archive.addEntry(with: "word/link", type: .symlink, uncompressedSize: Int64(9),
                             provider: { _, _ in Data("/etc/host".utf8) })
        XCTAssertThrowsError(try DocxPackage.read(from: input)) {
            guard case .unreadable = $0 as? DocxPackageError else { return XCTFail("\($0)") }
        }
    }

    func testForceReplacesTheOutput() throws {
        let dir = try tempDir()
        let input = dir.appendingPathComponent("in.docx")
        let output = dir.appendingPathComponent("out.docx")
        _ = try samplePackage(at: input)
        try Data("old".utf8).write(to: output)
        try DocxPackage.rewriteDocument(input: input, output: output, force: true) { d, _ in d }
        XCTAssertEqual(try DocxPackage.read(from: output).count, 5)
    }

    func testFailedTransformLeavesNoOutputAndNoTemporaryFile() throws {
        let dir = try tempDir()
        let input = dir.appendingPathComponent("in.docx")
        let output = dir.appendingPathComponent("out.docx")
        _ = try samplePackage(at: input)
        XCTAssertThrowsError(try DocxPackage.rewriteDocument(input: input, output: output, force: false) { document, _ in
            Data(try FormPlan(removals: ["DEADBEEF"]).apply(toDocumentXML: Array(document)).documentXML)
        })
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted(), ["in.docx"])
    }

    func testOversizedPackageIsRefused() throws {
        let dir = try tempDir()
        let input = dir.appendingPathComponent("in.docx")
        _ = try samplePackage(at: input)
        XCTAssertThrowsError(try DocxPackage.read(from: input, limit: 1024)) {
            XCTAssertEqual($0 as? DocxPackageError, .tooLarge(limit: 1024))
        }
    }

    func testMissingMainPartIsReported() throws {
        let dir = try tempDir()
        let input = dir.appendingPathComponent("in.docx")
        try DocxPackage.write([DocxPackage.Entry(path: "a.xml", data: Data("<a/>".utf8))], to: input)
        XCTAssertThrowsError(try DocxPackage.rewriteDocument(input: input, output: dir.appendingPathComponent("o.docx"),
                                                             force: false) { d, _ in d }) {
            XCTAssertEqual($0 as? DocxPackageError, .missingPart("word/document.xml"))
        }
    }
}
