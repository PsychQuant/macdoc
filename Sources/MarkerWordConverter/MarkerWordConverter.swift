import Foundation
import DocConverterSwift
import OOXMLSwift
import MarkdownSwift
import MarkerSwift

/// Word to Marker format converter
/// Outputs: MD + JSON metadata + images folder
public struct MarkerWordConverter {
    public static let sourceFormat = "docx"

    private let classifier: any ImageClassifier

    public init(classifier: any ImageClassifier = PassthroughClassifier()) {
        self.classifier = classifier
    }

    /// Convert Word document to marker format output
    /// - Parameters:
    ///   - input: Input .docx file URL
    ///   - outputDirectory: Output directory for MD, JSON, and images
    ///   - options: Conversion options
    /// - Returns: URLs of generated files
    @discardableResult
    public func convert(
        input: URL,
        outputDirectory: URL,
        options: ConversionOptions = .default
    ) async throws -> MarkerOutputFiles {
        // Read Word document
        let document = try DocxReader.read(from: input)

        // Get base filename (without extension)
        let filename = input.deletingPathExtension().lastPathComponent

        // Initialize MarkerWriter
        let writer = try MarkerWriter(
            outputDirectory: outputDirectory,
            filename: filename,
            classifier: classifier
        )

        // Build image lookup table: imageId -> ImageReference
        var imageMap: [String: ImageReference] = [:]
        for image in document.images {
            imageMap[image.id] = image
        }

        // Write frontmatter if requested
        if options.includeFrontmatter {
            try writeFrontmatter(document: document, writer: writer)
        }

        // Process each element
        for child in document.body.children {
            switch child {
            case .paragraph(let paragraph):
                try await processParagraph(
                    paragraph,
                    styles: document.styles,
                    numbering: document.numbering,
                    imageMap: imageMap,
                    writer: writer,
                    options: options
                )
            case .table(let table):
                try processTable(table, writer: writer, options: options)
            }
        }

        // Finalize and write all files
        return try writer.finalize()
    }

    // MARK: - Frontmatter

    private func writeFrontmatter(document: WordDocument, writer: MarkerWriter) throws {
        var frontmatter = "---\n"

        let props = document.properties
        if let title = props.title, !title.isEmpty {
            frontmatter += "title: \"\(escapeYAML(title))\"\n"
        }
        if let author = props.creator, !author.isEmpty {
            frontmatter += "author: \"\(escapeYAML(author))\"\n"
        }
        if let subject = props.subject, !subject.isEmpty {
            frontmatter += "subject: \"\(escapeYAML(subject))\"\n"
        }

        frontmatter += "---\n\n"
        try writer.raw(frontmatter)
    }

    // MARK: - Paragraph Processing

    private func processParagraph(
        _ paragraph: Paragraph,
        styles: [Style],
        numbering: Numbering,
        imageMap: [String: ImageReference],
        writer: MarkerWriter,
        options: ConversionOptions
    ) async throws {
        // Check for images in runs first
        for run in paragraph.runs {
            if let drawing = run.drawing {
                try await processDrawing(drawing, imageMap: imageMap, writer: writer)
            }
        }

        // Get text content (excluding image runs)
        let text = formatRuns(paragraph.runs.filter { $0.drawing == nil })

        // Skip empty paragraphs (if no images were processed)
        if text.trimmingCharacters(in: CharacterSet.whitespaces).isEmpty {
            return
        }

        // 🆕 使用語義標註來決定輸出格式
        if let semantic = paragraph.semantic {
            switch semantic.type {
            case .heading(let level):
                try writer.heading(text, level: level)
                return

            case .title:
                try writer.heading(text, level: 1)
                return

            case .subtitle:
                try writer.heading(text, level: 2)
                return

            case .bulletListItem(let level):
                try writer.bulletItem(text, level: level)
                return

            case .numberedListItem(let level):
                try writer.numberedItem(text, level: level)
                return

            case .pageBreak, .sectionBreak:
                // 分頁符通常不輸出到 Markdown
                return

            case .formula:
                // 公式處理（未來可擴展為 LaTeX 轉換）
                try writer.paragraph(text)
                return

            case .image:
                // 圖片已在上面的迴圈處理
                return

            case .paragraph, .unknown, .table, .tableHeaderRow, .tableDataRow,
                 .tableCell, .codeBlock, .blockquote, .footnote, .hyperlink:
                // 預設為一般段落
                break
            }
        }

        // Fallback: 使用舊的推斷邏輯（相容性）
        // Check if heading
        if let styleName = paragraph.properties.style,
           let headingLevel = detectHeadingLevel(styleName: styleName, styles: styles) {
            try writer.heading(text, level: headingLevel)
            return
        }

        // Check if list item
        if let numInfo = paragraph.properties.numbering {
            let isBullet = isListBullet(numId: numInfo.numId, level: numInfo.level, numbering: numbering)
            if isBullet {
                try writer.bulletItem(text, level: numInfo.level)
            } else {
                try writer.numberedItem(text, level: numInfo.level)
            }
            return
        }

        // Regular paragraph
        try writer.paragraph(text)
    }

    // MARK: - Drawing/Image Processing

    private func processDrawing(
        _ drawing: Drawing,
        imageMap: [String: ImageReference],
        writer: MarkerWriter
    ) async throws {
        // Look up image data by relationship ID
        guard let imageRef = imageMap[drawing.imageId] else {
            // Image not found, skip
            return
        }

        // Process image through MarkerWriter (which uses classifier)
        try await writer.image(data: imageRef.data, originalName: imageRef.fileName)
    }

    // MARK: - List Detection

    private func isListBullet(numId: Int, level: Int, numbering: Numbering) -> Bool {
        guard let num = numbering.nums.first(where: { $0.numId == numId }) else {
            return true  // Default to bullet
        }

        guard let abstractNum = numbering.abstractNums.first(where: { $0.abstractNumId == num.abstractNumId }) else {
            return true
        }

        guard let levelDef = abstractNum.levels.first(where: { $0.ilvl == level }) else {
            return true
        }

        return levelDef.numFmt == .bullet
    }

    // MARK: - Run Formatting

    private func formatRuns(_ runs: [Run]) -> String {
        var result = ""

        for run in runs {
            var text = run.text

            // Skip empty text
            if text.isEmpty { continue }

            // Apply formatting
            let props = run.properties
            if props.bold && props.italic {
                text = MarkdownInline.boldItalic(text)
            } else if props.bold {
                text = MarkdownInline.bold(text)
            } else if props.italic {
                text = MarkdownInline.italic(text)
            }

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

        // Check style inheritance
        if let style = styles.first(where: { $0.id.lowercased() == lowerName }),
           let basedOn = style.basedOn {
            return detectHeadingLevel(styleName: basedOn, styles: styles)
        }

        return nil
    }

    // MARK: - Table Processing

    private func processTable(
        _ table: Table,
        writer: MarkerWriter,
        options: ConversionOptions
    ) throws {
        guard !table.rows.isEmpty else { return }

        let columnCount = table.rows.map { $0.cells.count }.max() ?? 0
        guard columnCount > 0 else { return }

        // Normalize rows
        let normalizedRows = table.rows.map { row -> [String] in
            var cells = row.cells.map { cell -> String in
                let content = cell.paragraphs.map { formatRuns($0.runs) }.joined(separator: " ")
                return MarkdownEscaping.escape(content, context: .tableCell)
            }
            while cells.count < columnCount {
                cells.append("")
            }
            return cells
        }

        // First row as headers
        let headers = normalizedRows[0]
        let dataRows = Array(normalizedRows.dropFirst())

        try writer.table(headers: headers, rows: dataRows)
    }

    // MARK: - Helpers

    private func escapeYAML(_ text: String) -> String {
        return text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
