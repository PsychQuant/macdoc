// APAStyler.swift — BibEntry → APAReference semantic model
// Applies APA 7 rules to produce format-agnostic reference data.

import Foundation
import BiblatexAPA

public struct APAStyler {

    // MARK: - Public API

    /// Convert a BibEntry into a format-agnostic APAReference.
    public static func style(_ entry: BibEntry) -> APAReference {
        switch entry.normalizedType {
        case "ARTICLE":
            return .article(styleArticle(entry))
        case "BOOK", "COLLECTION", "PROCEEDINGS", "REFERENCE":
            return .book(styleBook(entry))
        case "INBOOK", "INCOLLECTION", "INPROCEEDINGS":
            return .chapter(styleChapter(entry))
        case "THESIS", "PHDTHESIS", "MASTERSTHESIS":
            return .thesis(styleThesis(entry))
        case "REPORT":
            return .report(styleReport(entry))
        case "PRESENTATION":
            return .presentation(stylePresentation(entry))
        case "ONLINE", "MISC":
            return .online(styleOnline(entry))
        default:
            return .online(styleOnline(entry))
        }
    }

    /// Format a single BibEntry as an in-text citation: (Author, Year)
    public static func formatCitation(_ entry: BibEntry) -> String {
        let authors = formatCitationAuthors(entry)
        let year = extractYear(entry)
        return "(\(authors), \(year))"
    }

    /// Format a single BibEntry as a narrative citation: Author (Year)
    public static func formatNarrativeCitation(_ entry: BibEntry) -> String {
        let authors = formatCitationAuthors(entry)
        let year = extractYear(entry)
        return "\(authors) (\(year))"
    }

    // MARK: - Per-Type Styling

    private static func styleArticle(_ entry: BibEntry) -> APAArticleRef {
        let title = buildTitle(entry)
        let journal = field(entry, "JOURNALTITLE").map(stripBraces) ?? ""

        return APAArticleRef(
            authors: formatAuthorsString(entry),
            date: formatDate(entry),
            title: title,
            journal: journal,
            volume: field(entry, "VOLUME"),
            issue: field(entry, "NUMBER"),
            pages: field(entry, "PAGES").map(normalizePages),
            doi: normalizeDOI(entry),
            url: doi(entry) == nil ? field(entry, "URL").map(stripBraces) : nil
        )
    }

    private static func styleBook(_ entry: BibEntry) -> APABookRef {
        let title = buildTitleWithSubtitle(entry)

        return APABookRef(
            authors: formatAuthorsString(entry),
            date: formatDate(entry),
            title: title,
            edition: formatEdition(field(entry, "EDITION")),
            volume: field(entry, "VOLUME"),
            publisher: field(entry, "PUBLISHER").map(stripBraces),
            doi: normalizeDOI(entry),
            url: doi(entry) == nil ? field(entry, "URL").map(stripBraces) : nil
        )
    }

    private static func styleChapter(_ entry: BibEntry) -> APAChapterRef {
        let chapterTitle = toSentenceCase(stripBraces(entry.title ?? ""))
        let bookTitle = toSentenceCase(stripBraces(field(entry, "BOOKTITLE") ?? ""))
        let editorStr = buildEditorString(entry)
        let pages = field(entry, "PAGES").map { "pp. \(normalizePages($0))" }

        return APAChapterRef(
            authors: formatAuthorsString(entry),
            date: formatDate(entry),
            chapterTitle: chapterTitle,
            editors: editorStr,
            bookTitle: bookTitle,
            edition: formatEdition(field(entry, "EDITION")),
            volume: field(entry, "VOLUME").map { "Vol. \($0)" },
            pages: pages,
            publisher: field(entry, "PUBLISHER").map(stripBraces),
            doi: normalizeDOI(entry),
            url: doi(entry) == nil ? field(entry, "URL").map(stripBraces) : nil
        )
    }

    private static func styleThesis(_ entry: BibEntry) -> APAThesisRef {
        let thesisType: String
        if let addon = field(entry, "TITLEADDON"), !addon.isEmpty {
            thesisType = stripBraces(addon)
        } else if entry.normalizedType == "MASTERSTHESIS" {
            thesisType = "Master's thesis"
        } else if let bibType = field(entry, "TYPE")?.lowercased(), bibType.contains("mathesis") {
            thesisType = "Master's thesis"
        } else {
            thesisType = "Doctoral dissertation"
        }

        let institution = (field(entry, "INSTITUTION") ?? field(entry, "SCHOOL")).map(stripBraces)

        return APAThesisRef(
            authors: formatAuthorsString(entry),
            date: formatDate(entry),
            title: toSentenceCase(stripBraces(entry.title ?? "")),
            thesisType: thesisType,
            institution: institution,
            doi: normalizeDOI(entry),
            url: doi(entry) == nil ? field(entry, "URL").map(stripBraces) : nil
        )
    }

    private static func styleReport(_ entry: BibEntry) -> APAReportRef {
        let titleAddon = field(entry, "TITLEADDON").map(stripBraces)
        let number: String?
        if let num = field(entry, "NUMBER"), !num.isEmpty {
            let typeLabel = field(entry, "TYPE") ?? ""
            if !typeLabel.isEmpty {
                number = "\(stripBraces(typeLabel)) \(num)"
            } else {
                number = "No. \(num)"
            }
        } else {
            number = nil
        }

        return APAReportRef(
            authors: formatAuthorsString(entry),
            date: formatDate(entry),
            title: toSentenceCase(stripBraces(entry.title ?? "")),
            titleAddon: titleAddon,
            number: number,
            institution: field(entry, "INSTITUTION").map(stripBraces),
            doi: normalizeDOI(entry),
            url: doi(entry) == nil ? field(entry, "URL").map(stripBraces) : nil
        )
    }

    private static func stylePresentation(_ entry: BibEntry) -> APAPresentationRef {
        let presentationType: String
        if let addon = field(entry, "TITLEADDON"), !addon.isEmpty {
            presentationType = stripBraces(addon)
        } else {
            presentationType = "Conference presentation"
        }

        return APAPresentationRef(
            authors: formatAuthorsString(entry),
            date: formatDate(entry),
            title: toSentenceCase(stripBraces(entry.title ?? "")),
            presentationType: presentationType,
            conference: field(entry, "EVENTTITLE").map(stripBraces),
            venue: field(entry, "VENUE").map(stripBraces),
            doi: normalizeDOI(entry),
            url: doi(entry) == nil ? field(entry, "URL").map(stripBraces) : nil
        )
    }

    private static func styleOnline(_ entry: BibEntry) -> APAOnlineRef {
        return APAOnlineRef(
            authors: formatAuthorsString(entry),
            date: formatDate(entry),
            title: toSentenceCase(stripBraces(entry.title ?? "")),
            publisher: field(entry, "PUBLISHER").map(stripBraces),
            doi: normalizeDOI(entry),
            url: doi(entry) == nil ? field(entry, "URL").map(stripBraces) : nil
        )
    }

    // MARK: - Helpers

    private static func doi(_ entry: BibEntry) -> String? {
        entry.doi.flatMap { $0.isEmpty ? nil : $0 }
    }

    private static func normalizeDOI(_ entry: BibEntry) -> String? {
        guard let raw = entry.doi, !raw.isEmpty else { return nil }
        let clean = stripBraces(raw)
        return clean.hasPrefix("http") ? clean : "https://doi.org/\(clean)"
    }

    private static func buildTitle(_ entry: BibEntry) -> String {
        let cleanTitle = stripBraces(entry.title ?? "")
        var full = toSentenceCase(cleanTitle)
        if let sub = field(entry, "SUBTITLE"), !sub.isEmpty {
            full += ": \(capitalizeFirst(toSentenceCase(stripBraces(sub)).lowercased()))"
        }
        return full
    }

    private static func buildTitleWithSubtitle(_ entry: BibEntry) -> String {
        buildTitle(entry)
    }

    private static func buildEditorString(_ entry: BibEntry) -> String? {
        guard let edRaw = field(entry, "EDITOR"), !edRaw.isEmpty else { return nil }
        let editors = edRaw.components(separatedBy: " and ")
            .map { parseSingleAuthor($0.trimmingCharacters(in: .whitespaces)) }
        let edNames = editors.map(formatSingleAuthorForIn).joined(separator: ", ")
        let edLabel = editors.count == 1 ? "Ed." : "Eds."
        return "\(edNames) (\(edLabel))"
    }
}
