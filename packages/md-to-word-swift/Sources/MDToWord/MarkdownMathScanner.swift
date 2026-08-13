import Foundation

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

    private enum ReferenceContinuation: Equatable {
        case destination
        case optionalTitle
    }

    private let markerPrefix: String
    private let markerNonce: String

    init(
        markerPrefix: String = Self.defaultMarkerPrefix,
        markerNonce: String = UUID().uuidString.replacingOccurrences(of: "-", with: "")
    ) {
        self.markerPrefix = markerPrefix
        self.markerNonce = markerNonce
    }

    func scan(_ source: String) throws -> Result {
        let characters = Array(source)
        var output = ""
        var tokens: [Token] = []
        var nextMarkerIndex = 0
        var index = 0
        var line = 1
        var column = 1
        var lineStart = 0
        var fence: (character: Character, length: Int)?
        var referenceContinuation: ReferenceContinuation?

        func marker() -> String {
            var candidate: String
            repeat {
                candidate = "\(markerPrefix)\(markerNonce)\(nextMarkerIndex)TOKEN"
                nextMarkerIndex += 1
            } while source.contains(candidate) || tokens.contains(where: { $0.placeholder == candidate })
            return candidate
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
                if let activeFence = fence {
                    if Self.isFenceClosingLine(
                        characters,
                        start: context.contentStart,
                        end: contentEnd,
                        fence: activeFence
                    ) {
                        fence = nil
                    }
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

                if context.isIndentedCode {
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

                if let openingFence = Self.fenceOpening(
                    characters,
                    start: context.contentStart,
                    end: contentEnd
                ) {
                    fence = openingFence
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

                if let activeReferenceContinuation = referenceContinuation {
                    if context.isBlank {
                        referenceContinuation = nil
                    } else if activeReferenceContinuation == .destination
                        || context.indentation > 0 {
                        referenceContinuation = .optionalTitle
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
                    } else {
                        referenceContinuation = nil
                    }
                }

                if let needsDestination = Self.referenceDefinitionNeedsDestination(
                    characters,
                    start: context.contentStart,
                    end: contentEnd
                ) {
                    referenceContinuation = needsDestination ? .destination : .optionalTitle
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

            if characters[index] == "`" {
                let runLength = Self.runLength(of: "`", in: characters, from: index)
                if let end = Self.inlineCodeEnd(
                    in: characters,
                    after: index + runLength,
                    delimiterLength: runLength
                ) {
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
            }

            if characters[index] == "<",
               let end = Self.angleRegionEnd(in: characters, from: index) {
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

            if characters[index] == "]",
               index + 1 < characters.count,
               characters[index + 1] == "(",
               let end = Self.linkDestinationEnd(in: characters, from: index + 1) {
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
                    lineStart: lineStart
                ) {
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
                   !last.isWhitespace {
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
        lineStart: Int
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
            let mixed = !prefixIsWhitespace
                || !suffixIsWhitespace
                || adjacentPreviousLineHasContent(
                    in: characters,
                    before: lineStart
                )
                || adjacentNextLineHasContent(
                    in: characters,
                    after: consumedEnd
                )
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
        let bodyStart = search
        while search < characters.count {
            let candidateLineEnd = contentEndBeforeNewline(
                in: characters,
                lineEnd: lineEnd(in: characters, from: search)
            )
            var firstNonWhitespace = search
            while firstNonWhitespace < candidateLineEnd,
                  characters[firstNonWhitespace].isWhitespace {
                firstNonWhitespace += 1
            }
            if firstNonWhitespace + 2 <= candidateLineEnd,
               characters[firstNonWhitespace] == "$",
               characters[firstNonWhitespace + 1] == "$",
               characters[(firstNonWhitespace + 2)..<candidateLineEnd].allSatisfy(\.isWhitespace) {
                let body = String(characters[bodyStart..<search])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                var consumedEnd = candidateLineEnd
                if consumedEnd < characters.count, characters[consumedEnd].isNewline {
                    consumedEnd += 1
                }
                return DisplayMatch(
                    latex: body,
                    replacementStart: opening,
                    replacementEnd: firstNonWhitespace + 2,
                    consumedEnd: consumedEnd,
                    mixedWithText: adjacentPreviousLineHasContent(
                        in: characters,
                        before: lineStart
                    ) || adjacentNextLineHasContent(
                        in: characters,
                        after: consumedEnd
                    )
                )
            }
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

    private static func fenceOpening(
        _ characters: [Character],
        start: Int,
        end: Int
    ) -> (character: Character, length: Int)? {
        var index = start
        var indentation = 0
        while index < end, characters[index] == " ", indentation < 4 {
            index += 1
            indentation += 1
        }
        guard indentation <= 3, index < end else { return nil }
        let character = characters[index]
        guard character == "`" || character == "~" else { return nil }
        let length = runLength(of: character, in: characters, from: index)
        guard length >= 3 else { return nil }
        return (character, length)
    }

    private struct LineContext {
        let contentStart: Int
        let indentation: Int
        let isIndentedCode: Bool
        let isBlank: Bool
    }

    private static func lineContext(
        _ characters: [Character],
        start: Int,
        end: Int
    ) -> LineContext {
        var index = start
        var indentation = 0

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
                indentation: indentation,
                isIndentedCode: true,
                isBlank: index == end
            )
        }

        while index < end {
            if characters[index] == ">" {
                index += 1
                if index < end, characters[index] == " " || characters[index] == "\t" {
                    index += 1
                }
                consumeIndentation()
                if indentation >= 4 {
                    return LineContext(
                        contentStart: index,
                        indentation: indentation,
                        isIndentedCode: true,
                        isBlank: index == end
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
            indentation: indentation,
            isIndentedCode: false,
            isBlank: characters[index..<end].allSatisfy(\.isWhitespace)
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

    private static func adjacentPreviousLineHasContent(
        in characters: [Character],
        before lineStart: Int
    ) -> Bool {
        guard lineStart > 0 else { return false }
        var end = lineStart
        if characters[end - 1].isNewline {
            end -= 1
        }
        var start = end
        while start > 0, !characters[start - 1].isNewline {
            start -= 1
        }
        return lineHasLogicalContent(characters, start: start, end: end)
    }

    private static func adjacentNextLineHasContent(
        in characters: [Character],
        after consumedEnd: Int
    ) -> Bool {
        var start = consumedEnd
        if start > 0, !characters[start - 1].isNewline {
            start = lineEnd(in: characters, from: start)
        }
        guard start < characters.count else { return false }
        let end = contentEndBeforeNewline(
            in: characters,
            lineEnd: lineEnd(in: characters, from: start)
        )
        return lineHasLogicalContent(characters, start: start, end: end)
    }

    private static func lineHasLogicalContent(
        _ characters: [Character],
        start: Int,
        end: Int
    ) -> Bool {
        let context = lineContext(characters, start: start, end: end)
        return !context.isBlank
    }

    private static func referenceDefinitionNeedsDestination(
        _ characters: [Character],
        start: Int,
        end: Int
    ) -> Bool? {
        var index = start
        var indentation = 0
        while index < end, characters[index] == " ", indentation < 4 {
            index += 1
            indentation += 1
        }
        guard indentation <= 3, index < end, characters[index] == "[" else {
            return nil
        }

        index += 1
        let labelStart = index
        while index < end {
            if characters[index] == "\\" {
                index = min(index + 2, end)
                continue
            }
            if characters[index] == "]" {
                guard index > labelStart else { return nil }
                let colon = index + 1
                guard colon < end, characters[colon] == ":" else { return nil }
                return characters[(colon + 1)..<end].allSatisfy(\.isWhitespace)
            }
            index += 1
        }
        return nil
    }

    private static func isFenceClosingLine(
        _ characters: [Character],
        start: Int,
        end: Int,
        fence: (character: Character, length: Int)
    ) -> Bool {
        var index = start
        var indentation = 0
        while index < end, characters[index] == " ", indentation < 4 {
            index += 1
            indentation += 1
        }
        guard indentation <= 3, index < end else { return false }
        let length = runLength(of: fence.character, in: characters, from: index)
        guard length >= fence.length else { return false }
        return characters[(index + length)..<end].allSatisfy(\.isWhitespace)
    }

    private static func inlineCodeEnd(
        in characters: [Character],
        after start: Int,
        delimiterLength: Int
    ) -> Int? {
        var index = start
        while index < characters.count {
            if characters[index] == "`" {
                let length = runLength(of: "`", in: characters, from: index)
                if length == delimiterLength {
                    return index + length
                }
                index += length
                continue
            }
            index += 1
        }
        return nil
    }

    private static func angleRegionEnd(
        in characters: [Character],
        from start: Int
    ) -> Int? {
        var index = start + 1
        while index < characters.count {
            if characters[index] == ">" {
                return index + 1
            }
            if characters[index].isNewline {
                return nil
            }
            index += 1
        }
        return nil
    }

    private static func linkDestinationEnd(
        in characters: [Character],
        from openingParenthesis: Int
    ) -> Int? {
        var depth = 0
        var index = openingParenthesis
        while index < characters.count {
            if characters[index] == "\\" {
                index = min(index + 2, characters.count)
                continue
            }
            if characters[index] == "(" {
                depth += 1
            } else if characters[index] == ")" {
                depth -= 1
                if depth == 0 {
                    return index + 1
                }
            } else if characters[index].isNewline {
                return nil
            }
            index += 1
        }
        return nil
    }

    private static func runLength(
        of character: Character,
        in characters: [Character],
        from start: Int
    ) -> Int {
        var end = start
        while end < characters.count, characters[end] == character {
            end += 1
        }
        return end - start
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
