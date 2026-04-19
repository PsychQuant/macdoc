// BibToAPAFormatter.swift — Backward-compatible facade
// Delegates to APAStyler + MarkdownRenderer pipeline.

import BibAPA
import BiblatexAPA

public struct BibToAPAFormatter {

    private static let renderer = MarkdownRenderer()

    /// Format a single BibEntry as an APA 7 reference list entry.
    /// Returns plain text with markdown-style italics (*...*).
    public static func formatReference(_ entry: BibEntry) -> String {
        let reference = APAStyler.style(entry)
        return renderer.render(reference)
    }

    /// Format a single BibEntry as an in-text citation: (Author, Year)
    public static func formatCitation(_ entry: BibEntry) -> String {
        APAStyler.formatCitation(entry)
    }

    /// Format a single BibEntry as a narrative citation: Author (Year)
    public static func formatNarrativeCitation(_ entry: BibEntry) -> String {
        APAStyler.formatNarrativeCitation(entry)
    }

    /// Format multiple BibEntries as a reference list (sorted alphabetically).
    public static func formatReferenceList(_ entries: [BibEntry]) -> String {
        let formatted = entries.map { (entry: $0, ref: formatReference($0)) }
        let sorted = formatted.sorted { $0.ref.lowercased() < $1.ref.lowercased() }
        return sorted.map(\.ref).joined(separator: "\n\n")
    }

    // MARK: - Re-exported helpers for test compatibility

    public static func parseSingleAuthor(_ raw: String) -> BibAPA.AuthorName {
        BibAPA.parseSingleAuthor(raw)
    }

    public static func formatInitials(_ firstName: String) -> String {
        BibAPA.formatInitials(firstName)
    }

    public static func formatAuthors(_ entry: BibEntry) -> String {
        BibAPA.formatAuthorsString(entry)
    }

    public static func formatCitationAuthors(_ entry: BibEntry) -> String {
        BibAPA.formatCitationAuthors(entry)
    }

    public static func formatDate(_ entry: BibEntry) -> String {
        BibAPA.formatDate(entry)
    }

    public static func formatEventDate(_ eventDate: String) -> String {
        BibAPA.formatEventDate(eventDate)
    }

    public static func toSentenceCase(_ title: String) -> String {
        BibAPA.toSentenceCase(title)
    }

    public static func normalizePages(_ pages: String) -> String {
        BibAPA.normalizePages(pages)
    }

    public static func stripBraces(_ text: String) -> String {
        BibAPA.stripBraces(text)
    }
}
