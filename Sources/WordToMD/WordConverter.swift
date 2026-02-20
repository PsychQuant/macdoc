import Foundation
import MacDocCore
import OOXMLSwift
import MarkdownSwift

/// Word 轉 Markdown 轉換器
public struct WordConverter: DocumentConverter {
    public static let sourceFormat = "docx"

    public init() {}

    public func convert<W: MacDocCore.StreamingOutput>(
        input: URL,
        output: inout W,
        options: ConversionOptions
    ) throws {
        // 讀取 Word 文件
        let document = try DocxReader.read(from: input)

        // 輸出 frontmatter（可選）
        if options.includeFrontmatter {
            try writeFrontmatter(document: document, output: &output)
        }

        // 串流處理每個元素
        for child in document.body.children {
            switch child {
            case .paragraph(let paragraph):
                try processParagraph(
                    paragraph,
                    styles: document.styles,
                    numbering: document.numbering,
                    output: &output,
                    options: options
                )
            case .table(let table):
                try processTable(table, output: &output, options: options)
            }
        }
    }

    // MARK: - Frontmatter

    private func writeFrontmatter<W: MacDocCore.StreamingOutput>(
        document: WordDocument,
        output: inout W
    ) throws {
        try output.writeLine("---")

        let props = document.properties
        if let title = props.title, !title.isEmpty {
            try output.writeLine("title: \"\(escapeYAML(title))\"")
        }
        if let author = props.creator, !author.isEmpty {
            try output.writeLine("author: \"\(escapeYAML(author))\"")
        }
        if let subject = props.subject, !subject.isEmpty {
            try output.writeLine("subject: \"\(escapeYAML(subject))\"")
        }

        try output.writeLine("---")
        try output.writeBlankLine()
    }

    // MARK: - Paragraph Processing

    private func processParagraph<W: MacDocCore.StreamingOutput>(
        _ paragraph: Paragraph,
        styles: [Style],
        numbering: Numbering,
        output: inout W,
        options: ConversionOptions
    ) throws {
        let text = formatRuns(paragraph.runs)

        // 空段落 → 跳過
        if text.trimmingCharacters(in: CharacterSet.whitespaces).isEmpty {
            return
        }

        // 檢查是否為標題
        if let styleName = paragraph.properties.style,
           let headingLevel = detectHeadingLevel(styleName: styleName, styles: styles) {
            let prefix = String(repeating: "#", count: headingLevel)
            try output.writeLine("\(prefix) \(text)")
            try output.writeBlankLine()
            return
        }

        // 檢查是否為清單項目
        if let numInfo = paragraph.properties.numbering {
            let isBullet = isListBullet(numId: numInfo.numId, level: numInfo.level, numbering: numbering)
            let prefix = isBullet ? "- " : "1. "
            let indent = String(repeating: "  ", count: numInfo.level)
            try output.writeLine("\(indent)\(prefix)\(text)")
            return
        }

        // 一般段落
        try output.writeLine(text)
        try output.writeBlankLine()
    }

    // MARK: - List Detection

    /// 判斷是否為項目符號清單（bullet）
    private func isListBullet(numId: Int, level: Int, numbering: Numbering) -> Bool {
        // 找到對應的 Num
        guard let num = numbering.nums.first(where: { $0.numId == numId }) else {
            return true  // 預設為 bullet
        }

        // 找到對應的 AbstractNum
        guard let abstractNum = numbering.abstractNums.first(where: { $0.abstractNumId == num.abstractNumId }) else {
            return true
        }

        // 找到對應層級的 Level
        guard let levelDef = abstractNum.levels.first(where: { $0.ilvl == level }) else {
            return true
        }

        // 判斷是否為 bullet
        return levelDef.numFmt == .bullet
    }

    // MARK: - Run Formatting

    private func formatRuns(_ runs: [Run]) -> String {
        var result = ""

        for run in runs {
            var text = run.text

            // 跳過空文字
            if text.isEmpty { continue }

            // 套用格式（使用 MarkdownSwift）
            let props = run.properties
            if props.bold && props.italic {
                text = MarkdownInline.boldItalic(text)
            } else if props.bold {
                text = MarkdownInline.bold(text)
            } else if props.italic {
                text = MarkdownInline.italic(text)
            }

            // 刪除線
            if props.strikethrough {
                text = MarkdownInline.strikethrough(text)
            }

            result += text
        }

        return result
    }

    // MARK: - Heading Detection

    private func detectHeadingLevel(styleName: String, styles: [Style]) -> Int? {
        let lowerName = styleName.lowercased()

        // 直接匹配標準樣式
        let headingPatterns: [(String, Int)] = [
            ("heading1", 1), ("heading 1", 1), ("標題 1", 1), ("標題1", 1),
            ("heading2", 2), ("heading 2", 2), ("標題 2", 2), ("標題2", 2),
            ("heading3", 3), ("heading 3", 3), ("標題 3", 3), ("標題3", 3),
            ("heading4", 4), ("heading 4", 4), ("標題 4", 4), ("標題4", 4),
            ("heading5", 5), ("heading 5", 5), ("標題 5", 5), ("標題5", 5),
            ("heading6", 6), ("heading 6", 6), ("標題 6", 6), ("標題6", 6),
            ("title", 1), ("subtitle", 2),
        ]

        for (pattern, level) in headingPatterns {
            if lowerName == pattern {
                return level
            }
        }

        // 檢查樣式繼承鏈
        if let style = styles.first(where: { $0.id.lowercased() == lowerName }),
           let basedOn = style.basedOn {
            return detectHeadingLevel(styleName: basedOn, styles: styles)
        }

        return nil
    }

    // MARK: - Table Processing

    private func processTable<W: MacDocCore.StreamingOutput>(
        _ table: Table,
        output: inout W,
        options: ConversionOptions
    ) throws {
        guard !table.rows.isEmpty else { return }

        // 計算最大欄數
        let columnCount = table.rows.map { $0.cells.count }.max() ?? 0
        guard columnCount > 0 else { return }

        // 正規化列（確保每列欄數相同）
        let normalizedRows = table.rows.map { row -> [String] in
            var cells = row.cells.map { cell -> String in
                let content = cell.paragraphs.map { formatRuns($0.runs) }.joined(separator: " ")
                // 使用 MarkdownSwift 跳脫表格儲存格
                return MarkdownEscaping.escape(content, context: .tableCell)
            }
            // 補足欄數
            while cells.count < columnCount {
                cells.append("")
            }
            return cells
        }

        // 輸出標題列
        let headerRow = normalizedRows[0]
        try output.writeLine("| " + headerRow.joined(separator: " | ") + " |")

        // 輸出分隔線
        let separator = Array(repeating: "---", count: columnCount)
        try output.writeLine("|" + separator.joined(separator: "|") + "|")

        // 輸出資料列
        for row in normalizedRows.dropFirst() {
            try output.writeLine("| " + row.joined(separator: " | ") + " |")
        }

        try output.writeBlankLine()
    }

    // MARK: - Helpers

    private func escapeYAML(_ text: String) -> String {
        return text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
