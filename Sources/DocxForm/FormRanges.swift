// FormRanges.swift — markup that pairs across element boundaries, for
// `--remove` and `--truncate-from` (macdoc#253, change docx-form-normalization).
//
// Both operations delete a contiguous byte range of word/document.xml. Three
// kinds of markup can pair across that range's edge:
//   - range markers, paired by kind and `w:id` (closed list below) — they may
//     sit at block level, so a marker whose partner survives is kept;
//   - complex fields, whose `begin` and `end` `w:fldChar` nest in document
//     order — they live inside runs, so a split field is refused;
//   - comment references, a run that anchors a comment whose range markers
//     are elsewhere — also inside a run, so taking one away is refused.

import Foundation

enum FormRanges {
    /// Paired range markers (closed list): element name → (pair kind, is start).
    static let pairedMarkers: [String: (kind: String, isStart: Bool)] = [
        "w:bookmarkStart": ("bookmark", true), "w:bookmarkEnd": ("bookmark", false),
        "w:commentRangeStart": ("comment", true), "w:commentRangeEnd": ("comment", false),
        "w:moveFromRangeStart": ("moveFrom", true), "w:moveFromRangeEnd": ("moveFrom", false),
        "w:moveToRangeStart": ("moveTo", true), "w:moveToRangeEnd": ("moveTo", false),
        "w:permStart": ("perm", true), "w:permEnd": ("perm", false),
        "w:customXmlInsRangeStart": ("customXmlIns", true), "w:customXmlInsRangeEnd": ("customXmlIns", false),
        "w:customXmlDelRangeStart": ("customXmlDel", true), "w:customXmlDelRangeEnd": ("customXmlDel", false),
        "w:customXmlMoveFromRangeStart": ("customXmlMoveFrom", true),
        "w:customXmlMoveFromRangeEnd": ("customXmlMoveFrom", false),
        "w:customXmlMoveToRangeStart": ("customXmlMoveTo", true),
        "w:customXmlMoveToRangeEnd": ("customXmlMoveTo", false),
    ]

    private struct Key: Hashable {
        let kind: String
        let id: String
        let isStart: Bool
    }

    /// A byte range one command deletes, and the paragraph id that names it.
    struct DeletionSpan {
        let id: String
        let range: Range<Int>
    }

    /// Every pairing decision is taken against the union of all ranges the
    /// command deletes (#253 verify R1): naming every paragraph of a field, or
    /// both halves of a bookmark, deletes them together instead of each
    /// paragraph being judged as if the others stayed.
    private static func inAny(_ offset: Int, _ ranges: [Range<Int>]) -> Bool {
        ranges.contains { $0.contains(offset) }
    }

    /// Range markers inside `span` that must survive the deletion, in document
    /// order: those whose partner lies outside every deleted range, and those
    /// with no partner in the part (including a marker without `w:id`).
    static func keptMarkers(in span: Range<Int>, deleted: [Range<Int>], index: XMLTagIndex) -> [Int] {
        var positions: [Key: [Int]] = [:]
        var inside: [(element: Int, key: Key?)] = []
        for (i, tag) in index.tags.enumerated() where tag.kind != .close {
            guard let marker = pairedMarkers[tag.name] else { continue }
            let key = index.attribute("w:id", of: i).map { Key(kind: marker.kind, id: $0, isStart: marker.isStart) }
            if let key { positions[key, default: []].append(tag.start) }
            if span.contains(tag.start) { inside.append((i, key)) }
        }
        return inside.filter { entry in
            guard let key = entry.key else { return true }
            let partners = positions[Key(kind: key.kind, id: key.id, isStart: !key.isStart)] ?? []
            return !partners.contains { inAny($0, deleted) }
        }.map(\.element)
    }

    /// The kept markers of `span`, serialized in document order. A marker
    /// leaves its deleted ancestors behind, so the namespace declarations it
    /// inherited from them travel with it (#253 verify R1).
    static func keptMarkerXML(in span: Range<Int>, deleted: [Range<Int>], index: XMLTagIndex) -> String {
        keptMarkers(in: span, deleted: deleted, index: index).map { serialize($0, leaving: span, index: index) }.joined()
    }

    private static func serialize(_ marker: Int, leaving span: Range<Int>, index: XMLTagIndex) -> String {
        var declared = Set(namespaceDeclarations(of: marker, index: index).map(\.prefix))
        var carried: [String] = []
        var current = index.tags[marker].parent
        while let c = current, span.contains(index.tags[c].start) {
            for declaration in namespaceDeclarations(of: c, index: index) where !declared.contains(declaration.prefix) {
                declared.insert(declaration.prefix)
                carried.append(declaration.text)
            }
            current = index.tags[c].parent
        }
        guard !carried.isEmpty else { return index.elementString(marker) }
        let tag = index.tags[marker]
        return index.string(tag.start..<tag.attributes.upperBound) + " " + carried.joined(separator: " ")
            + index.string(tag.attributes.upperBound..<index.elementRange(marker).upperBound)
    }

    private static let declaration = try! NSRegularExpression(
        pattern: #"(xmlns(?::[^\s=/>]+)?)\s*=\s*("[^"]*"|'[^']*')"#)

    /// `xmlns` / `xmlns:p` attributes of an element, as (prefix, source text).
    private static func namespaceDeclarations(of element: Int, index: XMLTagIndex) -> [(prefix: String, text: String)] {
        let attributes = index.string(index.tags[element].attributes)
        let ns = attributes as NSString
        return declaration.matches(in: attributes, range: NSRange(location: 0, length: ns.length)).map {
            (ns.substring(with: $0.range(at: 1)), ns.substring(with: $0.range))
        }
    }

    /// Refuses a deletion that would split markup living inside runs, naming
    /// the paragraph whose range holds the part that would go.
    static func checkPairedMarkup(_ spans: [DeletionSpan], index: XMLTagIndex) throws {
        if let id = fieldSplit(spans, index: index) { throw FormError.splitsField(id) }
        if let id = commentOrphan(spans, index: index) { throw FormError.splitsComment(id) }
    }

    private static func owner(of offset: Int, in spans: [DeletionSpan]) -> String? {
        spans.first { $0.range.contains(offset) }?.id
    }

    /// The span holding part, but not all, of one complex field's `begin`,
    /// `separate` and `end` `w:fldChar` (a field nests in document order, and a
    /// separator belongs to the innermost open field). A paragraph wholly
    /// inside a field's result holds none of them and may go; one holding the
    /// separator alone may not (#253 verify R1). A field missing its `end` is
    /// already broken and is ignored.
    static func fieldSplit(_ spans: [DeletionSpan], index: XMLTagIndex) -> String? {
        let ranges = spans.map(\.range)
        var open: [[Int]] = []
        for (i, tag) in index.tags.enumerated() where tag.kind != .close && tag.name == "w:fldChar" {
            switch index.attribute("w:fldCharType", of: i) {
            case "begin":
                open.append([tag.start])
            case "separate":
                if !open.isEmpty { open[open.count - 1].append(tag.start) }
            case "end":
                guard var parts = open.popLast() else { continue }
                parts.append(tag.start)
                let deleted = parts.filter { inAny($0, ranges) }
                if !deleted.isEmpty && deleted.count < parts.count { return owner(of: deleted[0], in: spans) }
            default:
                continue
            }
        }
        return nil
    }

    /// The span holding a `w:commentReference` whose comment keeps a
    /// `w:commentRangeStart` or `w:commentRangeEnd` outside every deleted range.
    static func commentOrphan(_ spans: [DeletionSpan], index: XMLTagIndex) -> String? {
        let ranges = spans.map(\.range)
        var rangeKept: Set<String> = []
        var references: [(id: String, offset: Int)] = []
        for (i, tag) in index.tags.enumerated() where tag.kind != .close {
            switch tag.name {
            case "w:commentRangeStart", "w:commentRangeEnd":
                if !inAny(tag.start, ranges), let id = index.attribute("w:id", of: i) { rangeKept.insert(id) }
            case "w:commentReference":
                if inAny(tag.start, ranges), let id = index.attribute("w:id", of: i) { references.append((id, tag.start)) }
            default:
                continue
            }
        }
        return references.first { rangeKept.contains($0.id) }.flatMap { owner(of: $0.offset, in: spans) }
    }
}
