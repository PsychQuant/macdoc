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

    let authorStrings = raw.components(separatedBy: " and ")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }

    return authorStrings.map(parseSingleAuthor)
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
    let clean = stripBraces(ed)
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
    var result = stripBraces(pages)
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
