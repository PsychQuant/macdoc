import Foundation
import Markdown
import OOXMLSwift

/// 走訪 swift-markdown AST，建構 WordDocument
///
/// 實作 `MarkupWalker` protocol，將每個 block/inline node
/// 轉換為對應的 OOXMLSwift 模型。
struct MarkdownASTWalker {
    var document: WordDocument
    var metadata: DocumentMetadata?
    var figures: [String: Data]
    var footnoteDefinitions: [String: String]  // id → text

    /// 追蹤目前的段落索引（用於 metadata overlay）
    private var paragraphIndex: Int = 0

    /// 追蹤 image rId 計數
    private var nextImageRId: Int = 100

    /// 追蹤 hyperlink rId 計數
    private var nextHyperlinkRId: Int = 200

    /// 當前段落累積的 hyperlinks（在 processLink 中填入，visitParagraph 中消費）
    private var pendingHyperlinks: [Hyperlink] = []

    init(
        metadata: DocumentMetadata? = nil,
        figures: [String: Data] = [:],
        footnoteDefinitions: [String: String] = [:]
    ) {
        self.document = WordDocument()
        self.metadata = metadata
        self.figures = figures
        self.footnoteDefinitions = footnoteDefinitions
    }

    // MARK: - Public Entry Point

    /// 走訪整個 Document
    mutating func walk(_ markupDocument: Markdown.Document) {
        for child in markupDocument.children {
            walkBlock(child)
        }

        // 套用 document-level metadata
        applyDocumentMetadata()
    }

    // MARK: - Block-Level Dispatch

    private mutating func walkBlock(_ markup: any Markup) {
        if let heading = markup as? Heading {
            visitHeading(heading)
        } else if let paragraph = markup as? Markdown.Paragraph {
            visitParagraph(paragraph)
        } else if let codeBlock = markup as? CodeBlock {
            visitCodeBlock(codeBlock)
        } else if let blockQuote = markup as? BlockQuote {
            visitBlockQuote(blockQuote)
        } else if let orderedList = markup as? OrderedList {
            visitOrderedList(orderedList)
        } else if let unorderedList = markup as? UnorderedList {
            visitUnorderedList(unorderedList)
        } else if let table = markup as? Markdown.Table {
            visitTable(table)
        } else if let thematicBreak = markup as? ThematicBreak {
            visitThematicBreak(thematicBreak)
        } else if let htmlBlock = markup as? HTMLBlock {
            visitHTMLBlock(htmlBlock)
        } else {
            // 其他 block types — 遞迴走訪 children
            for child in markup.children {
                walkBlock(child)
            }
        }
    }

    // MARK: - Block Visitors

    private mutating func visitHeading(_ heading: Heading) {
        pendingHyperlinks = []
        let level = heading.level
        let styleName = "Heading\(level)"
        let runs = processInlines(heading.children)

        var props = ParagraphProperties()
        props.style = styleName

        var para = OOXMLSwift.Paragraph(runs: runs, properties: props)
        para.hyperlinks = pendingHyperlinks
        pendingHyperlinks = []
        applyMetadataOverlay(to: &para)
        document.appendParagraph(para)
    }

    private mutating func visitParagraph(_ mdParagraph: Markdown.Paragraph) {
        pendingHyperlinks = []
        let runs = processInlines(mdParagraph.children)

        // 空段落跳過（除非有 hyperlinks）
        guard !runs.isEmpty || !pendingHyperlinks.isEmpty else { return }

        var para = OOXMLSwift.Paragraph(runs: runs)
        para.hyperlinks = pendingHyperlinks
        pendingHyperlinks = []
        applyMetadataOverlay(to: &para)
        document.appendParagraph(para)
    }

    private mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        let code = codeBlock.code.trimmingCharacters(in: .newlines)
        let lines = code.components(separatedBy: "\n")

        for line in lines {
            var props = ParagraphProperties()
            props.style = "Code"

            var runProps = RunProperties()
            runProps.fontName = "Consolas"
            runProps.fontSize = 20  // 10pt

            let run = Run(text: line, properties: runProps)
            var para = OOXMLSwift.Paragraph(runs: [run], properties: props)
            applyMetadataOverlay(to: &para)
            document.appendParagraph(para)
        }
    }

    private mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
        // BlockQuote 的 children 是其他 block elements
        for child in blockQuote.children {
            if let paragraph = child as? Markdown.Paragraph {
                let runs = processInlines(paragraph.children)
                var props = ParagraphProperties()
                props.style = "Quote"
                props.indentation = Indentation(left: 720)

                var para = OOXMLSwift.Paragraph(runs: runs, properties: props)
                applyMetadataOverlay(to: &para)
                document.appendParagraph(para)
            } else {
                walkBlock(child)
            }
        }
    }

    private mutating func visitOrderedList(_ orderedList: OrderedList) {
        let numId = document.numbering.createNumberedList()
        visitListItems(orderedList.children, numId: numId, level: 0)
    }

    private mutating func visitUnorderedList(_ unorderedList: UnorderedList) {
        let numId = document.numbering.createBulletList()
        visitListItems(unorderedList.children, numId: numId, level: 0)
    }

    private mutating func visitListItems(_ items: some Sequence<any Markup>, numId: Int, level: Int) {
        for item in items {
            guard let listItem = item as? ListItem else { continue }

            for child in listItem.children {
                if let paragraph = child as? Markdown.Paragraph {
                    let runs = processInlines(paragraph.children)

                    var props = ParagraphProperties()
                    props.numbering = NumberingInfo(numId: numId, level: level)

                    var para = OOXMLSwift.Paragraph(runs: runs, properties: props)
                    applyMetadataOverlay(to: &para)
                    document.appendParagraph(para)
                } else if let nestedOrdered = child as? OrderedList {
                    let nestedNumId = document.numbering.createNumberedList()
                    visitListItems(nestedOrdered.children, numId: nestedNumId, level: level + 1)
                } else if let nestedUnordered = child as? UnorderedList {
                    let nestedNumId = document.numbering.createBulletList()
                    visitListItems(nestedUnordered.children, numId: nestedNumId, level: level + 1)
                } else {
                    walkBlock(child)
                }
            }
        }
    }

    private mutating func visitTable(_ table: Markdown.Table) {
        var wordRows: [TableRow] = []

        // Header
        let headerRow = table.head
        var headerCells: [TableCell] = []
        for cell in headerRow.cells {
            let runs = processInlines(cell.children)
            let para = OOXMLSwift.Paragraph(runs: runs)
            headerCells.append(TableCell(paragraphs: [para]))
        }
        var headerTableRow = TableRow(cells: headerCells)
        headerTableRow.properties.isHeader = true
        wordRows.append(headerTableRow)

        // Body rows
        for bodyRow in table.body.rows {
            var cells: [TableCell] = []
            for cell in bodyRow.cells {
                let runs = processInlines(cell.children)
                let para = OOXMLSwift.Paragraph(runs: runs)
                cells.append(TableCell(paragraphs: [para]))
            }
            wordRows.append(TableRow(cells: cells))
        }

        var tableProps = TableProperties()
        tableProps.borders = TableBorders.all(Border())
        tableProps.width = 9000
        tableProps.widthType = .dxa

        let wordTable = Table(rows: wordRows, properties: tableProps)
        document.appendTable(wordTable)
        paragraphIndex += 1  // Table 佔一個 index
    }

    private mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {
        var para = OOXMLSwift.Paragraph()
        para.hasPageBreak = true
        document.appendParagraph(para)
        paragraphIndex += 1
    }

    private mutating func visitHTMLBlock(_ htmlBlock: HTMLBlock) {
        // HTML blocks → 當作純文字段落
        let text = htmlBlock.rawHTML.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let run = Run(text: text)
        var para = OOXMLSwift.Paragraph(runs: [run])
        applyMetadataOverlay(to: &para)
        document.appendParagraph(para)
    }

    // MARK: - Inline Processing

    /// 處理一組 inline children → [Run]
    mutating func processInlines<S: Sequence>(_ children: S) -> [Run] where S.Element: Markup {
        processInlineSequence(Array(children), inheritedProps: RunProperties())
    }

    /// 處理 existential Markup children（Table.Cell 等回傳 [any Markup] 的場景）
    mutating func processInlines(_ children: some Sequence<any Markup>) -> [Run] {
        processInlineSequence(Array(children), inheritedProps: RunProperties())
    }

    /// 處理一組 inline siblings，支援 HTML extension 狀態追蹤
    ///
    /// swift-markdown 把 `<u>text</u>` 解析為三個扁平 sibling：
    ///   InlineHTML("<u>") → Text("text") → InlineHTML("</u>")
    /// 此方法用 activeProps 狀態機在 sibling 間傳遞格式。
    private mutating func processInlineSequence(
        _ children: [any Markup],
        inheritedProps: RunProperties
    ) -> [Run] {
        var runs: [Run] = []
        var activeProps = inheritedProps

        for child in children {
            if let inlineHTML = child as? InlineHTML {
                applyHTMLTag(inlineHTML.rawHTML, to: &activeProps, base: inheritedProps)
            } else {
                runs.append(contentsOf: processInline(child, inheritedProps: activeProps))
            }
        }
        return runs
    }

    /// 根據 HTML tag 更新 activeProps，closing tag 還原到 base
    private func applyHTMLTag(_ tag: String, to props: inout RunProperties, base: RunProperties) {
        switch tag {
        case "<u>":     props.underline = .single
        case "</u>":    props.underline = base.underline
        case "<sup>":   props.verticalAlign = .superscript
        case "</sup>":  props.verticalAlign = base.verticalAlign
        case "<sub>":   props.verticalAlign = .subscript
        case "</sub>":  props.verticalAlign = base.verticalAlign
        case "<mark>":  props.highlight = .yellow
        case "</mark>": props.highlight = base.highlight
        default: break
        }
    }

    /// 處理單一 inline node
    private mutating func processInline(_ markup: any Markup, inheritedProps: RunProperties) -> [Run] {
        if let text = markup as? Markdown.Text {
            return [Run(text: text.string, properties: inheritedProps)]
        }

        if let strong = markup as? Strong {
            var props = inheritedProps
            props.bold = true
            return processInlineSequence(Array(strong.children), inheritedProps: props)
        }

        if let emphasis = markup as? Emphasis {
            var props = inheritedProps
            props.italic = true
            return processInlineSequence(Array(emphasis.children), inheritedProps: props)
        }

        if let strikethrough = markup as? Strikethrough {
            var props = inheritedProps
            props.strikethrough = true
            return processInlineSequence(Array(strikethrough.children), inheritedProps: props)
        }

        if let inlineCode = markup as? InlineCode {
            var props = inheritedProps
            props.fontName = "Consolas"
            props.fontSize = 20  // 10pt
            var run = Run(text: inlineCode.code, properties: props)
            run.semantic = SemanticAnnotation(type: .codeBlock)
            return [run]
        }

        if let link = markup as? Markdown.Link {
            return processLink(link, inheritedProps: inheritedProps)
        }

        if let image = markup as? Markdown.Image {
            return processImage(image)
        }

        if let inlineHTML = markup as? InlineHTML {
            // 已知 HTML tags 由 processInlineSequence 的 applyHTMLTag 處理
            // 這裡處理未知 HTML（當作純文字）
            return [Run(text: inlineHTML.rawHTML, properties: inheritedProps)]
        }

        if markup is SoftBreak {
            return [Run(text: " ", properties: inheritedProps)]
        }

        if markup is LineBreak {
            return [Run(text: "\n", properties: inheritedProps)]
        }

        // Fallback: 遞迴 children（使用 processInlineSequence 保持 HTML 狀態追蹤）
        return processInlineSequence(Array(markup.children), inheritedProps: inheritedProps)
    }

    // MARK: - Link Processing

    private mutating func processLink(_ link: Markdown.Link, inheritedProps: RunProperties) -> [Run] {
        let text = link.children.compactMap { child -> String? in
            if let t = child as? Markdown.Text { return t.string }
            return nil
        }.joined()

        let destination = link.destination ?? ""

        // 將連結加入 document-level 超連結引用
        let rIdNum = nextHyperlinkRId
        nextHyperlinkRId += 1
        let rId = "rId\(rIdNum)"

        document.hyperlinkReferences.append(
            HyperlinkReference(relationshipId: rId, url: destination)
        )

        // 建立 Hyperlink 物件（與正向轉換器對齊）
        let hyperlink = Hyperlink(
            id: "h\(rIdNum)",
            text: text,
            url: destination,
            relationshipId: rId
        )
        pendingHyperlinks.append(hyperlink)

        // Link 文字由 Hyperlink 攜帶，不產生 run
        return []
    }

    // MARK: - Image Processing

    private mutating func processImage(_ image: Markdown.Image) -> [Run] {
        let altText = image.children.compactMap { ($0 as? Markdown.Text)?.string }.joined()
        let source = image.source ?? ""

        let fileName = URL(fileURLWithPath: source).lastPathComponent

        guard let imageData = figures[fileName] else {
            // 圖片找不到，退化為文字
            return [Run(text: "[\(altText)](\(source))")]
        }

        let rId = "rId\(nextImageRId)"
        nextImageRId += 1

        let ext = (fileName as NSString).pathExtension.lowercased()
        let contentType: String
        switch ext {
        case "png": contentType = "image/png"
        case "jpg", "jpeg": contentType = "image/jpeg"
        case "gif": contentType = "image/gif"
        default: contentType = "image/png"
        }

        let imageRef = ImageReference(
            id: rId,
            fileName: fileName,
            contentType: contentType,
            data: imageData
        )
        document.images.append(imageRef)

        // 查詢 metadata 中的圖片尺寸
        var width = 4572000   // 預設 ~4.8 inches
        var height = 3429000  // 預設 ~3.6 inches

        if let meta = metadata?.figures.first(where: { $0.file.hasSuffix(fileName) }) {
            width = meta.width
            height = meta.height
        }

        let drawing = Drawing(
            width: width,
            height: height,
            imageId: rId,
            name: fileName,
            description: altText
        )

        return [Run.withDrawing(drawing)]
    }

    // MARK: - Metadata Overlay

    /// 套用 paragraph-level metadata
    private mutating func applyMetadataOverlay(to paragraph: inout OOXMLSwift.Paragraph) {
        defer { paragraphIndex += 1 }

        guard let meta = metadata?.paragraphs.first(where: { $0.index == paragraphIndex }) else {
            return
        }

        // Alignment
        if let alignmentStr = meta.alignment, let alignment = Alignment(rawValue: alignmentStr) {
            paragraph.properties.alignment = alignment
        }

        // Spacing
        if let spacing = meta.spacing {
            paragraph.properties.spacing = Spacing(
                before: spacing.before,
                after: spacing.after,
                line: spacing.line
            )
        }

        // Indentation
        if let indent = meta.indentation {
            paragraph.properties.indentation = Indentation(
                left: indent.left,
                right: indent.right,
                firstLine: indent.firstLine,
                hanging: indent.hanging
            )
        }

        // Run-level metadata overlay
        for runMeta in meta.runs {
            applyRunMetadata(to: &paragraph, runMeta: runMeta)
        }
    }

    /// 套用 run-level metadata（font, color, size）
    private func applyRunMetadata(to paragraph: inout OOXMLSwift.Paragraph, runMeta: RunMeta) {
        guard runMeta.range.count == 2 else { return }
        let start = runMeta.range[0]
        let end = runMeta.range[1]

        // 找到對應字元範圍的 runs
        var offset = 0
        for i in 0..<paragraph.runs.count {
            let runLen = paragraph.runs[i].text.count
            let runStart = offset
            let runEnd = offset + runLen

            // 檢查是否有重疊
            if runStart < end && runEnd > start {
                if let fontName = runMeta.fontName {
                    paragraph.runs[i].properties.fontName = fontName
                }
                if let fontSize = runMeta.fontSize {
                    paragraph.runs[i].properties.fontSize = fontSize
                }
                if let color = runMeta.color {
                    paragraph.runs[i].properties.color = color
                }
                if let highlight = runMeta.highlightColor,
                   let highlightColor = HighlightColor(rawValue: highlight) {
                    paragraph.runs[i].properties.highlight = highlightColor
                }
                if let underline = runMeta.underlineType,
                   let underlineType = UnderlineType(rawValue: underline) {
                    paragraph.runs[i].properties.underline = underlineType
                }
            }

            offset += runLen
        }
    }

    // MARK: - Document-Level Metadata

    private mutating func applyDocumentMetadata() {
        guard let meta = metadata else { return }

        // Document properties
        if let docInfo = meta.document {
            document.properties.title = docInfo.properties.title
            document.properties.creator = docInfo.properties.creator
            document.properties.subject = docInfo.properties.subject
            document.properties.description = docInfo.properties.description

            // Section properties
            if let section = docInfo.sections.first {
                if let pageSize = section.pageSize {
                    document.sectionProperties.pageSize = PageSize(
                        width: pageSize.width,
                        height: pageSize.height
                    )
                }
                if let orientation = section.orientation {
                    document.sectionProperties.orientation =
                        orientation == "landscape" ? .landscape : .portrait
                }
                if let margins = section.margins {
                    document.sectionProperties.pageMargins = PageMargins(
                        top: margins.top,
                        right: margins.right,
                        bottom: margins.bottom,
                        left: margins.left
                    )
                }
            }

            // Styles
            if !docInfo.styles.isEmpty {
                // 保留 default styles，加入 metadata 中定義的
                for styleMeta in docInfo.styles {
                    if !document.styles.contains(where: { $0.id == styleMeta.id }) {
                        document.styles.append(Style(
                            id: styleMeta.id,
                            name: styleMeta.name,
                            type: .paragraph,
                            basedOn: styleMeta.basedOn
                        ))
                    }
                }
            }
        }

        // 確保 Code 和 Quote styles 存在
        ensureStyleExists(id: "Code", name: "Code", basedOn: "Normal")
        ensureStyleExists(id: "Quote", name: "Quote", basedOn: "Normal")
    }

    private mutating func ensureStyleExists(id: String, name: String, basedOn: String?) {
        if !document.styles.contains(where: { $0.id == id }) {
            document.styles.append(Style(
                id: id,
                name: name,
                type: .paragraph,
                basedOn: basedOn
            ))
        }
    }
}
