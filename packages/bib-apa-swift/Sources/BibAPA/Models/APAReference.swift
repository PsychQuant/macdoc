// APAReference.swift — Format-agnostic APA 7 reference semantic model
// Each case carries all the data needed to render a reference list entry.

/// A fully resolved APA 7 reference, ready for rendering.
public enum APAReference: Equatable, Sendable {
    case article(APAArticleRef)
    case book(APABookRef)
    case chapter(APAChapterRef)
    case thesis(APAThesisRef)
    case report(APAReportRef)
    case presentation(APAPresentationRef)
    case online(APAOnlineRef)
}

// MARK: - Ref Structs

public struct APAArticleRef: Equatable, Sendable {
    public let authors: String        // "Cheng, C., Yang, H.-H., & Hsu, Y.-F."
    public let date: String           // "2025"
    public let title: String          // sentence case, no formatting
    public let journal: String        // preserved case (renderer italicizes)
    public let volume: String?
    public let issue: String?
    public let pages: String?         // en-dash normalized
    public let doi: String?           // full URL
    public let url: String?

    public init(authors: String, date: String, title: String, journal: String,
                volume: String? = nil, issue: String? = nil, pages: String? = nil,
                doi: String? = nil, url: String? = nil) {
        self.authors = authors; self.date = date; self.title = title
        self.journal = journal; self.volume = volume; self.issue = issue
        self.pages = pages; self.doi = doi; self.url = url
    }
}

public struct APABookRef: Equatable, Sendable {
    public let authors: String
    public let date: String
    public let title: String          // sentence case (renderer italicizes)
    public let edition: String?       // "2nd ed."
    public let volume: String?
    public let publisher: String?
    public let doi: String?
    public let url: String?

    public init(authors: String, date: String, title: String,
                edition: String? = nil, volume: String? = nil, publisher: String? = nil,
                doi: String? = nil, url: String? = nil) {
        self.authors = authors; self.date = date; self.title = title
        self.edition = edition; self.volume = volume; self.publisher = publisher
        self.doi = doi; self.url = url
    }
}

public struct APAChapterRef: Equatable, Sendable {
    public let authors: String
    public let date: String
    public let chapterTitle: String   // sentence case, plain
    public let editors: String?       // "F. M. Last (Ed.),"
    public let bookTitle: String      // sentence case (renderer italicizes)
    public let edition: String?
    public let volume: String?
    public let pages: String?         // "pp. 1–51"
    public let publisher: String?
    public let doi: String?
    public let url: String?

    public init(authors: String, date: String, chapterTitle: String,
                editors: String? = nil, bookTitle: String,
                edition: String? = nil, volume: String? = nil, pages: String? = nil,
                publisher: String? = nil, doi: String? = nil, url: String? = nil) {
        self.authors = authors; self.date = date; self.chapterTitle = chapterTitle
        self.editors = editors; self.bookTitle = bookTitle
        self.edition = edition; self.volume = volume; self.pages = pages
        self.publisher = publisher; self.doi = doi; self.url = url
    }
}

public struct APAThesisRef: Equatable, Sendable {
    public let authors: String
    public let date: String
    public let title: String          // sentence case (renderer italicizes)
    public let thesisType: String     // "Doctoral dissertation" or "Master's thesis"
    public let institution: String?
    public let doi: String?
    public let url: String?

    public init(authors: String, date: String, title: String,
                thesisType: String, institution: String? = nil,
                doi: String? = nil, url: String? = nil) {
        self.authors = authors; self.date = date; self.title = title
        self.thesisType = thesisType; self.institution = institution
        self.doi = doi; self.url = url
    }
}

public struct APAReportRef: Equatable, Sendable {
    public let authors: String
    public let date: String
    public let title: String          // sentence case (renderer italicizes)
    public let titleAddon: String?    // e.g. report type description
    public let number: String?        // "No. 123" or "Technical Report 123"
    public let institution: String?
    public let doi: String?
    public let url: String?

    public init(authors: String, date: String, title: String,
                titleAddon: String? = nil, number: String? = nil,
                institution: String? = nil, doi: String? = nil, url: String? = nil) {
        self.authors = authors; self.date = date; self.title = title
        self.titleAddon = titleAddon; self.number = number
        self.institution = institution; self.doi = doi; self.url = url
    }
}

public struct APAPresentationRef: Equatable, Sendable {
    public let authors: String
    public let date: String           // "2025, May 1–3"
    public let title: String          // sentence case (renderer italicizes)
    public let presentationType: String // "Oral presentation", "Poster presentation"
    public let conference: String?    // event title
    public let venue: String?         // "Tainan, Taiwan"
    public let doi: String?
    public let url: String?

    public init(authors: String, date: String, title: String,
                presentationType: String, conference: String? = nil,
                venue: String? = nil, doi: String? = nil, url: String? = nil) {
        self.authors = authors; self.date = date; self.title = title
        self.presentationType = presentationType; self.conference = conference
        self.venue = venue; self.doi = doi; self.url = url
    }
}

public struct APAOnlineRef: Equatable, Sendable {
    public let authors: String
    public let date: String
    public let title: String          // sentence case (renderer italicizes)
    public let publisher: String?
    public let doi: String?
    public let url: String?

    public init(authors: String, date: String, title: String,
                publisher: String? = nil, doi: String? = nil, url: String? = nil) {
        self.authors = authors; self.date = date; self.title = title
        self.publisher = publisher; self.doi = doi; self.url = url
    }
}
