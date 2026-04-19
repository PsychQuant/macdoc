// MarkdownRenderer.swift — APAReference → Markdown string
// Produces output identical to the original BibToAPAFormatter.formatReference()

import BibAPA

public struct MarkdownRenderer: APAReferenceRenderer {
    public typealias Output = String

    public init() {}

    // MARK: - Article

    public func renderArticle(_ ref: APAArticleRef) -> String {
        let body = "\(ref.title)."

        var sourceParts: [String] = []
        if !ref.journal.isEmpty {
            var journalPart = "*\(ref.journal)*"
            if let vol = ref.volume, !vol.isEmpty {
                journalPart += ", *\(vol)*"
                if let issue = ref.issue, !issue.isEmpty {
                    journalPart += "(\(issue))"
                }
            }
            if let pages = ref.pages, !pages.isEmpty {
                journalPart += ", \(pages)"
            }
            journalPart += "."
            sourceParts.append(journalPart)
        }
        appendLink(&sourceParts, doi: ref.doi, url: ref.url)

        return assemble(authors: ref.authors, date: ref.date, body: body, source: sourceParts.joined(separator: " "))
    }

    // MARK: - Book

    public func renderBook(_ ref: APABookRef) -> String {
        var parenthetical: [String] = []
        if let ed = ref.edition { parenthetical.append(ed) }
        if let vol = ref.volume, !vol.isEmpty { parenthetical.append("Vol. \(vol)") }
        let paren = parenthetical.isEmpty ? "" : " (\(parenthetical.joined(separator: ", ")))"
        let body = "*\(ref.title)*\(paren)."

        var sourceParts: [String] = []
        if let pub = ref.publisher, !pub.isEmpty { sourceParts.append("\(pub).") }
        appendLink(&sourceParts, doi: ref.doi, url: ref.url)

        return assemble(authors: ref.authors, date: ref.date, body: body, source: sourceParts.joined(separator: " "))
    }

    // MARK: - Chapter

    public func renderChapter(_ ref: APAChapterRef) -> String {
        let chapterTitle = "\(ref.chapterTitle)."

        var inPart = "In "
        if let editors = ref.editors, !editors.isEmpty {
            inPart += "\(editors), "
        }
        inPart += "*\(ref.bookTitle)*"

        var parenthetical: [String] = []
        if let ed = ref.edition { parenthetical.append(ed) }
        if let vol = ref.volume, !vol.isEmpty { parenthetical.append(vol) }
        if let pages = ref.pages, !pages.isEmpty { parenthetical.append(pages) }
        if !parenthetical.isEmpty {
            inPart += " (\(parenthetical.joined(separator: ", ")))"
        }
        inPart += "."

        let body = "\(chapterTitle) \(inPart)"

        var sourceParts: [String] = []
        if let pub = ref.publisher, !pub.isEmpty { sourceParts.append("\(pub).") }
        appendLink(&sourceParts, doi: ref.doi, url: ref.url)

        return assemble(authors: ref.authors, date: ref.date, body: body, source: sourceParts.joined(separator: " "))
    }

    // MARK: - Thesis

    public func renderThesis(_ ref: APAThesisRef) -> String {
        let body: String
        if let inst = ref.institution, !inst.isEmpty {
            body = "*\(ref.title)* [\(ref.thesisType), \(inst)]."
        } else {
            body = "*\(ref.title)* [\(ref.thesisType)]."
        }

        var sourceParts: [String] = []
        appendLink(&sourceParts, doi: ref.doi, url: ref.url)

        return assemble(authors: ref.authors, date: ref.date, body: body, source: sourceParts.joined(separator: " "))
    }

    // MARK: - Report

    public func renderReport(_ ref: APAReportRef) -> String {
        var titlePart = "*\(ref.title)*"
        var parenthetical: [String] = []
        if let addon = ref.titleAddon, !addon.isEmpty { parenthetical.append(addon) }
        if let num = ref.number, !num.isEmpty { parenthetical.append(num) }
        if !parenthetical.isEmpty {
            titlePart += " (\(parenthetical.joined(separator: " ")))"
        }
        let body = titlePart + "."

        var sourceParts: [String] = []
        if let inst = ref.institution, !inst.isEmpty { sourceParts.append("\(inst).") }
        appendLink(&sourceParts, doi: ref.doi, url: ref.url)

        return assemble(authors: ref.authors, date: ref.date, body: body, source: sourceParts.joined(separator: " "))
    }

    // MARK: - Presentation

    public func renderPresentation(_ ref: APAPresentationRef) -> String {
        let body = "*\(ref.title)* [\(ref.presentationType)]."

        var sourceParts: [String] = []
        if let conf = ref.conference, !conf.isEmpty {
            var confPart = conf
            if let venue = ref.venue, !venue.isEmpty {
                confPart += ", \(venue)"
            }
            confPart += "."
            sourceParts.append(confPart)
        }
        appendLink(&sourceParts, doi: ref.doi, url: ref.url)

        return assemble(authors: ref.authors, date: ref.date, body: body, source: sourceParts.joined(separator: " "))
    }

    // MARK: - Online

    public func renderOnline(_ ref: APAOnlineRef) -> String {
        let body = "*\(ref.title)*."

        var sourceParts: [String] = []
        if let pub = ref.publisher, !pub.isEmpty { sourceParts.append("\(pub).") }
        appendLink(&sourceParts, doi: ref.doi, url: ref.url)

        return assemble(authors: ref.authors, date: ref.date, body: body, source: sourceParts.joined(separator: " "))
    }

    // MARK: - Assembly

    private func appendLink(_ parts: inout [String], doi: String?, url: String?) {
        if let doi = doi, !doi.isEmpty {
            parts.append(doi)
        } else if let url = url, !url.isEmpty {
            parts.append(url)
        }
    }

    private func assemble(authors: String, date: String, body: String, source: String) -> String {
        var parts: [String] = []
        if !authors.isEmpty { parts.append(authors) }
        parts.append("(\(date)).")
        if !body.isEmpty { parts.append(body) }
        if !source.isEmpty { parts.append(source) }

        var result = parts.joined(separator: " ")
        if !result.hasSuffix(".") && !result.contains("https://") {
            result += "."
        }
        return result
    }
}
