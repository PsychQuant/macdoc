// HTMLRenderer.swift — APAReference → HTML string
// Uses semantic HTML: <em> for italics, <a href> for links.

import BibAPA

public struct HTMLRenderer: APAReferenceRenderer {
    public typealias Output = String

    public init() {}

    // MARK: - Article

    public func renderArticle(_ ref: APAArticleRef) -> String {
        let body = "\(esc(ref.title))."

        var sourceParts: [String] = []
        if !ref.journal.isEmpty {
            var journalPart = "<em>\(esc(ref.journal))</em>"
            if let vol = ref.volume, !vol.isEmpty {
                journalPart += ", <em>\(esc(vol))</em>"
                if let issue = ref.issue, !issue.isEmpty {
                    journalPart += "(\(esc(issue)))"
                }
            }
            if let pages = ref.pages, !pages.isEmpty {
                journalPart += ", \(esc(pages))"
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
        if let ed = ref.edition { parenthetical.append(esc(ed)) }
        if let vol = ref.volume, !vol.isEmpty { parenthetical.append("Vol. \(esc(vol))") }
        let paren = parenthetical.isEmpty ? "" : " (\(parenthetical.joined(separator: ", ")))"
        let body = "<em>\(esc(ref.title))</em>\(paren)."

        var sourceParts: [String] = []
        if let pub = ref.publisher, !pub.isEmpty { sourceParts.append("\(esc(pub)).") }
        appendLink(&sourceParts, doi: ref.doi, url: ref.url)

        return assemble(authors: ref.authors, date: ref.date, body: body, source: sourceParts.joined(separator: " "))
    }

    // MARK: - Chapter

    public func renderChapter(_ ref: APAChapterRef) -> String {
        let chapterTitle = "\(esc(ref.chapterTitle))."

        var inPart = "In "
        if let editors = ref.editors, !editors.isEmpty {
            inPart += "\(esc(editors)), "
        }
        inPart += "<em>\(esc(ref.bookTitle))</em>"

        var parenthetical: [String] = []
        if let ed = ref.edition { parenthetical.append(esc(ed)) }
        if let vol = ref.volume, !vol.isEmpty { parenthetical.append(esc(vol)) }
        if let pages = ref.pages, !pages.isEmpty { parenthetical.append(esc(pages)) }
        if !parenthetical.isEmpty {
            inPart += " (\(parenthetical.joined(separator: ", ")))"
        }
        inPart += "."

        let body = "\(chapterTitle) \(inPart)"

        var sourceParts: [String] = []
        if let pub = ref.publisher, !pub.isEmpty { sourceParts.append("\(esc(pub)).") }
        appendLink(&sourceParts, doi: ref.doi, url: ref.url)

        return assemble(authors: ref.authors, date: ref.date, body: body, source: sourceParts.joined(separator: " "))
    }

    // MARK: - Thesis

    public func renderThesis(_ ref: APAThesisRef) -> String {
        let body: String
        if let inst = ref.institution, !inst.isEmpty {
            body = "<em>\(esc(ref.title))</em> [\(esc(ref.thesisType)), \(esc(inst))]."
        } else {
            body = "<em>\(esc(ref.title))</em> [\(esc(ref.thesisType))]."
        }

        var sourceParts: [String] = []
        appendLink(&sourceParts, doi: ref.doi, url: ref.url)

        return assemble(authors: ref.authors, date: ref.date, body: body, source: sourceParts.joined(separator: " "))
    }

    // MARK: - Report

    public func renderReport(_ ref: APAReportRef) -> String {
        var titlePart = "<em>\(esc(ref.title))</em>"
        var parenthetical: [String] = []
        if let addon = ref.titleAddon, !addon.isEmpty { parenthetical.append(esc(addon)) }
        if let num = ref.number, !num.isEmpty { parenthetical.append(esc(num)) }
        if !parenthetical.isEmpty {
            titlePart += " (\(parenthetical.joined(separator: " ")))"
        }
        let body = titlePart + "."

        var sourceParts: [String] = []
        if let inst = ref.institution, !inst.isEmpty { sourceParts.append("\(esc(inst)).") }
        appendLink(&sourceParts, doi: ref.doi, url: ref.url)

        return assemble(authors: ref.authors, date: ref.date, body: body, source: sourceParts.joined(separator: " "))
    }

    // MARK: - Presentation

    public func renderPresentation(_ ref: APAPresentationRef) -> String {
        let body = "<em>\(esc(ref.title))</em> [\(esc(ref.presentationType))]."

        var sourceParts: [String] = []
        if let conf = ref.conference, !conf.isEmpty {
            var confPart = esc(conf)
            if let venue = ref.venue, !venue.isEmpty {
                confPart += ", \(esc(venue))"
            }
            confPart += "."
            sourceParts.append(confPart)
        }
        appendLink(&sourceParts, doi: ref.doi, url: ref.url)

        return assemble(authors: ref.authors, date: ref.date, body: body, source: sourceParts.joined(separator: " "))
    }

    // MARK: - Online

    public func renderOnline(_ ref: APAOnlineRef) -> String {
        let body = "<em>\(esc(ref.title))</em>."

        var sourceParts: [String] = []
        if let pub = ref.publisher, !pub.isEmpty { sourceParts.append("\(esc(pub)).") }
        appendLink(&sourceParts, doi: ref.doi, url: ref.url)

        return assemble(authors: ref.authors, date: ref.date, body: body, source: sourceParts.joined(separator: " "))
    }

    // MARK: - Helpers

    private func esc(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private func appendLink(_ parts: inout [String], doi: String?, url: String?) {
        if let doi = doi, !doi.isEmpty {
            parts.append("<a href=\"\(esc(doi))\">\(esc(doi))</a>")
        } else if let url = url, !url.isEmpty {
            parts.append("<a href=\"\(esc(url))\">\(esc(url))</a>")
        }
    }

    private func assemble(authors: String, date: String, body: String, source: String) -> String {
        var parts: [String] = []
        if !authors.isEmpty { parts.append(esc(authors)) }
        parts.append("(\(esc(date))).")
        if !body.isEmpty { parts.append(body) }
        if !source.isEmpty { parts.append(source) }

        var result = parts.joined(separator: " ")
        if !result.hasSuffix(".") && !result.contains("</a>") {
            result += "."
        }
        return result
    }
}
