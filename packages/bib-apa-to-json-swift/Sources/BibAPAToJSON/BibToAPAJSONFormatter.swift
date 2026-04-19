// BibToAPAJSONFormatter.swift — .bib → APA 7 JSON with pre-rendered HTML

import Foundation
import BibAPAToHTML
import BibAPA
import BiblatexAPA

/// A single reference entry with pre-rendered HTML and in-text citations.
public struct APAJSONEntry: Codable, Sendable {
    public let key: String
    public let type: String
    public let year: String
    public let rendered: String
    public let citation: String
    public let narrativeCitation: String

    public init(key: String, type: String, year: String,
                rendered: String, citation: String, narrativeCitation: String) {
        self.key = key
        self.type = type
        self.year = year
        self.rendered = rendered
        self.citation = citation
        self.narrativeCitation = narrativeCitation
    }
}

public struct BibToAPAJSONFormatter {

    /// Convert a single BibEntry to an APAJSONEntry.
    public static func formatEntry(_ entry: BibEntry) -> APAJSONEntry {
        let html = BibToAPAHTMLFormatter.formatReference(entry)
        let citation = BibToAPAHTMLFormatter.formatInTextCitation(entry)
        let narrative = BibToAPAHTMLFormatter.formatNarrativeInTextCitation(entry)
        let year = entry.date ?? "n.d."

        return APAJSONEntry(
            key: entry.key,
            type: entry.normalizedType,
            year: extractYear(year),
            rendered: html,
            citation: citation,
            narrativeCitation: narrative
        )
    }

    /// Convert multiple BibEntries to an array of APAJSONEntry, sorted alphabetically.
    public static func formatEntries(_ entries: [BibEntry]) -> [APAJSONEntry] {
        entries
            .map { formatEntry($0) }
            .sorted { $0.rendered.lowercased() < $1.rendered.lowercased() }
    }

    /// Convert multiple BibEntries to a JSON string.
    public static func formatJSON(_ entries: [BibEntry], prettyPrint: Bool = true) throws -> String {
        let jsonEntries = formatEntries(entries)
        let encoder = JSONEncoder()
        encoder.outputFormatting = prettyPrint ? [.prettyPrinted, .sortedKeys] : .sortedKeys
        let data = try encoder.encode(jsonEntries)
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    // MARK: - Helpers

    private static func extractYear(_ date: String) -> String {
        // Extract just the year from dates like "2025", "2025-05-01", etc.
        String(date.prefix(4))
    }
}
