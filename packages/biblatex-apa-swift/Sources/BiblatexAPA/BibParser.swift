// Sources/BiblatexAPA/BibParser.swift
// BibTeX/biblatex parser — handles nested braces, comments, multi-line values.

import Foundation

// MARK: - Data Model

public struct BibEntry: Equatable {
    public let entryType: String   // e.g. "ARTICLE", "PRESENTATION", "REPORT"
    public let key: String         // e.g. "cheng_psychometrika_2025"
    public var fields: OrderedDict  // preserves field order
    public let rawText: String     // original text for lossless round-tripping
    public let lineNumber: Int     // 1-based line number in file

    public init(entryType: String, key: String, fields: OrderedDict, rawText: String, lineNumber: Int) {
        self.entryType = entryType
        self.key = key
        self.fields = fields
        self.rawText = rawText
        self.lineNumber = lineNumber
    }

    public var title: String? { fields.caseInsensitiveValue(forKey: "TITLE") }
    public var date: String? { fields.caseInsensitiveValue(forKey: "DATE") }
    public var doi: String? { fields.caseInsensitiveValue(forKey: "DOI") }
    public var authors: String? { fields.caseInsensitiveValue(forKey: "AUTHOR") }
    public var bibType: String? { fields.caseInsensitiveValue(forKey: "TYPE") }

    /// Normalized entry type (uppercased)
    public var normalizedType: String { entryType.uppercased() }
}

/// Simple ordered dictionary preserving insertion order.
public struct OrderedDict: Equatable {
    public private(set) var keys: [String] = []
    public private(set) var values: [String: String] = [:]

    public init() {}

    public subscript(key: String) -> String? {
        get { values[key] }
        set {
            if let v = newValue {
                if values[key] == nil { keys.append(key) }
                values[key] = v
            } else {
                keys.removeAll { $0 == key }
                values.removeValue(forKey: key)
            }
        }
    }

    public var count: Int { keys.count }
    public var isEmpty: Bool { keys.isEmpty }

    public var pairs: [(key: String, value: String)] {
        keys.compactMap { k in values[k].map { (key: k, value: $0) } }
    }

    /// Case-insensitive field lookup (biblatex field names are case-insensitive).
    public func caseInsensitiveValue(forKey name: String) -> String? {
        let lower = name.lowercased()
        if let key = keys.first(where: { $0.lowercased() == lower }) {
            return values[key]
        }
        return nil
    }
}

// MARK: - Parser

public struct BibParser {

    /// Parse a .bib file at the given path.
    public static func parse(filePath: String) throws -> BibFile {
        let content = try String(contentsOfFile: filePath, encoding: .utf8)
        return parse(content: content, filePath: filePath)
    }

    /// Parse .bib content string.
    public static func parse(content: String, filePath: String? = nil) -> BibFile {
        var entries: [BibEntry] = []
        var comments: [String] = []
        let lines = content.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)

            // Skip empty lines and pure comment lines
            if trimmed.isEmpty || trimmed.hasPrefix("%") {
                if trimmed.hasPrefix("%") {
                    comments.append(trimmed)
                }
                i += 1
                continue
            }

            // Detect entry start: @TYPE{key,
            if trimmed.hasPrefix("@") {
                let startLine = i
                // Collect all lines until we find the matching closing brace
                var entryText = lines[i]
                var braceDepth = countBraces(in: lines[i])

                while braceDepth > 0 && i + 1 < lines.count {
                    i += 1
                    entryText += "\n" + lines[i]
                    braceDepth += countBraces(in: lines[i])
                }

                if let entry = parseEntry(entryText, lineNumber: startLine + 1) {
                    entries.append(entry)
                }
            }

            i += 1
        }

        return BibFile(
            entries: entries,
            filePath: filePath,
            rawContent: content,
            comments: comments
        )
    }

    // MARK: - Entry Parsing

    private static func parseEntry(_ text: String, lineNumber: Int) -> BibEntry? {
        // Match @TYPE{key, ... }
        // Allow flexible whitespace
        guard let atIndex = text.firstIndex(of: "@") else { return nil }
        let afterAt = text[text.index(after: atIndex)...]

        guard let braceIndex = afterAt.firstIndex(of: "{") else { return nil }
        let entryType = String(afterAt[afterAt.startIndex..<braceIndex])
            .trimmingCharacters(in: .whitespaces)

        // Skip @comment, @string, @preamble
        let typeUpper = entryType.uppercased()
        if typeUpper == "COMMENT" || typeUpper == "STRING" || typeUpper == "PREAMBLE" {
            return nil
        }

        let afterBrace = afterAt[afterAt.index(after: braceIndex)...]

        // Find the key (everything before first comma)
        guard let commaIndex = afterBrace.firstIndex(of: ",") else { return nil }
        let key = String(afterBrace[afterBrace.startIndex..<commaIndex])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Parse fields from the remainder
        let fieldsText = String(afterBrace[afterBrace.index(after: commaIndex)...])
        let fields = parseFields(fieldsText)

        return BibEntry(
            entryType: entryType,
            key: key,
            fields: fields,
            rawText: text,
            lineNumber: lineNumber
        )
    }

    private static func parseFields(_ text: String) -> OrderedDict {
        var fields = OrderedDict()
        var remaining = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove trailing }
        if remaining.hasSuffix("}") {
            remaining = String(remaining.dropLast())
        }

        while !remaining.isEmpty {
            remaining = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
            if remaining.isEmpty || remaining == "}" { break }

            // Skip commas and whitespace between fields
            if remaining.hasPrefix(",") {
                remaining = String(remaining.dropFirst())
                continue
            }

            // Skip comment lines within entry
            if remaining.hasPrefix("%") {
                if let newline = remaining.firstIndex(of: "\n") {
                    remaining = String(remaining[remaining.index(after: newline)...])
                } else {
                    break
                }
                continue
            }

            // Match: FIELD = {value} or FIELD = "value" or FIELD = number
            guard let eqIndex = remaining.firstIndex(of: "=") else { break }
            let fieldName = String(remaining[remaining.startIndex..<eqIndex])
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if fieldName.isEmpty { break }

            remaining = String(remaining[remaining.index(after: eqIndex)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // Extract value
            let (value, rest) = extractValue(from: remaining)
            fields[fieldName] = value
            remaining = rest
        }

        return fields
    }

    /// Extract a brace-delimited or quoted value, respecting nesting.
    private static func extractValue(from text: String) -> (value: String, remaining: String) {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if s.hasPrefix("{") {
            // Brace-delimited value
            var depth = 0
            var endIdx = s.startIndex
            for idx in s.indices {
                if s[idx] == "{" { depth += 1 }
                else if s[idx] == "}" {
                    depth -= 1
                    if depth == 0 {
                        endIdx = idx
                        break
                    }
                }
            }
            let inner = String(s[s.index(after: s.startIndex)..<endIdx])
            let rest = String(s[s.index(after: endIdx)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (inner, rest)
        } else if s.hasPrefix("\"") {
            // Quoted value — find closing " that isn't a LaTeX escape \"
            s = String(s.dropFirst())
            var closeIdx: String.Index? = nil
            var prev: Character = "\0"
            for idx in s.indices {
                if s[idx] == "\"" && prev != "\\" {
                    closeIdx = idx
                    break
                }
                prev = s[idx]
            }
            if let closeQuote = closeIdx {
                let inner = String(s[s.startIndex..<closeQuote])
                let rest = String(s[s.index(after: closeQuote)...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return (inner, rest)
            }
            return (s, "")
        } else {
            // Numeric or simple value (until comma or closing brace)
            var endIdx = s.endIndex
            for idx in s.indices {
                if s[idx] == "," || s[idx] == "}" {
                    endIdx = idx
                    break
                }
            }
            let value = String(s[s.startIndex..<endIdx])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let rest = endIdx < s.endIndex ? String(s[endIdx...]) : ""
            return (value, rest)
        }
    }

    private static func countBraces(in line: String) -> Int {
        var count = 0
        var inQuote = false
        var prevChar: Character = "\0"
        for ch in line {
            // Skip \" — it's a LaTeX diacritical (umlaut), not a BibTeX quote delimiter
            if ch == "\"" && prevChar != "\\" { inQuote.toggle() }
            if !inQuote {
                if ch == "{" { count += 1 }
                else if ch == "}" { count -= 1 }
            }
            prevChar = ch
        }
        return count
    }
}

// MARK: - BibFile

public struct BibFile {
    public let entries: [BibEntry]
    public let filePath: String?
    public let rawContent: String
    public let comments: [String]

    public func entry(forKey key: String) -> BibEntry? {
        entries.first { $0.key == key }
    }

    public func search(query: String) -> [BibEntry] {
        let q = query.lowercased()
        return entries.filter { entry in
            entry.key.lowercased().contains(q) ||
            (entry.title?.lowercased().contains(q) ?? false) ||
            (entry.authors?.lowercased().contains(q) ?? false) ||
            entry.entryType.lowercased().contains(q)
        }
    }

    public var articleEntries: [BibEntry] {
        entries.filter { $0.normalizedType == "ARTICLE" }
    }

    public var presentationEntries: [BibEntry] {
        entries.filter { $0.normalizedType == "PRESENTATION" }
    }

    public var reportEntries: [BibEntry] {
        entries.filter { $0.normalizedType == "REPORT" }
    }
}
