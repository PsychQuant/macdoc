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
        guard FormClassifier.enclosingCell(of: p, in: index) != nil else { throw FormError.notInTableCell(id) }
    }

    static func checkTick(_ id: String, in index: XMLTagIndex) throws {
        let p = try locate(id, in: index)
        // numId 0 means "numbering removed", so it is not a list bullet to tick.
        guard FormLocator.ownNumbering(of: p, in: index) != nil else { throw FormError.noOwnNumbering(id) }
    }

    static func checkRemove(_ id: String, in index: XMLTagIndex) throws {
        let p = try locate(id, in: index)
        if ownSectPr(of: p, in: index) != nil { throw FormError.carriesSectionBreak(id) }
        // Fields and comment references are checked by the plan against the
        // union of everything it deletes (FormRanges.checkPairedMarkup).
        // Cells (and text boxes) must keep at least one paragraph and end with
        // one. Their blocks are counted through content-control and custom-XML
        // wrappers, so a wrapped paragraph is guarded like a direct one.
        guard let container = blockContainer(of: p, in: index),
              ["w:tc", "w:txbxContent"].contains(index.tags[container].name) else { return }
        let blocks = flattenBlocks(index.children(of: container), in: index)
        guard blocks.contains(p) else { return }
        if blocks.filter({ index.tags[$0].name == "w:p" }).count <= 1 { throw FormError.onlyParagraphInCell(id) }
        if let last = blocks.filter({ $0 != p }).last, index.tags[last].name != "w:p" {
            throw FormError.cellWouldEndWithoutParagraph(id)
        }
    }

    /// Block-level wrappers that do not change which container a paragraph belongs to.
    static let blockWrappers: Set<String> = ["w:sdt", "w:sdtContent", "w:customXml"]

    /// Nearest ancestor that is not a block wrapper.
    static func blockContainer(of element: Int, in index: XMLTagIndex) -> Int? {
        var current = index.tags[element].parent
        while let c = current, blockWrappers.contains(index.tags[c].name) { current = index.tags[c].parent }
        return current
    }

    /// Paragraphs and tables among `elements`, looking through block wrappers,
    /// in document order.
    static func flattenBlocks(_ elements: [Int], in index: XMLTagIndex) -> [Int] {
        var out: [Int] = []
        for e in elements {
            switch index.tags[e].name {
            case "w:p", "w:tbl": out.append(e)
            case "w:sdt": out += flattenBlocks(index.children(of: e).filter { index.tags[$0].name == "w:sdtContent" }, in: index)
            case "w:sdtContent", "w:customXml": out += flattenBlocks(index.children(of: e), in: index)
            default: break
            }
        }
        return out
    }

    /// Body-level children that are neither content nor wrappers: range
    /// markers and the wrappers' own property elements (closed list).
    static let nonBlockElements: Set<String> = [
        "w:bookmarkStart", "w:bookmarkEnd", "w:commentRangeStart", "w:commentRangeEnd",
        "w:moveFromRangeStart", "w:moveFromRangeEnd", "w:moveToRangeStart", "w:moveToRangeEnd",
        "w:permStart", "w:permEnd", "w:proofErr",
        "w:customXmlInsRangeStart", "w:customXmlInsRangeEnd", "w:customXmlDelRangeStart", "w:customXmlDelRangeEnd",
        "w:customXmlMoveFromRangeStart", "w:customXmlMoveFromRangeEnd",
        "w:customXmlMoveToRangeStart", "w:customXmlMoveToRangeEnd",
        "w:sdtPr", "w:sdtEndPr", "w:customXmlPr", "w:sectPr",
    ]

    /// Content blocks among `elements`, looking through block wrappers, in
    /// document order. Unlike `flattenBlocks`, every element that is not a
    /// range marker counts — `w:altChunk`, math, anything not listed — so a
    /// block of an unforeseen kind is never mistaken for nothing.
    static func contentBlocks(_ elements: [Int], in index: XMLTagIndex) -> [Int] {
        var out: [Int] = []
        for e in elements {
            let name = index.tags[e].name
            switch name {
            case "w:sdt": out += contentBlocks(index.children(of: e).filter { index.tags[$0].name == "w:sdtContent" }, in: index)
            case "w:sdtContent", "w:customXml": out += contentBlocks(index.children(of: e), in: index)
            default: if !nonBlockElements.contains(name) { out.append(e) }
            }
        }
        return out
    }

    static func checkTruncate(_ id: String, in index: XMLTagIndex) throws -> (paragraph: Int, body: Int) {
        let p = try locate(id, in: index)
        guard let body = index.tags[p].parent, index.tags[body].name == "w:body" else {
            throw FormError.notBodyChild(id)
        }
        // Nothing but range markers before the cut means every content block
        // would go; that is the same as cutting at the first child.
        let before = index.children(of: body).filter { index.tags[$0].start < index.tags[p].start }
        if contentBlocks(before, in: index).isEmpty { throw FormError.firstBodyChild(id) }
        return (p, body)
    }

    /// Start of the body's closing tag.
    static func bodyEnd(of body: Int, in index: XMLTagIndex) -> Int {
        index.tags[index.tags[body].match!].start
    }

    /// The byte range `--truncate-from` deletes: from the paragraph to the
    /// start of the body's closing tag.
    static func truncationRange(from id: String, in index: XMLTagIndex) throws -> Range<Int> {
        let (p, body) = try checkTruncate(id, in: index)
        return index.tags[p].start..<bodyEnd(of: body, in: index)
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
    /// closed list: its own `w:pPr` shows nothing (see `markShowsContent`),
    /// and apart from that the paragraph holds only `w:proofErr` markers and
    /// runs whose children are `w:rPr`, `w:lastRenderedPageBreak` or a `w:t`
    /// with no text. Everything else — bookmarks, comment ranges, tracked
    /// changes, hyperlinks, fields, drawings, symbols — counts as content, so
    /// it is never deleted.
    static func hasContent(_ p: Int, in index: XMLTagIndex) -> Bool {
        for child in index.children(of: p) {
            switch index.tags[child].name {
            case "w:pPr":
                if markShowsContent(child, in: index) { return true }
            case "w:proofErr":
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

    /// True when a paragraph's own `w:pPr` carries something the reader sees
    /// or a revision would lose (#253): numbering (a visible bullet — a
    /// `w:numPr` without `w:numId` may take its id from the style, and only
    /// `w:numId` 0 removes numbering), `w:pPrChange`, or a revision marker in
    /// the paragraph-mark `w:rPr`.
    static func markShowsContent(_ pPr: Int, in index: XMLTagIndex) -> Bool {
        if let numPr = index.child(of: pPr, named: "w:numPr") {
            let numId = index.child(of: numPr, named: "w:numId").flatMap { index.attribute("w:val", of: $0) }
            if numId != "0" { return true }
        }
        if index.child(of: pPr, named: "w:pPrChange") != nil { return true }
        if let mark = ownRPr(of: pPr, in: index),
           index.children(of: mark).contains(where: { revisionMarks.contains(index.tags[$0].name) }) {
            return true
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

    /// Returns the skipped cleanup when the cell holds a structure that stops
    /// the removal of empty siblings (#253), so the caller can report it.
    @discardableResult
    static func normalizeField(_ id: String, halfPoints: Int, protected: Set<String>,
                               editor: inout XMLEditor) throws -> CleanupSkip? {
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

        // A content control's own run properties format what Word writes when
        // a value is picked, so they carry the size too; one without them is
        // left without (#253).
        for sdt in FormLocator.ownElements(named: "w:sdt", of: p, in: index) {
            guard let sdtPr = index.child(of: sdt, named: "w:sdtPr"),
                  let rPr = ownRPr(of: sdtPr, in: index) else { continue }
            edits.append(.replace(index.elementRange(rPr),
                                  with: try Fragment.rPrWithSize(index.elementString(rPr), halfPoints: halfPoints)))
        }

        // The enclosing cell is vertically centred.
        let tc = FormClassifier.enclosingCell(of: p, in: index)!
        let vAlign = "<w:vAlign w:val=\"center\"/>"
        if let tcPr = index.child(of: tc, named: "w:tcPr") {
            edits.append(.replace(index.elementRange(tcPr),
                                  with: try Fragment.setChild(index.elementString(tcPr), removing: ["w:vAlign"],
                                                              insert: vAlign, followers: Fragment.afterVAlign)))
        } else {
            edits.append(.insert("<w:tcPr>" + vAlign + "</w:tcPr>", at: index.tags[tc].end))
        }

        // Paragraphs without content in the same cell push the value off centre.
        // The spec skips the cleanup when the cell holds one of these
        // structures; the skip is returned so it is never silent (#253).
        let present = Set(index.descendants(of: tc).map { index.tags[$0].name })
        let reasons = CleanupSkip.Reason.allCases.filter { present.contains($0.elementName) }
        let removable = index.children(of: tc).filter { sibling in
            guard sibling != p, index.tags[sibling].name == "w:p" else { return false }
            if let siblingId = index.attribute("w14:paraId", of: sibling), protected.contains(siblingId) { return false }
            return ownSectPr(of: sibling, in: index) == nil && !hasContent(sibling, in: index)
        }
        if reasons.isEmpty {
            for sibling in removable { edits.append(.remove(index.elementRange(sibling))) }
        }
        try editor.apply(edits)
        // Only a skip that left an empty paragraph behind is reported (#253 verify R1).
        return reasons.isEmpty || removable.isEmpty ? nil : CleanupSkip(paragraphId: id, reasons: reasons)
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
            // A native checkbox content control redraws its glyph from the
            // fonts in w14:checkedState / w14:uncheckedState when toggled, so
            // re-fonting the run alone would not hold; leave it and count it.
            if insideCheckboxControl(r, in: index) { skipped += 1; continue }

            let opening = index.openingTagString(r)
            let rPr = ownRPr(of: r, in: index).map { index.elementString($0) }
            let boxRPr = try Fragment.rPrWithFont(rPr, font: font)
            let segments = splitBoxes(text)
            // Splitting would copy a tracked formatting change (and its w:id)
            // into every piece; leave such a run alone and count it instead.
            if segments.count > 1, let props = ownRPr(of: r, in: index), index.child(of: props, named: "w:rPrChange") != nil {
                skipped += 1
                continue
            }
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

    /// True when an enclosing `w:sdt` declares `w14:checkbox` in its `w:sdtPr`.
    static func insideCheckboxControl(_ element: Int, in index: XMLTagIndex) -> Bool {
        var current = index.tags[element].parent
        while let c = current {
            if index.tags[c].name == "w:sdt", let sdtPr = index.child(of: c, named: "w:sdtPr"),
               index.child(of: sdtPr, named: "w14:checkbox") != nil {
                return true
            }
            current = index.tags[c].parent
        }
        return false
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
            runProperties = try ownRPr(of: first, in: index)
                .map { try Fragment.removeChildren(index.elementString($0), named: ["w:rPrChange"]) } ?? ""
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
        // An anchor that ends a section keeps the inserted paragraphs in its
        // section: the break moves from the anchor to the last inserted
        // paragraph, instead of the new text starting the next section.
        var edits: [Edit] = []
        var lastPPr = pPr
        if let own = ownSectPr(of: anchor, in: index), let anchorPPr = ownPPr(of: anchor, in: index), !texts.isEmpty {
            edits.append(.replace(index.elementRange(anchorPPr),
                                  with: try Fragment.removeChildren(index.elementString(anchorPPr), named: ["w:sectPr"])))
            lastPPr = try Fragment.setChild(pPr.isEmpty ? "<w:pPr></w:pPr>" : pPr, removing: [],
                                            insert: index.elementString(own), followers: ["w:pPrChange"])
        }
        let paragraphs = texts.enumerated().map { offset, text in
            "<w:p>" + (offset == texts.count - 1 ? lastPPr : pPr) + "<w:r>" + rPr + textElement(text) + "</w:r></w:p>"
        }.joined()
        edits.append(.insert(paragraphs, at: index.elementRange(anchor).upperBound))
        try editor.apply(edits)
    }

    // MARK: Remove and truncate

    /// Checks everything the command deletes as one set (#253 verify R1, R2):
    /// fields and comment references against the union of the `--remove`
    /// paragraphs and the `--truncate-from` range, and each cell or text box
    /// against what is left after all of its named paragraphs go.
    static func checkDeletions(_ ids: [String], tables: [String] = [], truncateFrom: String?,
                               in index: XMLTagIndex) throws -> [FormRanges.DeletionSpan] {
        try deletionPlan(ids, tables: tables, truncateFrom: truncateFrom, in: index).spans
    }

    /// What `checkDeletions` judges, plus whether the body needs an empty
    /// final paragraph afterwards (rule (b) of `checkBodyStructure`).
    static func deletionPlan(_ ids: [String], tables: [String], truncateFrom: String?,
                             in index: XMLTagIndex) throws -> (spans: [FormRanges.DeletionSpan], addFinalParagraph: Bool) {
        // Nothing to delete: no pairing or container question arises, and the
        // whole-part scans below are skipped (#253 verify R3).
        guard !ids.isEmpty || !tables.isEmpty || truncateFrom != nil else { return ([], false) }
        var distinct: Set<String> = []
        let ids = ids.filter { distinct.insert($0).inserted }
        for id in ids { try checkRemove(id, in: index) }
        let removed = try ids.map { try locate($0, in: index) }
        var spans = zip(ids, removed).map { FormRanges.DeletionSpan(id: $0, range: index.elementRange($1)) }
        // A part with more than one body is not a document the structure
        // rules below can judge (#250 verify R1).
        if index.elements(named: "w:body").count > 1 {
            throw FormError.malformedPart("有多個 w:body，不是一般的 Word 文件，拒絕刪除")
        }
        // Each named table once, under the first id naming it (#250).
        let removedTables = try uniqueTables(tables, in: index)
        // A paragraph inside the table carrying its own section break would go
        // with it, as `--remove` refuses for a paragraph (#250 verify R1).
        // Only the table's own tags are walked, so the cost is the size of the
        // removed tables, not tables times paragraphs (#250 verify R2).
        for entry in removedTables {
            for t in entry.table...index.tags[entry.table].match! where index.tags[t].kind != .close
                && index.tags[t].name == "w:p" && ownSectPr(of: t, in: index) != nil {
                throw FormError.tableCarriesSectionBreak(entry.id)
            }
        }
        let tableSpans = removedTables.map { FormRanges.DeletionSpan(id: $0.id, range: index.elementRange($0.table)) }
        for (id, p) in zip(ids, removed) {
            if let table = tableSpans.first(where: { $0.range.contains(index.tags[p].start) }) {
                throw FormError.conflictingOperations(id, detail: "位在 --remove-table \(table.id) 會刪掉的表格裡")
            }
        }
        spans += tableSpans
        // The cut is located and checked once; every later use reads it here.
        let cut = try truncateFrom.map { try checkTruncate($0, in: index) }
        if let id = truncateFrom, let cut {
            let cutStart = index.tags[cut.paragraph].start
            if let table = tableSpans.first(where: { $0.range.lowerBound >= cutStart }) {
                throw FormError.conflictingOperations(table.id, detail: "位在 --truncate-from \(id) 會截掉的範圍內")
            }
            spans.append(.init(id: id, range: cutStart..<bodyEnd(of: cut.body, in: index)))
        }
        try FormRanges.checkPairedMarkup(spans, index: index)
        let removedSet = Set(removed)
        var seen: Set<Int> = []
        for p in removed.sorted() {
            guard let container = blockContainer(of: p, in: index),
                  ["w:tc", "w:txbxContent"].contains(index.tags[container].name), seen.insert(container).inserted else { continue }
            // checkRemove has refused every paragraph that breaks the
            // container alone, so what is left is a combination. Name the
            // paragraphs that cause it, in document order (tag order).
            let named = removed.filter { blockContainer(of: $0, in: index) == container }.sorted()
            let remaining = flattenBlocks(index.children(of: container), in: index).filter { !removedSet.contains($0) }
            let ids = { (ps: [Int]) in ps.map { index.attribute("w14:paraId", of: $0) ?? "" } }
            if !remaining.contains(where: { index.tags[$0].name == "w:p" }) {
                throw FormError.removalsLeaveNoParagraph(ids(named))
            }
            if let last = remaining.last, index.tags[last].name != "w:p" {
                throw FormError.removalsEndWithoutParagraph(ids(named.filter { $0 > last }))
            }
        }
        let deletedBlocks = removedSet.union(removedTables.map(\.table))
        if let id = truncateFrom, let cut, !deletedBlocks.isEmpty {
            let before = index.children(of: cut.body).filter { index.tags[$0].start < index.tags[cut.paragraph].start }
            if contentBlocks(before, in: index).allSatisfy({ deletedBlocks.contains($0) }) {
                throw FormError.removalsLeaveNothingBeforeCut(id)
            }
        }
        var owners: [Int: String] = [:]
        for (id, p) in zip(ids, removed) where owners[p] == nil { owners[p] = id }
        for entry in removedTables { owners[entry.table] = entry.id }
        let addFinalParagraph = try checkBodyStructure(owners, truncateFrom: truncateFrom.flatMap { id in
            cut.map { (id, $0.paragraph, $0.body) }
        }, in: index)
        // A kept marker goes where deleteAll puts it; refuse when that would
        // change the Markup Compatibility rules applying to it (R4).
        let deleted = spans.map(\.range)
        for p in removedSet.sorted() {
            // A named paragraph with no parent is the root of a crafted part;
            // the result check reports it, there is no context to compare.
            guard let destination = survivingParagraphBefore(p, removed: removedSet, in: index) ?? index.tags[p].parent else { continue }
            for marker in FormRanges.keptMarkers(in: index.elementRange(p), deleted: deleted, index: index)
            where FormRanges.compatibilityContextChanges(marker, destination: destination, index: index) {
                throw FormError.markerUnderCompatibilityRules(index.attribute("w14:paraId", of: p) ?? "")
            }
        }
        for entry in removedTables {
            guard let parent = index.tags[entry.table].parent else { continue }
            for marker in FormRanges.keptMarkers(in: index.elementRange(entry.table), deleted: deleted, index: index)
            where FormRanges.compatibilityContextChanges(marker, destination: parent, index: index) {
                throw FormError.markerUnderCompatibilityRules(entry.id)
            }
        }
        if let id = truncateFrom, let body = cut?.body, let span = spans.last(where: { $0.id == id }) {
            for marker in FormRanges.keptMarkers(in: span.range, deleted: deleted, index: index)
            where FormRanges.compatibilityContextChanges(marker, destination: body, index: index) {
                throw FormError.markerUnderCompatibilityRules(id)
            }
        }
        return (spans, addFinalParagraph)
    }

    /// The table `--remove-table` deletes for a paragraph: the nearest table
    /// around it, which must be a body-level block (looking through
    /// body-level content controls and custom XML) (#250).
    static func tableToRemove(_ id: String, in index: XMLTagIndex) throws -> Int {
        let table: Int
        switch enclosingTable(of: try locate(id, in: index), in: index) {
        case .table(let t): table = t
        case .notInTable: throw FormError.notInTable(id)
        case .inTextBox: throw FormError.inTextBox(id)
        }
        guard let container = blockContainer(of: table, in: index), index.tags[container].name == "w:body" else {
            throw FormError.tableNotBodyLevel(id)
        }
        return table
    }

    enum TableLookup: Equatable {
        case table(Int)
        case notInTable
        /// The paragraph is in a text box inside a table.
        case inTextBox
    }

    /// The nearest table around a paragraph. A text box is its own story:
    /// the table around it is not the paragraph's table, so the walk stops
    /// there (#250 verify R1).
    static func enclosingTable(of p: Int, in index: XMLTagIndex) -> TableLookup {
        var current = index.tags[p].parent
        while let c = current, index.tags[c].name != "w:tbl" {
            if index.tags[c].name == "w:txbxContent" {
                return index.ancestor(of: c, named: "w:tbl") == nil ? .notInTable : .inTextBox
            }
            current = index.tags[c].parent
        }
        return current.map { .table($0) } ?? .notInTable
    }

    /// Each table named by `ids` once, under the first id naming it, in
    /// document order.
    static func uniqueTables(_ ids: [String], in index: XMLTagIndex) throws -> [(id: String, table: Int)] {
        var seen: Set<Int> = []
        var out: [(id: String, table: Int)] = []
        for id in ids {
            let table = try tableToRemove(id, in: index)
            if seen.insert(table).inserted { out.append((id, table)) }
        }
        return out.sorted { $0.table < $1.table }
    }

    /// The body-level block structure every deletion keeps (#250), judged on
    /// the body's content blocks (looking through content controls and
    /// custom XML) before and after everything named goes. Only what this
    /// command causes is refused; a part that already had the shape passes.
    /// (a) Two tables that something other than a table separated must not
    ///     become adjacent: Word would join them.
    /// (b) The body must keep content; deleting every block is refused. A body
    ///     that ended with a paragraph and would end with a table (or another
    ///     block that is not a paragraph) gets an empty final paragraph; the
    ///     return value says so.
    /// (c) Without a truncation, the last section must keep content: the last
    ///     kept block must not be a paragraph with its own section break when
    ///     the body has its own final section properties. (Truncation folds
    ///     such a break into the final section, #249.)
    @discardableResult
    static func checkBodyStructure(_ owners: [Int: String], truncateFrom cut: (id: String, paragraph: Int, body: Int)?,
                                   in index: XMLTagIndex) throws -> Bool {
        guard let body = cut?.body ?? index.elements(named: "w:body").first else { return false }
        let blocks = contentBlocks(index.children(of: body), in: index)
        guard let lastBlock = blocks.indices.last else { return false }
        let cutStart = cut.map { index.tags[$0.paragraph].start }
        func owner(_ i: Int) -> String? {
            if let id = owners[blocks[i]] { return id }
            if let cut, let cutStart, index.tags[blocks[i]].start >= cutStart { return cut.id }
            return nil
        }
        func names(_ positions: ClosedRange<Int>) -> [String] {
            var seen: Set<String> = []
            return positions.compactMap(owner).filter { seen.insert($0).inserted }
        }
        let isTable = { (i: Int) in index.tags[blocks[i]].name == "w:tbl" }
        let isParagraph = { (i: Int) in index.tags[blocks[i]].name == "w:p" }
        let kept = blocks.indices.filter { owner($0) == nil }
        for (a, b) in zip(kept, kept.dropFirst()) where b > a + 1 && isTable(a) && isTable(b) {
            if ((a + 1)..<b).contains(where: { !isTable($0) }) { throw FormError.tablesWouldJoin(names((a + 1)...(b - 1))) }
        }
        guard let last = kept.last else { throw FormError.removalsLeaveEmptyBody(names(0...lastBlock)) }
        if cut == nil, last < lastBlock, isParagraph(last),
           ownSectPr(of: blocks[last], in: index) != nil,
           index.children(of: body).contains(where: { index.tags[$0].name == "w:sectPr" }) {
            throw FormError.lastSectionWouldBeEmpty(names((last + 1)...lastBlock))
        }
        return isParagraph(lastBlock) && !isParagraph(last)
    }

    /// The only entry point that deletes (#253 verify R2, R3): checks the whole
    /// deletion, removes every named paragraph and table in one edit, then
    /// truncates.
    /// A range marker whose partner stays is kept where its paragraph was;
    /// when no surviving block follows the paragraph in its cell or text box,
    /// it goes to the end of the nearest surviving paragraph before it, so the
    /// container still ends with a paragraph whatever order the ids came in.
    /// The truncation's kept markers are taken on the part before the removal
    /// edit, where the partners of removed markers can still be seen.
    @discardableResult
    static func deleteAll(_ ids: [String], tables: [String] = [], truncateFrom: String?, editor: inout XMLEditor) throws -> Bool {
        let index = editor.index
        let (spans, addFinalParagraph) = try deletionPlan(ids, tables: tables, truncateFrom: truncateFrom, in: index)
        guard !spans.isEmpty else { return false }
        let deleted = spans.map(\.range)
        let removed = Set(try ids.map { try locate($0, in: index) })
        var edits: [Edit] = []
        var appended: [Int: String] = [:]
        for p in removed.sorted() {
            let span = index.elementRange(p)
            if let destination = survivingParagraphBefore(p, removed: removed, in: index) {
                appended[destination, default: ""] += FormRanges.keptMarkerXML(in: span, deleted: deleted,
                                                                               destination: destination, index: index)
                edits.append(.remove(span))
            } else {
                edits.append(.replace(span, with: FormRanges.keptMarkerXML(in: span, deleted: deleted,
                                                                           destination: index.tags[p].parent, index: index)))
            }
        }
        // A removed table leaves its kept range markers where it was (#250).
        for entry in try uniqueTables(tables, in: index) {
            let span = index.elementRange(entry.table)
            edits.append(.replace(span, with: FormRanges.keptMarkerXML(in: span, deleted: deleted,
                                                                       destination: index.tags[entry.table].parent, index: index)))
        }
        for (destination, markers) in appended where !markers.isEmpty {
            edits.append(index.tags[destination].kind == .selfClosing
                ? .replace(index.elementRange(destination), with: openTag(of: destination, in: index) + markers + "</w:p>")
                : .insert(markers, at: index.tags[index.tags[destination].match!].start))
        }
        let truncation = try truncateFrom.map { id -> (id: String, markers: String) in
            guard let span = spans.last(where: { $0.id == id }) else { return (id, "") }
            return (id, FormRanges.keptMarkerXML(in: span.range, deleted: deleted,
                                                 destination: try checkTruncate(id, in: index).body, index: index))
        }
        // Rule (b): the body ends with a paragraph again, as its last block
        // right before the body's own section properties; the cut writes it
        // itself after the kept range markers.
        if addFinalParagraph, truncation == nil, let body = index.elements(named: "w:body").first {
            let at = index.children(of: body).last(where: { index.tags[$0].name == "w:sectPr" })
                .map { index.tags[$0].start } ?? bodyEnd(of: body, in: index)
            edits.append(.insert("<w:p/>", at: at))
        }
        if !edits.isEmpty { try editor.apply(edits) }
        if let truncation {
            // The paragraph goes last, right before the final section
            // properties, as it does without a cut.
            try truncate(from: truncation.id, keptMarkers: truncation.markers + (addFinalParagraph ? "<w:p/>" : ""),
                         editor: &editor)
        }
        return addFinalParagraph
    }

    /// For a removed paragraph with no surviving block after it in its cell or
    /// text box: the nearest surviving paragraph before it.
    static func survivingParagraphBefore(_ p: Int, removed: Set<Int>, in index: XMLTagIndex) -> Int? {
        guard let container = blockContainer(of: p, in: index),
              ["w:tc", "w:txbxContent"].contains(index.tags[container].name) else { return nil }
        let blocks = flattenBlocks(index.children(of: container), in: index)
        guard let at = blocks.firstIndex(of: p),
              !blocks[(at + 1)...].contains(where: { !removed.contains($0) }),
              let before = blocks[..<at].last(where: { !removed.contains($0) }),
              index.tags[before].name == "w:p" else { return nil }
        return before
    }

    /// Reached only through `deleteAll`, which has judged the whole deletion;
    /// here only the cut's own structure is checked again, not the pairing.
    private static func truncate(from id: String, keptMarkers: String, editor: inout XMLEditor) throws {
        let (p, body) = try checkTruncate(id, in: editor.index)
        let index = editor.index
        let cut = index.tags[p].start
        let bodyEnd = bodyEnd(of: body, in: index)
        // Only live section properties count: a body-level paragraph's own
        // w:pPr/w:sectPr, or the body's own w:sectPr. A w:sectPr kept inside
        // w:pPrChange is revision history and must not become the result.
        var section = ""
        search: for child in index.children(of: body) where index.tags[child].start >= cut {
            if index.tags[child].name == "w:sectPr" {
                section = index.elementString(child)
                break
            }
            // Body-level paragraphs, including those inside body-level content controls.
            for paragraph in flattenBlocks([child], in: index) where index.tags[paragraph].name == "w:p" {
                if let own = ownSectPr(of: paragraph, in: index) {
                    section = index.elementString(own)
                    break search
                }
            }
        }
        // When the kept content ends with its own section break, the cut
        // removed a whole section. Keeping both would leave a final section
        // with no content (an extra blank page), so the kept break becomes the
        // body's final w:sectPr and the removed range's one is dropped.
        var edits: [Edit] = []
        let kept = contentBlocks(index.children(of: body).filter { index.tags[$0].start < cut }, in: index)
        if let last = kept.last, index.tags[last].name == "w:p", let own = ownSectPr(of: last, in: index),
           let pPr = ownPPr(of: last, in: index) {
            section = index.elementString(own)
            edits.append(.replace(index.elementRange(pPr),
                                  with: try Fragment.removeChildren(index.elementString(pPr), named: ["w:sectPr"])))
        }
        // Range markers whose partner is kept end the kept content, before the
        // final section properties (#253); the plan serializes them.
        edits.append(.replace(cut..<bodyEnd, with: keptMarkers + section))
        try editor.apply(edits)
    }
}
