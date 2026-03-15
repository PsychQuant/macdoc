import Foundation
import CommonConverterSwift
import MarkdownSwift
import SwiftSoup

public struct HTMLConverter: DocumentConverter {
    public static let sourceFormat = "html"

    public init() {}

    public func convert<W: CommonConverterSwift.StreamingOutput>(
        input: URL,
        output: inout W,
        options: ConversionOptions
    ) throws {
        let html: String
        if let utf8 = try? String(contentsOf: input, encoding: .utf8) {
            html = utf8
        } else if let latin1 = try? String(contentsOf: input, encoding: .isoLatin1) {
            html = latin1
        } else {
            html = try String(contentsOf: input, encoding: .utf8)
        }
        let document = try SwiftSoup.parse(html, "")

        if options.includeFrontmatter {
            try emitFrontmatter(document: document, source: input, output: &output)
        }

        if let body = document.body() {
            try emitBlockNodes(body.getChildNodes(), options: options, output: &output)
        } else {
            try emitBlockNodes(document.getChildNodes(), options: options, output: &output)
        }
    }

    private func emitFrontmatter<W: CommonConverterSwift.StreamingOutput>(
        document: Document,
        source: URL,
        output: inout W
    ) throws {
        try output.writeLine("---")
        let title = try document.title().trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty {
            try output.writeLine("title: \"\(escapeYAML(title))\"")
        }
        try output.writeLine("source: \"\(escapeYAML(source.lastPathComponent))\"")
        try output.writeLine("format: \"html\"")
        try output.writeLine("---")
        try output.writeBlankLine()
    }

    private func emitBlockNodes<W: CommonConverterSwift.StreamingOutput>(
        _ nodes: [Node],
        options: ConversionOptions,
        output: inout W
    ) throws {
        for node in nodes {
            try emitBlock(node, options: options, output: &output)
        }
    }

    private func emitBlock<W: CommonConverterSwift.StreamingOutput>(
        _ node: Node,
        options: ConversionOptions,
        output: inout W
    ) throws {
        if let textNode = node as? TextNode {
            let text = normalizeInlineWhitespace(textNode.getWholeText())
            guard !text.isEmpty else { return }
            try output.writeLine(MarkdownEscaping.escape(text, context: .paragraph))
            try output.writeBlankLine()
            return
        }

        guard let element = node as? Element else { return }
        let tag = element.tagName().lowercased()

        if ignoredTags.contains(tag) {
            return
        }

        switch tag {
        case "h1", "h2", "h3", "h4", "h5", "h6":
            let level = Int(String(tag.dropFirst())) ?? 1
            let text = trimMarkdownText(try renderInlineNodes(element.getChildNodes(), options: options))
            guard !text.isEmpty else { return }
            try output.writeLine("\(String(repeating: "#", count: max(1, min(level, 6)))) \(text)")
            try output.writeBlankLine()

        case "p":
            let text = trimMarkdownText(try renderInlineNodes(element.getChildNodes(), options: options))
            guard !text.isEmpty else { return }
            try output.writeLine(text)
            try output.writeBlankLine()

        case "ul":
            try emitList(element, ordered: false, depth: 0, options: options, output: &output)
            try output.writeBlankLine()

        case "ol":
            let startAttr = try? element.attr("start")
            let startIndex = startAttr.flatMap(Int.init) ?? 1
            try emitList(element, ordered: true, depth: 0, startIndex: startIndex, options: options, output: &output)
            try output.writeBlankLine()

        case "blockquote":
            try emitBlockquote(element, options: options, output: &output)

        case "pre":
            try emitCodeBlock(element, output: &output)

        case "hr":
            try output.writeLine("* * *")
            try output.writeBlankLine()

        case "table":
            try emitTable(element, options: options, output: &output)

        case "br":
            if options.hardLineBreaks {
                try output.writeLine("  ")
            } else {
                try output.writeLine("")
            }

        default:
            if containerTags.contains(tag) {
                let childElements = element.children().array()
                if childElements.contains(where: { blockTags.contains($0.tagName().lowercased()) }) {
                    try emitBlockNodes(element.getChildNodes(), options: options, output: &output)
                } else {
                    let text = trimMarkdownText(try renderInlineNodes(element.getChildNodes(), options: options))
                    guard !text.isEmpty else { return }
                    try output.writeLine(text)
                    try output.writeBlankLine()
                }
            } else {
                let text = trimMarkdownText(try renderInlineNode(element, options: options, preserveWhitespace: false))
                guard !text.isEmpty else { return }
                try output.writeLine(text)
                try output.writeBlankLine()
            }
        }
    }

    private func emitList<W: CommonConverterSwift.StreamingOutput>(
        _ list: Element,
        ordered: Bool,
        depth: Int,
        startIndex: Int = 1,
        options: ConversionOptions,
        output: inout W
    ) throws {
        let items = list.children().array().filter { $0.tagName().lowercased() == "li" }
        for (index, item) in items.enumerated() {
            let prefix = ordered ? "\(startIndex + index). " : "- "
            let indent = String(repeating: "  ", count: depth)
            let text = trimMarkdownText(try renderListItemInline(item, options: options))
            if !text.isEmpty {
                try output.writeLine("\(indent)\(prefix)\(text)")
            }

            for child in item.children().array() {
                let childTag = child.tagName().lowercased()
                if childTag == "ul" {
                    try emitList(child, ordered: false, depth: depth + 1, options: options, output: &output)
                } else if childTag == "ol" {
                    let nestedStart = (try? child.attr("start")).flatMap(Int.init) ?? 1
                    try emitList(child, ordered: true, depth: depth + 1, startIndex: nestedStart, options: options, output: &output)
                }
            }
        }
    }

    private func renderListItemInline(_ item: Element, options: ConversionOptions) throws -> String {
        var chunks: [String] = []
        for child in item.getChildNodes() {
            if let element = child as? Element {
                let tag = element.tagName().lowercased()
                if tag == "ul" || tag == "ol" {
                    continue
                }
                if blockTags.contains(tag) && tag != "p" {
                    let rendered = trimMarkdownText(try renderInlineNodes(element.getChildNodes(), options: options))
                    if !rendered.isEmpty {
                        chunks.append(rendered)
                    }
                    continue
                }
            }

            let rendered = try renderInlineNode(child, options: options, preserveWhitespace: false)
            if !rendered.isEmpty {
                chunks.append(rendered)
            }
        }
        return trimMarkdownText(chunks.joined())
    }

    private func emitBlockquote<W: CommonConverterSwift.StreamingOutput>(
        _ element: Element,
        options: ConversionOptions,
        output: inout W
    ) throws {
        var nested = CommonConverterSwift.StringOutput()
        try emitBlockNodes(element.getChildNodes(), options: options, output: &nested)
        let content = nested.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }

        for line in content.components(separatedBy: .newlines) {
            if line.isEmpty {
                try output.writeLine(">")
            } else {
                try output.writeLine("> \(line)")
            }
        }
        try output.writeBlankLine()
    }

    private func emitCodeBlock<W: CommonConverterSwift.StreamingOutput>(
        _ pre: Element,
        output: inout W
    ) throws {
        let codeElement = pre.children().array().first { $0.tagName().lowercased() == "code" }
        let sourceElement = codeElement ?? pre
        let code = trimTrailingNewlines(rawText(sourceElement, preserveWhitespace: true))
        guard !code.isEmpty else { return }
        let language = codeElement.flatMap { detectCodeLanguage(from: $0) } ?? detectCodeLanguage(from: pre)
        if let language, !language.isEmpty {
            try output.writeLine("```\(language)")
        } else {
            try output.writeLine("```")
        }
        try output.writeLine(code)
        try output.writeLine("```")
        try output.writeBlankLine()
    }

    private func emitTable<W: CommonConverterSwift.StreamingOutput>(
        _ table: Element,
        options: ConversionOptions,
        output: inout W
    ) throws {
        let rows = try table.select("tr").array()
        guard !rows.isEmpty else { return }

        let matrix: [[String]] = try rows.map { row in
            let cells = row.children().array().filter {
                let tag = $0.tagName().lowercased()
                return tag == "th" || tag == "td"
            }
            return try cells.map { cell in
                let rendered = try renderInlineNodes(cell.getChildNodes(), options: options)
                return sanitizeTableCell(trimMarkdownText(rendered))
            }
        }.filter { !$0.isEmpty }

        guard let header = matrix.first, !header.isEmpty else { return }
        let columnCount = matrix.map(\.count).max() ?? header.count
        let normalized = matrix.map { row in
            row + Array(repeating: "", count: max(0, columnCount - row.count))
        }

        try output.writeLine("| \(normalized[0].joined(separator: " | ")) |")
        try output.writeLine("|\(Array(repeating: "---", count: columnCount).joined(separator: "|"))|")
        for row in normalized.dropFirst() {
            try output.writeLine("| \(row.joined(separator: " | ")) |")
        }
        try output.writeBlankLine()
    }

    private func renderInline(_ element: Element, options: ConversionOptions) throws -> String {
        try renderInlineNodes(element.getChildNodes(), options: options)
    }

    private func renderInlineNodes(
        _ nodes: [Node],
        options: ConversionOptions,
        preserveWhitespace: Bool = false
    ) throws -> String {
        try nodes.map { try renderInlineNode($0, options: options, preserveWhitespace: preserveWhitespace) }.joined()
    }

    private func renderInlineNode(
        _ node: Node,
        options: ConversionOptions,
        preserveWhitespace: Bool
    ) throws -> String {
        if let textNode = node as? TextNode {
            let text = preserveWhitespace ? textNode.getWholeText() : normalizeInlineWhitespace(textNode.getWholeText())
            return preserveWhitespace ? text : MarkdownEscaping.escape(text, context: .paragraph)
        }

        guard let element = node as? Element else { return "" }
        let tag = element.tagName().lowercased()

        switch tag {
        case "strong", "b":
            return MarkdownInline.bold(trimMarkdownText(try renderInlineNodes(element.getChildNodes(), options: options, preserveWhitespace: preserveWhitespace)))

        case "em", "i":
            return MarkdownInline.italic(trimMarkdownText(try renderInlineNodes(element.getChildNodes(), options: options, preserveWhitespace: preserveWhitespace)))

        case "del", "s", "strike":
            return MarkdownInline.strikethrough(trimMarkdownText(try renderInlineNodes(element.getChildNodes(), options: options, preserveWhitespace: preserveWhitespace)))

        case "code":
            if let parent = element.parent(), parent.tagName().lowercased() == "pre" {
                return rawText(element, preserveWhitespace: true)
            }
            return MarkdownInline.code(trimMarkdownText(rawText(element, preserveWhitespace: true)))

        case "a":
            let text = trimMarkdownText(try renderInlineNodes(element.getChildNodes(), options: options, preserveWhitespace: preserveWhitespace))
            let href = try element.attr("href")
            guard !href.isEmpty else { return text }
            return MarkdownInline.link(text.isEmpty ? href : text, url: href)

        case "img":
            let src = try element.attr("src")
            guard !src.isEmpty else { return "" }
            let alt = try element.attr("alt")
            let title = try element.attr("title")
            return title.isEmpty
                ? MarkdownInline.image(alt, url: src)
                : MarkdownInline.image(alt, url: src, title: title)

        case "br":
            return options.hardLineBreaks ? MarkdownInline.hardBreak() : "\n"

        case "u":
            let inner = trimMarkdownText(try renderInlineNodes(element.getChildNodes(), options: options, preserveWhitespace: preserveWhitespace))
            guard options.useHTMLExtensions else { return inner }
            return MarkdownInline.rawHTML("<u>\(inner)</u>")

        case "sup":
            let inner = trimMarkdownText(try renderInlineNodes(element.getChildNodes(), options: options, preserveWhitespace: preserveWhitespace))
            guard options.useHTMLExtensions else { return inner }
            return MarkdownInline.rawHTML("<sup>\(inner)</sup>")

        case "sub":
            let inner = trimMarkdownText(try renderInlineNodes(element.getChildNodes(), options: options, preserveWhitespace: preserveWhitespace))
            guard options.useHTMLExtensions else { return inner }
            return MarkdownInline.rawHTML("<sub>\(inner)</sub>")

        case "mark":
            let inner = trimMarkdownText(try renderInlineNodes(element.getChildNodes(), options: options, preserveWhitespace: preserveWhitespace))
            guard options.useHTMLExtensions else { return inner }
            return MarkdownInline.rawHTML("<mark>\(inner)</mark>")

        case "p", "span", "small", "big", "label", "div", "section", "article", "header", "footer", "main", "body":
            return try renderInlineNodes(element.getChildNodes(), options: options, preserveWhitespace: preserveWhitespace)

        case "script", "style", "noscript":
            return ""

        default:
            return try renderInlineNodes(element.getChildNodes(), options: options, preserveWhitespace: preserveWhitespace)
        }
    }

    private func rawText(_ node: Node, preserveWhitespace: Bool) -> String {
        if let textNode = node as? TextNode {
            return preserveWhitespace ? textNode.getWholeText() : normalizeInlineWhitespace(textNode.getWholeText())
        }
        guard let element = node as? Element else { return "" }
        return element.getChildNodes().map { rawText($0, preserveWhitespace: preserveWhitespace) }.joined()
    }

    private func detectCodeLanguage(from element: Element) -> String? {
        guard let className = try? element.className(), !className.isEmpty else {
            return nil
        }

        for token in className.split(whereSeparator: \.isWhitespace) {
            let value = String(token)
            if value.hasPrefix("language-") {
                return String(value.dropFirst("language-".count))
            }
            if value.hasPrefix("lang-") {
                return String(value.dropFirst("lang-".count))
            }
        }
        return nil
    }

    private func normalizeInlineWhitespace(_ text: String) -> String {
        let collapsed = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return collapsed
    }

    private func trimMarkdownText(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sanitizeTableCell(_ text: String) -> String {
        text
            .replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\n", with: " ")
    }

    private func trimTrailingNewlines(_ text: String) -> String {
        String(text.reversed().drop(while: { $0 == "\n" || $0 == "\r" }).reversed())
    }

    private func escapeYAML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private let ignoredTags: Set<String> = ["script", "style", "noscript", "head"]

    private let containerTags: Set<String> = [
        "body", "main", "article", "section", "div", "header", "footer", "aside", "nav"
    ]

    private let blockTags: Set<String> = [
        "address", "article", "aside", "blockquote", "details", "dialog", "div", "dl", "fieldset",
        "figcaption", "figure", "footer", "form", "h1", "h2", "h3", "h4", "h5", "h6", "header",
        "hr", "li", "main", "nav", "ol", "p", "pre", "section", "table", "ul"
    ]
}
