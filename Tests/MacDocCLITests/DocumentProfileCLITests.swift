import XCTest
import OOXMLSwift

final class DocumentProfileCLITests: XCTestCase {
    /// Word ML 固定命名空間；rFonts／docDefaults／sectPr 等節點皆掛在此命名空間下。
    private static let wordNamespace = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"

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

    /// §196 編碼／缺欄位矩陣專用：word/styles.xml 的位元組由呼叫端指定，document.xml
    /// 沿用 `template(in:)` 相同的最小 sectPr。獨立於 `template(in:)`，不牽動既有通過案例。
    private func officialTemplate(in dir: URL, stylesBytes: Data, suffix: String) throws -> URL {
        let w = Self.wordNamespace
        let source = dir.appendingPathComponent("template-parts-\(suffix)")
        let documentXML = "<w:document xmlns:w=\"\(w)\"><w:body><w:p><w:r><w:t>PRIVATE TEMPLATE TEXT</w:t></w:r></w:p><w:sectPr><w:pgSz w:w=\"11906\" w:h=\"16838\"/><w:pgMar w:top=\"1440\" w:right=\"1800\" w:bottom=\"1440\" w:left=\"1800\" w:header=\"720\" w:footer=\"720\" w:gutter=\"0\"/></w:sectPr></w:body></w:document>"
        let parts: [(path: String, data: Data)] = [
            ("word/styles.xml", stylesBytes),
            ("word/document.xml", Data(documentXML.utf8)),
        ]
        for (path, data) in parts {
            let file = source.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file)
        }
        let url = dir.appendingPathComponent("Normal-\(suffix).dotm")
        try ZipHelper.zipToData(source).write(to: url)
        return url
    }

    // MARK: - Namespace-aware XML 斷言 helpers（issue #196：取代 String.contains 的字型比對）

    /// 解析 part bytes 為 OOXMLSwift 公開的 lossless tree，回傳文件節點。
    private func parseXml(_ data: Data) throws -> XmlNode {
        try XmlTreeReader.parse(data).root
    }

    /// 依 local name 逐層下鑽（限定 w: 命名空間），對應不到就回傳 nil——
    /// 呼叫端用 XCTUnwrap 斷言「該節點必須存在」。
    private func descendant(_ root: XmlNode, _ path: String...) -> XmlNode? {
        var current = root
        for name in path {
            guard let next = current.children.first(where: {
                $0.kind == .element && $0.namespaceURI == Self.wordNamespace && $0.localName == name
            }) else { return nil }
            current = next
        }
        return current
    }

    /// 收集整棵樹裡所有符合 local name 的 w: 命名空間元素（不限層級）。
    private func allElements(_ root: XmlNode, localName: String) -> [XmlNode] {
        var found: [XmlNode] = []
        func walk(_ node: XmlNode) {
            if node.kind == .element, node.namespaceURI == Self.wordNamespace, node.localName == localName {
                found.append(node)
            }
            for child in node.children { walk(child) }
        }
        walk(root)
        return found
    }

    /// 整棵樹裡所有 `w:rFonts` 元素的 ascii／hAnsi／eastAsia／cs 四軸屬性值集合——
    /// 用來斷言「特定字型名稱完全沒被寫進任何 rFonts 軸」，取代 String.contains 對整份
    /// 檔案文字的粗略掃描（後者連 "Calibri Light" 這類子字串命中都分不清）。
    private func rFontsAxisValues(_ data: Data) throws -> Set<String> {
        let root = try parseXml(data)
        var values = Set<String>()
        for node in allElements(root, localName: "rFonts") {
            for axis in ["ascii", "hAnsi", "eastAsia", "cs"] {
                if let value = node.attributeValue(prefix: "w", localName: axis) { values.insert(value) }
            }
        }
        return values
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
            let parts = try RawPartChannel.readAllParts(from: official)
            let stylesRoot = try parseXml(try XCTUnwrap(parts["word/styles.xml"], input))
            // namespace-aware：只認 docDefaults/rPrDefault/rPr/rFonts 的 eastAsia 軸，
            // 不對整份檔案文字做 String.contains("DFKai-SB")（issue #196）。
            let docDefaultsRFonts = try XCTUnwrap(
                descendant(stylesRoot, "docDefaults", "rPrDefault", "rPr", "rFonts"), input)
            XCTAssertEqual(docDefaultsRFonts.attributeValue(prefix: "w", localName: "eastAsia"), "DFKai-SB", input)
            // official profile 只明示設定 eastAsia 這一軸；範本沒宣告的 ascii／hAnsi 不該被
            // 官方注入行為憑空生成——區分「呼叫端刻意設定」與「未設定」，不是靠字型值猜意圖。
            XCTAssertNil(docDefaultsRFonts.attributeValue(prefix: "w", localName: "ascii"), input)
            XCTAssertNil(docDefaultsRFonts.attributeValue(prefix: "w", localName: "hAnsi"), input)
            let docDefaultsSz = try XCTUnwrap(
                descendant(stylesRoot, "docDefaults", "rPrDefault", "rPr", "sz"), input)
            XCTAssertEqual(docDefaultsSz.attributeValue(prefix: "w", localName: "val"), "24", input)
            let documentData = try XCTUnwrap(parts["word/document.xml"], input)
            let documentRoot = try parseXml(documentData)
            let pgSz = try XCTUnwrap(descendant(documentRoot, "body", "sectPr", "pgSz"), input)
            XCTAssertEqual(pgSz.attributeValue(prefix: "w", localName: "w"), "11906", input)
            XCTAssertFalse(String(decoding: documentData, as: UTF8.self).contains("PRIVATE TEMPLATE TEXT"))

            let inherit = dir.appendingPathComponent("inherit-\(index).docx")
            let override = try CLITestHelper.run(["convert", "--to", "docx", input, "--output", inherit.path, "--document-config", config.path, "--profile", "inherit"])
            XCTAssertEqual(override.exitCode, 0, override.stderr)
            let inheritedParts = try RawPartChannel.readAllParts(from: inherit)
            let inheritedStylesFonts = try rFontsAxisValues(try XCTUnwrap(inheritedParts["word/styles.xml"], input))
            XCTAssertFalse(inheritedStylesFonts.contains("Calibri"), input)
            XCTAssertFalse(inheritedStylesFonts.contains("Times New Roman"), input)
            if input.hasSuffix(".md") {
                let inheritedDocumentFonts = try rFontsAxisValues(try XCTUnwrap(inheritedParts["word/document.xml"], input))
                XCTAssertTrue(inheritedDocumentFonts.contains("Menlo"), input)
            }
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
            let stylesData = try XCTUnwrap(RawPartChannel.readAllParts(from: output)["word/styles.xml"])
            let styleFonts = try rFontsAxisValues(stylesData)
            XCTAssertFalse(styleFonts.contains("Calibri"), input)
            XCTAssertFalse(styleFonts.contains("Times New Roman"), input)
            XCTAssertFalse(styleFonts.contains("DFKai-SB"), input)
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

    // MARK: - §196 字型／編碼合成矩陣（CLI 層，不牽動 ooxml-swift 生產程式碼）

    /// 範本完全缺 `docDefaults` 應在 `import-official` 這關就被拒絕——不留到套用 profile
    /// 時才出錯，也不讓半成品快照留在設定檔內。
    func testImportOfficialRejectsTemplateMissingDocDefaults() throws {
        let dir = try directory(), config = dir.appendingPathComponent("config.json")
        let w = Self.wordNamespace
        let stylesXML = "<w:styles xmlns:w=\"\(w)\"><w:style w:type=\"paragraph\" w:default=\"1\" w:styleId=\"Normal\"><w:name w:val=\"Normal\"/></w:style></w:styles>"
        let source = try officialTemplate(in: dir, stylesBytes: Data(stylesXML.utf8), suffix: "no-docdefaults")
        let imported = try CLITestHelper.run(["config", "document", "import-official", "--config", config.path, "--template", source.path])
        XCTAssertNotEqual(imported.exitCode, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: config.path))
    }

    /// 範本有 `docDefaults` 但缺 `pPrDefault` 同樣應被拒絕——兩個必要欄位分開驗證，
    /// 避免「只測了其中一種缺漏就當作整個矩陣過了」。
    func testImportOfficialRejectsTemplateMissingPPrDefault() throws {
        let dir = try directory(), config = dir.appendingPathComponent("config.json")
        let w = Self.wordNamespace
        let stylesXML = "<w:styles xmlns:w=\"\(w)\"><w:docDefaults><w:rPrDefault><w:rPr><w:sz w:val=\"24\"/></w:rPr></w:rPrDefault></w:docDefaults><w:style w:type=\"paragraph\" w:default=\"1\" w:styleId=\"Normal\"><w:name w:val=\"Normal\"/></w:style></w:styles>"
        let source = try officialTemplate(in: dir, stylesBytes: Data(stylesXML.utf8), suffix: "no-pprdefault")
        let imported = try CLITestHelper.run(["config", "document", "import-official", "--config", config.path, "--template", source.path])
        XCTAssertNotEqual(imported.exitCode, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: config.path))
    }

    /// UTF-8 BOM 前綴的 styles.xml（部分工具，如 LibreOffice，會寫出這種位元組序）應被
    /// 接受，且套用 official profile 後 eastAsia 軸仍正確落在 DFKai-SB——驗證編碼接受邊界，
    /// 不是拒絕矩陣的另一半。
    func testImportOfficialAcceptsUtf8BomPrefixedStylesXml() throws {
        let dir = try directory(), config = dir.appendingPathComponent("config.json")
        let w = Self.wordNamespace
        let bom = Data([0xEF, 0xBB, 0xBF])
        let stylesXML = "<w:styles xmlns:w=\"\(w)\"><w:docDefaults><w:rPrDefault><w:rPr><w:sz w:val=\"24\"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr/></w:pPrDefault></w:docDefaults><w:style w:type=\"paragraph\" w:default=\"1\" w:styleId=\"Normal\"><w:name w:val=\"Normal\"/></w:style></w:styles>"
        let source = try officialTemplate(in: dir, stylesBytes: bom + Data(stylesXML.utf8), suffix: "bom")
        let imported = try CLITestHelper.run(["config", "document", "import-official", "--config", config.path, "--template", source.path])
        XCTAssertEqual(imported.exitCode, 0, imported.stderr)
        let official = dir.appendingPathComponent("official-bom.docx")
        let result = try CLITestHelper.run(["convert", "--to", "docx", FixtureManager.markdownFile(), "--output", official.path, "--document-config", config.path, "--profile", "official"])
        XCTAssertEqual(result.exitCode, 0, result.stderr)
        let stylesData = try XCTUnwrap(RawPartChannel.readAllParts(from: official)["word/styles.xml"])
        let stylesRoot = try parseXml(stylesData)
        let docDefaultsRFonts = try XCTUnwrap(descendant(stylesRoot, "docDefaults", "rPrDefault", "rPr", "rFonts"))
        XCTAssertEqual(docDefaultsRFonts.attributeValue(prefix: "w", localName: "eastAsia"), "DFKai-SB")
    }

    /// 範本 docDefaults 明示設定 ascii／hAnsi／cs（呼叫端刻意選擇的字型）時，official 注入
    /// 只覆寫 eastAsia 這一軸，其餘三軸原樣保留——區分「factory 預設」與「呼叫端明示 setter」，
    /// 不是靠字型值是否相同去猜呼叫端的意圖。
    func testOfficialProfilePreservesExplicitCallerFontAxesAndOnlyOverridesEastAsia() throws {
        let dir = try directory(), config = dir.appendingPathComponent("config.json")
        let w = Self.wordNamespace
        let stylesXML = "<w:styles xmlns:w=\"\(w)\"><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii=\"PMingLiU\" w:hAnsi=\"PMingLiU\" w:eastAsia=\"MingLiU\" w:cs=\"PMingLiU\"/><w:sz w:val=\"24\"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr/></w:pPrDefault></w:docDefaults><w:style w:type=\"paragraph\" w:default=\"1\" w:styleId=\"Normal\"><w:name w:val=\"Normal\"/></w:style></w:styles>"
        let source = try officialTemplate(in: dir, stylesBytes: Data(stylesXML.utf8), suffix: "explicit-axes")
        let imported = try CLITestHelper.run(["config", "document", "import-official", "--config", config.path, "--template", source.path])
        XCTAssertEqual(imported.exitCode, 0, imported.stderr)
        let official = dir.appendingPathComponent("official-explicit-axes.docx")
        let result = try CLITestHelper.run(["convert", "--to", "docx", FixtureManager.markdownFile(), "--output", official.path, "--document-config", config.path, "--profile", "official"])
        XCTAssertEqual(result.exitCode, 0, result.stderr)
        let stylesData = try XCTUnwrap(RawPartChannel.readAllParts(from: official)["word/styles.xml"])
        let stylesRoot = try parseXml(stylesData)
        let docDefaultsRFonts = try XCTUnwrap(descendant(stylesRoot, "docDefaults", "rPrDefault", "rPr", "rFonts"))
        XCTAssertEqual(docDefaultsRFonts.attributeValue(prefix: "w", localName: "ascii"), "PMingLiU")
        XCTAssertEqual(docDefaultsRFonts.attributeValue(prefix: "w", localName: "hAnsi"), "PMingLiU")
        XCTAssertEqual(docDefaultsRFonts.attributeValue(prefix: "w", localName: "cs"), "PMingLiU")
        // eastAsia 這一軸永遠被 officialEastAsianFont 覆蓋，即使範本本來就設定了別的中文
        // 字型——這是 official profile 的既定語意，不是「猜」使用者想要哪個中文字型。
        XCTAssertEqual(docDefaultsRFonts.attributeValue(prefix: "w", localName: "eastAsia"), "DFKai-SB")
    }

    // MARK: - config document gc（issue #194：不可變快照的清理策略）

    /// 預設只列出、不刪除；`--force` 才刪。被 officialSnapshot 引用的快照與
    /// profiles/ 內其他檔案永遠不碰。刪除是不可逆動作，所以「沒給旗標」必須是安全的那一側。
    func testDocumentGcIsDryRunByDefaultAndForceDeletesOnlyUnreferencedSnapshots() throws {
        let dir = try directory(), config = dir.appendingPathComponent("config.json")
        let imported = try CLITestHelper.run(["config", "document", "import-official", "--config", config.path, "--template", template(in: dir).path])
        XCTAssertEqual(imported.exitCode, 0, imported.stderr)
        let referenced = try XCTUnwrap(DocumentProfileStore(configURL: config).settings().officialSnapshot)
        let profiles = dir.appendingPathComponent("profiles")
        let stale = profiles.appendingPathComponent("official-stale.json")
        let unrelated = profiles.appendingPathComponent("notes.txt")
        try Data("{}".utf8).write(to: stale)
        try Data("keep".utf8).write(to: unrelated)

        let preview = try CLITestHelper.run(["config", "document", "gc", "--config", config.path])
        XCTAssertEqual(preview.exitCode, 0, preview.stderr)
        XCTAssertTrue(preview.stdout.contains("profiles/official-stale.json"), preview.stdout)
        XCTAssertFalse(preview.stdout.contains(referenced), preview.stdout)
        XCTAssertTrue(preview.stdout.contains("--force"), "dry-run 要告訴使用者怎麼真的刪：\(preview.stdout)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: stale.path), "dry-run 不得刪檔")

        let forced = try CLITestHelper.run(["config", "document", "gc", "--force", "--config", config.path])
        XCTAssertEqual(forced.exitCode, 0, forced.stderr)
        XCTAssertTrue(forced.stdout.contains("profiles/official-stale.json"), forced.stdout)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stale.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent(referenced).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))

        let again = try CLITestHelper.run(["config", "document", "gc", "--force", "--config", config.path])
        XCTAssertEqual(again.exitCode, 0, again.stderr)
        XCTAssertFalse(again.stdout.contains("official-"), "已無可清理的快照：\(again.stdout)")
    }

    /// 設定檔損毀時無法判斷哪個快照仍被引用，必須在刪除任何東西之前失敗。
    func testDocumentGcRefusesCorruptConfigWithoutDeleting() throws {
        let dir = try directory(), config = dir.appendingPathComponent("config.json")
        let profiles = dir.appendingPathComponent("profiles")
        try FileManager.default.createDirectory(at: profiles, withIntermediateDirectories: true)
        let snapshot = profiles.appendingPathComponent("official-a.json")
        try Data("{}".utf8).write(to: snapshot)
        try Data(#"{"document":{"officialSnapshot":"../escape.json"}}"#.utf8).write(to: config)

        let result = try CLITestHelper.run(["config", "document", "gc", "--force", "--config", config.path])
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: snapshot.path))
    }
}
