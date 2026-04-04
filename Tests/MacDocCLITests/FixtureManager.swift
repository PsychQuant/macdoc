import Foundation
import CoreGraphics
import CoreText

/// 程式化產生測試 fixture 檔案
enum FixtureManager {

    /// 暫存目錄
    static let fixtureDir: URL = {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("macdoc-e2e-fixtures")
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// 輸出暫存目錄
    static let outputDir: URL = {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("macdoc-e2e-output")
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// 清理所有暫存檔案
    static func cleanup() {
        try? FileManager.default.removeItem(at: fixtureDir)
        try? FileManager.default.removeItem(at: outputDir)
    }

    // MARK: - Fixture Generators

    static func markdownFile() -> String {
        let url = fixtureDir.appendingPathComponent("test.md")
        let content = """
        # Test Heading

        This is a **bold** paragraph with *italic* text.

        ## Second Heading

        - Item 1
        - Item 2
        - Item 3

        A [link](https://example.com) and `inline code`.
        """
        try? content.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    static func htmlFile() -> String {
        let url = fixtureDir.appendingPathComponent("test.html")
        let content = """
        <h1>Test Document</h1>
        <p>This is a <strong>bold</strong> paragraph with <em>italic</em> text.</p>
        <h2>Second Section</h2>
        <ul>
        <li>Item 1</li>
        <li>Item 2</li>
        </ul>
        <p>A <u>underlined</u> word and <sup>superscript</sup>.</p>
        """
        try? content.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    static func srtFile() -> String {
        let url = fixtureDir.appendingPathComponent("test.srt")
        let content = """
        1
        00:00:01,000 --> 00:00:04,000
        Speaker 1: Hello, welcome to the meeting.

        2
        00:00:04,500 --> 00:00:08,000
        Speaker 2: Thank you for having me.

        3
        00:00:08,500 --> 00:00:12,000
        Speaker 1: Let's get started with the agenda.
        """
        try? content.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    static func bibFile() -> String {
        let url = fixtureDir.appendingPathComponent("test.bib")
        let content = """
        @article{smith2024,
          author = {Smith, John and Doe, Jane},
          title = {A Study on Testing},
          journal = {Journal of Software Engineering},
          year = {2024},
          volume = {42},
          pages = {1--20},
          doi = {10.1234/jse.2024.001}
        }

        @book{johnson2023,
          author = {Johnson, Robert},
          title = {Introduction to Software Testing},
          publisher = {Academic Press},
          year = {2023},
          address = {New York}
        }
        """
        try? content.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    static func texFile() -> String {
        let url = fixtureDir.appendingPathComponent("test.tex")
        let content = #"""
        \documentclass{article}
        \begin{document}
        \title{Test Document}
        \maketitle

        \section{Introduction}
        This is a test document for macdoc E2E testing.

        \subsection{Details}
        Some mathematical content: $E = mc^2$.

        \end{document}
        """#
        try? content.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    static func docxFile() -> String {
        let url = fixtureDir.appendingPathComponent("test.docx")
        createMinimalDocx(at: url)
        return url.path
    }

    static func pdfFile() -> String {
        let url = fixtureDir.appendingPathComponent("test.pdf")
        createMinimalPDF(at: url)
        return url.path
    }

    /// 輸出路徑（用於 --output flag 測試）
    static func outputPath(_ filename: String) -> String {
        outputDir.appendingPathComponent(filename).path
    }

    // MARK: - Minimal DOCX Generator

    private static func createMinimalDocx(at url: URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("docx-gen-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let contentTypes = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
        </Types>
        """

        let rels = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
        </Relationships>
        """

        let documentXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            <w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr><w:r><w:t>Test Heading</w:t></w:r></w:p>
            <w:p><w:r><w:t>This is a test paragraph for E2E testing.</w:t></w:r></w:p>
            <w:p><w:r><w:rPr><w:b/></w:rPr><w:t>Bold text</w:t></w:r><w:r><w:t> and normal text.</w:t></w:r></w:p>
          </w:body>
        </w:document>
        """

        try? contentTypes.write(to: tempDir.appendingPathComponent("[Content_Types].xml"), atomically: true, encoding: .utf8)

        let relsDir = tempDir.appendingPathComponent("_rels")
        try? FileManager.default.createDirectory(at: relsDir, withIntermediateDirectories: true)
        try? rels.write(to: relsDir.appendingPathComponent(".rels"), atomically: true, encoding: .utf8)

        let wordDir = tempDir.appendingPathComponent("word")
        try? FileManager.default.createDirectory(at: wordDir, withIntermediateDirectories: true)
        try? documentXML.write(to: wordDir.appendingPathComponent("document.xml"), atomically: true, encoding: .utf8)

        // ZIP it — use /usr/bin/zip from inside the temp directory
        let zipProcess = Process()
        zipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zipProcess.arguments = ["-r", "-q", url.path, "."]
        zipProcess.currentDirectoryURL = tempDir
        try? zipProcess.run()
        zipProcess.waitUntilExit()
    }

    // MARK: - Minimal PDF Generator

    private static func createMinimalPDF(at url: URL) {
        guard let context = CGContext(url as CFURL, mediaBox: nil, nil) else { return }

        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        context.beginPage(mediaBox: &mediaBox)

        let text = "Test PDF for E2E Testing"
        let font = CTFontCreateWithName("Helvetica" as CFString, 24, nil)
        let attributes: [String: Any] = [
            kCTFontAttributeName as String: font
        ]
        let attrString = CFAttributedStringCreate(nil, text as CFString, attributes as CFDictionary)!
        let line = CTLineCreateWithAttributedString(attrString)

        context.textPosition = CGPoint(x: 72, y: 700)
        CTLineDraw(line, context)

        context.endPage()
        context.closePDF()
    }
}
