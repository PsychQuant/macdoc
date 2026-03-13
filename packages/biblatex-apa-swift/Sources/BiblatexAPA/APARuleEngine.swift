// Sources/CheBiblatexMCPCore/APARuleEngine.swift
// APA 7 rule engine — transforms any biblatex entry into correct APA format.

import Foundation

// MARK: - Fix Result

public struct FixAction: CustomStringConvertible {
    public enum Kind: String {
        case typeChanged = "TYPE_CHANGED"
        case fieldRenamed = "FIELD_RENAMED"
        case fieldAdded = "FIELD_ADDED"
        case fieldRemoved = "FIELD_REMOVED"
        case fieldValueFixed = "VALUE_FIXED"
        case authorFormatted = "AUTHOR_FORMATTED"
        case dateFormatted = "DATE_FORMATTED"
        case warning = "WARNING"
    }

    public let kind: Kind
    public let message: String

    public var description: String { "[\(kind.rawValue)] \(message)" }
}

public struct FixResult {
    public let originalKey: String
    public let fixedEntry: BibEntry
    public let actions: [FixAction]

    public var hasChanges: Bool { !actions.isEmpty }

    public var summary: String {
        if actions.isEmpty {
            return "[\(originalKey)] No changes needed."
        }
        var lines = ["[\(originalKey)] \(actions.count) fix(es) applied:"]
        for a in actions { lines.append("  \(a)") }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Rule Engine

public struct APARuleEngine {

    /// Apply all APA rules to an entry and return the fixed version.
    public static func fix(entry: BibEntry) -> FixResult {
        var actions: [FixAction] = []
        var entryType = entry.entryType.uppercased()
        var fields = entry.fields

        // Phase 1: Resolve entry type aliases
        if let canonical = APADataModel.entryTypeAliases[entryType] {
            actions.append(FixAction(
                kind: .typeChanged,
                message: "@\(entryType) → @\(canonical)"
            ))
            entryType = canonical
        }

        // Phase 2: Suggest entry type upgrades
        if let upgrade = APADataModel.suggestTypeUpgrade(
            currentType: entryType, fields: fields
        ) {
            // For PHDTHESIS/MASTERSTHESIS, also add the type field
            if entry.entryType.uppercased() == "PHDTHESIS" {
                fields["type"] = "phdthesis"
                actions.append(FixAction(
                    kind: .fieldAdded,
                    message: "Added type = {phdthesis}"
                ))
            } else if entry.entryType.uppercased() == "MASTERSTHESIS" {
                fields["type"] = "mathesis"
                actions.append(FixAction(
                    kind: .fieldAdded,
                    message: "Added type = {mathesis}"
                ))
            }
            actions.append(FixAction(
                kind: .typeChanged,
                message: "@\(entryType) → @\(upgrade.newType): \(upgrade.reason)"
            ))
            entryType = upgrade.newType
        }

        // Phase 3: Normalize field names
        fields = normalizeFieldNames(fields, actions: &actions)

        // Phase 4: Fix HOWPUBLISHED containing URL
        if let howpub = caseInsensitiveGet(fields, "HOWPUBLISHED") {
            if howpub.contains("http") || howpub.contains("www.") {
                let url = howpub
                    .replacingOccurrences(of: "\\url{", with: "")
                    .replacingOccurrences(of: "}", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if caseInsensitiveGet(fields, "URL") == nil {
                    fields["URL"] = url
                    actions.append(FixAction(
                        kind: .fieldRenamed,
                        message: "HOWPUBLISHED URL → URL field"
                    ))
                }
                fields = caseInsensitiveRemove(fields, "HOWPUBLISHED")
                actions.append(FixAction(
                    kind: .fieldRemoved,
                    message: "Removed HOWPUBLISHED (migrated to URL)"
                ))
            }
        }

        // Phase 5: Format authors
        fields = formatAuthors(fields, actions: &actions)

        // Phase 6: Format dates
        fields = formatDates(fields, actions: &actions)

        // Phase 7: Check for missing required fields
        if let required = APADataModel.requiredFields[entryType] {
            for field in required {
                if caseInsensitiveGet(fields, field) == nil {
                    actions.append(FixAction(
                        kind: .warning,
                        message: "Missing required field: \(field)"
                    ))
                }
            }
        }

        // Phase 8: Check for missing recommended fields (context-aware for PRESENTATION)
        let recommended: [String]
        if entryType == "PRESENTATION" {
            let hasMainTitle = caseInsensitiveGet(fields, "MAINTITLE") != nil
            recommended = APADataModel.presentationRecommendedFields(
                hasMainTitle: hasMainTitle
            )
        } else {
            recommended = APADataModel.recommendedFields[entryType] ?? []
        }
        for field in recommended {
            if caseInsensitiveGet(fields, field) == nil {
                actions.append(FixAction(
                    kind: .warning,
                    message: "Consider adding recommended field: \(field)"
                ))
            }
        }

        let fixedEntry = BibEntry(
            entryType: entryType,
            key: entry.key,
            fields: fields,
            rawText: "",
            lineNumber: entry.lineNumber
        )

        return FixResult(
            originalKey: entry.key,
            fixedEntry: fixedEntry,
            actions: actions
        )
    }

    /// Fix all entries in a BibFile, return combined results.
    public static func fixAll(_ bibFile: BibFile) -> [FixResult] {
        bibFile.entries.map { fix(entry: $0) }
    }

    // MARK: - Field Name Normalization

    private static func normalizeFieldNames(
        _ fields: OrderedDict,
        actions: inout [FixAction]
    ) -> OrderedDict {
        var result = OrderedDict()

        for pair in fields.pairs {
            let upper = pair.key.uppercased()

            if let canonical = APADataModel.fieldAliases[upper] {
                // Check if the canonical field already exists
                if caseInsensitiveGet(result, canonical) == nil {
                    result[canonical] = pair.value
                    actions.append(FixAction(
                        kind: .fieldRenamed,
                        message: "\(pair.key) → \(canonical)"
                    ))
                }
                // Drop the alias (don't add duplicate)
            } else {
                // Normalize field name to UPPERCASE (biblatex-apa convention)
                let normalized = pair.key.uppercased()
                if normalized != pair.key {
                    actions.append(FixAction(
                        kind: .fieldRenamed,
                        message: "\(pair.key) → \(normalized)"
                    ))
                }
                result[normalized] = pair.value
            }
        }

        return result
    }

    // MARK: - Author Formatting

    private static func formatAuthors(
        _ fields: OrderedDict,
        actions: inout [FixAction]
    ) -> OrderedDict {
        var result = fields

        guard let authorKey = fields.keys.first(where: {
            $0.uppercased() == "AUTHOR"
        }) else { return result }

        guard let authors = fields[authorKey] else { return result }

        // Fix semicolon separators → "and"
        if authors.contains(";") {
            let fixed = authors
                .components(separatedBy: ";")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .joined(separator: " and ")
            result[authorKey] = fixed
            actions.append(FixAction(
                kind: .authorFormatted,
                message: "Replaced ';' with 'and' in author list"
            ))
        }

        // Fix "&" separators → "and" (common in copy-paste)
        if let current = result[authorKey], current.contains(" & ") {
            let fixed = current.replacingOccurrences(of: " & ", with: " and ")
            result[authorKey] = fixed
            actions.append(FixAction(
                kind: .authorFormatted,
                message: "Replaced '&' with 'and' in author list"
            ))
        }

        // Check each author for "First Last" → "Last, First" format
        if let current = result[authorKey] {
            let authorList = current.components(separatedBy: " and ")
            var anyFixed = false
            let fixedList = authorList.map { author -> String in
                let trimmed = author.trimmingCharacters(in: .whitespaces)

                // Skip if already in "Last, First" format
                if trimmed.contains(",") { return trimmed }

                // Skip corporate authors (wrapped in {})
                if trimmed.hasPrefix("{") { return trimmed }

                // Skip single-word names (e.g., "Plato")
                let parts = trimmed.components(separatedBy: " ")
                    .filter { !$0.isEmpty }
                if parts.count < 2 { return trimmed }

                // Convert "First M. Last" → "Last, F. M."
                let lastName = parts.last!
                let firstNames = parts.dropLast()
                let initials = firstNames.map { name -> String in
                    // If already an initial (e.g., "J."), keep it
                    if name.count <= 3 && name.hasSuffix(".") { return name }
                    // Otherwise, take first character + "."
                    return String(name.prefix(1)) + "."
                }
                anyFixed = true
                return "\(lastName), \(initials.joined(separator: " "))"
            }

            if anyFixed {
                result[authorKey] = fixedList.joined(separator: " and ")
                actions.append(FixAction(
                    kind: .authorFormatted,
                    message: "Converted author names to 'Last, F. M.' format"
                ))
            }
        }

        return result
    }

    // MARK: - Date Formatting

    private static func formatDates(
        _ fields: OrderedDict,
        actions: inout [FixAction]
    ) -> OrderedDict {
        var result = fields

        // Handle YEAR field → DATE
        // (Already handled by field alias normalization, but double-check)

        // Check DATE format
        if let dateKey = fields.keys.first(where: { $0.uppercased() == "DATE" }),
           let dateVal = fields[dateKey] {
            let fixed = normalizeDate(dateVal)
            if fixed != dateVal {
                result[dateKey] = fixed
                actions.append(FixAction(
                    kind: .dateFormatted,
                    message: "Date normalized: \(dateVal) → \(fixed)"
                ))
            }
        }

        // Handle "in press" → PUBSTATE
        if let dateKey = fields.keys.first(where: { $0.uppercased() == "DATE" }),
           let dateVal = fields[dateKey] {
            let lower = dateVal.lowercased().trimmingCharacters(in: .whitespaces)
            if lower == "in press" || lower == "inpress" || lower == "in-press"
                || lower == "forthcoming" {
                result[dateKey] = nil  // remove DATE
                result["PUBSTATE"] = "inpress"
                actions.append(FixAction(
                    kind: .dateFormatted,
                    message: "Moved 'in press' to PUBSTATE = {inpress}"
                ))
            }
        }

        return result
    }

    /// Attempt to normalize a date string to biblatex format.
    private static func normalizeDate(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)

        // Already valid ISO format
        if isValidBiblatexDate(trimmed) { return trimmed }

        // Try: "March 2020" → "2020-03"
        let monthNames: [String: String] = [
            "january": "01", "february": "02", "march": "03",
            "april": "04", "may": "05", "june": "06",
            "july": "07", "august": "08", "september": "09",
            "october": "10", "november": "11", "december": "12",
            "jan": "01", "feb": "02", "mar": "03", "apr": "04",
            "jun": "06", "jul": "07", "aug": "08", "sep": "09",
            "oct": "10", "nov": "11", "dec": "12"
        ]

        let lower = trimmed.lowercased()

        // "Month Year" pattern
        for (month, num) in monthNames {
            if lower.hasPrefix(month) {
                let rest = lower.dropFirst(month.count)
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: ","))
                    .trimmingCharacters(in: .whitespaces)
                if let _ = Int(rest), rest.count == 4 {
                    return "\(rest)-\(num)"
                }
            }
        }

        // "Year Month" pattern (e.g., "2020 March")
        let parts = trimmed.components(separatedBy: " ").filter { !$0.isEmpty }
        if parts.count == 2, let _ = Int(parts[0]), parts[0].count == 4 {
            let monthLower = parts[1].lowercased()
                .trimmingCharacters(in: CharacterSet(charactersIn: ","))
            if let num = monthNames[monthLower] {
                return "\(parts[0])-\(num)"
            }
        }

        // Season patterns
        let seasons: [String: String] = [
            "spring": "21", "summer": "22",
            "fall": "23", "autumn": "23", "winter": "24"
        ]
        for (season, code) in seasons {
            if lower.contains(season) {
                // Extract the year
                let digits = trimmed.filter { $0.isNumber }
                if digits.count == 4 {
                    return "\(digits)-\(code)"
                }
            }
        }

        // Can't normalize, return as-is
        return trimmed
    }

    private static func isValidBiblatexDate(_ s: String) -> Bool {
        APADataModel.datePatterns.contains { p in
            s.range(of: p.pattern, options: .regularExpression) != nil
        }
    }

    // MARK: - Case-insensitive Field Helpers

    private static func caseInsensitiveGet(
        _ fields: OrderedDict, _ name: String
    ) -> String? {
        let lower = name.lowercased()
        if let key = fields.keys.first(where: { $0.lowercased() == lower }) {
            return fields[key]
        }
        return nil
    }

    private static func caseInsensitiveRemove(
        _ fields: OrderedDict, _ name: String
    ) -> OrderedDict {
        var result = fields
        let lower = name.lowercased()
        if let key = fields.keys.first(where: { $0.lowercased() == lower }) {
            result[key] = nil
        }
        return result
    }
}

// MARK: - Plain Text Citation Parser

public struct APACitationParser {

    /// Attempt to parse a plain-text APA reference into a BibEntry.
    /// Handles common patterns like:
    ///   "Author, A. A., & Author, B. B. (2020). Title. Journal, 1(2), 3–4. https://doi.org/..."
    public static func parse(_ text: String, suggestedKey: String? = nil) -> BibEntry? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var fields = OrderedDict()

        // Extract year from parentheses: (2020) or (2020, March) or (n.d.)
        let yearPattern = #"\((\d{4}[a-z]?(?:,\s*\w+(?:\s+\d{1,2})?)?|n\.d\.)\)"#
        var dateStr = ""
        var authorPart = ""
        var afterDate = ""

        if let yearMatch = trimmed.range(of: yearPattern, options: .regularExpression) {
            let yearFull = String(trimmed[yearMatch])
            dateStr = String(yearFull.dropFirst().dropLast()) // remove parens
            authorPart = String(trimmed[trimmed.startIndex..<yearMatch.lowerBound])
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "."))
                .trimmingCharacters(in: .whitespaces)
            afterDate = String(trimmed[yearMatch.upperBound...])
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "."))
                .trimmingCharacters(in: .whitespaces)
        }

        // Parse authors
        if !authorPart.isEmpty {
            // Replace ", &" or " &" with " and " for biblatex
            var authors = authorPart
                .replacingOccurrences(of: ", & ", with: " and ")
                .replacingOccurrences(of: " & ", with: " and ")
                .replacingOccurrences(of: ", and ", with: " and ")
            // Remove trailing period
            if authors.hasSuffix(".") {
                authors = String(authors.dropLast())
            }
            fields["AUTHOR"] = authors
        }

        // Parse date
        if dateStr == "n.d." {
            // No date
        } else if !dateStr.isEmpty {
            // Handle "2020, March 15" → "2020-03-15"
            fields["DATE"] = APARuleEngine.fix(entry: BibEntry(
                entryType: "MISC", key: "", fields: {
                    var f = OrderedDict(); f["DATE"] = dateStr; return f
                }(), rawText: "", lineNumber: 0
            )).fixedEntry.fields["DATE"] ?? dateStr
        }

        // Try to split afterDate into title + source
        // Pattern: Title in italics ends at first period. Source follows.
        if !afterDate.isEmpty {
            // Simple heuristic: first sentence = title, rest = source info
            let sentences = splitAtFirstSentence(afterDate)
            fields["TITLE"] = sentences.first

            if let rest = sentences.second {
                // Look for DOI
                let doiPattern = #"https?://doi\.org/[^\s]+"#
                if let doiMatch = rest.range(of: doiPattern, options: .regularExpression) {
                    fields["DOI"] = String(rest[doiMatch])
                }

                // Look for URL (non-DOI)
                if fields["DOI"] == nil {
                    let urlPattern = #"https?://[^\s]+"#
                    if let urlMatch = rest.range(of: urlPattern, options: .regularExpression) {
                        fields["URL"] = String(rest[urlMatch])
                    }
                }

                // Try to extract journal/volume/pages
                // Pattern: "Journal Name, 12(3), 45–67"
                let jvpPattern = #"^(.+?),\s*(\d+)\((\d+)\),\s*(\d+[–-]\d+)"#
                let cleanRest = rest
                    .replacingOccurrences(of: fields["DOI"] ?? "§§§", with: "")
                    .replacingOccurrences(of: fields["URL"] ?? "§§§", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "."))

                if let jvpMatch = cleanRest.range(of: jvpPattern,
                                                   options: .regularExpression) {
                    let matched = String(cleanRest[jvpMatch])
                    let captures = extractJVP(matched)
                    if let j = captures.journal { fields["JOURNALTITLE"] = j }
                    if let v = captures.volume { fields["VOLUME"] = v }
                    if let n = captures.number { fields["NUMBER"] = n }
                    if let p = captures.pages {
                        fields["PAGES"] = p.replacingOccurrences(of: "–", with: "--")
                    }
                }
            }
        }

        // Determine entry type
        let entryType: String
        if fields["JOURNALTITLE"] != nil {
            entryType = "ARTICLE"
        } else if fields["URL"] != nil && fields["DOI"] == nil {
            entryType = "ONLINE"
        } else {
            entryType = "MISC"
        }

        // Generate key
        let key = suggestedKey ?? generateKey(fields: fields)

        return BibEntry(
            entryType: entryType,
            key: key,
            fields: fields,
            rawText: "",
            lineNumber: 0
        )
    }

    // MARK: - Helpers

    private static func splitAtFirstSentence(
        _ text: String
    ) -> (first: String?, second: String?) {
        // Find the first ". " that's not part of an initial (e.g., "A. B.")
        let chars = Array(text)
        var i = 0
        while i < chars.count - 1 {
            if chars[i] == "." && i + 1 < chars.count && chars[i + 1] == " " {
                // Check if this is an initial (single letter before the period)
                if i > 0 && chars[i - 1].isLetter && (i < 2 || !chars[i - 2].isLetter) {
                    i += 1
                    continue
                }
                let first = String(chars[0...i])
                    .trimmingCharacters(in: .whitespaces)
                let second = String(chars[(i + 1)...])
                    .trimmingCharacters(in: .whitespaces)
                return (first, second.isEmpty ? nil : second)
            }
            i += 1
        }
        return (text, nil)
    }

    private static func extractJVP(
        _ text: String
    ) -> (journal: String?, volume: String?, number: String?, pages: String?) {
        let pattern = #"^(.+?),\s*(\d+)\((\d+)\),\s*(\d+[–-]\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: text,
                range: NSRange(text.startIndex..., in: text)
              ) else { return (nil, nil, nil, nil) }

        func group(_ n: Int) -> String? {
            let r = match.range(at: n)
            guard r.location != NSNotFound,
                  let range = Range(r, in: text) else { return nil }
            return String(text[range]).trimmingCharacters(in: .whitespaces)
        }

        return (group(1), group(2), group(3), group(4))
    }

    private static func generateKey(fields: OrderedDict) -> String {
        let author = (fields["AUTHOR"] ?? "unknown")
            .components(separatedBy: " and ").first?
            .components(separatedBy: ",").first?
            .trimmingCharacters(in: .whitespaces)
            .lowercased() ?? "unknown"
        let year = fields["DATE"]?
            .prefix(4) ?? "nd"
        let titleWord = (fields["TITLE"] ?? "")
            .components(separatedBy: " ")
            .first(where: { $0.count > 3 })?
            .lowercased()
            .filter { $0.isLetter } ?? "untitled"
        return "\(author)_\(titleWord)_\(year)"
    }
}
