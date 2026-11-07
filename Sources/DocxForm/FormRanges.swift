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

    /// Range markers inside `span` that must survive its deletion, in
    /// document order: those whose partner lies outside `span`, and those with
    /// no partner in the part (including a marker without `w:id`). A marker
    /// whose partner is also inside goes with the span.
    static func keptMarkers(in span: Range<Int>, index: XMLTagIndex) -> [Int] {
        var starts: [Key: [Int]] = [:]
        var inside: [(element: Int, key: Key?)] = []
        for (i, tag) in index.tags.enumerated() where tag.kind != .close {
            guard let marker = pairedMarkers[tag.name] else { continue }
            let key = index.attribute("w:id", of: i).map { Key(kind: marker.kind, id: $0, isStart: marker.isStart) }
            if let key { starts[key, default: []].append(tag.start) }
            if span.contains(tag.start) { inside.append((i, key)) }
        }
        return inside.filter { entry in
            guard let key = entry.key else { return true }
            let partners = starts[Key(kind: key.kind, id: key.id, isStart: !key.isStart)] ?? []
            return !partners.contains { span.contains($0) }
        }.map(\.element)
    }

    /// The kept markers of `span`, serialized in document order.
    static func keptMarkerXML(in span: Range<Int>, index: XMLTagIndex) -> String {
        keptMarkers(in: span, index: index).map { index.elementString($0) }.joined()
    }

    /// True when `span` holds the `begin` or the `end` `w:fldChar` of a
    /// complex field but not both. Fields nest, so begins and ends are matched
    /// with a stack in document order; an unmatched `end` or `begin` belongs to
    /// a field that is already broken and is ignored.
    static func splitsField(_ span: Range<Int>, index: XMLTagIndex) -> Bool {
        var open: [Int] = []
        for (i, tag) in index.tags.enumerated() where tag.kind != .close && tag.name == "w:fldChar" {
            switch index.attribute("w:fldCharType", of: i) {
            case "begin":
                open.append(tag.start)
            case "end":
                guard let begin = open.popLast() else { continue }
                if span.contains(begin) != span.contains(tag.start) { return true }
            default:
                continue
            }
        }
        return false
    }

    /// True when `span` holds a `w:commentReference` whose comment has a
    /// `w:commentRangeStart` or `w:commentRangeEnd` outside `span`.
    static func orphansComment(_ span: Range<Int>, index: XMLTagIndex) -> Bool {
        var rangeOutside: Set<String> = []
        var referencedInside: Set<String> = []
        for (i, tag) in index.tags.enumerated() where tag.kind != .close {
            switch tag.name {
            case "w:commentRangeStart", "w:commentRangeEnd":
                if !span.contains(tag.start), let id = index.attribute("w:id", of: i) { rangeOutside.insert(id) }
            case "w:commentReference":
                if span.contains(tag.start), let id = index.attribute("w:id", of: i) { referencedInside.insert(id) }
            default:
                continue
            }
        }
        return !referencedInside.isDisjoint(with: rangeOutside)
    }
}
