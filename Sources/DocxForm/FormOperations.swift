// FormOperations.swift — the string-level operations of `macdoc word form
// apply` (macdoc#249, change docx-form-normalization).
//
// Each operation checks its own preconditions against the current part, so a
// precondition that only becomes false after an earlier step still fails
// loudly instead of editing the wrong element.

import Foundation

enum FormOperations {
    /// Children of a run that leave it empty (closed list; see the spec).
    /// Anything else inside a run — text, a tab, a drawing, a field character,
    /// a deleted-text record — is content.
    static let emptyRunChildren: Set<String> = ["w:rPr", "w:lastRenderedPageBreak"]

    /// Revision markers of a paragraph-mark `w:rPr`; copies must not carry them.
    static let revisionMarks: Set<String> = ["w:ins", "w:del", "w:moveFrom", "w:moveTo", "w:rPrChange"]

    // MARK: Lookup

    static func locate(_ id: String, in index: XMLTagIndex) throws -> Int {
        switch FormLocator.paragraph(withId: id, in: index) {
        case .found(let p): return p
        case .notFound: throw FormError.paragraphNotFound(id)
        case .ambiguous(let count): throw FormError.paragraphAmbiguous(id, count: count)
        case .notOnParagraph(let carrier): throw FormError.notOnParagraph(id, carrier: carrier)
        }
    }

    // MARK: Preconditions

    static func checkField(_ id: String, in index: XMLTagIndex) throws {
        let p = try locate(id, in: index)
        guard index.ancestor(of: p, named: "w:tc") != nil else { throw FormError.notInTableCell(id) }
    }

    static func checkTick(_ id: String, in index: XMLTagIndex) throws {
        let p = try locate(id, in: index)
        // numId 0 means "numbering removed", so it is not a list bullet to tick.
        guard FormLocator.ownNumbering(of: p, in: index) != nil else { throw FormError.noOwnNumbering(id) }
    }

    static func checkRemove(_ id: String, in index: XMLTagIndex) throws {
        let p = try locate(id, in: index)
        if ownSectPr(of: p, in: index) != nil { throw FormError.carriesSectionBreak(id) }
        if let parent = index.tags[p].parent, index.tags[parent].name == "w:tc" {
            let blocks = index.children(of: parent).filter { index.tags[$0].name != "w:tcPr" }
            let paragraphs = blocks.filter { index.tags[$0].name == "w:p" }
            if paragraphs.count <= 1 { throw FormError.onlyParagraphInCell(id) }
            // A cell must end with a paragraph; removing the last one after a
            // nested table would leave it ending with the table.
            let remaining = blocks.filter { $0 != p }
            if let last = remaining.last, index.tags[last].name != "w:p" {
                throw FormError.cellWouldEndWithoutParagraph(id)
            }
        }
    }

    static func checkTruncate(_ id: String, in index: XMLTagIndex) throws -> (paragraph: Int, body: Int) {
        let p = try locate(id, in: index)
        guard let body = index.tags[p].parent, index.tags[body].name == "w:body" else {
            throw FormError.notBodyChild(id)
        }
        if index.children(of: body).first == p { throw FormError.firstBodyChild(id) }
        return (p, body)
    }

    // MARK: Structure helpers

    static func ownPPr(of p: Int, in index: XMLTagIndex) -> Int? { index.child(of: p, named: "w:pPr") }

    static func ownNumPr(of p: Int, in index: XMLTagIndex) -> Int? {
        ownPPr(of: p, in: index).flatMap { index.child(of: $0, named: "w:numPr") }
    }

    static func ownSectPr(of p: Int, in index: XMLTagIndex) -> Int? {
        ownPPr(of: p, in: index).flatMap { index.child(of: $0, named: "w:sectPr") }
    }

    static func ownRPr(of element: Int, in index: XMLTagIndex) -> Int? { index.child(of: element, named: "w:rPr") }

    static func explicitSize(of rPr: Int?, in index: XMLTagIndex) -> Int? {
        guard let rPr, let sz = index.child(of: rPr, named: "w:sz"),
              let value = index.attribute("w:val", of: sz) else { return nil }
        return Int(value)
    }

    /// True unless the paragraph is provably empty. Empty is defined by a
    /// closed list: apart from its own `w:pPr`, the paragraph holds only
    /// `w:proofErr` markers and runs whose children are `w:rPr`,
    /// `w:lastRenderedPageBreak` or a `w:t` with no text. Everything else —
    /// bookmarks, comment ranges, tracked changes, hyperlinks, fields,
    /// drawings, symbols — counts as content, so it is never deleted.
    static func hasContent(_ p: Int, in index: XMLTagIndex) -> Bool {
        for child in index.children(of: p) {
            switch index.tags[child].name {
            case "w:pPr", "w:proofErr":
                continue
            case "w:r":
                for runChild in index.children(of: child) {
                    let name = index.tags[runChild].name
                    if emptyRunChildren.contains(name) { continue }
                    if name == "w:t", index.text(of: runChild).isEmpty { continue }
                    return true
                }
            default:
                return true
            }
        }
        return false
    }

    /// A paragraph opening tag rebuilt as an open tag (expands `<w:p …/>`).
    static func openTag(of p: Int, in index: XMLTagIndex) -> String {
        let tag = index.tags[p]
        guard tag.kind == .selfClosing else { return index.openingTagString(p) }
        return index.string(tag.start..<tag.attributes.upperBound) + ">"
    }

    // MARK: Field size

    /// Explicit sizes contributed by the designated fields, per the spec:
    /// each own run with text contributes its own `w:sz`; a field without
    /// any run with text contributes its paragraph-mark `w:sz`.
    static func collectFieldSizes(_ ids: [String], in index: XMLTagIndex) throws -> [Int] {
        var sizes: [Int] = []
        for id in ids {
            let p = try locate(id, in: index)
            let textRuns = FormLocator.ownRuns(of: p, in: index)
                .filter { !FormLocator.runText($0, in: index).isEmpty }
            if textRuns.isEmpty {
                let mark = ownPPr(of: p, in: index).flatMap { ownRPr(of: $0, in: index) }
                if let size = explicitSize(of: mark, in: index) { sizes.append(size) }
            } else {
                for r in textRuns {
                    if let size = explicitSize(of: ownRPr(of: r, in: index), in: index) { sizes.append(size) }
                }
            }
        }
        return sizes
    }

    /// Most common value, ties to the larger value; nil when empty.
    static func mode(_ values: [Int]) -> Int? {
        var counts: [Int: Int] = [:]
        for v in values { counts[v, default: 0] += 1 }
        return counts.max { a, b in a.value != b.value ? a.value < b.value : a.key < b.key }?.key
    }

    // MARK: Field normalization

    static func normalizeField(_ id: String, halfPoints: Int, protected: Set<String>,
                               editor: inout XMLEditor) throws {
        try checkField(id, in: editor.index)
        let index = editor.index
        let p = try locate(id, in: index)
        var edits: [Edit] = []

        // Paragraph properties: no style, no indent, left aligned, sized mark.
        let jc = "<w:jc w:val=\"left\"/>"
        if let pPr = ownPPr(of: p, in: index) {
            var fragment = try Fragment.setChild(index.elementString(pPr),
                                                 removing: ["w:pStyle", "w:ind", "w:jc"],
                                                 insert: jc, followers: Fragment.afterJc)
            fragment = try Fragment.updateChild(fragment, named: "w:rPr", followers: Fragment.afterParagraphMarkRPr) {
                try Fragment.rPrWithSize($0, halfPoints: halfPoints)
            }
            edits.append(.replace(index.elementRange(pPr), with: fragment))
        } else {
            let pPr = "<w:pPr>" + jc + (try Fragment.rPrWithSize(nil, halfPoints: halfPoints)) + "</w:pPr>"
            if index.tags[p].kind == .selfClosing {
                edits.append(.replace(index.elementRange(p), with: openTag(of: p, in: index) + pPr + "</w:p>"))
            } else {
                edits.append(.insert(pPr, at: index.tags[p].end))
            }
        }

        // Every run of the paragraph carries the size.
        for r in FormLocator.ownRuns(of: p, in: index) where index.tags[r].kind == .open {
            if let rPr = ownRPr(of: r, in: index) {
                edits.append(.replace(index.elementRange(rPr),
                                      with: try Fragment.rPrWithSize(index.elementString(rPr), halfPoints: halfPoints)))
            } else {
                edits.append(.insert(try Fragment.rPrWithSize(nil, halfPoints: halfPoints), at: index.tags[r].end))
            }
        }

        // The enclosing cell is vertically centred.
        let tc = index.ancestor(of: p, named: "w:tc")!
        let vAlign = "<w:vAlign w:val=\"center\"/>"
        if let tcPr = index.child(of: tc, named: "w:tcPr") {
            edits.append(.replace(index.elementRange(tcPr),
                                  with: try Fragment.setChild(index.elementString(tcPr), removing: ["w:vAlign"],
                                                              insert: vAlign, followers: Fragment.afterVAlign)))
        } else {
            edits.append(.insert("<w:tcPr>" + vAlign + "</w:tcPr>", at: index.tags[tc].end))
        }

        // Paragraphs without content in the same cell push the value off centre.
        let nestedTable = index.descendants(of: tc).contains { index.tags[$0].name == "w:tbl" }
        if !nestedTable {
            for sibling in index.children(of: tc) where sibling != p && index.tags[sibling].name == "w:p" {
                if let siblingId = index.attribute("w14:paraId", of: sibling), protected.contains(siblingId) { continue }
                if ownSectPr(of: sibling, in: index) != nil || hasContent(sibling, in: index) { continue }
                edits.append(.remove(index.elementRange(sibling)))
            }
        }
        try editor.apply(edits)
    }

    // MARK: Box glyph font

    /// Re-fonts box glyphs in every eligible run of the part; returns the
    /// number of runs holding a box glyph that were left alone because they
    /// carry other content.
    static func uniformCheckboxes(font: String, editor: inout XMLEditor) throws -> Int {
        let index = editor.index
        var edits: [Edit] = []
        var skipped = 0
        for r in index.elements(named: "w:r") where index.tags[r].kind == .open {
            let kids = index.children(of: r)
            let texts = kids.filter { index.tags[$0].name == "w:t" }
            let text = texts.map { index.text(of: $0) }.joined()
            guard FormClassifier.containsBoxGlyph(text) else { continue }
            let others = kids.filter { index.tags[$0].name != "w:t" && index.tags[$0].name != "w:rPr" }
            guard texts.count == 1, others.isEmpty else { skipped += 1; continue }

            let opening = index.openingTagString(r)
            let rPr = ownRPr(of: r, in: index).map { index.elementString($0) }
            let boxRPr = try Fragment.rPrWithFont(rPr, font: font)
            let segments = splitBoxes(text)
            let rebuilt: String
            if segments.count == 1 {
                rebuilt = opening + boxRPr + index.elementString(texts[0]) + "</w:r>"
            } else {
                rebuilt = segments.map { segment in
                    opening + (segment.isBox ? boxRPr : (rPr ?? "")) + textElement(segment.text) + "</w:r>"
                }.joined()
            }
            edits.append(.replace(index.elementRange(r), with: rebuilt))
        }
        try editor.apply(edits)
        return skipped
    }

    struct Segment: Equatable {
        let text: String
        let isBox: Bool
    }

    /// Maximal runs of box glyphs and of other text, in order.
    static func splitBoxes(_ text: String) -> [Segment] {
        var out: [Segment] = []
        var current = String.UnicodeScalarView()
        var currentIsBox: Bool?
        for scalar in text.unicodeScalars {
            let isBox = FormClassifier.boxGlyphs.contains(scalar)
            if let c = currentIsBox, c != isBox {
                out.append(Segment(text: String(current), isBox: c))
                current = String.UnicodeScalarView()
            }
            currentIsBox = isBox
            current.append(scalar)
        }
        if let c = currentIsBox { out.append(Segment(text: String(current), isBox: c)) }
        return out
    }

    static func textElement(_ text: String) -> String {
        let needsPreserve = text.first.map { $0 == " " || $0 == "\t" } == true
            || text.last.map { $0 == " " || $0 == "\t" } == true
        return (needsPreserve ? "<w:t xml:space=\"preserve\">" : "<w:t>") + XMLText.escapeText(text) + "</w:t>"
    }

    // MARK: List tick

    static func tickList(_ id: String, editor: inout XMLEditor) throws {
        try checkTick(id, in: editor.index)
        let index = editor.index
        let p = try locate(id, in: index)
        let pPr = ownPPr(of: p, in: index)!
        let runProperties: String
        if let first = FormLocator.firstTextRun(of: p, in: index) {
            runProperties = ownRPr(of: first, in: index).map { index.elementString($0) } ?? ""
        } else if let mark = ownRPr(of: pPr, in: index) {
            runProperties = try Fragment.removeChildren(index.elementString(mark), named: revisionMarks)
        } else {
            runProperties = ""
        }
        let tick = "<w:r>" + runProperties + "<w:t>\u{25A0}</w:t></w:r>"
        try editor.apply([
            .replace(index.elementRange(pPr),
                     with: try Fragment.removeChildren(index.elementString(pPr), named: ["w:numPr"])),
            .insert(tick, at: index.elementRange(pPr).upperBound),
        ])
    }

    // MARK: Insert

    static func insertParagraphs(after id: String, texts: [String], editor: inout XMLEditor) throws {
        for text in texts where !XMLText.isAllowed(text) { throw FormError.invalidText(id) }
        let index = editor.index
        let anchor = try locate(id, in: index)
        // The copy keeps the anchor's look but none of its one-off structure:
        // no numbering, section break, page break before, or revision marks
        // (copied revision marks would duplicate their w:id).
        let pPr = try ownPPr(of: anchor, in: index).map { element -> String in
            var fragment = try Fragment.removeChildren(index.elementString(element),
                                                       named: ["w:numPr", "w:sectPr", "w:pPrChange", "w:pageBreakBefore"])
            if try Fragment.child(fragment, named: "w:rPr") != nil {
                fragment = try Fragment.updateChild(fragment, named: "w:rPr", followers: []) {
                    try Fragment.removeChildren($0 ?? "<w:rPr></w:rPr>", named: revisionMarks)
                }
            }
            return fragment
        } ?? ""
        let rPr = try FormLocator.firstTextRun(of: anchor, in: index)
            .flatMap { ownRPr(of: $0, in: index) }
            .map { try Fragment.removeChildren(index.elementString($0), named: ["w:rPrChange"]) } ?? ""
        let paragraphs = texts.map { "<w:p>" + pPr + "<w:r>" + rPr + textElement($0) + "</w:r></w:p>" }.joined()
        try editor.apply([.insert(paragraphs, at: index.elementRange(anchor).upperBound)])
    }

    // MARK: Remove and truncate

    static func remove(_ id: String, editor: inout XMLEditor) throws {
        try checkRemove(id, in: editor.index)
        let p = try locate(id, in: editor.index)
        try editor.apply([.remove(editor.index.elementRange(p))])
    }

    static func truncate(from id: String, editor: inout XMLEditor) throws {
        let (p, body) = try checkTruncate(id, in: editor.index)
        let index = editor.index
        let cut = index.tags[p].start
        let bodyEnd = index.tags[index.tags[body].match!].start
        // Only live section properties count: a body-level paragraph's own
        // w:pPr/w:sectPr, or the body's own w:sectPr. A w:sectPr kept inside
        // w:pPrChange is revision history and must not become the result.
        var section = ""
        for child in index.children(of: body) where index.tags[child].start >= cut {
            if index.tags[child].name == "w:sectPr" {
                section = index.elementString(child)
                break
            }
            if index.tags[child].name == "w:p", let own = ownSectPr(of: child, in: index) {
                section = index.elementString(own)
                break
            }
        }
        try editor.apply([.replace(cut..<bodyEnd, with: section)])
    }
}
