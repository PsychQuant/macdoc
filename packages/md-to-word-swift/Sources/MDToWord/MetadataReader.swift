import Foundation
import Yams

// MARK: - Metadata Models (鏡像 MetadataCollector 輸出)

/// 完整的文件 metadata
public struct DocumentMetadata {
    public var version: String
    public var source: SourceInfo
    public var document: DocumentInfo?
    public var paragraphs: [ParagraphMeta]
    public var tables: [TableMeta]
    public var figures: [FigureMeta]

    public init(
        version: String = "1.0",
        source: SourceInfo = SourceInfo(format: "docx"),
        document: DocumentInfo? = nil,
        paragraphs: [ParagraphMeta] = [],
        tables: [TableMeta] = [],
        figures: [FigureMeta] = []
    ) {
        self.version = version
        self.source = source
        self.document = document
        self.paragraphs = paragraphs
        self.tables = tables
        self.figures = figures
    }
}

public struct SourceInfo {
    public var format: String
    public var file: String?

    public init(format: String, file: String? = nil) {
        self.format = format
        self.file = file
    }
}

public struct DocumentInfo {
    public var properties: PropertyMap
    public var styles: [StyleMeta]
    public var sections: [SectionMeta]
    public var comments: [CommentMeta]
    public var numbering: [NumberingDefMeta]

    public init(
        properties: PropertyMap = PropertyMap(),
        styles: [StyleMeta] = [],
        sections: [SectionMeta] = [],
        comments: [CommentMeta] = [],
        numbering: [NumberingDefMeta] = []
    ) {
        self.properties = properties
        self.styles = styles
        self.sections = sections
        self.comments = comments
        self.numbering = numbering
    }
}

public struct PropertyMap {
    public var title: String?
    public var creator: String?
    public var subject: String?
    public var description: String?
    public var keywords: String?
    public var created: String?
    public var modified: String?

    public init(title: String? = nil, creator: String? = nil,
                subject: String? = nil, description: String? = nil,
                keywords: String? = nil, created: String? = nil,
                modified: String? = nil) {
        self.title = title
        self.creator = creator
        self.subject = subject
        self.description = description
        self.keywords = keywords
        self.created = created
        self.modified = modified
    }
}

public struct StyleMeta {
    public var id: String
    public var name: String
    public var basedOn: String?

    public init(id: String, name: String, basedOn: String? = nil) {
        self.id = id
        self.name = name
        self.basedOn = basedOn
    }
}

public struct CommentMeta {
    public var id: Int
    public var author: String
    public var text: String
    public var paragraphIndex: Int
    public var parentId: Int?
    public var done: Bool

    public init(id: Int, author: String, text: String,
                paragraphIndex: Int, parentId: Int? = nil, done: Bool = false) {
        self.id = id
        self.author = author
        self.text = text
        self.paragraphIndex = paragraphIndex
        self.parentId = parentId
        self.done = done
    }
}

public struct NumberingDefMeta {
    public var abstractNumId: Int
    public var levels: [NumberingLevelMeta]

    public init(abstractNumId: Int, levels: [NumberingLevelMeta] = []) {
        self.abstractNumId = abstractNumId
        self.levels = levels
    }
}

public struct NumberingLevelMeta {
    public var ilvl: Int
    public var numFmt: String
    public var lvlText: String
    public var start: Int
    public var indent: Int
    public var fontName: String?

    public init(ilvl: Int, numFmt: String, lvlText: String,
                start: Int = 1, indent: Int = 720, fontName: String? = nil) {
        self.ilvl = ilvl
        self.numFmt = numFmt
        self.lvlText = lvlText
        self.start = start
        self.indent = indent
        self.fontName = fontName
    }
}

public struct SectionMeta {
    public var pageSize: PageSizeMeta?
    public var orientation: String?
    public var margins: MarginsMeta?

    public init(pageSize: PageSizeMeta? = nil, orientation: String? = nil,
                margins: MarginsMeta? = nil) {
        self.pageSize = pageSize
        self.orientation = orientation
        self.margins = margins
    }
}

public struct PageSizeMeta {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}

public struct MarginsMeta {
    public var top: Int
    public var bottom: Int
    public var left: Int
    public var right: Int

    public init(top: Int, bottom: Int, left: Int, right: Int) {
        self.top = top
        self.bottom = bottom
        self.left = left
        self.right = right
    }
}

public struct ParagraphMeta {
    public var index: Int
    public var alignment: String?
    public var spacing: SpacingMeta?
    public var indentation: IndentationMeta?
    public var commentIds: [Int]?
    public var bookmarkNames: [String]?
    public var keepNext: Bool?
    public var keepLines: Bool?
    public var pageBreakBefore: Bool?
    public var border: ParagraphBorderMeta?
    public var shading: ShadingMeta?
    public var runs: [RunMeta]

    public init(index: Int, alignment: String? = nil,
                spacing: SpacingMeta? = nil,
                indentation: IndentationMeta? = nil,
                commentIds: [Int]? = nil,
                bookmarkNames: [String]? = nil,
                keepNext: Bool? = nil,
                keepLines: Bool? = nil,
                pageBreakBefore: Bool? = nil,
                border: ParagraphBorderMeta? = nil,
                shading: ShadingMeta? = nil,
                runs: [RunMeta] = []) {
        self.index = index
        self.alignment = alignment
        self.spacing = spacing
        self.indentation = indentation
        self.commentIds = commentIds
        self.bookmarkNames = bookmarkNames
        self.keepNext = keepNext
        self.keepLines = keepLines
        self.pageBreakBefore = pageBreakBefore
        self.border = border
        self.shading = shading
        self.runs = runs
    }
}

public struct ParagraphBorderMeta {
    public var top: BorderStyleMeta?
    public var bottom: BorderStyleMeta?
    public var left: BorderStyleMeta?
    public var right: BorderStyleMeta?

    public init(top: BorderStyleMeta? = nil, bottom: BorderStyleMeta? = nil,
                left: BorderStyleMeta? = nil, right: BorderStyleMeta? = nil) {
        self.top = top
        self.bottom = bottom
        self.left = left
        self.right = right
    }
}

public struct BorderStyleMeta {
    public var type: String
    public var color: String
    public var size: Int

    public init(type: String, color: String, size: Int) {
        self.type = type
        self.color = color
        self.size = size
    }
}

public struct ShadingMeta {
    public var fill: String
    public var pattern: String?

    public init(fill: String, pattern: String? = nil) {
        self.fill = fill
        self.pattern = pattern
    }
}

public struct SpacingMeta {
    public var before: Int?
    public var after: Int?
    public var line: Int?

    public init(before: Int? = nil, after: Int? = nil, line: Int? = nil) {
        self.before = before
        self.after = after
        self.line = line
    }
}

public struct IndentationMeta {
    public var left: Int?
    public var right: Int?
    public var firstLine: Int?
    public var hanging: Int?

    public init(left: Int? = nil, right: Int? = nil,
                firstLine: Int? = nil, hanging: Int? = nil) {
        self.left = left
        self.right = right
        self.firstLine = firstLine
        self.hanging = hanging
    }
}

public struct RunMeta {
    public var range: [Int]  // [start, end]
    public var fontName: String?
    public var fontSize: Int?
    public var color: String?
    public var highlightColor: String?
    public var underlineType: String?
    public var characterSpacing: CharacterSpacingMeta?

    public init(range: [Int], fontName: String? = nil, fontSize: Int? = nil,
                color: String? = nil, highlightColor: String? = nil,
                underlineType: String? = nil, characterSpacing: CharacterSpacingMeta? = nil) {
        self.range = range
        self.fontName = fontName
        self.fontSize = fontSize
        self.color = color
        self.highlightColor = highlightColor
        self.underlineType = underlineType
        self.characterSpacing = characterSpacing
    }
}

public struct CharacterSpacingMeta {
    public var spacing: Int?
    public var position: Int?
    public var kern: Int?

    public init(spacing: Int? = nil, position: Int? = nil, kern: Int? = nil) {
        self.spacing = spacing
        self.position = position
        self.kern = kern
    }
}

public struct TableMeta {
    public var index: Int
    public var width: Int?
    public var widthType: String?
    public var alignment: String?
    public var layout: String?
    public var rows: [TableRowMeta]

    public init(index: Int, width: Int? = nil, widthType: String? = nil,
                alignment: String? = nil, layout: String? = nil,
                rows: [TableRowMeta] = []) {
        self.index = index
        self.width = width
        self.widthType = widthType
        self.alignment = alignment
        self.layout = layout
        self.rows = rows
    }
}

public struct TableRowMeta {
    public var rowIndex: Int
    public var isHeader: Bool?
    public var height: Int?

    public init(rowIndex: Int, isHeader: Bool? = nil, height: Int? = nil) {
        self.rowIndex = rowIndex
        self.isHeader = isHeader
        self.height = height
    }
}

public struct FigureMeta {
    public var id: String
    public var file: String
    public var contentType: String
    public var placement: String
    public var width: Int
    public var height: Int
    public var altText: String?

    public init(id: String, file: String, contentType: String,
                placement: String, width: Int, height: Int,
                altText: String? = nil) {
        self.id = id
        self.file = file
        self.contentType = contentType
        self.placement = placement
        self.width = width
        self.height = height
        self.altText = altText
    }
}

// MARK: - MetadataReader

/// 讀取 MetadataCollector 輸出的 .meta.yaml sidecar
public struct MetadataReader {

    public static func read(from url: URL) throws -> DocumentMetadata {
        let content = try String(contentsOf: url, encoding: .utf8)
        return try parse(content)
    }

    public static func parse(_ yaml: String) throws -> DocumentMetadata {
        guard let dict = try Yams.load(yaml: yaml) as? [String: Any] else {
            throw MetadataError.invalidFormat("Root must be a YAML mapping")
        }

        let version = dict["version"] as? String ?? "1.0"

        // Source
        let source: SourceInfo
        if let sourceDict = dict["source"] as? [String: Any] {
            source = SourceInfo(
                format: sourceDict["format"] as? String ?? "docx",
                file: sourceDict["file"] as? String
            )
        } else {
            source = SourceInfo(format: "docx")
        }

        // Document
        var documentInfo: DocumentInfo?
        if let docDict = dict["document"] as? [String: Any] {
            documentInfo = parseDocumentInfo(docDict)
        }

        // Paragraphs
        var paragraphs: [ParagraphMeta] = []
        if let paraArray = dict["paragraphs"] as? [[String: Any]] {
            paragraphs = paraArray.compactMap { parseParagraphMeta($0) }
        }

        // Tables
        var tables: [TableMeta] = []
        if let tableArray = dict["tables"] as? [[String: Any]] {
            tables = tableArray.compactMap { parseTableMeta($0) }
        }

        // Figures
        var figures: [FigureMeta] = []
        if let figArray = dict["figures"] as? [[String: Any]] {
            figures = figArray.compactMap { parseFigureMeta($0) }
        }

        return DocumentMetadata(
            version: version,
            source: source,
            document: documentInfo,
            paragraphs: paragraphs,
            tables: tables,
            figures: figures
        )
    }

    // MARK: - Private Parsers

    private static func parseDocumentInfo(_ dict: [String: Any]) -> DocumentInfo {
        var properties = PropertyMap()
        if let propsDict = dict["properties"] as? [String: Any] {
            properties.title = propsDict["title"] as? String
            properties.creator = propsDict["creator"] as? String
            properties.subject = propsDict["subject"] as? String
            properties.description = propsDict["description"] as? String
            properties.keywords = propsDict["keywords"] as? String
            properties.created = propsDict["created"] as? String
            properties.modified = propsDict["modified"] as? String
        }

        var styles: [StyleMeta] = []
        if let stylesArray = dict["styles"] as? [[String: Any]] {
            styles = stylesArray.map { styleDict in
                StyleMeta(
                    id: styleDict["id"] as? String ?? "",
                    name: styleDict["name"] as? String ?? "",
                    basedOn: styleDict["basedOn"] as? String
                )
            }
        }

        var sections: [SectionMeta] = []
        if let sectionsArray = dict["sections"] as? [[String: Any]] {
            sections = sectionsArray.map { parseSectionMeta($0) }
        }

        var comments: [CommentMeta] = []
        if let commentsArray = dict["comments"] as? [[String: Any]] {
            comments = commentsArray.compactMap { parseCommentMeta($0) }
        }

        var numbering: [NumberingDefMeta] = []
        if let numberingArray = dict["numbering"] as? [[String: Any]] {
            numbering = numberingArray.compactMap { parseNumberingDefMeta($0) }
        }

        return DocumentInfo(properties: properties, styles: styles, sections: sections,
                          comments: comments, numbering: numbering)
    }

    private static func parseSectionMeta(_ dict: [String: Any]) -> SectionMeta {
        var pageSize: PageSizeMeta?
        if let psDict = dict["pageSize"] as? [String: Any] {
            pageSize = PageSizeMeta(
                width: psDict["width"] as? Int ?? 12240,
                height: psDict["height"] as? Int ?? 15840
            )
        }

        var margins: MarginsMeta?
        if let mDict = dict["margins"] as? [String: Any] {
            margins = MarginsMeta(
                top: mDict["top"] as? Int ?? 1440,
                bottom: mDict["bottom"] as? Int ?? 1440,
                left: mDict["left"] as? Int ?? 1440,
                right: mDict["right"] as? Int ?? 1440
            )
        }

        return SectionMeta(
            pageSize: pageSize,
            orientation: dict["orientation"] as? String,
            margins: margins
        )
    }

    private static func parseCommentMeta(_ dict: [String: Any]) -> CommentMeta? {
        guard let id = dict["id"] as? Int,
              let author = dict["author"] as? String,
              let text = dict["text"] as? String else { return nil }

        return CommentMeta(
            id: id,
            author: author,
            text: text,
            paragraphIndex: dict["paragraphIndex"] as? Int ?? 0,
            parentId: dict["parentId"] as? Int,
            done: dict["done"] as? Bool ?? false
        )
    }

    private static func parseNumberingDefMeta(_ dict: [String: Any]) -> NumberingDefMeta? {
        guard let abstractNumId = dict["abstractNumId"] as? Int else { return nil }

        var levels: [NumberingLevelMeta] = []
        if let levelsArray = dict["levels"] as? [[String: Any]] {
            levels = levelsArray.compactMap { levelDict in
                guard let ilvl = levelDict["ilvl"] as? Int,
                      let numFmt = levelDict["numFmt"] as? String,
                      let lvlText = levelDict["lvlText"] as? String else { return nil }
                return NumberingLevelMeta(
                    ilvl: ilvl,
                    numFmt: numFmt,
                    lvlText: lvlText,
                    start: levelDict["start"] as? Int ?? 1,
                    indent: levelDict["indent"] as? Int ?? 720,
                    fontName: levelDict["fontName"] as? String
                )
            }
        }

        return NumberingDefMeta(abstractNumId: abstractNumId, levels: levels)
    }

    private static func parseParagraphMeta(_ dict: [String: Any]) -> ParagraphMeta? {
        guard let index = dict["index"] as? Int else { return nil }

        var spacing: SpacingMeta?
        if let sDict = dict["spacing"] as? [String: Any] {
            spacing = SpacingMeta(
                before: sDict["before"] as? Int,
                after: sDict["after"] as? Int,
                line: sDict["line"] as? Int
            )
        }

        var indentation: IndentationMeta?
        if let iDict = dict["indentation"] as? [String: Any] {
            indentation = IndentationMeta(
                left: iDict["left"] as? Int,
                right: iDict["right"] as? Int,
                firstLine: iDict["firstLine"] as? Int,
                hanging: iDict["hanging"] as? Int
            )
        }

        var runs: [RunMeta] = []
        if let runsArray = dict["runs"] as? [[String: Any]] {
            runs = runsArray.compactMap { parseRunMeta($0) }
        }

        let commentIds = (dict["commentIds"] as? [Any])?.compactMap { $0 as? Int }

        var border: ParagraphBorderMeta?
        if let borderDict = dict["border"] as? [String: Any] {
            border = ParagraphBorderMeta(
                top: parseBorderStyleMeta(borderDict["top"]),
                bottom: parseBorderStyleMeta(borderDict["bottom"]),
                left: parseBorderStyleMeta(borderDict["left"]),
                right: parseBorderStyleMeta(borderDict["right"])
            )
        }

        var shading: ShadingMeta?
        if let shadingDict = dict["shading"] as? [String: Any] {
            shading = ShadingMeta(
                fill: shadingDict["fill"] as? String ?? "",
                pattern: shadingDict["pattern"] as? String
            )
        }

        return ParagraphMeta(
            index: index,
            alignment: dict["alignment"] as? String,
            spacing: spacing,
            indentation: indentation,
            commentIds: commentIds,
            bookmarkNames: dict["bookmarkNames"] as? [String],
            keepNext: dict["keepNext"] as? Bool,
            keepLines: dict["keepLines"] as? Bool,
            pageBreakBefore: dict["pageBreakBefore"] as? Bool,
            border: border,
            shading: shading,
            runs: runs
        )
    }

    private static func parseBorderStyleMeta(_ value: Any?) -> BorderStyleMeta? {
        guard let dict = value as? [String: Any],
              let type = dict["type"] as? String,
              let color = dict["color"] as? String,
              let size = dict["size"] as? Int else { return nil }
        return BorderStyleMeta(type: type, color: color, size: size)
    }

    private static func parseRunMeta(_ dict: [String: Any]) -> RunMeta? {
        guard let range = (dict["range"] as? [Any])?.compactMap({ $0 as? Int }),
              range.count == 2 else { return nil }

        var color = dict["color"] as? String
        // 移除 "#" 前綴（MetadataCollector 輸出 "#FF0000" 格式）
        if let c = color, c.hasPrefix("#") {
            color = String(c.dropFirst())
        }

        var characterSpacing: CharacterSpacingMeta?
        if let csDict = dict["characterSpacing"] as? [String: Any] {
            characterSpacing = CharacterSpacingMeta(
                spacing: csDict["spacing"] as? Int,
                position: csDict["position"] as? Int,
                kern: csDict["kern"] as? Int
            )
        }

        return RunMeta(
            range: range,
            fontName: dict["font"] as? String,
            fontSize: dict["fontSize"] as? Int,
            color: color,
            highlightColor: dict["highlight"] as? String,
            underlineType: dict["underline"] as? String,
            characterSpacing: characterSpacing
        )
    }

    private static func parseTableMeta(_ dict: [String: Any]) -> TableMeta? {
        guard let index = dict["index"] as? Int else { return nil }

        var rows: [TableRowMeta] = []
        if let rowsArray = dict["rows"] as? [[String: Any]] {
            rows = rowsArray.compactMap { rowDict in
                guard let rowIndex = rowDict["rowIndex"] as? Int else { return nil }
                return TableRowMeta(
                    rowIndex: rowIndex,
                    isHeader: rowDict["isHeader"] as? Bool,
                    height: rowDict["height"] as? Int
                )
            }
        }

        return TableMeta(
            index: index,
            width: dict["width"] as? Int,
            widthType: dict["widthType"] as? String,
            alignment: dict["alignment"] as? String,
            layout: dict["layout"] as? String,
            rows: rows
        )
    }

    private static func parseFigureMeta(_ dict: [String: Any]) -> FigureMeta? {
        guard let id = dict["id"] as? String,
              let file = dict["file"] as? String else { return nil }

        return FigureMeta(
            id: id,
            file: file,
            contentType: dict["contentType"] as? String ?? "image/png",
            placement: dict["placement"] as? String ?? "inline",
            width: dict["width"] as? Int ?? 0,
            height: dict["height"] as? Int ?? 0,
            altText: dict["altText"] as? String
        )
    }
}

// MARK: - Errors

public enum MetadataError: Error, LocalizedError {
    case invalidFormat(String)
    case fileNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .invalidFormat(let msg): return "Invalid metadata format: \(msg)"
        case .fileNotFound(let path): return "Metadata file not found: \(path)"
        }
    }
}
