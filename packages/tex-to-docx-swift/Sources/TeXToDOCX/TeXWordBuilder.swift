import Foundation
import CommonConverterSwift
import OOXMLSwift

// MARK: - Fallback colors (used when preamble doesn't define them)
private enum DefaultColor {
    static let titlePink = "CC0066"
    static let keywordBlue = "002060"
    static let timecodeGray = "808080"
    static let summaryBorder = "999999"
    static let summaryBackground = "F5F5F5"
    static let sectionBg = "333333"
    static let sectionFg = "FFFFFF"
    static let subsectionBrown = "663300"
    static let subsubsectionBlue = "003399"
}

struct TeXWordBuilder {
    private let source: String
    private let sourceURL: URL
    private let options: ConversionOptions
    private var document = WordDocument()
    private var lines: [String] = []
    private var cursor = 0

    /// Full preamble config (colors, fonts, titleformat)
    private var config: TeXPreambleParser.PreambleConfig

    init(source: String, sourceURL: URL, options: ConversionOptions) {
        self.source = source
        self.sourceURL = sourceURL
        self.options = options
        self.config = TeXPreambleParser.parse(from: source)
    }

    /// Resolve a color name via preamble definitions, falling back to defaults
    private func color(_ name: String, fallback: String) -> String {
        config.colors.resolve(name, fallback: fallback)
    }

    /// Resolve a font command (e.g. "songti") to system font name
    private func font(_ command: String) -> String? {
        config.fonts.resolve(command)
    }

    mutating func build() -> WordDocument {
        let body = extractDocumentBody(source)
        lines = body.components(separatedBy: .newlines)
        cursor = 0

        while cursor < lines.count {
            let line = lines[cursor].trimmingCharacters(in: .whitespaces)

            if line.isEmpty || line.hasPrefix("%") {
                cursor += 1
                continue
            }

            // \begin{titlepage} ... \end{titlepage} → parse as cover
            if line.hasPrefix("\\begin{titlepage}") {
                cursor += 1
                emitTitlePage()
                continue
            }

            if isSkippableLine(line) {
                cursor += 1
                continue
            }

            // \篇名{行1}{行2}
            if let (line1, line2) = matchPianMing(line) {
                emitPianMing(line1: line1, line2: line2)
                cursor += 1
                continue
            }

            // \摘要{內容}
            if let content = matchZhaiYao(line) {
                emitZhaiYao(content)
                cursor += 1
                continue
            }

            if let title = matchCommand("section", in: line) {
                emitSection(title)
                cursor += 1
                continue
            }

            if let title = matchCommand("subsection", in: line) {
                emitSubsection(title)
                cursor += 1
                continue
            }

            if let title = matchCommand("subsubsection", in: line) {
                emitSubsubsection(title)
                cursor += 1
                continue
            }

            // Lines with inline formatting (\fontsize, \color, \bfseries)
            // that aren't recognized commands → heuristic parse
            if line.contains("\\fontsize") || line.contains("\\color{") {
                emitFormattedLine(line)
                cursor += 1
                continue
            }

            emitParagraph(line)
            cursor += 1
        }

        if document.body.children.isEmpty {
            document.appendParagraph(Paragraph())
        }

        return document
    }

    // MARK: - Document body extraction

    private func extractDocumentBody(_ source: String) -> String {
        guard let beginRange = source.range(of: "\\begin{document}") else {
            return source
        }
        let afterBegin = source[beginRange.upperBound...]
        if let endRange = afterBegin.range(of: "\\end{document}") {
            return String(afterBegin[..<endRange.lowerBound])
        }
        return String(afterBegin)
    }

    // MARK: - Titlepage parser (heuristic)

    /// Parse \begin{titlepage} ... \end{titlepage} block
    /// Each line with \fontsize + text → a centered paragraph with matching size/color
    private mutating func emitTitlePage() {
        var titleLines: [(text: String, sizePt: Int, colorHex: String?, bold: Bool)] = []

        while cursor < lines.count {
            let line = lines[cursor].trimmingCharacters(in: .whitespaces)
            cursor += 1

            if line.hasPrefix("\\end{titlepage}") { break }
            if line.isEmpty || line.hasPrefix("%") || line.hasPrefix("\\centering") ||
               line.hasPrefix("\\vspace") || line.hasPrefix("\\vfill") { continue }

            // Parse formatting from the line
            let font = TeXPreambleParser.parseFontSize(from: line)
            let colorName = extractColorName(from: line)
            let resolvedColor = colorName.flatMap { config.colors.resolve($0) }
            let bold = TeXPreambleParser.isBold(line)
            let text = TeXPreambleParser.extractText(from: line)

            guard !text.isEmpty else { continue }

            titleLines.append((
                text: text,
                sizePt: font?.sizePt ?? 14,
                colorHex: resolvedColor,
                bold: bold
            ))
        }

        guard !titleLines.isEmpty else { return }

        // Emit page break before cover
        var breakPara = Paragraph()
        breakPara.properties.pageBreakBefore = true
        document.appendParagraph(breakPara)

        // Emit each title line as centered paragraph
        for (index, item) in titleLines.enumerated() {
            var props = RunProperties()
            props.fontSize = item.sizePt * 2  // half-points
            props.bold = item.bold
            if let hex = item.colorHex { props.color = hex }

            let run = Run(text: item.text, properties: props)
            var para = Paragraph(runs: [run])
            para.properties.alignment = .center

            // Spacing: more space before first, after last
            let before = index == 0 ? 2000 : 240
            let after = index == titleLines.count - 1 ? 2000 : 240
            para.properties.spacing = Spacing(before: before, after: after)

            document.appendParagraph(para)
        }

        // Page break after cover
        var afterBreak = Paragraph()
        afterBreak.properties.pageBreakBefore = true
        document.appendParagraph(afterBreak)
    }

    // MARK: - Formatted line (heuristic)

    /// Parse a line with inline \fontsize/\color/\bfseries and emit styled paragraph
    private mutating func emitFormattedLine(_ line: String) {
        let font = TeXPreambleParser.parseFontSize(from: line)
        let colorName = extractColorName(from: line)
        let resolvedColor = colorName.flatMap { config.colors.resolve($0) }
        let bold = TeXPreambleParser.isBold(line)
        let text = TeXPreambleParser.extractText(from: line)

        guard !text.isEmpty else { return }

        var props = RunProperties()
        if let font = font { props.fontSize = font.sizePt * 2 }
        if let hex = resolvedColor { props.color = hex }
        props.bold = bold

        let run = Run(text: text, properties: props)
        var para = Paragraph(runs: [run])
        para.properties.spacing = Spacing(before: 0, after: 60)
        document.appendParagraph(para)
    }

    // MARK: - Helpers

    /// Extract \color{name} → name (before resolving to hex)
    private func extractColorName(from line: String) -> String? {
        let pattern = #"\\color\{([^}]+)\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let r = Range(match.range(at: 1), in: line) else {
            return nil
        }
        return String(line[r])
    }

    // MARK: - Command matchers

    /// Match \篇名{line1}{line2} — may span current + next line
    private mutating func matchPianMing(_ line: String) -> (String, String)? {
        // Try single-line match first
        let pattern = #"\\篇名\{([^}]*)\}\{([^}]*)\}"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
           let r1 = Range(match.range(at: 1), in: line),
           let r2 = Range(match.range(at: 2), in: line) {
            return (String(line[r1]), String(line[r2]))
        }

        // Try multi-line: \篇名{line1} on this line, {line2} on next
        let partialPattern = #"\\篇名\{([^}]*)\}"#
        guard line.hasPrefix("\\篇名"),
              let regex = try? NSRegularExpression(pattern: partialPattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let r1 = Range(match.range(at: 1), in: line) else {
            return nil
        }

        // Check if there's a second {line2} remaining on same line or next line
        let line1 = String(line[r1])
        let afterFirst = String(line[Range(match.range, in: line)!.upperBound...]).trimmingCharacters(in: .whitespaces)

        if let secondBrace = extractBraceContentRaw(from: afterFirst) {
            return (line1, secondBrace.0)
        }

        // Look ahead to next line
        if cursor + 1 < lines.count {
            let nextLine = lines[cursor + 1].trimmingCharacters(in: .whitespaces)
            if nextLine.hasPrefix("{"),
               let secondBrace = extractBraceContentRaw(from: nextLine) {
                cursor += 1  // consume the next line
                return (line1, secondBrace.0)
            }
        }

        return nil
    }

    private func matchZhaiYao(_ line: String) -> String? {
        matchCommand("摘要", in: line)
    }

    private func matchCommand(_ name: String, in line: String) -> String? {
        // Match both \command{} and \command*{} (starred variant)
        let pattern = "\\\\\(NSRegularExpression.escapedPattern(for: name))\\*?\\{([^}]*)\\}"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let r = Range(match.range(at: 1), in: line) else {
            return nil
        }
        return String(line[r])
    }

    private func isSkippableLine(_ line: String) -> Bool {
        let skippable = [
            "\\maketitle", "\\tableofcontents", "\\clearpage", "\\cleardoublepage",
            "\\newpage", "\\thispagestyle", "\\addcontentsline",
            "\\begin{center}", "\\end{center}",
            "\\begin{flushleft}", "\\end{flushleft}",
            "\\pagenumbering",
        ]
        for prefix in skippable {
            if line.hasPrefix(prefix) { return true }
        }
        if line.hasPrefix("\\vspace") || line.hasPrefix("\\setlength") { return true }
        return false
    }

    // MARK: - Emitters

    private mutating func emitPianMing(line1: String, line2: String) {
        // From commands.tex: \songti\fontsize{24pt}{30pt}\bfseries\color{titlePink}
        var breakPara = Paragraph()
        breakPara.properties.pageBreakBefore = true
        document.appendParagraph(breakPara)

        let titleColor = color("titlePink", fallback: DefaultColor.titlePink)
        let songtiFont = font("songti")

        var runProps = RunProperties(bold: true, fontSize: 48, color: titleColor)
        if let f = songtiFont { runProps.fontName = f }

        let run1 = Run(text: line1, properties: runProps)
        var para1 = Paragraph(runs: [run1])
        para1.properties.alignment = .center
        para1.properties.spacing = Spacing(before: 4000, after: 240)
        document.appendParagraph(para1)

        let run2 = Run(text: line2, properties: runProps)
        var para2 = Paragraph(runs: [run2])
        para2.properties.alignment = .center
        para2.properties.spacing = Spacing(before: 0, after: 4000)
        document.appendParagraph(para2)
    }

    private mutating func emitZhaiYao(_ content: String) {
        // From commands.tex: \fcolorbox{black!40}{black!5}{\songti\fontsize{14pt}{18pt} ◆#1}
        let borderColor = color("black!40", fallback: "666666")
        let bgColor = color("black!5", fallback: "F2F2F2")
        let songtiFont = font("songti")

        var runProps = RunProperties(fontSize: 28)  // 14pt
        if let f = songtiFont { runProps.fontName = f }

        let diamondRun = Run(text: "◆", properties: runProps)
        let textRun = Run(text: content, properties: runProps)

        var para = Paragraph(runs: [diamondRun, textRun])
        para.properties.border = ParagraphBorder.all(
            ParagraphBorderStyle(type: .single, color: borderColor, size: 4)
        )
        para.properties.shading = CellShading.solid(bgColor)
        para.properties.spacing = Spacing(before: 120, after: 120)
        para.properties.indentation = Indentation(left: 120, right: 120)
        document.appendParagraph(para)
    }

    private mutating func emitSection(_ title: String) {
        let fmt = config.sectionFormat
        let bg = color("sectionBg", fallback: DefaultColor.sectionBg)
        let sizePt = fmt?.fontSizePt ?? 16
        let songtiFont = fmt?.fontFamily.flatMap { font($0) }

        var runProps = RunProperties(bold: fmt?.bold ?? true, fontSize: sizePt * 2, color: "FFFFFF")
        if let f = songtiFont { runProps.fontName = f }

        let run = Run(text: title, properties: runProps)
        var para = Paragraph(runs: [run])
        para.properties.style = "Heading2"
        para.properties.shading = CellShading.solid(bg)
        para.properties.spacing = Spacing(before: 360, after: 120)
        document.appendParagraph(para)
    }

    private mutating func emitSubsection(_ title: String) {
        let fmt = config.subsectionFormat
        let colorName = fmt?.colorName ?? "titleBrown"
        let c = color(colorName, fallback: DefaultColor.subsectionBrown)
        let sizePt = fmt?.fontSizePt ?? 16
        let songtiFont = fmt?.fontFamily.flatMap { font($0) }

        var runProps = RunProperties(bold: fmt?.bold ?? true, fontSize: sizePt * 2, color: c)
        if let f = songtiFont { runProps.fontName = f }

        let run = Run(text: title, properties: runProps)
        var para = Paragraph(runs: [run])
        para.properties.style = "Heading3"
        if fmt?.alignment == "center" { para.properties.alignment = .center }
        para.properties.spacing = Spacing(before: 240, after: 120)
        document.appendParagraph(para)
    }

    private mutating func emitSubsubsection(_ title: String) {
        let fmt = config.subsubsectionFormat
        let colorName = fmt?.colorName ?? "subsubBlue"
        let c = color(colorName, fallback: DefaultColor.subsubsectionBlue)
        let sizePt = fmt?.fontSizePt ?? 14
        let songtiFont = fmt?.fontFamily.flatMap { font($0) }

        var runProps = RunProperties(bold: fmt?.bold ?? true, fontSize: sizePt * 2, color: c)
        if let f = songtiFont { runProps.fontName = f }

        let run = Run(text: "【\(title)】", properties: runProps)
        var para = Paragraph(runs: [run])
        para.properties.style = "Heading4"
        para.properties.spacing = Spacing(before: 240, after: 120)
        document.appendParagraph(para)
    }

    private mutating func emitParagraph(_ line: String) {
        let runs = parseInlineCommands(line)
        guard !runs.isEmpty else { return }
        var para = Paragraph(runs: runs)
        para.properties.spacing = Spacing(before: 0, after: 60)
        document.appendParagraph(para)
    }

    // MARK: - Inline command parser

    func parseInlineCommands(_ text: String) -> [Run] {
        var runs: [Run] = []
        var remaining = text[text.startIndex...]

        while !remaining.isEmpty {
            guard let backslashIndex = remaining.firstIndex(of: "\\") else {
                let plain = cleanLaTeX(String(remaining))
                if !plain.isEmpty { runs.append(Run(text: plain)) }
                break
            }

            if backslashIndex > remaining.startIndex {
                let before = cleanLaTeX(String(remaining[remaining.startIndex..<backslashIndex]))
                if !before.isEmpty { runs.append(Run(text: before)) }
            }

            let fromBackslash = String(remaining[backslashIndex...])

            if let (content, len) = extractBraceContent("\\kw", from: fromBackslash) {
                // From commands.tex: \color{keywordBlue}
                let c = color("keywordBlue", fallback: DefaultColor.keywordBlue)
                var kwProps = RunProperties(bold: true, color: c)
                // kw doesn't specify font, inherits main font
                runs.append(Run(text: content, properties: kwProps))
                remaining = remaining[remaining.index(backslashIndex, offsetBy: len)...]
            } else if let (content, len) = extractBraceContent("\\tc", from: fromBackslash) {
                runs.append(Run(text: "(\(content))", properties: RunProperties(color: DefaultColor.timecodeGray)))
                remaining = remaining[remaining.index(backslashIndex, offsetBy: len)...]
            } else if let (content, len) = extractBraceContent("\\textbf", from: fromBackslash) {
                runs.append(Run(text: content, properties: RunProperties(bold: true)))
                remaining = remaining[remaining.index(backslashIndex, offsetBy: len)...]
            } else if let (content, len) = extractBraceContent("\\emph", from: fromBackslash) {
                runs.append(Run(text: content, properties: RunProperties(italic: true)))
                remaining = remaining[remaining.index(backslashIndex, offsetBy: len)...]
            } else if let (content, len) = extractBraceContent("\\textit", from: fromBackslash) {
                runs.append(Run(text: content, properties: RunProperties(italic: true)))
                remaining = remaining[remaining.index(backslashIndex, offsetBy: len)...]
            } else {
                let afterBackslash = remaining.index(after: backslashIndex)
                if afterBackslash < remaining.endIndex {
                    var end = afterBackslash
                    while end < remaining.endIndex && remaining[end].isLetter { end = remaining.index(after: end) }
                    if end < remaining.endIndex && remaining[end] == "{" {
                        if let (content, len) = extractBraceContentRaw(from: String(remaining[backslashIndex...])) {
                            let plain = cleanLaTeX(content)
                            if !plain.isEmpty { runs.append(Run(text: plain)) }
                            remaining = remaining[remaining.index(backslashIndex, offsetBy: len)...]
                        } else {
                            remaining = remaining[end...]
                        }
                    } else {
                        remaining = remaining[end...]
                    }
                } else {
                    break
                }
            }
        }
        return runs
    }

    private func extractBraceContent(_ command: String, from text: String) -> (String, Int)? {
        guard text.hasPrefix(command) else { return nil }
        let afterCommand = text.dropFirst(command.count)
        guard afterCommand.first == "{" else { return nil }
        var depth = 0
        var contentStart: String.Index?
        for i in afterCommand.indices {
            if afterCommand[i] == "{" {
                if depth == 0 { contentStart = afterCommand.index(after: i) }
                depth += 1
            } else if afterCommand[i] == "}" {
                depth -= 1
                if depth == 0, let start = contentStart {
                    let content = String(afterCommand[start..<i])
                    let totalLen = command.count + afterCommand.distance(from: afterCommand.startIndex, to: afterCommand.index(after: i))
                    return (content, totalLen)
                }
            }
        }
        return nil
    }

    private func extractBraceContentRaw(from text: String) -> (String, Int)? {
        guard let openBrace = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        for i in text[openBrace...].indices {
            if text[i] == "{" { depth += 1 }
            else if text[i] == "}" {
                depth -= 1
                if depth == 0 {
                    let contentStart = text.index(after: openBrace)
                    let content = String(text[contentStart..<i])
                    let totalLen = text.distance(from: text.startIndex, to: text.index(after: i))
                    return (content, totalLen)
                }
            }
        }
        return nil
    }

    private func cleanLaTeX(_ text: String) -> String {
        text
            .replacingOccurrences(of: "~", with: " ")
            .replacingOccurrences(of: "\\,", with: " ")
            .replacingOccurrences(of: "\\;", with: " ")
            .replacingOccurrences(of: "\\!", with: "")
            .replacingOccurrences(of: "\\\\", with: "")
            .replacingOccurrences(of: "\\&", with: "&")
            .replacingOccurrences(of: "\\%", with: "%")
            .replacingOccurrences(of: "\\$", with: "$")
            .replacingOccurrences(of: "\\#", with: "#")
            .replacingOccurrences(of: "\\_", with: "_")
            .replacingOccurrences(of: "\\{", with: "{")
            .replacingOccurrences(of: "\\}", with: "}")
            .replacingOccurrences(of: "--", with: "–")
            .trimmingCharacters(in: .whitespaces)
    }
}
