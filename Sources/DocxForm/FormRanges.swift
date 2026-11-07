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
        // Only the marker elements are walked, from the index's name table (#252).
        for i in index.elements(namedAnyOf: pairedMarkers.keys) {
            let tag = index.tags[i]
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

    /// The kept markers of `span`, serialized in document order for placement
    /// under `destination` (the element they will be children of). A moved
    /// marker must keep the namespace each of its prefixes had where it was, so
    /// a binding is declared on the marker whenever the destination would
    /// resolve that prefix differently or not at all (#253 verify R1, R2).
    static func keptMarkerXML(in span: Range<Int>, deleted: [Range<Int>], destination: Int?, index: XMLTagIndex) -> String {
        keptMarkers(in: span, deleted: deleted, index: index)
            .map { serialize($0, under: destination, index: index) }.joined()
    }

    private static func serialize(_ marker: Int, under destination: Int?, index: XMLTagIndex) -> String {
        let own = Set(declarations(of: marker, index: index).map(\.prefix))
        var carried: [String] = []
        for prefix in usedPrefixes(of: marker, index: index) where !own.contains(prefix) {
            guard let source = binding(of: prefix, from: marker, index: index),
                  source != binding(of: prefix, from: destination, index: index) else { continue }
            carried.append((prefix.isEmpty ? "xmlns" : "xmlns:" + prefix) + "=" + source)
        }
        guard !carried.isEmpty else { return index.elementString(marker) }
        let tag = index.tags[marker]
        return index.string(tag.start..<tag.attributes.upperBound) + " " + carried.joined(separator: " ")
            + index.string(tag.attributes.upperBound..<index.elementRange(marker).upperBound)
    }

    /// Prefixes the marker's own name and attribute names use, in first-use
    /// order; "" stands for the default namespace of an unprefixed element.
    /// Unprefixed attributes and the reserved `xml` prefix bind nothing.
    /// Prefixes named inside Markup Compatibility values are never needed:
    /// a marker that carries such an attribute is not moved (#253 verify R4).
    private static func usedPrefixes(of element: Int, index: XMLTagIndex) -> [String] {
        func prefix(_ name: String) -> String? { name.firstIndex(of: ":").map { String(name[..<$0]) } }
        var out: [String] = [prefix(index.tags[element].name) ?? ""]
        for attribute in attributes(of: element, index: index) {
            guard attribute.name != "xmlns", !attribute.name.hasPrefix("xmlns:"),
                  let p = prefix(attribute.name), p != "xml", !out.contains(p) else { continue }
            out.append(p)
        }
        return out
    }

    static let markupCompatibilityNamespace = "http://schemas.openxmlformats.org/markup-compatibility/2006"

    /// Whether `element` is Markup Compatibility markup or carries some: its
    /// own name (`mc:AlternateContent`, `mc:Choice`, `mc:Fallback`), or the
    /// name of one of its attributes (`mc:Ignorable` and the rest), resolves
    /// on the element to the markup-compatibility namespace, the declared URI
    /// read with character references decoded. An unprefixed element name
    /// resolves through the default namespace; an unprefixed attribute has no
    /// namespace. The spelling of the prefix does not matter (#253 verify R4, R5).
    static func carriesCompatibilityMarkup(_ element: Int, index: XMLTagIndex) -> Bool {
        func isCompatibility(_ prefix: String) -> Bool {
            guard prefix != "xml", let quoted = binding(of: prefix, from: element, index: index) else { return false }
            return XMLText.decode(String(quoted.dropFirst().dropLast())) == markupCompatibilityNamespace
        }
        let name = index.tags[element].name
        if isCompatibility(name.firstIndex(of: ":").map { String(name[..<$0]) } ?? "") { return true }
        return attributes(of: element, index: index).contains { attribute in
            guard attribute.name != "xmlns", !attribute.name.hasPrefix("xmlns:"),
                  let colon = attribute.name.firstIndex(of: ":") else { return false }
            return isCompatibility(String(attribute.name[..<colon]))
        }
    }

    /// Whether moving `marker` to become a child of `destination` would change
    /// the Markup Compatibility rules that apply to it (#253 verify R4). The
    /// rules come from the marker and its ancestors, so they change when an
    /// element between the marker and the lowest common ancestor of the two
    /// positions carries one: on the source side the marker itself and the
    /// elements removed around it, on the destination side the elements the
    /// marker would newly sit inside. Rules above the common ancestor apply
    /// in both places.
    static func compatibilityContextChanges(_ marker: Int, destination: Int, index: XMLTagIndex) -> Bool {
        func chain(_ from: Int) -> [Int] {
            var out: [Int] = []
            var current: Int? = from
            while let c = current { out.append(c); current = index.tags[c].parent }
            return out
        }
        let destinationChain = chain(destination)
        let common = Set(destinationChain)
        let sourceChain = chain(marker)
        guard let lca = sourceChain.first(where: { common.contains($0) }) else { return true }
        let lost = sourceChain.prefix { $0 != lca }
        let gained = destinationChain.prefix { $0 != lca }
        return (Array(lost) + Array(gained)).contains { carriesCompatibilityMarkup($0, index: index) }
    }

    /// The quoted value (source text, quotes included) declaring `prefix` on
    /// the nearest element from `element` up to the root.
    private static func binding(of prefix: String, from element: Int?, index: XMLTagIndex) -> String? {
        var current = element
        while let c = current {
            if let found = declarations(of: c, index: index).first(where: { $0.prefix == prefix }) { return found.value }
            current = index.tags[c].parent
        }
        return nil
    }

    /// `xmlns` / `xmlns:p` attributes of an element, as (prefix, quoted value).
    private static func declarations(of element: Int, index: XMLTagIndex) -> [(prefix: String, value: String)] {
        attributes(of: element, index: index).compactMap { attribute in
            if attribute.name == "xmlns" { return ("", attribute.value) }
            if attribute.name.hasPrefix("xmlns:") { return (String(attribute.name.dropFirst(6)), attribute.value) }
            return nil
        }
    }

    /// Attributes of an element, read with quote awareness so text inside a
    /// value is never taken for another attribute (#253 verify R2). Values keep
    /// their quotes and escapes; parsing stops at anything malformed.
    static func attributes(of element: Int, index: XMLTagIndex) -> [(name: String, value: String)] {
        let text = Array(index.string(index.tags[element].attributes).unicodeScalars)
        var out: [(String, String)] = []
        var i = 0
        func isSpace(_ c: Unicode.Scalar) -> Bool { c == " " || c == "\t" || c == "\n" || c == "\r" }
        while i < text.count {
            while i < text.count, isSpace(text[i]) { i += 1 }
            let nameStart = i
            while i < text.count, !isSpace(text[i]), text[i] != "=" { i += 1 }
            guard i > nameStart else { break }
            let name = String(String.UnicodeScalarView(text[nameStart..<i]))
            while i < text.count, isSpace(text[i]) { i += 1 }
            guard i < text.count, text[i] == "=" else { break }
            i += 1
            while i < text.count, isSpace(text[i]) { i += 1 }
            guard i < text.count, text[i] == "\"" || text[i] == "'" else { break }
            let quote = text[i]
            let valueStart = i
            i += 1
            while i < text.count, text[i] != quote { i += 1 }
            guard i < text.count else { break }
            i += 1
            out.append((name, String(String.UnicodeScalarView(text[valueStart..<i]))))
        }
        return out
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
        for i in index.elements(named: "w:fldChar") {
            let tag = index.tags[i]
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
        for i in index.elements(namedAnyOf: ["w:commentRangeStart", "w:commentRangeEnd", "w:commentReference"]) {
            let tag = index.tags[i]
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
