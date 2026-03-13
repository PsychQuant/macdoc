// APAUtilities.swift — Shared APA/BibLaTeX utility functions
// Extracted from che-zotero-mcp's BiblatexAPAFormatter and che-biblatex-mcp's APARuleEngine.
// Pure Foundation, no MCP or Zotero dependencies.

import Foundation

public struct APAUtilities {

    // MARK: - Date Normalization

    /// Normalize date strings to ISO format for biblatex.
    /// Handles: "2019-02-00 2/2019", "2019", "2019-03-15", "Spring 2020",
    /// "2015/" (ongoing), "2020-03-15/2020-03-20" (range)
    public static func normalizeDate(_ dateStr: String) -> String {
        let trimmed = dateStr.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "" }

        // Date ranges with "/" (not URLs)
        if trimmed.contains("/") && !trimmed.hasPrefix("http") {
            let parts = trimmed.components(separatedBy: "/")
            if parts.count == 2 {
                let start = normalizeSingleDate(parts[0])
                let end = parts[1].isEmpty ? "" : normalizeSingleDate(parts[1])
                return "\(start)/\(end)"
            }
        }

        return normalizeSingleDate(trimmed)
    }

    public static func normalizeSingleDate(_ dateStr: String) -> String {
        let trimmed = dateStr.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "" }

        // Season dates ("Spring 2020" → "2020-21")
        let seasonMap: [(String, String)] = [
            ("spring", "-21"), ("summer", "-22"),
            ("fall", "-23"), ("autumn", "-23"), ("winter", "-24")
        ]
        let lower = trimmed.lowercased()
        for (season, code) in seasonMap {
            if lower.contains(season) {
                let yearPattern = try! NSRegularExpression(pattern: "(\\d{4})")
                if let match = yearPattern.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
                   let range = Range(match.range(at: 1), in: trimmed) {
                    return "\(trimmed[range])\(code)"
                }
            }
        }

        // Take the first space-separated token (the ISO part)
        let isoCandidate = trimmed.components(separatedBy: " ").first ?? trimmed

        if isoCandidate.contains("-") || (isoCandidate.count == 4 && Int(isoCandidate) != nil) {
            var result = isoCandidate
            while result.hasSuffix("-00") {
                result = String(result.dropLast(3))
            }
            return result
        }

        // Fallback: extract year
        let yearPattern = try! NSRegularExpression(pattern: "(\\d{4})")
        if let match = yearPattern.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
           let range = Range(match.range(at: 1), in: trimmed) {
            return String(trimmed[range])
        }

        return trimmed
    }

    // MARK: - Title Utilities

    /// Split title at ": " into main title and subtitle.
    /// Guards against false positives like "Re: Something".
    public static func splitTitle(_ title: String) -> (main: String, subtitle: String?) {
        guard title.count > 5 else { return (title, nil) }

        let falsePositivePrefixes = ["Re: ", "re: ", "RE: ", "Fw: ", "FW: ", "Fwd: "]
        for fp in falsePositivePrefixes {
            if title.hasPrefix(fp) { return (title, nil) }
        }

        if let range = title.range(of: ": ",
                                    range: title.index(title.startIndex, offsetBy: 3)..<title.endIndex) {
            let main = String(title[..<range.lowerBound])
            let sub = String(title[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            if !sub.isEmpty && sub.count > 2 {
                return (main, sub)
            }
        }

        if let range = title.range(of: " — ",
                                    range: title.index(title.startIndex, offsetBy: 3)..<title.endIndex) {
            let main = String(title[..<range.lowerBound])
            let sub = String(title[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            if !sub.isEmpty && sub.count > 2 {
                return (main, sub)
            }
        }

        return (title, nil)
    }

    /// Detect whether a title is in sentence case (vs Title Case).
    /// Heuristic: if <40% of content words start with uppercase → sentence case.
    public static func detectSentenceCase(_ text: String) -> Bool {
        let words = text.components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }

        guard words.count >= 3 else { return false }

        let shortWords: Set<String> = ["a", "an", "the", "and", "or", "but", "in",
                                        "on", "at", "to", "for", "of", "by", "with",
                                        "from", "as", "is", "was", "are", "were",
                                        "not", "nor", "so", "yet", "vs", "vs."]
        let contentWords = words.dropFirst().filter { word in
            let clean = word.trimmingCharacters(in: .punctuationCharacters).lowercased()
            return clean.count > 1 && !shortWords.contains(clean)
        }

        guard !contentWords.isEmpty else { return false }

        let capitalizedCount = contentWords.filter { word in
            guard let first = word.first else { return false }
            return first.isUppercase
        }.count

        let ratio = Double(capitalizedCount) / Double(contentWords.count)
        return ratio < 0.40
    }

    // MARK: - Proper Noun Protection

    /// Protect proper nouns and acronyms with braces for biblatex.
    /// biblatex-apa lowercases English titles; braced words are preserved.
    public static func protectProperNouns(_ text: String) -> String {
        var result = text

        // 1. Always protect sequences of 2+ uppercase letters (acronyms: ADHD, LGBTQ, USA)
        let acronymPattern = try! NSRegularExpression(pattern: "\\b([A-Z]{2,})\\b")
        let acronymMatches = acronymPattern.matches(in: result, range: NSRange(result.startIndex..., in: result))
        for match in acronymMatches.reversed() {
            if let range = Range(match.range(at: 1), in: result) {
                let acronym = String(result[range])
                result.replaceSubrange(range, with: "{\(acronym)}")
            }
        }

        // 2. Always protect dotted abbreviations (U.S., U.K.)
        let dottedPattern = try! NSRegularExpression(pattern: "(?<![{])\\b([A-Z]\\.(?:[A-Za-z]\\.)+)")
        let dottedMatches = dottedPattern.matches(in: result, range: NSRange(result.startIndex..., in: result))
        for match in dottedMatches.reversed() {
            if let range = Range(match.range(at: 1), in: result) {
                let dotted = String(result[range])
                result.replaceSubrange(range, with: "{\(dotted)}")
            }
        }

        // 3. Always protect words with internal uppercase (iPhone, macOS, LaTeX)
        let camelPattern = try! NSRegularExpression(pattern: "(?<![{])\\b([a-z]+[A-Z][a-zA-Z]*)\\b")
        let camelMatches = camelPattern.matches(in: result, range: NSRange(result.startIndex..., in: result))
        for match in camelMatches.reversed() {
            if let range = Range(match.range(at: 1), in: result) {
                let word = String(result[range])
                result.replaceSubrange(range, with: "{\(word)}")
            }
        }

        // 4. Detect title casing and apply appropriate strategy
        let isSentenceCase = detectSentenceCase(text)

        if isSentenceCase {
            result = protectSentenceCaseCapitals(result)
        } else {
            result = protectKnownProperNouns(result)
        }

        return result
    }

    /// For sentence case titles: brace any word starting with uppercase (after position 0).
    public static func protectSentenceCaseCapitals(_ text: String) -> String {
        let pattern = try! NSRegularExpression(pattern: "(?<![{A-Za-z])([A-Z][a-z]+)(?![}])")
        var result = text
        let matches = pattern.matches(in: result, range: NSRange(result.startIndex..., in: result))

        let firstWordEnd = text.firstIndex(where: { $0 == " " }) ?? text.endIndex
        let firstWordRange = text.startIndex..<firstWordEnd

        for match in matches.reversed() {
            if let range = Range(match.range(at: 1), in: result) {
                if range.lowerBound < firstWordRange.upperBound { continue }
                let word = String(result[range])
                if range.lowerBound > result.startIndex {
                    let before = result[result.index(before: range.lowerBound)]
                    if before == "{" { continue }
                }
                result.replaceSubrange(range, with: "{\(word)}")
            }
        }

        return result
    }

    /// For Title Case titles: protect words that match the known proper noun list.
    public static func protectKnownProperNouns(_ text: String) -> String {
        var result = text
        let words = text.components(separatedBy: .whitespaces)

        for word in words {
            let cleaned = word.trimmingCharacters(in: .punctuationCharacters)
            guard !cleaned.isEmpty, cleaned.first?.isUppercase == true else { continue }
            if word.hasPrefix("{") { continue }

            if ProperNounList.isProperNoun(cleaned) {
                if let range = result.range(of: cleaned) {
                    let beforeIdx = range.lowerBound
                    if beforeIdx > result.startIndex {
                        let charBefore = result[result.index(before: beforeIdx)]
                        if charBefore == "{" { continue }
                    }
                    result.replaceSubrange(range, with: "{\(cleaned)}")
                }
            }
        }

        return result
    }

    // MARK: - Page & Edition Normalization

    /// Convert page ranges: single hyphen → double hyphen (biblatex en-dash).
    public static func normalizePages(_ pages: String) -> String {
        var result = pages
        result = result.replacingOccurrences(of: "–", with: "-")   // en-dash
        result = result.replacingOccurrences(of: "—", with: "-")   // em-dash
        result = result.replacingOccurrences(of: "--", with: "-")   // already doubled
        result = result.replacingOccurrences(of: "-", with: "--")   // single → double
        return result
    }

    /// Normalize edition to numeric value for biblatex.
    /// "2nd edition" → "2", "Second" → "2", "3" → "3"
    public static func normalizeEdition(_ edition: String) -> String {
        let trimmed = edition.trimmingCharacters(in: .whitespaces)
        if Int(trimmed) != nil { return trimmed }

        let numPattern = try! NSRegularExpression(pattern: "^(\\d+)")
        if let match = numPattern.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
           let range = Range(match.range(at: 1), in: trimmed) {
            return String(trimmed[range])
        }

        let wordMap: [String: String] = [
            "first": "1", "second": "2", "third": "3", "fourth": "4",
            "fifth": "5", "sixth": "6", "seventh": "7", "eighth": "8",
            "ninth": "9", "tenth": "10", "eleventh": "11", "twelfth": "12"
        ]
        let lower = trimmed.lowercased()
        for (word, num) in wordMap {
            if lower.hasPrefix(word) { return num }
        }

        return trimmed
    }

    // MARK: - Language Mapping

    /// Map language string to biblatex LANGID.
    public static func mapLanguageToLangID(_ lang: String) -> String {
        let lower = lang.lowercased()
        if lower.hasPrefix("en") { return "english" }
        if lower.hasPrefix("zh") || lower.contains("chinese") { return "chinese" }
        if lower.hasPrefix("ja") || lower.contains("japanese") { return "japanese" }
        if lower.hasPrefix("ko") || lower.contains("korean") { return "korean" }
        if lower.hasPrefix("fr") || lower.contains("french") { return "french" }
        if lower.hasPrefix("de") || lower.contains("german") { return "german" }
        if lower.hasPrefix("es") || lower.contains("spanish") { return "spanish" }
        if lower.hasPrefix("pt") || lower.contains("portuguese") { return "portuguese" }
        if lower.hasPrefix("it") || lower.contains("italian") { return "italian" }
        return lower
    }

    // MARK: - Extra Field Parsing

    /// Parse Zotero/BibTeX extra field (key: value per line).
    public static func parseExtraField(_ extra: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in extra.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let colonRange = trimmed.range(of: ": ") {
                let key = String(trimmed[..<colonRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                let value = String(trimmed[colonRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                result[key] = value
            }
        }
        return result
    }
}
