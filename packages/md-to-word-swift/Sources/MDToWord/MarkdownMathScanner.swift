import Foundation
import Markdown

struct MarkdownMathScanner {
    static let defaultMarkerPrefix = "MDTOWORDMATHPLACEHOLDER"

    enum TokenKind: Equatable {
        case inline
        case display
    }

    struct Token: Equatable {
        let placeholder: String
        let latex: String
        let kind: TokenKind
        let line: Int
        let column: Int
    }

    struct Result: Equatable {
        let markdown: String
        let tokens: [Token]
    }

    enum ScanError: Error, Equatable {
        case misplacedDisplayFormula(line: Int, column: Int)
    }

    private let markerPrefix: String
    private let markerNonce: String

    /// Original CommonMark source ranges are the authority for math eligibility.
    /// A narrow raw-angle shield supplements ranges when cmark normalizes quoted tag spelling.
    private struct SourceEligibility {
        private struct Point: Hashable {
            let line: Int
            let column: Int
        }

        private let inlineIneligiblePrefix: [Int]
        private let visibleOffsets: [Bool]
        private let paragraphRanges: Set<Range<Int>>
        private let displayRanges: Set<Range<Int>>

        init(source: String, characters: [Character]) {
            let offsets = Self.sourceOffsets(for: characters)
            let document = Document(parsing: source)
            var inlineRanges: [Range<Int>] = []
            var fallbackInlineRanges: [Range<Int>] = []
            var paragraphRanges: Set<Range<Int>> = []
            var displayRanges: Set<Range<Int>> = []

            func offsetRange(for markup: Markup) -> Range<Int>? {
                guard let range = markup.range,
                      let lower = offsets[
                          Point(line: range.lowerBound.line, column: range.lowerBound.column)
                      ],
                      let upper = offsets[
                          Point(line: range.upperBound.line, column: range.upperBound.column)
                      ],
                      lower <= upper else {
                    return nil
                }
                return lower..<upper
            }

            func trimmingWhitespace(_ range: Range<Int>) -> Range<Int> {
                var lower = range.lowerBound
                var upper = range.upperBound
                while lower < upper, characters[lower].isWhitespace {
                    lower += 1
                }
                while lower < upper, characters[upper - 1].isWhitespace {
                    upper -= 1
                }
                return lower..<upper
            }

            func isAutolink(_ link: Markdown.Link) -> Bool {
                guard let range = offsetRange(for: link),
                      range.lowerBound < range.upperBound else {
                    return false
                }
                return characters[range.lowerBound] == "<"
                    && characters[range.upperBound - 1] == ">"
            }

            func paragraphAllowsDisplay(_ paragraph: Markdown.Paragraph) -> Bool {
                paragraph.children.allSatisfy { child in
                    child is Text || child is SoftBreak || child is LineBreak
                }
            }

            func recoverNormalizedTextRanges(
                in paragraph: Markdown.Paragraph,
                sourceRange: Range<Int>
            ) {
                guard paragraphAllowsDisplay(paragraph) else { return }
                var needed: [String: Int] = [:]
                for child in paragraph.children {
                    guard let text = child as? Text else { continue }
                    for candidate in Self.inlineCandidates(in: Array(text.string)) {
                        needed[candidate.signature, default: 0] += 1
                    }
                }
                guard !needed.isEmpty else { return }

                let rawCandidates = Self.inlineCandidates(
                    in: characters,
                    range: sourceRange
                )
                for candidate in rawCandidates.reversed()
                    where needed[candidate.signature, default: 0] > 0 {
                    fallbackInlineRanges.append(candidate.range)
                    needed[candidate.signature, default: 0] -= 1
                }
            }

            func collect(_ markup: Markup, insideAutolink: Bool = false) {
                if let paragraph = markup as? Markdown.Paragraph,
                   let range = offsetRange(for: paragraph) {
                    let contentRange = trimmingWhitespace(range)
                    paragraphRanges.insert(contentRange)
                    if paragraphAllowsDisplay(paragraph) {
                        displayRanges.insert(contentRange)
                        recoverNormalizedTextRanges(in: paragraph, sourceRange: range)
                    }
                }

                let childrenInsideAutolink = insideAutolink
                    || ((markup as? Markdown.Link).map(isAutolink) ?? false)
                if markup is Text, !insideAutolink, let range = offsetRange(for: markup) {
                    inlineRanges.append(range)
                }
                for child in markup.children {
                    collect(child, insideAutolink: childrenInsideAutolink)
                }
            }

            collect(document)
            var visibleOffsets = [Bool](repeating: false, count: characters.count)
            for range in inlineRanges + fallbackInlineRanges {
                for offset in range where offset < visibleOffsets.count {
                    visibleOffsets[offset] = true
                }
            }
            for range in Self.angleRanges(in: characters) {
                for offset in range where offset < visibleOffsets.count {
                    visibleOffsets[offset] = false
                }
            }
            var inlineIneligiblePrefix = [Int](repeating: 0, count: characters.count + 1)
            for offset in characters.indices {
                inlineIneligiblePrefix[offset + 1] = inlineIneligiblePrefix[offset]
                    + (visibleOffsets[offset] ? 0 : 1)
            }
            self.inlineIneligiblePrefix = inlineIneligiblePrefix
            self.visibleOffsets = visibleOffsets
            self.paragraphRanges = paragraphRanges
            self.displayRanges = displayRanges
        }

        func containsInline(_ range: Range<Int>) -> Bool {
            guard !range.isEmpty,
                  0 <= range.lowerBound,
                  range.upperBound < inlineIneligiblePrefix.count else {
                return false
            }
            return inlineIneligiblePrefix[range.upperBound]
                == inlineIneligiblePrefix[range.lowerBound]
        }

        func containsVisibleText(at offset: Int) -> Bool {
            visibleOffsets.indices.contains(offset) && visibleOffsets[offset]
        }

        func isParagraph(_ range: Range<Int>) -> Bool {
            paragraphRanges.contains(range)
        }

        func allowsDisplay(_ range: Range<Int>) -> Bool {
            displayRanges.contains(range)
        }

        private static func sourceOffsets(for characters: [Character]) -> [Point: Int] {
            var result: [Point: Int] = [:]
            var line = 1
            var column = 1
            for (offset, character) in characters.enumerated() {
                result[Point(line: line, column: column)] = offset
                if character.isNewline {
                    line += 1
                    column = 1
                } else {
                    column += String(character).utf8.count
                }
            }
            result[Point(line: line, column: column)] = characters.count
            return result
        }

        private static func angleRanges(in characters: [Character]) -> [Range<Int>] {
            var result: [Range<Int>] = []
            var index = 0
            while index < characters.count {
                guard characters[index] == "<", index + 1 < characters.count else {
                    index += 1
                    continue
                }
                let next = characters[index + 1]
                guard next.isLetter || next == "/" || next == "!" || next == "?" else {
                    index += 1
                    continue
                }

                var cursor = index + 2
                var quote: Character?
                while cursor < characters.count, !characters[cursor].isNewline {
                    let character = characters[cursor]
                    if let activeQuote = quote {
                        if character == activeQuote {
                            quote = nil
                        }
                    } else if character == "\"" || character == "'" {
                        quote = character
                    } else if character == ">" {
                        result.append(index..<(cursor + 1))
                        index = cursor
                        break
                    }
                    cursor += 1
                }
                index += 1
            }
            return result
        }

        private static func inlineCandidates(
            in characters: [Character],
            range: Range<Int>? = nil
        ) -> [(range: Range<Int>, signature: String)] {
            let bounds = range ?? characters.startIndex..<characters.endIndex
            var result: [(range: Range<Int>, signature: String)] = []
            var index = bounds.lowerBound
            while index < bounds.upperBound {
                guard characters[index] == "$" else {
                    index += 1
                    continue
                }
                var closing = index + 1
                while closing < bounds.upperBound,
                      !characters[closing].isNewline,
                      characters[closing] != "$" {
                    if characters[closing] == "\\" {
                        closing = min(closing + 2, bounds.upperBound)
                    } else {
                        closing += 1
                    }
                }
                guard closing < bounds.upperBound, characters[closing] == "$" else {
                    index += 1
                    continue
                }
                let bodyRange = (index + 1)..<closing
                if let first = bodyRange.first.map({ characters[$0] }),
                   let lastIndex = bodyRange.last,
                   !first.isWhitespace,
                   !characters[lastIndex].isWhitespace {
                    let candidateRange = index..<(closing + 1)
                    result.append(
                        (candidateRange, String(characters[candidateRange]))
                    )
                    index = closing + 1
                } else {
                    index += 1
                }
            }
            return result
        }
    }

    init(
        markerPrefix: String = Self.defaultMarkerPrefix,
        markerNonce: String = UUID().uuidString.replacingOccurrences(of: "-", with: "")
    ) {
        self.markerPrefix = markerPrefix
        self.markerNonce = markerNonce
    }

    func scan(_ source: String) throws -> Result {
        let characters = Array(source)
        let eligibility = SourceEligibility(source: source, characters: characters)
        let markerStem = markerPrefix + markerNonce
        let reservedMarkerIndices = Self.reservedMarkerIndices(
            in: characters,
            markerStem: Array(markerStem)
        )
        var output = ""
        var tokens: [Token] = []
        var nextMarkerIndex = 0
        var index = 0
        var line = 1
        var column = 1
        var lineStart = 0
        var logicalLineStart = 0
        var logicalQuoteDepth = 0

        func marker() -> String {
            while reservedMarkerIndices.contains(nextMarkerIndex) {
                nextMarkerIndex += 1
            }
            defer { nextMarkerIndex += 1 }
            return "\(markerStem)\(nextMarkerIndex)TOKEN"
        }

        while index < characters.count {
            if index == lineStart {
                let end = Self.lineEnd(in: characters, from: index)
                let contentEnd = Self.contentEndBeforeNewline(in: characters, lineEnd: end)
                let context = Self.lineContext(
                    characters,
                    start: index,
                    end: contentEnd
                )
                logicalLineStart = context.contentStart
                logicalQuoteDepth = context.quoteDepth
            }

            if characters[index] == "\\", index + 1 < characters.count {
                let end = index + 2
                output += String(characters[index..<end])
                Self.advance(
                    characters,
                    from: index,
                    to: end,
                    line: &line,
                    column: &column,
                    lineStart: &lineStart
                )
                index = end
                continue
            }

            if characters[index] == "$",
               index + 1 < characters.count,
               characters[index + 1] == "$" {
                let openingLine = line
                let openingColumn = column
                if let display = Self.displayFormula(
                    in: characters,
                    opening: index,
                    lineStart: logicalLineStart,
                    openingQuoteDepth: logicalQuoteDepth
                ) {
                    let sourceRange = index..<display.replacementEnd
                    if !eligibility.allowsDisplay(sourceRange) {
                        if eligibility.isParagraph(sourceRange) {
                            let end = min(index + 2, characters.count)
                            output += String(characters[index..<end])
                            Self.advance(
                                characters,
                                from: index,
                                to: end,
                                line: &line,
                                column: &column,
                                lineStart: &lineStart
                            )
                            index = end
                            continue
                        }
                        if eligibility.containsVisibleText(at: index) {
                            throw ScanError.misplacedDisplayFormula(
                                line: openingLine,
                                column: openingColumn
                            )
                        }
                        let end = min(index + 2, characters.count)
                        output += String(characters[index..<end])
                        Self.advance(
                            characters,
                            from: index,
                            to: end,
                            line: &line,
                            column: &column,
                            lineStart: &lineStart
                        )
                        index = end
                        continue
                    }
                    if display.mixedWithText {
                        throw ScanError.misplacedDisplayFormula(
                            line: openingLine,
                            column: openingColumn
                        )
                    }
                    let placeholder = marker()
                    output += String(characters[index..<display.replacementStart])
                    output += placeholder
                    output += String(characters[display.replacementEnd..<display.consumedEnd])
                    tokens.append(
                        Token(
                            placeholder: placeholder,
                            latex: display.latex,
                            kind: .display,
                            line: openingLine,
                            column: openingColumn
                        )
                    )
                    Self.advance(
                        characters,
                        from: index,
                        to: display.consumedEnd,
                        line: &line,
                        column: &column,
                        lineStart: &lineStart
                    )
                    index = display.consumedEnd
                    continue
                }

                if eligibility.containsVisibleText(at: index),
                   let closing = Self.laterDoubleDollarClosing(
                       in: characters,
                       after: index + 2
                   ),
                   eligibility.containsVisibleText(at: closing) {
                    throw ScanError.misplacedDisplayFormula(
                        line: openingLine,
                        column: openingColumn
                    )
                }

                let end = min(index + 2, characters.count)
                output += String(characters[index..<end])
                Self.advance(
                    characters,
                    from: index,
                    to: end,
                    line: &line,
                    column: &column,
                    lineStart: &lineStart
                )
                index = end
                continue
            }

            if characters[index] == "$",
               let closing = Self.inlineFormulaClosing(in: characters, opening: index) {
                let bodyStart = index + 1
                let body = String(characters[bodyStart..<closing])
                if let first = body.first,
                   let last = body.last,
                   !first.isWhitespace,
                   !last.isWhitespace,
                   eligibility.containsInline(index..<(closing + 1)) {
                    let placeholder = marker()
                    output += placeholder
                    tokens.append(
                        Token(
                            placeholder: placeholder,
                            latex: body,
                            kind: .inline,
                            line: line,
                            column: column
                        )
                    )
                    let end = closing + 1
                    Self.advance(
                        characters,
                        from: index,
                        to: end,
                        line: &line,
                        column: &column,
                        lineStart: &lineStart
                    )
                    index = end
                    continue
                }
            }

            output.append(characters[index])
            Self.advance(
                characters,
                from: index,
                to: index + 1,
                line: &line,
                column: &column,
                lineStart: &lineStart
            )
            index += 1
        }

        return Result(markdown: output, tokens: tokens)
    }

    private struct DisplayMatch {
        let latex: String
        let replacementStart: Int
        let replacementEnd: Int
        let consumedEnd: Int
        let mixedWithText: Bool
    }

    private static func displayFormula(
        in characters: [Character],
        opening: Int,
        lineStart: Int,
        openingQuoteDepth: Int
    ) -> DisplayMatch? {
        let openingLineEnd = contentEndBeforeNewline(
            in: characters,
            lineEnd: lineEnd(in: characters, from: opening)
        )
        let prefixIsWhitespace = characters[lineStart..<opening].allSatisfy(\.isWhitespace)

        if let closing = doubleDollarClosing(
            in: characters,
            from: opening + 2,
            before: openingLineEnd
        ) {
            let suffixIsWhitespace = characters[(closing + 2)..<openingLineEnd]
                .allSatisfy(\.isWhitespace)
            let body = String(characters[(opening + 2)..<closing])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let consumedEnd = closing + 2
            let mixed = !prefixIsWhitespace || !suffixIsWhitespace
            return DisplayMatch(
                latex: body,
                replacementStart: opening,
                replacementEnd: consumedEnd,
                consumedEnd: consumedEnd,
                mixedWithText: mixed
            )
        }

        let openerSuffixIsWhitespace = characters[(opening + 2)..<openingLineEnd]
            .allSatisfy(\.isWhitespace)
        guard prefixIsWhitespace, openerSuffixIsWhitespace else {
            return nil
        }

        var search = openingLineEnd
        if search < characters.count, characters[search].isNewline {
            search += 1
        }
        var bodyLines: [String] = []
        while search < characters.count {
            let candidateLineEnd = contentEndBeforeNewline(
                in: characters,
                lineEnd: lineEnd(in: characters, from: search)
            )
            let context = lineContext(
                characters,
                start: search,
                end: candidateLineEnd
            )
            guard context.quoteDepth == openingQuoteDepth else {
                return nil
            }
            let contentStart = context.contentStart
            if contentStart + 2 <= candidateLineEnd,
               characters[contentStart] == "$",
               characters[contentStart + 1] == "$",
               characters[(contentStart + 2)..<candidateLineEnd].allSatisfy(\.isWhitespace) {
                let body = bodyLines.joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                var consumedEnd = candidateLineEnd
                if consumedEnd < characters.count, characters[consumedEnd].isNewline {
                    consumedEnd += 1
                }
                return DisplayMatch(
                    latex: body,
                    replacementStart: opening,
                    replacementEnd: contentStart + 2,
                    consumedEnd: consumedEnd,
                    mixedWithText: false
                )
            }
            bodyLines.append(String(characters[contentStart..<candidateLineEnd]))
            search = candidateLineEnd
            if search < characters.count, characters[search].isNewline {
                search += 1
            }
        }
        return nil
    }

    private static func inlineFormulaClosing(
        in characters: [Character],
        opening: Int
    ) -> Int? {
        var index = opening + 1
        while index < characters.count {
            if characters[index].isNewline {
                return nil
            }
            if characters[index] == "\\" {
                index = min(index + 2, characters.count)
                continue
            }
            if characters[index] == "$" {
                return index
            }
            index += 1
        }
        return nil
    }

    private static func doubleDollarClosing(
        in characters: [Character],
        from start: Int,
        before end: Int
    ) -> Int? {
        var index = start
        while index + 1 < end {
            if characters[index] == "\\" {
                index += 2
                continue
            }
            if characters[index] == "$", characters[index + 1] == "$" {
                return index
            }
            index += 1
        }
        return nil
    }

    private static func laterDoubleDollarClosing(
        in characters: [Character],
        after start: Int
    ) -> Int? {
        var index = start
        while index + 1 < characters.count {
            if characters[index] == "\\" {
                index += 2
                continue
            }
            if characters[index] == "$", characters[index + 1] == "$" {
                return index
            }
            index += 1
        }
        return nil
    }

    private struct LineContext {
        let contentStart: Int
        let quoteDepth: Int
    }

    private static func lineContext(
        _ characters: [Character],
        start: Int,
        end: Int
    ) -> LineContext {
        var index = start
        var indentation = 0
        var quoteDepth = 0

        func consumeIndentation() {
            indentation = 0
            while index < end {
                if characters[index] == " " {
                    indentation += 1
                    index += 1
                } else if characters[index] == "\t" {
                    indentation += 4
                    index += 1
                } else {
                    break
                }
            }
        }

        consumeIndentation()
        if indentation >= 4 {
            return LineContext(
                contentStart: index,
                quoteDepth: quoteDepth
            )
        }

        while index < end {
            if characters[index] == ">" {
                quoteDepth += 1
                index += 1
                if index < end, characters[index] == " " || characters[index] == "\t" {
                    index += 1
                }
                consumeIndentation()
                if indentation >= 4 {
                    return LineContext(
                        contentStart: index,
                        quoteDepth: quoteDepth
                    )
                }
                continue
            }

            if let markerEnd = listMarkerEnd(
                in: characters,
                from: index,
                before: end
            ) {
                index = markerEnd
                consumeIndentation()
                continue
            }
            break
        }

        return LineContext(
            contentStart: index,
            quoteDepth: quoteDepth
        )
    }

    private static func listMarkerEnd(
        in characters: [Character],
        from start: Int,
        before end: Int
    ) -> Int? {
        guard start < end else { return nil }
        if characters[start] == "-" || characters[start] == "+" || characters[start] == "*" {
            let after = start + 1
            guard after < end, characters[after].isWhitespace else { return nil }
            return after
        }

        var index = start
        var digits = 0
        while index < end, characters[index].isNumber, digits < 9 {
            index += 1
            digits += 1
        }
        guard digits > 0,
              index < end,
              characters[index] == "." || characters[index] == ")" else {
            return nil
        }
        let after = index + 1
        guard after < end, characters[after].isWhitespace else { return nil }
        return after
    }

    private static func reservedMarkerIndices(
        in characters: [Character],
        markerStem: [Character]
    ) -> Set<Int> {
        guard !markerStem.isEmpty else { return [] }
        let suffix = Array("TOKEN")
        var reserved: Set<Int> = []
        var index = 0

        while index + markerStem.count < characters.count {
            let stemEnd = index + markerStem.count
            if characters[index..<stemEnd].elementsEqual(markerStem) {
                var digitsEnd = stemEnd
                while digitsEnd < characters.count, characters[digitsEnd].isNumber {
                    digitsEnd += 1
                }
                let suffixEnd = digitsEnd + suffix.count
                if digitsEnd > stemEnd,
                   suffixEnd <= characters.count,
                   characters[digitsEnd..<suffixEnd].elementsEqual(suffix),
                   let value = Int(String(characters[stemEnd..<digitsEnd])) {
                    reserved.insert(value)
                }
            }
            index += 1
        }
        return reserved
    }

    private static func lineEnd(in characters: [Character], from start: Int) -> Int {
        var end = start
        while end < characters.count {
            if characters[end].isNewline {
                return end + 1
            }
            end += 1
        }
        return end
    }

    private static func contentEndBeforeNewline(
        in characters: [Character],
        lineEnd: Int
    ) -> Int {
        guard lineEnd > 0, lineEnd <= characters.count else { return lineEnd }
        var end = lineEnd
        if end > 0, characters[end - 1].isNewline {
            end -= 1
        }
        return end
    }

    private static func advance(
        _ characters: [Character],
        from start: Int,
        to end: Int,
        line: inout Int,
        column: inout Int,
        lineStart: inout Int
    ) {
        guard start < end else { return }
        for index in start..<end {
            if characters[index].isNewline {
                line += 1
                column = 1
                lineStart = index + 1
            } else {
                column += 1
            }
        }
    }
}
