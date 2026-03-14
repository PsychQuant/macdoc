import Foundation
import PDFKit
import DocConverterSwift

public struct PDFConverter: DocumentConverter {
    public static let sourceFormat = "pdf"

    public init() {}

    public func convert<W: DocConverterSwift.StreamingOutput>(
        input: URL,
        output: inout W,
        options: ConversionOptions
    ) throws {
        guard FileManager.default.fileExists(atPath: input.path) else {
            throw ConversionError.fileNotFound(input.path)
        }
        guard let document = PDFDocument(url: input) else {
            throw ConversionError.invalidDocument("無法開啟 PDF: \(input.lastPathComponent)")
        }

        if options.includeFrontmatter {
            try emitFrontmatter(document: document, source: input, output: &output)
        }

        var emittedPage = false
        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            let pageBlocks = extractBlocks(from: page, options: options)
            guard !pageBlocks.isEmpty else { continue }

            if emittedPage {
                try output.writeLine("---")
                try output.writeBlankLine()
            }

            for block in pageBlocks {
                switch block {
                case .heading(let text):
                    try output.writeLine("# \(text)")
                    try output.writeBlankLine()
                case .paragraph(let text):
                    try output.writeLine(text)
                    try output.writeBlankLine()
                case .unorderedList(let items):
                    for item in items {
                        try output.writeLine(item)
                    }
                    try output.writeBlankLine()
                case .orderedList(let items):
                    for item in items {
                        try output.writeLine(item)
                    }
                    try output.writeBlankLine()
                }
            }

            emittedPage = true
        }
    }

    private func emitFrontmatter<W: DocConverterSwift.StreamingOutput>(
        document: PDFDocument,
        source: URL,
        output: inout W
    ) throws {
        try output.writeLine("---")
        if let title = document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String,
           !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try output.writeLine("title: \"\(escapeYAML(title))\"")
        }
        try output.writeLine("source: \"\(escapeYAML(source.lastPathComponent))\"")
        try output.writeLine("format: \"pdf\"")
        try output.writeLine("pages: \(document.pageCount)")
        try output.writeLine("---")
        try output.writeBlankLine()
    }

    private func extractBlocks(from page: PDFPage, options: ConversionOptions) -> [MarkdownBlock] {
        let lines = extractLineFragments(from: page)
        guard !lines.isEmpty else { return [] }

        let grouped = groupLinesIntoBlocks(lines)
        let bodyLineHeight = median(lines.map(\.height))

        return grouped.compactMap { block in
            classify(block: block, bodyLineHeight: bodyLineHeight, options: options)
        }
    }

    private func extractLineFragments(from page: PDFPage) -> [LineFragment] {
        let bounds = page.bounds(for: .mediaBox)
        guard let selection = page.selection(for: bounds) else { return [] }

        return selection.selectionsByLine()
            .compactMap { line in
                let text = normalizedLine(line.string ?? "")
                guard !text.isEmpty else { return nil }
                return LineFragment(
                    text: text,
                    minY: line.bounds(for: page).minY,
                    height: line.bounds(for: page).height,
                    minX: line.bounds(for: page).minX
                )
            }
            .sorted {
                if abs($0.minY - $1.minY) > 0.5 {
                    return $0.minY > $1.minY
                }
                return $0.minX < $1.minX
            }
    }

    private func groupLinesIntoBlocks(_ lines: [LineFragment]) -> [[LineFragment]] {
        guard !lines.isEmpty else { return [] }
        guard lines.count > 1 else { return [lines] }

        let verticalSteps = zip(lines, lines.dropFirst())
            .map { max(0, $0.0.minY - $0.1.minY) }
            .filter { $0 > 0 }

        let baseStep = median(verticalSteps)
        let threshold = max(18, baseStep * 1.6)

        var blocks: [[LineFragment]] = []
        var current: [LineFragment] = [lines[0]]

        for (previous, currentLine) in zip(lines, lines.dropFirst()) {
            let delta = max(0, previous.minY - currentLine.minY)
            if delta > threshold {
                blocks.append(current)
                current = [currentLine]
            } else {
                current.append(currentLine)
            }
        }

        if !current.isEmpty {
            blocks.append(current)
        }

        return blocks
    }

    private func classify(
        block: [LineFragment],
        bodyLineHeight: Double,
        options: ConversionOptions
    ) -> MarkdownBlock? {
        let lines = block.map(\.text)

        if let items = parseUnorderedList(lines) {
            return .unorderedList(items)
        }
        if let items = parseOrderedList(lines) {
            return .orderedList(items)
        }

        let merged = mergeLines(lines, hardBreaks: options.hardLineBreaks)
        guard !merged.isEmpty else { return nil }

        let isHeading = block.count == 1
            && block[0].height > max(bodyLineHeight * 1.15, 18)
            && looksLikeHeading(merged)

        if isHeading {
            return .heading(merged)
        }

        return .paragraph(merged)
    }

    private func parseUnorderedList(_ lines: [String]) -> [String]? {
        guard !lines.isEmpty else { return nil }

        var items: [String] = []
        for line in lines {
            guard let captures = captureGroups(in: line, pattern: #"^([\t ]*)([•◦▪‣*\-])\s+(.+)$"#), captures.count == 3 else {
                return nil
            }
            let indentLevel = indentationLevel(captures[0])
            let text = normalizeInlineSpacing(captures[2])
            guard !text.isEmpty else { return nil }
            items.append("\(String(repeating: "  ", count: indentLevel))- \(text)")
        }

        return items
    }

    private func parseOrderedList(_ lines: [String]) -> [String]? {
        guard !lines.isEmpty else { return nil }

        var items: [String] = []
        for line in lines {
            guard let captures = captureGroups(in: line, pattern: #"^([\t ]*)(\d+)[\.)]\s+(.+)$"#), captures.count == 3 else {
                return nil
            }
            let indentLevel = indentationLevel(captures[0])
            let ordinal = captures[1]
            let text = normalizeInlineSpacing(captures[2])
            guard !text.isEmpty else { return nil }
            items.append("\(String(repeating: "  ", count: indentLevel))\(ordinal). \(text)")
        }

        return items
    }

    private func mergeLines(_ lines: [String], hardBreaks: Bool) -> String {
        guard let first = lines.first else { return "" }

        var merged = normalizeInlineSpacing(first)
        for line in lines.dropFirst() {
            let next = normalizeInlineSpacing(line)
            guard !next.isEmpty else { continue }

            if merged.hasSuffix("-"), startsWithLowercaseWord(next) {
                merged.removeLast()
                merged += next
            } else if hardBreaks {
                merged += "  \n" + next
            } else {
                merged += " " + next
            }
        }

        return merged.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func looksLikeHeading(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard trimmed.count <= 120 else { return false }
        guard !trimmed.hasSuffix("."), !trimmed.hasSuffix("?"), !trimmed.hasSuffix("!"), !trimmed.hasSuffix(";"), !trimmed.hasSuffix(",") else {
            return false
        }

        let words = trimmed.split(whereSeparator: \.isWhitespace)
        guard (1...12).contains(words.count) else { return false }

        let lowercase = trimmed.lowercased()
        if lowercase.hasPrefix("chapter ") || lowercase.hasPrefix("section ") || lowercase.hasPrefix("appendix ") {
            return true
        }

        return true
    }

    private func startsWithLowercaseWord(_ text: String) -> Bool {
        guard let scalar = text.unicodeScalars.first else { return false }
        return CharacterSet.lowercaseLetters.contains(scalar)
    }

    private func indentationLevel(_ rawIndent: String) -> Int {
        let spaces = rawIndent.reduce(into: 0) { partial, character in
            partial += character == "\t" ? 2 : 1
        }
        return max(0, spaces / 2)
    }

    private func normalizedLine(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizeInlineSpacing(_ text: String) -> String {
        text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private func captureGroups(in text: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else {
            return nil
        }

        return (1..<match.numberOfRanges).compactMap { index in
            let range = match.range(at: index)
            guard let swiftRange = Range(range, in: text) else {
                return nil
            }
            return String(text[swiftRange])
        }
    }

    private func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    private func escapeYAML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

private struct LineFragment {
    let text: String
    let minY: Double
    let height: Double
    let minX: Double
}

private enum MarkdownBlock {
    case heading(String)
    case paragraph(String)
    case unorderedList([String])
    case orderedList([String])
}
