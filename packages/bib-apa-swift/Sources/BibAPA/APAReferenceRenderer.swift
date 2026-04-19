// APAReferenceRenderer.swift — Protocol for rendering APAReference to output format

/// Renders an APAReference into a specific output format (Markdown, HTML, Astro props, etc.).
public protocol APAReferenceRenderer {
    associatedtype Output

    func render(_ reference: APAReference) -> Output

    func renderArticle(_ ref: APAArticleRef) -> Output
    func renderBook(_ ref: APABookRef) -> Output
    func renderChapter(_ ref: APAChapterRef) -> Output
    func renderThesis(_ ref: APAThesisRef) -> Output
    func renderReport(_ ref: APAReportRef) -> Output
    func renderPresentation(_ ref: APAPresentationRef) -> Output
    func renderOnline(_ ref: APAOnlineRef) -> Output
}

// Default dispatch
extension APAReferenceRenderer {
    public func render(_ reference: APAReference) -> Output {
        switch reference {
        case .article(let ref): return renderArticle(ref)
        case .book(let ref): return renderBook(ref)
        case .chapter(let ref): return renderChapter(ref)
        case .thesis(let ref): return renderThesis(ref)
        case .report(let ref): return renderReport(ref)
        case .presentation(let ref): return renderPresentation(ref)
        case .online(let ref): return renderOnline(ref)
        }
    }
}
