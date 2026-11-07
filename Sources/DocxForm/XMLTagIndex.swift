// XMLTagIndex.swift — one-pass, quote-aware tag scanner over a UTF-8 XML part
// (macdoc#249, change docx-form-normalization).
//
// Form normalization edits `word/document.xml` as text so a raw-channel form
// keeps every byte outside the edited elements. Regular expressions get the
// structure wrong (nested tables, `w:pPrChange` holding its own `w:pPr`, a `>`
// inside an attribute value), so every structural query goes through this
// index instead: tags with byte ranges, parent links and matching closes.

import Foundation

public struct XMLTag: Equatable {
    public enum Kind: Equatable { case open, close, selfClosing }

    public let name: String
    public let kind: Kind
    /// Byte offset of the tag's `<`.
    public let start: Int
    /// Byte offset just past the tag's `>`.
    public let end: Int
    /// Bytes between the element name and the closing `>` (or `/>`).
    public let attributes: Range<Int>
    /// Index of the enclosing `.open` tag; nil at the top level.
    public internal(set) var parent: Int?
    /// `.open`: index of the matching `.close`. `.close`: index of the matching `.open`.
    public internal(set) var match: Int?
}

public enum XMLScanError: Error, Equatable, CustomStringConvertible {
    case unterminated(at: Int)
    case unexpectedClose(name: String, at: Int)
    case unclosed(name: String)
    case doctypeNotAllowed(at: Int)
    /// More nested elements than `XMLTagIndex.maxDepth` (#252).
    case tooDeep(limit: Int, at: Int)
    /// More tags than `XMLTagIndex.maxTags` (#252).
    case tooManyTags(limit: Int)

    public var description: String {
        switch self {
        case .tooDeep(let limit, let at): return "位元組 \(at) 的元素超過 \(limit) 層巢狀，拒絕處理"
        case .tooManyTags(let limit): return "XML 標籤超過 \(limit) 個，拒絕處理"
        case .doctypeNotAllowed(let at): return "位元組 \(at) 有 DOCTYPE 宣告（OPC 封裝的 part 不允許 DTD）"
        case .unterminated(let at): return "XML 標籤在位元組 \(at) 沒有結束"
        case .unexpectedClose(let name, let at): return "位元組 \(at) 的 </\(name)> 沒有對應的開始標籤"
        case .unclosed(let name): return "<\(name)> 沒有結束標籤"
        }
    }
}

public struct XMLTagIndex {
    public let bytes: [UInt8]
    public let tags: [XMLTag]
    /// Non-close tags by element name, in document order (#252).
    private let byName: [String: [Int]]
    /// Non-close tags carrying a `w14:paraId`, by its value, in document order (#252).
    private let byParaId: [String: [Int]]

    /// Deepest nesting accepted: Foundation's XMLParser (libxml2 without
    /// XML_PARSE_HUGE) accepts 257 nested elements and rejects 258, measured
    /// on macOS 27.3, so the scan refuses nothing the output check would have
    /// passed (#252). The value belongs to the platform's parser;
    /// `testOutputCheckParserAcceptsExactlyTheScanDepth` fails if it moves.
    public static let maxDepth = 257
    /// Most tags accepted, counting close tags. The index grows with the tag
    /// count however small the tags are. One measurement, not a bound: a
    /// 47 MB part at this limit, every paragraph with its own eight-digit
    /// `w14:paraId`, peaked at about 1.3 GB resident memory while the index
    /// was built; longer ids or attributes cost more (#252 verify R1, R2;
    /// PsychQuant/macdoc#265).
    public static let maxTags = 5_000_000

    public init(_ bytes: [UInt8], maxDepth: Int = XMLTagIndex.maxDepth, maxTags: Int = XMLTagIndex.maxTags) throws {
        self.bytes = bytes
        let tags = try Self.scan(bytes, maxDepth: maxDepth, maxTags: maxTags)
        self.tags = tags
        // One pass builds both tables, so a lookup no longer walks the part.
        var byName: [String: [Int]] = [:]
        var byParaId: [String: [Int]] = [:]
        for (i, tag) in tags.enumerated() where tag.kind != .close {
            byName[tag.name, default: []].append(i)
            if !tag.attributes.isEmpty, let id = Self.attribute("w14:paraId", in: tag.attributes, of: bytes) {
                byParaId[id, default: []].append(i)
            }
        }
        self.byName = byName
        self.byParaId = byParaId
    }

    public init(_ string: String) throws {
        try self.init(Array(string.utf8))
    }

    // MARK: Scanning

    private static func scan(_ b: [UInt8], maxDepth: Int, maxTags: Int) throws -> [XMLTag] {
        var tags: [XMLTag] = []
        var stack: [Int] = []
        let n = b.count
        var i = 0
        while i < n {
            guard b[i] == lt else { i += 1; continue }
            if has(b, "<!--", at: i) { i = try skip(b, past: "-->", from: i + 4, tagStart: i); continue }
            if has(b, "<![CDATA[", at: i) { i = try skip(b, past: "]]>", from: i + 9, tagStart: i); continue }
            if has(b, "<?", at: i) { i = try skip(b, past: "?>", from: i + 2, tagStart: i); continue }
            // OPC forbids DTD declarations in package parts, and a DOCTYPE with
            // an internal subset cannot be skipped by "next >"; refuse it.
            if has(b, "<!", at: i) { throw XMLScanError.doctypeNotAllowed(at: i) }

            let isClose = i + 1 < n && b[i + 1] == slash
            var j = i + (isClose ? 2 : 1)
            let nameStart = j
            while j < n, isNameByte(b[j]) { j += 1 }
            guard j > nameStart else { throw XMLScanError.unterminated(at: i) }
            let name = String(decoding: b[nameStart..<j], as: UTF8.self)
            let attrStart = j
            var quote: UInt8? = nil
            while j < n {
                let c = b[j]
                if let q = quote {
                    if c == q { quote = nil }
                } else if c == dquote || c == squote {
                    quote = c
                } else if c == gt {
                    break
                }
                j += 1
            }
            guard j < n else { throw XMLScanError.unterminated(at: i) }
            let selfClosing = !isClose && j > attrStart && b[j - 1] == slash
            let attrEnd = selfClosing ? j - 1 : j
            let end = j + 1
            let index = tags.count
            if index >= maxTags { throw XMLScanError.tooManyTags(limit: maxTags) }
            // An element's depth counts itself and every open ancestor.
            if !isClose && stack.count + 1 > maxDepth { throw XMLScanError.tooDeep(limit: maxDepth, at: i) }
            if isClose {
                guard let top = stack.last, tags[top].name == name else {
                    throw XMLScanError.unexpectedClose(name: name, at: i)
                }
                stack.removeLast()
                tags.append(XMLTag(name: name, kind: .close, start: i, end: end,
                                   attributes: attrStart..<attrEnd,
                                   parent: tags[top].parent, match: top))
                tags[top].match = index
            } else {
                tags.append(XMLTag(name: name, kind: selfClosing ? .selfClosing : .open,
                                   start: i, end: end, attributes: attrStart..<attrEnd,
                                   parent: stack.last, match: nil))
                if !selfClosing { stack.append(index) }
            }
            i = end
        }
        if let open = stack.last { throw XMLScanError.unclosed(name: tags[open].name) }
        return tags
    }

    private static let lt = UInt8(ascii: "<")
    private static let gt = UInt8(ascii: ">")
    private static let slash = UInt8(ascii: "/")
    private static let dquote = UInt8(ascii: "\"")
    private static let squote = UInt8(ascii: "'")

    private static func isNameByte(_ c: UInt8) -> Bool {
        (c >= 0x61 && c <= 0x7A) || (c >= 0x41 && c <= 0x5A) || (c >= 0x30 && c <= 0x39)
            || c == UInt8(ascii: ":") || c == UInt8(ascii: "_") || c == UInt8(ascii: "-")
            || c == UInt8(ascii: ".") || c >= 0x80
    }

    private static func has(_ b: [UInt8], _ marker: String, at i: Int) -> Bool {
        let m = Array(marker.utf8)
        guard i + m.count <= b.count else { return false }
        for k in 0..<m.count where b[i + k] != m[k] { return false }
        return true
    }

    private static func skip(_ b: [UInt8], past marker: String, from start: Int, tagStart: Int) throws -> Int {
        let m = Array(marker.utf8)
        var i = start
        while i + m.count <= b.count {
            if has(b, marker, at: i) { return i + m.count }
            i += 1
        }
        throw XMLScanError.unterminated(at: tagStart)
    }

    // MARK: Element queries

    /// `.open` or `.selfClosing` tag index → byte range of the whole element.
    public func elementRange(_ i: Int) -> Range<Int> {
        let tag = tags[i]
        if tag.kind == .open, let close = tag.match { return tag.start..<tags[close].end }
        return tag.start..<tag.end
    }

    /// Bytes between the opening and closing tag; empty for a self-closing tag.
    public func contentRange(_ i: Int) -> Range<Int> {
        let tag = tags[i]
        if tag.kind == .open, let close = tag.match { return tag.end..<tags[close].start }
        return tag.end..<tag.end
    }

    public func string(_ range: Range<Int>) -> String {
        String(decoding: bytes[range], as: UTF8.self)
    }

    public func elementString(_ i: Int) -> String { string(elementRange(i)) }

    /// The opening tag as written, e.g. `<w:r w:rsidR="00AB12CD">`.
    public func openingTagString(_ i: Int) -> String { string(tags[i].start..<tags[i].end) }

    /// Direct child elements (`.open` and `.selfClosing`), in document order.
    public func children(of i: Int) -> [Int] {
        guard tags[i].kind == .open, let close = tags[i].match else { return [] }
        var out: [Int] = []
        var k = i + 1
        while k < close {
            let tag = tags[k]
            switch tag.kind {
            case .open:
                out.append(k)
                k = (tag.match ?? k) + 1
            case .selfClosing:
                out.append(k)
                k += 1
            case .close:
                k += 1
            }
        }
        return out
    }

    public func child(of i: Int, named name: String) -> Int? {
        children(of: i).first { tags[$0].name == name }
    }

    /// Every element inside `i` (not `i` itself), in document order.
    public func descendants(of i: Int) -> [Int] {
        guard tags[i].kind == .open, let close = tags[i].match else { return [] }
        return ((i + 1)..<close).filter { tags[$0].kind != .close }
    }

    public func ancestor(of i: Int, named name: String) -> Int? {
        var current = tags[i].parent
        while let p = current {
            if tags[p].name == name { return p }
            current = tags[p].parent
        }
        return nil
    }

    /// Elements with this name anywhere in the part (`.open` and `.selfClosing`).
    public func elements(named name: String) -> [Int] {
        byName[name] ?? []
    }

    /// Elements named any of `names`, merged in document order; a name given
    /// twice does not list its elements twice.
    func elements(namedAnyOf names: some Sequence<String>) -> [Int] {
        Set(names).flatMap { byName[$0] ?? [] }.sorted()
    }

    /// Non-close tags whose `w14:paraId` decodes to `id`, in document order.
    func tags(withParaId id: String) -> [Int] {
        byParaId[id] ?? []
    }

    /// Value of an attribute in the element's opening tag, entity-decoded.
    public func attribute(_ name: String, of i: Int) -> String? {
        Self.attribute(name, in: tags[i].attributes, of: bytes)
    }

    /// The attribute parser behind `attribute(_:of:)`, usable while the index
    /// is being built.
    static func attribute(_ name: String, in range: Range<Int>, of b: [UInt8]) -> String? {
        guard !range.isEmpty else { return nil }
        var k = range.lowerBound
        let end = range.upperBound
        while k < end {
            while k < end, Self.isSpace(b[k]) { k += 1 }
            let nameStart = k
            while k < end, b[k] != UInt8(ascii: "="), !Self.isSpace(b[k]) { k += 1 }
            let attrName = String(decoding: b[nameStart..<k], as: UTF8.self)
            while k < end, Self.isSpace(b[k]) { k += 1 }
            guard k < end, b[k] == UInt8(ascii: "=") else { return nil }
            k += 1
            while k < end, Self.isSpace(b[k]) { k += 1 }
            guard k < end, b[k] == Self.dquote || b[k] == Self.squote else { return nil }
            let quote = b[k]
            k += 1
            let valueStart = k
            while k < end, b[k] != quote { k += 1 }
            let value = String(decoding: b[valueStart..<min(k, end)], as: UTF8.self)
            k += 1
            if attrName == name { return XMLText.decode(value) }
        }
        return nil
    }

    private static func isSpace(_ c: UInt8) -> Bool {
        c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D
    }

    /// Character content of an element that holds text only (such as `w:t`):
    /// character data is entity-decoded, CDATA sections are taken literally
    /// without their markers, comments and processing instructions are dropped.
    public func text(of i: Int) -> String {
        let range = contentRange(i)
        var out = ""
        var k = range.lowerBound
        var runStart = k
        func flush(_ end: Int) {
            if end > runStart { out += XMLText.decode(string(runStart..<end)) }
        }
        while k < range.upperBound {
            if Self.has(bytes, "<![CDATA[", at: k), let close = Self.find(bytes, "]]>", from: k + 9, before: range.upperBound) {
                flush(k)
                out += string((k + 9)..<close)
                k = close + 3
                runStart = k
            } else if Self.has(bytes, "<!--", at: k), let close = Self.find(bytes, "-->", from: k + 4, before: range.upperBound) {
                flush(k)
                k = close + 3
                runStart = k
            } else if Self.has(bytes, "<?", at: k), let close = Self.find(bytes, "?>", from: k + 2, before: range.upperBound) {
                flush(k)
                k = close + 2
                runStart = k
            } else {
                k += 1
            }
        }
        flush(range.upperBound)
        return out
    }

    private static func find(_ b: [UInt8], _ marker: String, from start: Int, before end: Int) -> Int? {
        let m = Array(marker.utf8)
        var i = start
        while i + m.count <= end {
            if has(b, marker, at: i) { return i }
            i += 1
        }
        return nil
    }
}

/// XML 1.0 text helpers shared by the scanner and the operations.
public enum XMLText {
    /// Replaces the five predefined entities and well-formed character
    /// references. The text is walked as Unicode scalars, the units an XML
    /// parser reads: a combining mark after `&` or `;` would otherwise join it
    /// into one Character and hide it (#252 verify R1). The walk moves over
    /// the string's own scalar view and copies the text between references in
    /// slices, so decoding allocates only the output (#252 verify R2).
    public static func decode(_ s: String) -> String {
        guard s.utf8.contains(UInt8(ascii: "&")) else { return s }
        let view = s.unicodeScalars
        var out = String.UnicodeScalarView()
        var rest = view[...]
        while let amp = rest.firstIndex(of: "&") {
            out.append(contentsOf: rest[..<amp])
            let nameStart = view.index(after: amp)
            guard let semi = view[nameStart...].firstIndex(of: ";") else {
                out.append(contentsOf: view[amp...])
                return String(out)
            }
            if let decoded = decodeEntity(view[nameStart..<semi]) {
                out.append(contentsOf: decoded.unicodeScalars)
            } else {
                out.append(contentsOf: view[amp...semi])
            }
            rest = view[view.index(after: semi)...]
        }
        out.append(contentsOf: rest)
        return String(out)
    }

    private static let predefinedEntities: [(name: String, value: String)] = [
        ("amp", "&"), ("lt", "<"), ("gt", ">"), ("quot", "\""), ("apos", "'"),
    ]

    private static func decodeEntity(_ e: Substring.UnicodeScalarView) -> String? {
        if let entity = predefinedEntities.first(where: { e.elementsEqual($0.name.unicodeScalars) }) {
            return entity.value
        }
        // A character reference is `#` and ASCII decimal digits, or `#x`
        // (lowercase only, as XML 1.0 CharRef has it) and ASCII hex digits,
        // naming a character the XML 1.0 Char production allows. Anything
        // else (`#X`, a sign, an empty number, a control character, a
        // surrogate, a value past UInt32) is not one and stays as written, as
        // an XML parser would refuse it (#252). Digits are accumulated in
        // place, so a long run of them allocates nothing.
        var digits = e
        guard digits.first == "#" else { return nil }
        digits = digits.dropFirst()
        var radix: UInt32 = 10
        if digits.first == "x" { radix = 16; digits = digits.dropFirst() }
        guard !digits.isEmpty else { return nil }
        var value: UInt32 = 0
        for d in digits {
            let digit: UInt32
            switch d {
            case "0"..."9": digit = d.value - 0x30
            case "a"..."f" where radix == 16: digit = d.value - 0x61 + 10
            case "A"..."F" where radix == 16: digit = d.value - 0x41 + 10
            default: return nil
            }
            let (shifted, o1) = value.multipliedReportingOverflow(by: radix)
            let (sum, o2) = shifted.addingReportingOverflow(digit)
            if o1 || o2 { return nil }
            value = sum
        }
        guard let scalar = Unicode.Scalar(value) else { return nil }
        let decoded = String(Character(scalar))
        return isAllowed(decoded) ? decoded : nil
    }

    public static func escapeText(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.utf8.count)
        for ch in s.unicodeScalars {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            default: out.unicodeScalars.append(ch)
            }
        }
        return out
    }

    public static func escapeAttribute(_ s: String) -> String {
        var out = ""
        for ch in s.unicodeScalars {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&apos;"
            default: out.unicodeScalars.append(ch)
            }
        }
        return out
    }

    /// True when every character is allowed by XML 1.0 (`Char` production).
    public static func isAllowed(_ s: String) -> Bool {
        s.unicodeScalars.allSatisfy { c in
            let v = c.value
            return v == 0x9 || v == 0xA || v == 0xD
                || (0x20...0xD7FF).contains(v)
                || (0xE000...0xFFFD).contains(v)
                || (0x10000...0x10FFFF).contains(v)
        }
    }
}
