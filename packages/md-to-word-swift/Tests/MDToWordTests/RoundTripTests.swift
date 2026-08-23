import XCTest
@testable import MDToWord
import OOXMLSwift
import WordToMD
import CommonConverterSwift

/// Bijection 驗證：
///   A: convert(convert⁻¹(w)) ≡ w   — Word → MD → Word → MD，兩次 MD 一致
///   B: convert⁻¹(convert(md)) ≡ md  — MD → Word → MD，round-trip 後 MD 一致
///   C: g ∘ f = id_{W*}              — WordDocument 等價驗證（需 Equatable）
final class RoundTripTests: XCTestCase {

    let forward = WordConverter()       // Word → MD
    let reverse = MarkdownToWordConverter()  // MD → Word

    // MARK: - Helpers

    /// Word → MD string（Tier 1，純 markdown）
    func toMarkdown(_ doc: WordDocument) throws -> String {
        try forward.convertToString(document: doc, options: .default)
    }

    /// Word → MD string（Layer B，含 HTML extensions）
    func toMarkdownHTML(_ doc: WordDocument) throws -> String {
        var options = ConversionOptions.default
        options.useHTMLExtensions = true
        return try forward.convertToString(document: doc, options: options)
    }

    /// 正規化 markdown：去尾空白、統一換行、壓縮連續空行、去頭尾空行
    func normalize(_ md: String) -> String {
        let lines = md.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        // 壓縮連續空行為單一空行
        var result: [String] = []
        var lastWasEmpty = false
        for line in lines {
            if line.isEmpty {
                if !lastWasEmpty {
                    result.append(line)
                }
                lastWasEmpty = true
            } else {
                result.append(line)
                lastWasEmpty = false
            }
        }

        return result.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // =========================================================
    // MARK: - Direction A: Word → MD → Word → MD
    // =========================================================

    func testRoundTripA_BasicParagraph() throws {
        // 1. 建構 WordDocument
        var doc = WordDocument()
        var para = Paragraph()
        para.runs = [Run(text: "Hello world")]
        doc.body.children.append(.paragraph(para))

        // 2. Word → MD
        let md1 = try toMarkdown(doc)

        // 3. MD → Word'
        let doc2 = try reverse.convertMarkdown(md1)

        // 4. Word' → MD'
        let md2 = try toMarkdown(doc2)

        XCTAssertEqual(normalize(md1), normalize(md2))
    }

    func testRoundTripA_Heading() throws {
        var doc = WordDocument()
        var para = Paragraph()
        para.properties.style = "Heading1"
        para.runs = [Run(text: "Title")]
        doc.body.children.append(.paragraph(para))

        let md1 = try toMarkdown(doc)
        let doc2 = try reverse.convertMarkdown(md1)
        let md2 = try toMarkdown(doc2)

        XCTAssertEqual(normalize(md1), normalize(md2))
    }

    func testRoundTripA_BoldItalic() throws {
        var doc = WordDocument()
        var para = Paragraph()

        let normalRun = Run(text: "This is ")
        var boldRun = Run(text: "bold")
        boldRun.properties.bold = true
        let italicRun = Run(text: " and ")
        var biRun = Run(text: "both")
        biRun.properties.bold = true
        biRun.properties.italic = true
        let tail = Run(text: " text.")

        para.runs = [normalRun, boldRun, italicRun, biRun, tail]
        doc.body.children.append(.paragraph(para))

        let md1 = try toMarkdown(doc)
        let doc2 = try reverse.convertMarkdown(md1)
        let md2 = try toMarkdown(doc2)

        XCTAssertEqual(normalize(md1), normalize(md2))
    }

    func testRoundTripA_UnorderedList() throws {
        var doc = WordDocument()
        let numId = doc.numbering.createBulletList()

        for text in ["Apple", "Banana", "Cherry"] {
            var para = Paragraph()
            para.runs = [Run(text: text)]
            para.properties.numbering = NumberingInfo(numId: numId, level: 0)
            doc.body.children.append(.paragraph(para))
        }

        let md1 = try toMarkdown(doc)
        let doc2 = try reverse.convertMarkdown(md1)
        let md2 = try toMarkdown(doc2)

        XCTAssertEqual(normalize(md1), normalize(md2))
    }

    func testRoundTripA_OrderedList() throws {
        var doc = WordDocument()
        let numId = doc.numbering.createNumberedList()

        for text in ["First", "Second", "Third"] {
            var para = Paragraph()
            para.runs = [Run(text: text)]
            para.properties.numbering = NumberingInfo(numId: numId, level: 0)
            doc.body.children.append(.paragraph(para))
        }

        let md1 = try toMarkdown(doc)
        let doc2 = try reverse.convertMarkdown(md1)
        let md2 = try toMarkdown(doc2)

        XCTAssertEqual(normalize(md1), normalize(md2))
    }

    func testRoundTripA_CodeBlock() throws {
        var doc = WordDocument()

        for line in ["let x = 1", "let y = 2"] {
            var para = Paragraph()
            para.properties.style = "Code"
            para.runs = [Run(text: line)]
            doc.body.children.append(.paragraph(para))
        }

        let md1 = try toMarkdown(doc)
        let doc2 = try reverse.convertMarkdown(md1)
        let md2 = try toMarkdown(doc2)

        XCTAssertEqual(normalize(md1), normalize(md2))
    }

    func testRoundTripA_Blockquote() throws {
        var doc = WordDocument()
        var para = Paragraph()
        para.properties.style = "Quote"
        para.runs = [Run(text: "A wise saying.")]
        doc.body.children.append(.paragraph(para))

        let md1 = try toMarkdown(doc)
        let doc2 = try reverse.convertMarkdown(md1)
        let md2 = try toMarkdown(doc2)

        XCTAssertEqual(normalize(md1), normalize(md2))
    }

    func testRoundTripA_Table() throws {
        var doc = WordDocument()

        var headerProps = TableRowProperties()
        headerProps.isHeader = true
        let headerRow = TableRow(cells: [
            TableCell(paragraphs: [Paragraph(runs: [Run(text: "Name")])]),
            TableCell(paragraphs: [Paragraph(runs: [Run(text: "Age")])])
        ], properties: headerProps)

        let dataRow = TableRow(cells: [
            TableCell(paragraphs: [Paragraph(runs: [Run(text: "Alice")])]),
            TableCell(paragraphs: [Paragraph(runs: [Run(text: "30")])])
        ])

        let table = Table(rows: [headerRow, dataRow])
        doc.body.children.append(.table(table))

        let md1 = try toMarkdown(doc)
        let doc2 = try reverse.convertMarkdown(md1)
        let md2 = try toMarkdown(doc2)

        XCTAssertEqual(normalize(md1), normalize(md2))
    }

    func testRoundTripA_Link() throws {
        var doc = WordDocument()
        var para = Paragraph()

        let hyperlink = Hyperlink(
            id: "h1",
            text: "Example",
            url: "https://example.com",
            relationshipId: "rId1"
        )
        para.hyperlinks = [hyperlink]
        doc.body.children.append(.paragraph(para))
        doc.hyperlinkReferences.append(
            HyperlinkReference(relationshipId: "rId1", url: "https://example.com")
        )

        let md1 = try toMarkdown(doc)
        let doc2 = try reverse.convertMarkdown(md1)
        let md2 = try toMarkdown(doc2)

        XCTAssertEqual(normalize(md1), normalize(md2))
    }

    func testRoundTripA_ThematicBreak() throws {
        var doc = WordDocument()

        var before = Paragraph()
        before.runs = [Run(text: "Before")]
        doc.body.children.append(.paragraph(before))

        var hr = Paragraph()
        hr.hasPageBreak = true
        doc.body.children.append(.paragraph(hr))

        var after = Paragraph()
        after.runs = [Run(text: "After")]
        doc.body.children.append(.paragraph(after))

        let md1 = try toMarkdown(doc)
        let doc2 = try reverse.convertMarkdown(md1)
        let md2 = try toMarkdown(doc2)

        XCTAssertEqual(normalize(md1), normalize(md2))
    }

    func testRoundTripA_Footnote() throws {
        var doc = WordDocument()

        var para = Paragraph()
        para.runs = [Run(text: "Important claim")]
        para.footnoteIds = [1]
        doc.body.children.append(.paragraph(para))

        doc.footnotes.footnotes.append(
            Footnote(id: 1, text: "Source: Wikipedia", paragraphIndex: 0)
        )

        let md1 = try toMarkdown(doc)
        let doc2 = try reverse.convertMarkdown(md1)
        let md2 = try toMarkdown(doc2)

        XCTAssertEqual(normalize(md1), normalize(md2))
    }

    // =========================================================
    // MARK: - Direction B: MD → Word → MD
    // =========================================================

    func testRoundTripB_BasicParagraph() throws {
        let md = "Hello world\n"
        let doc = try reverse.convertMarkdown(md)
        let md2 = try toMarkdown(doc)
        XCTAssertEqual(normalize(md), normalize(md2))
    }

    func testRoundTripB_Heading() throws {
        let md = "# Title\n\n## Subtitle\n"
        let doc = try reverse.convertMarkdown(md)
        let md2 = try toMarkdown(doc)
        XCTAssertEqual(normalize(md), normalize(md2))
    }

    func testRoundTripB_BoldItalicStrike() throws {
        // 正向轉換器用 _ 做 italic，所以輸入也用 _
        let md = "This is **bold** and _italic_ and ~~deleted~~ text.\n"
        let doc = try reverse.convertMarkdown(md)
        let md2 = try toMarkdown(doc)
        XCTAssertEqual(normalize(md), normalize(md2))
    }

    func testRoundTripB_UnorderedList() throws {
        let md = "- Apple\n- Banana\n- Cherry\n"
        let doc = try reverse.convertMarkdown(md)
        let md2 = try toMarkdown(doc)
        XCTAssertEqual(normalize(md), normalize(md2))
    }

    func testRoundTripB_OrderedList() throws {
        let md = "1. First\n1. Second\n1. Third\n"
        let doc = try reverse.convertMarkdown(md)
        let md2 = try toMarkdown(doc)
        XCTAssertEqual(normalize(md), normalize(md2))
    }

    func testRoundTripB_CodeBlock() throws {
        let md = "```\nlet x = 1\n```\n"
        let doc = try reverse.convertMarkdown(md)
        let md2 = try toMarkdown(doc)
        XCTAssertEqual(normalize(md), normalize(md2))
    }

    func testRoundTripB_Blockquote() throws {
        let md = "> A wise saying.\n"
        let doc = try reverse.convertMarkdown(md)
        let md2 = try toMarkdown(doc)
        XCTAssertEqual(normalize(md), normalize(md2))
    }

    func testRoundTripB_Table() throws {
        let md = "| Name | Age |\n|---|---|\n| Alice | 30 |\n"
        let doc = try reverse.convertMarkdown(md)
        let md2 = try toMarkdown(doc)
        XCTAssertEqual(normalize(md), normalize(md2))
    }

    func testRoundTripB_Link() throws {
        // Word 模型中 runs 和 hyperlinks 分開存儲，
        // 正向轉換器先輸出 runs 再輸出 hyperlinks，
        // 所以 inline link 位置會移動。改用二次穩定性驗證：
        // MD → Word → MD' → Word' → MD''，確認 MD' == MD''
        let md = "Visit [Example](https://example.com) now.\n"
        let doc = try reverse.convertMarkdown(md)
        let md2 = try toMarkdown(doc)

        // 再走一次
        let doc3 = try reverse.convertMarkdown(md2)
        let md3 = try toMarkdown(doc3)

        XCTAssertEqual(normalize(md2), normalize(md3),
            "Round-trip should be idempotent after first pass")
    }

    func testRoundTripB_ThematicBreak() throws {
        let md = "Before\n\n---\n\nAfter\n"
        let doc = try reverse.convertMarkdown(md)
        let md2 = try toMarkdown(doc)
        XCTAssertEqual(normalize(md), normalize(md2))
    }

    func testRoundTripB_Footnote() throws {
        // 正向轉換器輸出：文字後面接 footnote ref，句號在 ref 之前
        let md = "Important claim.[^1]\n\n[^1]: Source: Wikipedia\n"
        let doc = try reverse.convertMarkdown(md)
        let md2 = try toMarkdown(doc)
        XCTAssertEqual(normalize(md), normalize(md2))
    }

    func testRoundTripB_MixedContent() throws {
        // 使用正向轉換器的輸出格式（_ for italic, blockquote 後無空行）
        let md = """
        # Introduction

        This is a **bold** paragraph with _italic_ text.

        - Item 1
        - Item 2
        > A quote

        ```
        code here
        ```
        """

        let doc = try reverse.convertMarkdown(md)
        let md2 = try toMarkdown(doc)
        XCTAssertEqual(normalize(md), normalize(md2))
    }

    // =========================================================
    // MARK: - Direction C: g ∘ f = id_{W*}（WordDocument 等價驗證）
    // =========================================================
    //
    // 數學定義（docs/lossless-conversion.md §4）：
    //   f: W → MD   (forward, WordConverter)
    //   g: MD → W   (reverse, MarkdownToWordConverter)
    //   W* = Im(g|_{MD*})
    //
    // 驗證：∀ w ∈ W*: g(f(w)) = w
    //
    // 策略：三步走法確保在 W* 中操作
    //   1. w₀ = g(md)          — 從任意 md 開始
    //   2. md* = f(w₀)         — 正規化為 MD*
    //   3. w₁ = g(md*)         — 建構 W* 元素
    //   4. md₁ = f(w₁)         — round-trip
    //   5. w₂ = g(md₁)         — 重建
    //   6. assert w₁ == w₂     — g ∘ f = id_{W*}

    /// 三步走法 helper：確保在 W* 上測試 g ∘ f = id
    private func assertWordLevelRoundTrip(
        _ md: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        // 1. 正規化為 MD*：md → w₀ → md*
        let w0 = try reverse.convertMarkdown(md)
        let mdStar = try toMarkdown(w0)

        // 2. 建構 W* 元素：md* → w₁
        let w1 = try reverse.convertMarkdown(mdStar)

        // 3. Round-trip：w₁ → md₁ → w₂
        let md1 = try toMarkdown(w1)
        let w2 = try reverse.convertMarkdown(md1)

        // 4. g ∘ f = id_{W*}
        XCTAssertEqual(w1, w2,
            "g ∘ f should be identity on W*.\n" +
            "md* = \(mdStar.debugDescription)\n" +
            "md₁ = \(md1.debugDescription)",
            file: file, line: line)

        // Bonus: f ∘ g = id_{MD*}（MD 層也應一致）
        XCTAssertEqual(normalize(mdStar), normalize(md1),
            "f ∘ g should also be identity on MD*",
            file: file, line: line)
    }

    // MARK: - C.1 Basic Paragraph

    func testRoundTripC_BasicParagraph() throws {
        try assertWordLevelRoundTrip("Hello world")
    }

    func testRoundTripC_MultipleParagraphs() throws {
        try assertWordLevelRoundTrip("First paragraph.\n\nSecond paragraph.")
    }

    // MARK: - C.2 Headings

    func testRoundTripC_Heading1() throws {
        try assertWordLevelRoundTrip("# Title")
    }

    func testRoundTripC_Heading2() throws {
        try assertWordLevelRoundTrip("## Subtitle")
    }

    func testRoundTripC_Heading3() throws {
        try assertWordLevelRoundTrip("### Section")
    }

    func testRoundTripC_MultipleHeadings() throws {
        try assertWordLevelRoundTrip("# Title\n\n## Section\n\n### Subsection")
    }

    // MARK: - C.3 Inline Formatting (Layer A)

    func testRoundTripC_Bold() throws {
        try assertWordLevelRoundTrip("This is **bold** text.")
    }

    func testRoundTripC_Italic() throws {
        try assertWordLevelRoundTrip("This is _italic_ text.")
    }

    func testRoundTripC_BoldItalic() throws {
        try assertWordLevelRoundTrip("This is ***bold italic*** text.")
    }

    func testRoundTripC_Strikethrough() throws {
        try assertWordLevelRoundTrip("This is ~~deleted~~ text.")
    }

    func testRoundTripC_MixedInline() throws {
        try assertWordLevelRoundTrip("Normal **bold** _italic_ ~~strike~~ end.")
    }

    // MARK: - C.4 Code

    func testRoundTripC_CodeBlock() throws {
        try assertWordLevelRoundTrip("```\nlet x = 1\nlet y = 2\n```")
    }

    func testRoundTripC_SingleLineCodeBlock() throws {
        try assertWordLevelRoundTrip("```\nprint(hello)\n```")
    }

    // MARK: - C.5 Blockquote

    func testRoundTripC_Blockquote() throws {
        try assertWordLevelRoundTrip("> A wise saying.")
    }

    // MARK: - C.6 Lists

    func testRoundTripC_UnorderedList() throws {
        try assertWordLevelRoundTrip("- Apple\n- Banana\n- Cherry")
    }

    func testRoundTripC_OrderedList() throws {
        try assertWordLevelRoundTrip("1. First\n2. Second\n3. Third")
    }

    // MARK: - C.7 Table

    func testRoundTripC_Table() throws {
        try assertWordLevelRoundTrip(
            "| Name | Age |\n|---|---|\n| Alice | 30 |"
        )
    }

    // MARK: - C.8 Thematic Break

    func testRoundTripC_ThematicBreak() throws {
        try assertWordLevelRoundTrip("Before\n\n---\n\nAfter")
    }

    // MARK: - C.9 Link

    func testRoundTripC_Link() throws {
        // Link 的位置可能在 canonicalization 時移動，
        // 但 W* 層的 round-trip 應該穩定
        try assertWordLevelRoundTrip("[Example](https://example.com)")
    }

    // MARK: - C.10 Mixed Content

    // MARK: - C.11 Inline Code (Layer A Advanced)

    func testRoundTripC_InlineCode() throws {
        try assertWordLevelRoundTrip("Use `code` here.")
    }

    // MARK: - C.12 Footnote

    func testRoundTripC_Footnote() throws {
        try assertWordLevelRoundTrip("Important claim.[^1]\n\n[^1]: Source: Wikipedia")
    }

    // MARK: - C.13 Nested Lists

    func testRoundTripC_NestedUnorderedList() throws {
        try assertWordLevelRoundTrip("- A\n  - B\n  - C\n- D")
    }

    func testRoundTripC_NestedOrderedList() throws {
        try assertWordLevelRoundTrip("1. A\n   1. B\n2. C")
    }

    // MARK: - C.14 Internal Link

    func testRoundTripC_InternalLink() throws {
        try assertWordLevelRoundTrip("[Go](#section)")
    }

    // MARK: - C.10 Mixed Content

    func testRoundTripC_HeadingWithFormatting() throws {
        try assertWordLevelRoundTrip("# **Bold** Title")
    }

    func testRoundTripC_ComplexDocument() throws {
        try assertWordLevelRoundTrip("""
        # Introduction

        This is a **bold** paragraph with _italic_ text.

        ## List Section

        - Item one
        - Item two

        > A quote

        ```
        code here
        ```

        End of document.
        """)
    }

    // =========================================================
    // MARK: - Direction C: Layer B（HTML Extensions）
    // =========================================================
    //
    // Layer B 的 round-trip 在 forward 方向需要 useHTMLExtensions: true，
    // 否則 underline/sup/sub/highlight 不會輸出 HTML tags。

    /// 三步走法 helper（HTML extensions 版本）
    private func assertWordLevelRoundTripHTML(
        _ md: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        // 1. 正規化為 MD*：md → w₀ → md*
        let w0 = try reverse.convertMarkdown(md)
        let mdStar = try toMarkdownHTML(w0)

        // 2. 建構 W* 元素：md* → w₁
        let w1 = try reverse.convertMarkdown(mdStar)

        // 3. Round-trip：w₁ → md₁ → w₂
        let md1 = try toMarkdownHTML(w1)
        let w2 = try reverse.convertMarkdown(md1)

        // 4. g ∘ f = id_{W*}
        XCTAssertEqual(w1, w2,
            "g ∘ f should be identity on W* (HTML).\n" +
            "md* = \(mdStar.debugDescription)\n" +
            "md₁ = \(md1.debugDescription)",
            file: file, line: line)

        // Bonus: f ∘ g = id_{MD*}
        XCTAssertEqual(normalize(mdStar), normalize(md1),
            "f ∘ g should also be identity on MD* (HTML)",
            file: file, line: line)
    }

    // MARK: - C.15 Underline

    func testRoundTripC_Underline() throws {
        try assertWordLevelRoundTripHTML("<u>text</u>")
    }

    // MARK: - C.16 Superscript

    func testRoundTripC_Superscript() throws {
        try assertWordLevelRoundTripHTML("x<sup>2</sup>")
    }

    // MARK: - C.17 Subscript

    func testRoundTripC_Subscript() throws {
        try assertWordLevelRoundTripHTML("H<sub>2</sub>O")
    }

    // MARK: - C.18 Highlight

    func testRoundTripC_Highlight() throws {
        try assertWordLevelRoundTripHTML("<mark>text</mark>")
    }

    // MARK: - C.19 Combined: Bold + Underline

    func testRoundTripC_BoldUnderline() throws {
        try assertWordLevelRoundTripHTML("**<u>text</u>**")
    }

    // MARK: - C.20 Combined: Underline wrapping Bold

    func testRoundTripC_UnderlineBold() throws {
        try assertWordLevelRoundTripHTML("<u>**text**</u>")
    }
}
