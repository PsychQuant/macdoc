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
        let placeholderSearchPrefix: String?
    }

    enum ScanError: Error, Equatable {
        case misplacedDisplayFormula(line: Int, column: Int)
    }

    private let markerPrefix: String
    private let markerNonce: String

    /// Original CommonMark source ranges are the authority for math eligibility.
    private struct SourceEligibility {
        private struct Point: Hashable {
            let line: Int
            let column: Int
        }

        private let inlineIneligiblePrefix: [Int]
        private let visibleOffsets: [Bool]
        private let paragraphIdentifiers: [Int?]
        private let paragraphRanges: Set<Range<Int>>
        private let displayRanges: Set<Range<Int>>

        init(source: String, characters: [Character]) {
            let offsets = Self.sourceOffsets(for: characters)
            let document = Document(parsing: source)
            var inlineRanges: [Range<Int>] = []
            var fallbackInlineRanges: [Range<Int>] = []
            var opaqueHTMLRanges: [Range<Int>] = []
            var closingHTMLTags: [Int: String] = [:]
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
                    range: sourceRange,
                    respectBackslashEscapes: true
                )
                for candidate in rawCandidates.reversed()
                    where needed[candidate.signature, default: 0] > 0 {
                    fallbackInlineRanges.append(candidate.range)
                    needed[candidate.signature, default: 0] -= 1
                }
            }

            func recoverInlineHTMLRange(_ inlineHTML: InlineHTML) -> Range<Int>? {
                guard let range = offsetRange(for: inlineHTML),
                      !range.isEmpty,
                      !inlineHTML.rawHTML.isEmpty else {
                    return nil
                }
                let raw = Array(inlineHTML.rawHTML)
                guard raw.count <= range.count else { return range }
                let candidate = range.lowerBound..<(range.lowerBound + raw.count)
                return characters[candidate].elementsEqual(raw) ? candidate : range
            }

            func closingHTMLTagName(_ inlineHTML: InlineHTML) -> String? {
                let raw = Array(inlineHTML.rawHTML)
                guard raw.count >= 4, raw[0] == "<", raw[1] == "/" else { return nil }
                var nameEnd = 2
                while nameEnd < raw.count,
                      raw[nameEnd].isLetter || raw[nameEnd].isNumber || raw[nameEnd] == "-" {
                    nameEnd += 1
                }
                guard nameEnd > 2 else { return nil }
                return String(raw[2..<nameEnd]).lowercased()
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
                if let inlineHTML = markup as? InlineHTML,
                   let range = recoverInlineHTMLRange(inlineHTML) {
                    opaqueHTMLRanges.append(range)
                    if let tagName = closingHTMLTagName(inlineHTML) {
                        closingHTMLTags[range.lowerBound] = tagName
                    }
                }
                for child in markup.children {
                    collect(child, insideAutolink: childrenInsideAutolink)
                }
            }

            collect(document)
            opaqueHTMLRanges += Self.normalizedOpeningHTMLRanges(
                in: characters,
                closingTags: closingHTMLTags
            )
            var visibleOffsets = [Bool](repeating: false, count: characters.count)
            for range in inlineRanges + fallbackInlineRanges {
                for offset in range where offset < visibleOffsets.count {
                    visibleOffsets[offset] = true
                }
            }
            for range in opaqueHTMLRanges {
                for offset in range where visibleOffsets.indices.contains(offset) {
                    visibleOffsets[offset] = false
                }
            }
            var inlineIneligiblePrefix = [Int](repeating: 0, count: characters.count + 1)
            for offset in characters.indices {
                inlineIneligiblePrefix[offset + 1] = inlineIneligiblePrefix[offset]
                    + (visibleOffsets[offset] ? 0 : 1)
            }
            var paragraphIdentifiers = [Int?](repeating: nil, count: characters.count)
            for (identifier, range) in paragraphRanges.enumerated() {
                for offset in range where paragraphIdentifiers.indices.contains(offset) {
                    paragraphIdentifiers[offset] = identifier
                }
            }
            self.inlineIneligiblePrefix = inlineIneligiblePrefix
            self.visibleOffsets = visibleOffsets
            self.paragraphIdentifiers = paragraphIdentifiers
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

        func sharesParagraph(_ lhs: Int, _ rhs: Int) -> Bool {
            guard paragraphIdentifiers.indices.contains(lhs),
                  paragraphIdentifiers.indices.contains(rhs),
                  let identifier = paragraphIdentifiers[lhs] else {
                return false
            }
            return paragraphIdentifiers[rhs] == identifier
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

        private static func inlineCandidates(
            in characters: [Character],
            range: Range<Int>? = nil,
            respectBackslashEscapes: Bool = false
        ) -> [(range: Range<Int>, signature: String)] {
            let bounds = range ?? characters.startIndex..<characters.endIndex
            var result: [(range: Range<Int>, signature: String)] = []
            var index = bounds.lowerBound
            while index < bounds.upperBound {
                if respectBackslashEscapes, characters[index] == "\\" {
                    index = min(index + 2, bounds.upperBound)
                    continue
                }
                guard characters[index] == "$" else {
                    index += 1
                    continue
                }
                var closing = index + 1
                while closing < bounds.upperBound,
                      !characters[closing].isNewline,
                      characters[closing] != "$" {
                    if respectBackslashEscapes, characters[closing] == "\\" {
                        closing = min(closing + 2, bounds.upperBound)
                    } else {
                        closing += 1
                    }
                }
                guard closing < bounds.upperBound, characters[closing] == "$" else {
                    index = closing
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
                    index = closing
                }
            }
            return result
        }

        private static func normalizedOpeningHTMLRanges(
            in characters: [Character],
            closingTags: [Int: String]
        ) -> [Range<Int>] {
            struct Opening {
                let range: Range<Int>
                let containsValidQuotedDollarAttribute: Bool
            }
            var stacks: [String: [Opening]] = [:]
            var result: [Range<Int>] = []
            var index = 0
            while index < characters.count {
                guard characters[index] == "<" else {
                    index += 1
                    continue
                }
                var cursor = index + 1
                let isClosing = cursor < characters.count && characters[cursor] == "/"
                if isClosing { cursor += 1 }
                let nameStart = cursor
                guard cursor < characters.count,
                      isASCIILetter(characters[cursor]) else {
                    index += 1
                    continue
                }
                cursor += 1
                while cursor < characters.count,
                      isASCIILetter(characters[cursor])
                        || isASCIINumber(characters[cursor])
                        || characters[cursor] == "-" {
                    cursor += 1
                }
                let tagName = String(characters[nameStart..<cursor]).lowercased()
                let attributesStart = cursor
                var quote: Character?
                var end: Int?
                while cursor < characters.count, !characters[cursor].isNewline {
                    let character = characters[cursor]
                    if let activeQuote = quote {
                        if character == activeQuote { quote = nil }
                    } else if character == "\"" || character == "'" {
                        quote = character
                    } else if character == ">" {
                        end = cursor + 1
                        break
                    }
                    cursor += 1
                }
                guard let end else {
                    // No candidate later on this physical line can close before the
                    // boundary we already reached. Skip the suffix once instead of
                    // restarting an end-of-line scan at every nested `<tag` prefix.
                    index = cursor
                    continue
                }
                if isClosing {
                    if closingTags[index] == tagName,
                       let opening = stacks[tagName]?.popLast(),
                       opening.containsValidQuotedDollarAttribute {
                        result.append(opening.range)
                    }
                } else if characters[max(index, end - 2)] != "/" {
                    stacks[tagName, default: []].append(
                        Opening(
                            range: index..<end,
                            containsValidQuotedDollarAttribute: hasValidQuotedDollarAttribute(
                                in: characters,
                                from: attributesStart,
                                before: end - 1
                            )
                        )
                    )
                }
                index = end
            }
            return result
        }

        private static func hasValidQuotedDollarAttribute(
            in characters: [Character],
            from start: Int,
            before end: Int
        ) -> Bool {
            var index = start
            var containsDollar = false
            while index < end {
                let separatorStart = index
                while index < end, isHTMLSpace(characters[index]) { index += 1 }
                if index >= end { return containsDollar }
                if characters[index] == "/" {
                    index += 1
                    return index == end && containsDollar
                }
                guard index > separatorStart,
                      isASCIIAttributeNameStart(characters[index]) else {
                    return false
                }
                index += 1
                while index < end,
                      isASCIIAttributeNameContinuation(characters[index]) {
                    index += 1
                }

                let afterName = index
                while index < end, isHTMLSpace(characters[index]) { index += 1 }
                guard index < end, characters[index] == "=" else {
                    index = afterName
                    continue
                }
                index += 1
                while index < end, isHTMLSpace(characters[index]) { index += 1 }
                guard index < end else { return false }

                if characters[index] == "\"" || characters[index] == "'" {
                    let quote = characters[index]
                    index += 1
                    var attributeContainsDollar = false
                    while index < end, characters[index] != quote {
                        guard characters[index].asciiValue != 0 else { return false }
                        if characters[index] == "$" { attributeContainsDollar = true }
                        index += 1
                    }
                    guard index < end else { return false }
                    index += 1
                    containsDollar = containsDollar || attributeContainsDollar
                } else {
                    let valueStart = index
                    while index < end, !isHTMLSpace(characters[index]) {
                        guard !isForbiddenUnquotedAttributeValueCharacter(characters[index])
                        else {
                            return false
                        }
                        index += 1
                    }
                    guard index > valueStart else { return false }
                }
            }
            return containsDollar
        }

        private static func isASCIILetter(_ character: Character) -> Bool {
            guard let value = character.asciiValue else { return false }
            return (65...90).contains(value) || (97...122).contains(value)
        }

        private static func isASCIINumber(_ character: Character) -> Bool {
            guard let value = character.asciiValue else { return false }
            return (48...57).contains(value)
        }

        private static func isASCIIAttributeNameStart(_ character: Character) -> Bool {
            isASCIILetter(character) || character == "_" || character == ":"
        }

        private static func isASCIIAttributeNameContinuation(_ character: Character) -> Bool {
            isASCIIAttributeNameStart(character) || isASCIINumber(character)
                || character == "." || character == "-"
        }

        private static func isHTMLSpace(_ character: Character) -> Bool {
            character == " " || character == "\t" || character == "\r"
                || character == "\n" || character == "\u{000B}"
                || character == "\u{000C}"
        }

        private static func isForbiddenUnquotedAttributeValueCharacter(
            _ character: Character
        ) -> Bool {
            character.asciiValue == 0 || character == "\"" || character == "'"
                || character == "=" || character == "<" || character == ">"
                || character == "`"
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
        var currentPhysicalLineEnd = 0
        var currentContentEnd = 0
        var logicalLineStart = 0
        var logicalQuoteDepth = 0
        var pendingVisibleDisplay: (offset: Int, line: Int, column: Int)?

        func marker() -> String {
            while reservedMarkerIndices.contains(nextMarkerIndex) {
                nextMarkerIndex += 1
            }
            defer { nextMarkerIndex += 1 }
            return "\u{E000}\(markerStem)\(nextMarkerIndex)TOKEN\u{E000}"
        }

        while index < characters.count {
            if index == lineStart {
                currentPhysicalLineEnd = Self.lineEnd(in: characters, from: index)
                currentContentEnd = Self.contentEndBeforeNewline(
                    in: characters,
                    lineEnd: currentPhysicalLineEnd
                )
                let context = Self.lineContext(
                    characters,
                    start: index,
                    end: currentContentEnd
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
                let delimiterIsStandalone = characters[logicalLineStart..<index]
                    .allSatisfy(\.isWhitespace)
                    && characters[(index + 2)..<currentContentEnd]
                        .allSatisfy(\.isWhitespace)
                if let display = Self.displayFormula(
                    in: characters,
                    opening: index,
                    openingLineEnd: currentContentEnd,
                    lineStart: logicalLineStart,
                    openingQuoteDepth: logicalQuoteDepth
                ) {
                    let sourceRange = index..<display.replacementEnd
                    let isIndependentCompleteDisplay = eligibility.allowsDisplay(sourceRange)
                        && !display.mixedWithText
                        && !display.latex.isEmpty
                    if let pendingVisibleDisplay,
                       !isIndependentCompleteDisplay,
                       delimiterIsStandalone,
                       eligibility.containsVisibleText(at: index)
                        || eligibility.sharesParagraph(
                                pendingVisibleDisplay.offset,
                                index
                            ) {
                        throw ScanError.misplacedDisplayFormula(
                            line: pendingVisibleDisplay.line,
                            column: pendingVisibleDisplay.column
                        )
                    }
                    if isIndependentCompleteDisplay {
                        // A complete later display is its own formula; any
                        // earlier unmatched `$$` remains literal.
                        pendingVisibleDisplay = nil
                    }
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

                let currentIsVisible = eligibility.containsVisibleText(at: index)
                if let pendingVisibleDisplay,
                   delimiterIsStandalone,
                   currentIsVisible
                    || eligibility.sharesParagraph(
                            pendingVisibleDisplay.offset,
                            index
                        ) {
                    throw ScanError.misplacedDisplayFormula(
                        line: pendingVisibleDisplay.line,
                        column: pendingVisibleDisplay.column
                    )
                }
                if currentIsVisible, delimiterIsStandalone {
                    pendingVisibleDisplay = (
                        offset: index,
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

        return Result(
            markdown: output,
            tokens: tokens,
            placeholderSearchPrefix: tokens.isEmpty ? nil : "\u{E000}\(markerStem)"
        )
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
        openingLineEnd: Int,
        lineStart: Int,
        openingQuoteDepth: Int
    ) -> DisplayMatch? {
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
