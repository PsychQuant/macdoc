// DocxPackageTests.swift — "Parts other than the main part are unchanged" and
// the output handling of `word form apply` (#249).

import XCTest
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
