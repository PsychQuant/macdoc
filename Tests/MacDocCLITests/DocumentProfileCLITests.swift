import XCTest
import OOXMLSwift

final class DocumentProfileCLITests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("profile-cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func template(in dir: URL) throws -> URL {
        let source = dir.appendingPathComponent("template-parts")
        let w = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
        let parts = [
            "word/styles.xml": "<w:styles xmlns:w=\"\(w)\"><w:docDefaults><w:rPrDefault><w:rPr><w:sz w:val=\"24\"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr/></w:pPrDefault></w:docDefaults><w:style w:type=\"paragraph\" w:default=\"1\" w:styleId=\"Normal\"><w:name w:val=\"Normal\"/></w:style></w:styles>",
            "word/document.xml": "<w:document xmlns:w=\"\(w)\"><w:body><w:p><w:r><w:t>PRIVATE TEMPLATE TEXT</w:t></w:r></w:p><w:sectPr><w:pgSz w:w=\"11906\" w:h=\"16838\"/><w:pgMar w:top=\"1440\" w:right=\"1800\" w:bottom=\"1440\" w:left=\"1800\" w:header=\"720\" w:footer=\"720\" w:gutter=\"0\"/></w:sectPr></w:body></w:document>"
        ]
        for (path, xml) in parts {
            let file = source.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(xml.utf8).write(to: file)
        }
        let url = dir.appendingPathComponent("Normal.dotm")
        try ZipHelper.zipToData(source).write(to: url)
        return url
    }

    func testConfigCommandsPreserveSecretsWithoutDisplayingThem() throws {
        let dir = try directory(), config = dir.appendingPathComponent("config.json")
        try Data(#"{"agent":"secret-agent","ocrHosts":{"private":"private-address"},"document":{"extension":42}}"#.utf8).write(to: config)
        let source = try template(in: dir), before = try Data(contentsOf: source)
        let imported = try CLITestHelper.run(["config", "document", "import-official", "--config", config.path, "--template", source.path])
        XCTAssertEqual(imported.exitCode, 0, imported.stderr)
        let store = DocumentProfileStore(configURL: config)
        XCTAssertEqual(try store.settings().defaultProfile, .inherit)
        XCTAssertEqual(try Data(contentsOf: source), before)
        let selected = try CLITestHelper.run(["config", "document", "set-default", "official", "--config", config.path])
        XCTAssertEqual(selected.exitCode, 0, selected.stderr)
        let shown = try CLITestHelper.run(["config", "document", "show", "--config", config.path])
        XCTAssertEqual(shown.exitCode, 0, shown.stderr)
        XCTAssertTrue(shown.stdout.contains("official"))
        XCTAssertFalse(shown.stdout.contains("secret-agent"))
        XCTAssertFalse(shown.stdout.contains("private-address"))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: config)) as? [String: Any])
        XCTAssertEqual(root["agent"] as? String, "secret-agent")
        XCTAssertEqual((root["document"] as? [String: Any])?["extension"] as? Int, 42)
        let saved = try Data(contentsOf: config)
        let invalid = try CLITestHelper.run(["config", "document", "set-default", "unknown", "--config", config.path])
        XCTAssertNotEqual(invalid.exitCode, 0)
        XCTAssertEqual(try Data(contentsOf: config), saved)
    }

    func testAllFourConvertersUseCreationDefaultAndExplicitInherit() throws {
        let dir = try directory(), config = dir.appendingPathComponent("config.json")
        let store = DocumentProfileStore(configURL: config)
        try store.importOfficial(from: template(in: dir))
        try store.setDefaultProfile(.official)
        let inputs = [FixtureManager.htmlFile(), FixtureManager.markdownFile(), FixtureManager.pdfFile(), FixtureManager.texFile()]
        for (index, input) in inputs.enumerated() {
            let official = dir.appendingPathComponent("official-\(index).docx")
            let result = try CLITestHelper.run(["convert", "--to", "docx", input, "--output", official.path, "--document-config", config.path])
            XCTAssertEqual(result.exitCode, 0, result.stderr)
            let parts = try RawPartChannel.readAllParts(from: official).mapValues { String(decoding: $0, as: UTF8.self) }
            XCTAssertTrue(parts["word/styles.xml"]!.contains("DFKai-SB"), input)
            XCTAssertTrue(parts["word/styles.xml"]!.contains("w:val=\"24\""), input)
            XCTAssertTrue(parts["word/document.xml"]!.contains("w:w=\"11906\""), input)
            XCTAssertFalse(parts["word/document.xml"]!.contains("PRIVATE TEMPLATE TEXT"))
            let inherit = dir.appendingPathComponent("inherit-\(index).docx")
            let override = try CLITestHelper.run(["convert", "--to", "docx", input, "--output", inherit.path, "--document-config", config.path, "--profile", "inherit"])
            XCTAssertEqual(override.exitCode, 0, override.stderr)
            let inherited = try RawPartChannel.readAllParts(from: inherit).mapValues { String(decoding: $0, as: UTF8.self) }
            XCTAssertFalse(inherited["word/styles.xml"]!.contains("Calibri"), input)
            XCTAssertFalse(inherited["word/styles.xml"]!.contains("Times New Roman"), input)
            if input.hasSuffix(".md") { XCTAssertTrue(inherited["word/document.xml"]!.contains("Menlo")) }
        }
    }

    func testConvertFailurePreservesOutputAndExplicitInheritBypassesCorruptConfig() throws {
        let dir = try directory(), config = dir.appendingPathComponent("config.json"), output = dir.appendingPathComponent("out.docx")
        let sentinel = Data("existing document bytes".utf8)
        try sentinel.write(to: output)
        for json in ["broken", #"{"document":{"defaultProfile":"official"}}"#] {
            try Data(json.utf8).write(to: config)
            let result = try CLITestHelper.run(["convert", "--to", "docx", FixtureManager.markdownFile(), "--output", output.path, "--document-config", config.path])
            XCTAssertNotEqual(result.exitCode, 0)
            XCTAssertEqual(try Data(contentsOf: output), sentinel)
        }
        try Data("broken".utf8).write(to: config)
        let result = try CLITestHelper.run(["convert", "--to", "docx", FixtureManager.markdownFile(), "--output", output.path, "--document-config", config.path, "--profile", "inherit"])
        XCTAssertEqual(result.exitCode, 0, result.stderr)
        XCTAssertNotEqual(try Data(contentsOf: output), sentinel)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: dir.path).contains { $0.contains("staging") })
    }

    func testAllFourConvertersDefaultInheritPassesReadbackBeforePublication() throws {
        let dir = try directory(), config = dir.appendingPathComponent("absent-config.json")
        for (index, input) in [FixtureManager.htmlFile(), FixtureManager.markdownFile(), FixtureManager.pdfFile(), FixtureManager.texFile()].enumerated() {
            let output = dir.appendingPathComponent("default-\(index).docx")
            try Data("previous output".utf8).write(to: output)
            let result = try CLITestHelper.run(["convert", "--to", "docx", input, "--output", output.path, "--document-config", config.path])
            XCTAssertEqual(result.exitCode, 0, result.stderr)
            var readback = try DocxReader.read(from: output)
            defer { readback.close() }
            let styles = String(decoding: try XCTUnwrap(RawPartChannel.readAllParts(from: output)["word/styles.xml"]), as: UTF8.self)
            XCTAssertFalse(styles.contains("Calibri"), input)
            XCTAssertFalse(styles.contains("Times New Roman"), input)
            XCTAssertFalse(styles.contains("DFKai-SB"), input)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: config.path))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: dir.path).contains { $0.contains("staging") })
    }

    func testUnsupportedProfileRoutesAndUnknownValuesFail() throws {
        let dir = try directory(), output = dir.appendingPathComponent("out.html")
        let sentinel = Data("old HTML".utf8)
        try sentinel.write(to: output)
        let nonDocx = try CLITestHelper.run(["convert", "--to", "html", FixtureManager.markdownFile(), "--output", output.path, "--profile", "inherit"])
        XCTAssertNotEqual(nonDocx.exitCode, 0)
        XCTAssertEqual(try Data(contentsOf: output), sentinel)
        let unknown = try CLITestHelper.run(["convert", "--to", "docx", FixtureManager.markdownFile(), "--output", output.path, "--profile", "unknown"])
        XCTAssertNotEqual(unknown.exitCode, 0)
        XCTAssertEqual(try Data(contentsOf: output), sentinel)
    }

    func testConvertPreservesLockedFileAndDirectoryOutput() throws {
        let dir = try directory(), config = dir.appendingPathComponent("missing-config.json")
        let output = dir.appendingPathComponent("locked.docx")
        let sentinel = Data("locked bytes".utf8)
        try sentinel.write(to: output)
        let lock = WordLock.lockFileURL(for: output)
        try Data("Word lock".utf8).write(to: lock)
        let locked = try CLITestHelper.run(["convert", "--to", "docx", FixtureManager.markdownFile(), "--output", output.path, "--document-config", config.path])
        XCTAssertNotEqual(locked.exitCode, 0)
        XCTAssertEqual(try Data(contentsOf: output), sentinel)
        let folder = dir.appendingPathComponent("folder.docx")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let child = folder.appendingPathComponent("keep.txt")
        try sentinel.write(to: child)
        let refused = try CLITestHelper.run(["convert", "--to", "docx", FixtureManager.markdownFile(), "--output", folder.path, "--document-config", config.path])
        XCTAssertNotEqual(refused.exitCode, 0)
        XCTAssertEqual(try Data(contentsOf: child), sentinel)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: dir.path).contains { $0.contains("staging") })
    }

    func testRenderIgnoresCreationDefaultAndProfilesBeforeVerification() throws {
        let dir = try directory(), config = dir.appendingPathComponent("config.json")
        let store = DocumentProfileStore(configURL: config)
        try store.importOfficial(from: template(in: dir))
        try store.setDefaultProfile(.official)
        let source = dir.appendingPathComponent("source.docx")
        var doc = WordDocument.emptyAuthoringDocument()
        try doc.apply(operations: [.appendParagraph(in: nil, paragraph: ParagraphPayload(text: "原文", paraId: "P1"))])
        try doc.writeAuthoringPackage(to: source)
        let script = dir.appendingPathComponent("source.mdocx.swift")
        let reversed = try CLITestHelper.run(["word", "reverse", source.path, "--to-mdocx", script.path])
        XCTAssertEqual(reversed.exitCode, 0, reversed.stderr)
        let output = dir.appendingPathComponent("output.docx")
        let arguments = ["word", "render", script.path, "--to-docx", output.path, "--document-config", config.path, "--verify-against", source.path, "--force"]
        let inherited = try CLITestHelper.run(arguments)
        XCTAssertEqual(inherited.exitCode, 0, inherited.stderr)
        let before = try Data(contentsOf: output)
        let changed = try CLITestHelper.run(arguments + ["--profile", "official"])
        XCTAssertNotEqual(changed.exitCode, 0)
        XCTAssertTrue(changed.stderr.contains("驗證失敗"), changed.stderr)
        XCTAssertEqual(try Data(contentsOf: output), before)
        let success = try CLITestHelper.run(["word", "render", script.path, "--to-docx", output.path, "--document-config", config.path, "--profile", "official", "--force"])
        XCTAssertEqual(success.exitCode, 0, success.stderr)
        let direct = dir.appendingPathComponent("direct.docx")
        _ = try scriptPipelineExecute(scriptPath: script.path, outputPath: direct.path, formattingProfile: store.resolve(explicit: .official, context: .existingDocument))
        XCTAssertEqual(try RawPartChannel.readAllParts(from: output), try RawPartChannel.readAllParts(from: direct))
        try Data("broken config".utf8).write(to: config)
        let ignored = try CLITestHelper.run(arguments)
        XCTAssertEqual(ignored.exitCode, 0, ignored.stderr)
    }
}
