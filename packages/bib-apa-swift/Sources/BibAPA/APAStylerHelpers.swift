// APAStylerHelpers.swift — Pure utility functions for APA 7 formatting
// Extracted from BibToAPAFormatter.swift (bib-to-apa-swift)

import Foundation
import BiblatexAPA

// MARK: - Author Name Model

public struct AuthorName: Equatable, Sendable {
    public let lastName: String
    public let firstName: String  // may be empty for corporate authors
    public let suffix: String     // e.g. "Jr."

    public var isCorporate: Bool { firstName.isEmpty && suffix.isEmpty }

    public init(lastName: String, firstName: String, suffix: String = "") {
        self.lastName = lastName
        self.firstName = firstName
        self.suffix = suffix
    }
}

// MARK: - Author Parsing

/// Parse biblatex author string into structured name parts.
/// Handles: "Last, First and Last, First" / "{Corporate Name}" / "Last, First, Jr."
public func parseAuthors(_ entry: BibEntry) -> [AuthorName] {
    guard let raw = field(entry, "AUTHOR") else { return [] }
    return parseNameList(raw)
}

public func parseSingleAuthor(_ raw: String) -> AuthorName {
    let trimmed = raw.trimmingCharacters(in: .whitespaces)

    // Corporate author: {American Psychological Association}
    if trimmed.hasPrefix("{") && trimmed.hasSuffix("}") {
        let name = String(trimmed.dropFirst().dropLast())
        return AuthorName(lastName: name, firstName: "", suffix: "")
    }

    let parts = trimmed.components(separatedBy: ",").map {
        $0.trimmingCharacters(in: .whitespaces)
    }

    switch parts.count {
    case 1:
        let words = parts[0].components(separatedBy: " ").filter { !$0.isEmpty }
        if words.count == 1 {
            return AuthorName(lastName: words[0], firstName: "")
        }
        let last = words.last!
        let first = words.dropLast().joined(separator: " ")
        return AuthorName(lastName: last, firstName: first)

    case 2:
        return AuthorName(lastName: parts[0], firstName: parts[1])

    case 3:
        if parts[1].lowercased().contains("jr") || parts[1].lowercased().contains("sr")
            || parts[1].lowercased().contains("iii") || parts[1].lowercased().contains("ii") {
            return AuthorName(lastName: parts[0], firstName: parts[2], suffix: parts[1])
        }
        return AuthorName(lastName: parts[0], firstName: "\(parts[1]), \(parts[2])")

    default:
        return AuthorName(lastName: trimmed, firstName: "")
    }
}

// MARK: - Author Formatting (Reference List)

/// APA 7 reference list format: Last, F. M., & Last, F. M.
public func formatAuthorNames(_ names: [AuthorName]) -> String {
    let formatted = names.map(formatSingleAuthorRef)
    let count = formatted.count

    switch count {
    case 0: return ""
    case 1: return formatted[0]
    case 2: return "\(formatted[0]), & \(formatted[1])"
    case 3...20:
        let allButLast = formatted.dropLast().joined(separator: ", ")
        return "\(allButLast), & \(formatted.last!)"
    default:
        let first19 = formatted.prefix(19).joined(separator: ", ")
        return "\(first19), . . . \(formatted.last!)"
    }
}

/// Format single author for reference list: Last, F. M.
public func formatSingleAuthorRef(_ author: AuthorName) -> String {
    if author.isCorporate { return author.lastName }

    let initials = formatInitials(author.firstName)
    var result = author.lastName
    if !initials.isEmpty {
        result += ", \(initials)"
    }
    if !author.suffix.isEmpty {
        result += ", \(author.suffix)"
    }
    return result
}

/// Format editor name for "In" clause: F. M. Last
public func formatSingleAuthorForIn(_ author: AuthorName) -> String {
    if author.isCorporate { return author.lastName }
    let initials = formatInitials(author.firstName)
    return initials.isEmpty ? author.lastName : "\(initials) \(author.lastName)"
}

/// Convert first name to initials: "Hau-Hung" → "H.-H.", "Sarah Michelle" → "S. M."
public func formatInitials(_ firstName: String) -> String {
    let parts = firstName.components(separatedBy: " ")
        .filter { !$0.isEmpty }

    return parts.map { part in
        if part.count <= 2 && part.first?.isUppercase == true {
            return part.hasSuffix(".") ? part : "\(part)."
        }
        if part.contains("-") {
            let sub = part.components(separatedBy: "-")
            return sub.map { s in
                guard let first = s.first else { return "" }
                return "\(first.uppercased())."
            }.joined(separator: "-")
        }
        guard let first = part.first else { return "" }
        return "\(first.uppercased())."
    }.joined(separator: " ")
}

// MARK: - Citation Authors

/// APA 7 in-text citation: 1 → Last; 2 → Last & Last; 3+ → Last et al.
public func formatCitationAuthors(_ entry: BibEntry) -> String {
    let names = parseAuthors(entry)
    if names.isEmpty { return "Unknown" }

    switch names.count {
    case 1: return names[0].lastName
    case 2: return "\(names[0].lastName) & \(names[1].lastName)"
    default: return "\(names[0].lastName) et al."
    }
}

// MARK: - Field Access

/// Case-insensitive field lookup
public func field(_ entry: BibEntry, _ name: String) -> String? {
    entry.fields.caseInsensitiveValue(forKey: name)
}

// MARK: - Text Processing

/// Strip outer braces: "{ADHD}" → "ADHD"
public func stripBraces(_ text: String) -> String {
    var result = text
    while result.hasPrefix("{") && result.hasSuffix("}") {
        let inner = String(result.dropFirst().dropLast())
        var depth = 0
        var balanced = true
        for ch in inner {
            if ch == "{" { depth += 1 }
            else if ch == "}" { depth -= 1 }
            if depth < 0 { balanced = false; break }
        }
        if balanced && depth == 0 {
            result = inner
        } else {
            break
        }
    }
    return result
}

// MARK: - LaTeX text decoding (macdoc#197)

/// Accent commands and their combining marks. Symbol accents (`\'`) are control
/// symbols: TeX does not skip spaces after them, so the base must follow
/// directly. Letter accents (`\c`, `\v`, …) are control words: TeX skips any
/// whitespace after them, and they must be the whole command name.
private let latexSymbolAccents: [Character: Character] = [
    "'": "\u{0301}", "`": "\u{0300}", "^": "\u{0302}", "\"": "\u{0308}",
    "~": "\u{0303}", "=": "\u{0304}", ".": "\u{0307}",
]
private let latexLetterAccents: [String: Character] = [
    "u": "\u{0306}", "v": "\u{030C}", "H": "\u{030B}", "c": "\u{0327}",
    "k": "\u{0328}", "r": "\u{030A}", "d": "\u{0323}", "b": "\u{0331}",
]

/// Letter macros that stand for a whole character, matched by full command name.
private let latexLetterMacros: [String: String] = [
    "ss": "ß", "o": "ø", "O": "Ø", "ae": "æ", "AE": "Æ", "oe": "œ", "OE": "Œ",
    "aa": "å", "AA": "Å", "l": "ł", "L": "Ł", "i": "ı", "j": "ȷ",
]

/// Escaped special characters (braces are handled separately as literals).
private let latexEscapes: [Character: String] = ["&": "&", "%": "%", "$": "$", "#": "#", "_": "_"]

/// Stand-ins for literal braces (`\{`, `\}`, and the argument braces of a
/// command we keep verbatim), so removing *protective* braces cannot delete
/// them. Chosen per call from the private-use area so they never collide with
/// a character already present in the input.
struct LiteralBraces {
    let open: Character
    let close: Character

    init(avoiding text: String) {
        let used = Set(text.unicodeScalars.map(\.value))
        var free = (0xE000...0xF8FF).lazy.filter { !used.contains(UInt32($0)) }.makeIterator()
        open = Character(Unicode.Scalar(UInt32(free.next()!))!)
        close = Character(Unicode.Scalar(UInt32(free.next()!))!)
    }

    func restore(_ text: String) -> String {
        String(text.map { $0 == open ? "{" : $0 == close ? "}" : $0 })
    }

    /// Drop protective braces, then turn the literal stand-ins back into braces.
    func removeProtectiveBraces(_ text: String) -> String {
        restore(String(text.filter { $0 != "{" && $0 != "}" }))
    }
}

/// Decode biblatex text markup to Unicode: accent macros, letter macros and
/// escaped special characters. Protective braces are left in place (sentence
/// case still needs them); only an accent's own argument is consumed. Unknown
/// commands are kept verbatim, including their argument.
public func decodeLaTeX(_ text: String) -> String {
    let literal = LiteralBraces(avoiding: text)
    return literal.restore(decodeLaTeX(text, literal: literal, protectUnknown: false))
}

/// Core decoder. Literal braces come back as `literal.open` / `literal.close`.
/// With `protectUnknown`, a verbatim-kept command is wrapped in a protective
/// brace pair so sentence case leaves its spelling alone.
func decodeLaTeX(_ text: String, literal: LiteralBraces, protectUnknown: Bool) -> String {
    guard text.contains("\\") else { return text }
    let chars = Array(text)
    var out = ""
    var i = 0
    while i < chars.count {
        guard chars[i] == "\\", i + 1 < chars.count else { out.append(chars[i]); i += 1; continue }
        let cmd = chars[i + 1]
        if let escaped = latexEscapes[cmd] { out += escaped; i += 2; continue }
        if cmd == "{" { out.append(literal.open); i += 2; continue }
        if cmd == "}" { out.append(literal.close); i += 2; continue }
        if let mark = latexSymbolAccents[cmd] {
            if let (base, next) = latexAccentBase(chars, from: i + 2) {
                out += (base + String(mark)).precomposedStringWithCanonicalMapping
                i = next
            } else {
                out.append(chars[i]); out.append(cmd); i += 2
            }
            continue
        }
        guard cmd.isLetter else { out.append(chars[i]); out.append(cmd); i += 2; continue }

        var j = i + 1
        while j < chars.count, chars[j].isLetter { j += 1 }
        let name = String(chars[(i + 1)..<j])
        let afterSpaces = skipWhitespace(chars, from: j)
        if let mark = latexLetterAccents[name], let (base, next) = latexAccentBase(chars, from: afterSpaces) {
            out += (base + String(mark)).precomposedStringWithCanonicalMapping
            i = next; continue
        }
        if let letter = latexLetterMacros[name] {
            out += letter
            // TeX swallows the spaces after a control word; `\ss{}` ends it explicitly.
            var k = afterSpaces
            if k + 1 < chars.count, chars[k] == "{", chars[k + 1] == "}" { k += 2 }
            i = k; continue
        }
        // Unknown command: keep `\name` and any argument groups exactly as written.
        var verbatim = "\\" + name
        var k = j
        while k < chars.count, chars[k] == "{", let close = matchingBrace(chars, from: k) {
            verbatim.append(literal.open)
            verbatim += String(chars[(k + 1)..<close].map { $0 == "{" ? literal.open : $0 == "}" ? literal.close : $0 })
            verbatim.append(literal.close)
            k = close + 1
        }
        out += protectUnknown ? "{\(verbatim)}" : verbatim
        i = k
    }
    return out
}

/// The base character of an accent: a braced group whose content (ignoring
/// nested braces) is one character or `\i`/`\j`, a bare letter, or a bare
/// `\i`/`\j` that is the whole command name. Returns nil when the argument is
/// not something we can compose, so the caller keeps the macro verbatim.
private func latexAccentBase(_ chars: [Character], from start: Int) -> (String, Int)? {
    guard start < chars.count else { return nil }
    if chars[start] == "{" {
        guard let close = matchingBrace(chars, from: start) else { return nil }
        let content = String(chars[(start + 1)..<close]).filter { $0 != "{" && $0 != "}" && !$0.isWhitespace }
        if content == "\\i" || content == "\\j" { return (content == "\\i" ? "i" : "j", close + 1) }
        guard content.count == 1, let only = content.first, only != "\\" else { return nil }
        return (String(only), close + 1)
    }
    if chars[start] == "\\" {
        var j = start + 1
        while j < chars.count, chars[j].isLetter { j += 1 }
        let name = String(chars[(start + 1)..<j])
        guard name == "i" || name == "j" else { return nil }
        var k = j
        if k + 1 < chars.count, chars[k] == "{", chars[k + 1] == "}" { k += 2 }
        return (name, k)
    }
    guard chars[start].isLetter else { return nil }
    return (String(chars[start]), start + 1)
}

private func skipWhitespace(_ chars: [Character], from start: Int) -> Int {
    var i = start
    while i < chars.count, chars[i].isWhitespace { i += 1 }
    return i
}

/// Index of the `}` that closes the `{` at `open`, or nil if it is unbalanced.
private func matchingBrace(_ chars: [Character], from open: Int) -> Int? {
    var depth = 0
    var i = open
    while i < chars.count {
        if chars[i] == "\\" { i += 2; continue }   // an escaped brace does not count
        if chars[i] == "{" { depth += 1 }
        if chars[i] == "}" { depth -= 1; if depth == 0 { return i } }
        i += 1
    }
    return nil
}

/// Rendered plain text for a non-sentence-case field: decode LaTeX, then drop
/// every protective brace. Escaped braces and unknown commands survive.
public func plainText(_ text: String) -> String {
    let literal = LiteralBraces(avoiding: text)
    return literal.removeProtectiveBraces(decodeLaTeX(stripBraces(text), literal: literal, protectUnknown: false))
}

/// Remove protective braces from already-decoded text (no escapes to restore).
public func removeProtectiveBraces(_ text: String) -> String {
    String(text.filter { $0 != "{" && $0 != "}" })
}

/// Parse a biblatex name list (AUTHOR / EDITOR): decode accents, split on
/// ` and `, parse each name, then drop protective braces. The outer braces of
/// a corporate name must survive until `parseSingleAuthor` has seen them.
public func parseNameList(_ raw: String) -> [AuthorName] {
    let literal = LiteralBraces(avoiding: raw)
    let decoded = decodeLaTeX(raw, literal: literal, protectUnknown: false)
    return decoded.components(separatedBy: " and ")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
        .map(parseSingleAuthor)
        .map {
            AuthorName(lastName: literal.removeProtectiveBraces($0.lastName),
                       firstName: literal.removeProtectiveBraces($0.firstName),
                       suffix: literal.removeProtectiveBraces($0.suffix))
        }
}

/// Rendered text for a sentence-case field (titles): decode LaTeX first so an
/// accent macro's argument braces are not mistaken for protection, apply APA
/// sentence case (which needs the protective braces), then drop what is left.
public func sentenceCaseText(_ text: String) -> String {
    let literal = LiteralBraces(avoiding: text)
    return literal.removeProtectiveBraces(
        toSentenceCase(decodeLaTeX(stripBraces(text), literal: literal, protectUnknown: true)))
}

/// Convert to APA sentence case. Preserves content inside braces as-is.
public func toSentenceCase(_ title: String) -> String {
    var segments: [(text: String, protected: Bool)] = []
    var current = ""
    var depth = 0

    for ch in title {
        if ch == "{" {
            if depth == 0 && !current.isEmpty {
                segments.append((current, false))
                current = ""
            }
            depth += 1
            if depth > 1 { current.append(ch) }
        } else if ch == "}" {
            depth -= 1
            if depth == 0 {
                segments.append((current, true))
                current = ""
            } else if depth > 0 {
                current.append(ch)
            }
        } else {
            current.append(ch)
        }
    }
    if !current.isEmpty {
        segments.append((current, false))
    }

    var isFirst = true
    let processed = segments.map { segment -> String in
        if segment.protected { return segment.text }

        let words = segment.text.components(separatedBy: " ")
        let result = words.enumerated().map { (_, word) -> String in
            if word.isEmpty { return word }

            if word.count >= 2 && word == word.uppercased()
                && word.rangeOfCharacter(from: .lowercaseLetters) == nil {
                return word
            }

            if isFirst {
                isFirst = false
                return capitalizeFirst(word.lowercased())
            }

            return word.lowercased()
        }.joined(separator: " ")

        return capitalizeAfterColon(result)
    }

    return processed.joined()
}

/// Capitalize the first letter after ": "
public func capitalizeAfterColon(_ text: String) -> String {
    guard let regex = try? NSRegularExpression(pattern: ": ([a-z])") else { return text }
    let nsText = text as NSString
    let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

    var result = text
    for match in matches.reversed() {
        guard let letterRange = Range(match.range(at: 1), in: result) else { continue }
        let letter = result[letterRange].uppercased()
        result.replaceSubrange(letterRange, with: letter)
    }
    return result
}

public func capitalizeFirst(_ word: String) -> String {
    guard let first = word.first else { return word }
    return first.uppercased() + word.dropFirst()
}

// MARK: - Edition & Pages

public func formatEdition(_ edition: String?) -> String? {
    guard let ed = edition, !ed.isEmpty else { return nil }
    let clean = plainText(ed)
    if clean.contains("ed") { return clean }
    guard let num = Int(clean), num > 1 else { return nil }
    let suffix: String
    switch num {
    case 2: suffix = "nd"
    case 3: suffix = "rd"
    default: suffix = "th"
    }
    return "\(num)\(suffix) ed."
}

/// Normalize pages: "1--51" → "1–51"
public func normalizePages(_ pages: String) -> String {
    var result = plainText(pages)
    result = result.replacingOccurrences(of: "--", with: "–")
    result = result.replacingOccurrences(of: "—", with: "–")
    if let regex = try? NSRegularExpression(pattern: "(\\d)-(\\d)") {
        result = regex.stringByReplacingMatches(
            in: result,
            range: NSRange(result.startIndex..., in: result),
            withTemplate: "$1–$2"
        )
    }
    return result
}

// MARK: - Date Formatting

public let monthNames = [
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December"
]

/// Format a normalized ISO date: "2025" → "2025", "2025-03" → "2025, March"
public func formatNormalizedDate(_ date: String) -> String {
    let parts = date.components(separatedBy: "-")
    guard let year = parts.first, !year.isEmpty else { return "n.d." }

    if parts.count >= 2, let monthNum = Int(parts[1]) {
        if monthNum >= 21 && monthNum <= 24 {
            let seasons = [21: "Spring", 22: "Summer", 23: "Fall", 24: "Winter"]
            return "\(year), \(seasons[monthNum]!)"
        }
        if monthNum >= 1 && monthNum <= 12 {
            let monthName = monthNames[monthNum - 1]
            if parts.count >= 3, let day = Int(parts[2]), day > 0 {
                return "\(year), \(monthName) \(day)"
            }
            return "\(year), \(monthName)"
        }
    }
    return year
}

/// Format EVENTDATE ranges: "2025-05-01/2025-05-03" → "2025, May 1–3"
public func formatEventDate(_ eventDate: String) -> String {
    let normalized = APAUtilities.normalizeDate(eventDate)

    if normalized.contains("/") {
        let parts = normalized.components(separatedBy: "/")
        if parts.count == 2 {
            let start = parts[0]
            let end = parts[1]

            let startParts = start.components(separatedBy: "-")
            let endParts = end.components(separatedBy: "-")

            guard startParts.count >= 3,
                  let year = startParts.first,
                  let startMonth = Int(startParts[1]),
                  let startDay = Int(startParts[2]) else {
                return formatNormalizedDate(start)
            }

            let startMonthName = monthNames[startMonth - 1]

            if endParts.count >= 3,
               let endMonth = Int(endParts[1]),
               let endDay = Int(endParts[2]) {
                if startMonth == endMonth {
                    return "\(year), \(startMonthName) \(startDay)–\(endDay)"
                } else {
                    let endMonthName = monthNames[endMonth - 1]
                    return "\(year), \(startMonthName) \(startDay)–\(endMonthName) \(endDay)"
                }
            }

            return "\(year), \(startMonthName) \(startDay)"
        }
    }

    return formatNormalizedDate(normalized)
}

/// Format date for reference list
public func formatDate(_ entry: BibEntry) -> String {
    let type = entry.normalizedType
    if type == "PRESENTATION" {
        if let eventDate = field(entry, "EVENTDATE"), !eventDate.isEmpty {
            return formatEventDate(eventDate)
        }
    }

    guard let dateStr = entry.date, !dateStr.isEmpty else { return "n.d." }
    let normalized = APAUtilities.normalizeDate(dateStr)
    return formatNormalizedDate(normalized)
}

/// Extract just the year
public func extractYear(_ entry: BibEntry) -> String {
    guard let dateStr = entry.date, !dateStr.isEmpty else { return "n.d." }
    let normalized = APAUtilities.normalizeDate(dateStr)
    return String(normalized.prefix(4))
}

// MARK: - Reference List Authors

/// Format authors for reference list with trailing period.
public func formatAuthorsString(_ entry: BibEntry) -> String {
    var names = parseAuthors(entry)
    if names.isEmpty {
        if let editorRaw = field(entry, "EDITOR"), !editorRaw.isEmpty {
            var mutable = entry
            mutable.fields["AUTHOR"] = editorRaw
            names = parseAuthors(mutable)
            if !names.isEmpty {
                let edFormatted = formatAuthorNames(names)
                let edLabel = names.count == 1 ? "Ed." : "Eds."
                let edResult = edFormatted.hasSuffix(".") ? String(edFormatted.dropLast()) : edFormatted
                return "\(edResult) (\(edLabel))."
            }
        }
        return ""
    }
    let formatted = formatAuthorNames(names)
    return formatted.hasSuffix(".") ? formatted : formatted + "."
}
