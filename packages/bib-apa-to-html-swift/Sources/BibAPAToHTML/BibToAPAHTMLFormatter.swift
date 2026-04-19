// BibToAPAHTMLFormatter.swift — Convenience API for .bib → APA HTML

import BibAPA
import BiblatexAPA

public struct BibToAPAHTMLFormatter {

    private static let renderer = HTMLRenderer()

    // MARK: - Reference List (full entries)

    /// Format a single BibEntry as an APA 7 reference in HTML (inner content only, no wrapper).
    public static func formatReference(_ entry: BibEntry) -> String {
        let reference = APAStyler.style(entry)
        return renderer.render(reference)
    }

    /// Format multiple BibEntries as an HTML reference list (sorted alphabetically).
    /// Each entry wrapped in `<p class="apa-reference" id="ref-{key}">` for anchor linking.
    public static func formatReferenceList(_ entries: [BibEntry]) -> String {
        let formatted = entries.map { (entry: $0, ref: formatReference($0)) }
        let sorted = formatted.sorted { $0.ref.lowercased() < $1.ref.lowercased() }
        return sorted
            .map { "<p class=\"apa-reference\" id=\"ref-\(escapeAttr($0.entry.key))\">\($0.ref)</p>" }
            .joined(separator: "\n")
    }

    /// Format as a complete HTML fragment with CSS and wrapping div.
    /// - Parameter css: CSS to include. Defaults to `APACSS.web`.
    public static func formatReferenceListWithCSS(
        _ entries: [BibEntry],
        css: String = APACSS.web
    ) -> String {
        let style = APACSS.styleTag(css)
        let list = formatReferenceList(entries)
        return "\(style)\n<div class=\"apa-reference-list\">\n\(list)\n</div>"
    }

    // MARK: - In-Text Citations

    /// Parenthetical citation with anchor link: `<a href="#ref-key">(Author, Year)</a>`
    public static func formatInTextCitation(_ entry: BibEntry) -> String {
        let text = APAStyler.formatCitation(entry)
        return "<a href=\"#ref-\(escapeAttr(entry.key))\">\(escapeHTML(text))</a>"
    }

    /// Narrative citation with anchor link: `<a href="#ref-key">Author (Year)</a>`
    public static func formatNarrativeInTextCitation(_ entry: BibEntry) -> String {
        let text = APAStyler.formatNarrativeCitation(entry)
        return "<a href=\"#ref-\(escapeAttr(entry.key))\">\(escapeHTML(text))</a>"
    }

    // MARK: - Helpers

    private static func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func escapeAttr(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
