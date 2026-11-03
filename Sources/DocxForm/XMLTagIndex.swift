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

    public var description: String {
        switch self {
        case .unterminated(let at): return "XML 標籤在位元組 \(at) 沒有結束"
        case .unexpectedClose(let name, let at): return "位元組 \(at) 的 </\(name)> 沒有對應的開始標籤"
        case .unclosed(let name): return "<\(name)> 沒有結束標籤"
        }
    }
}

public struct XMLTagIndex {
    public let bytes: [UInt8]
    public let tags: [XMLTag]

    public init(_ bytes: [UInt8]) throws {
        self.bytes = bytes
        self.tags = try Self.scan(bytes)
    }

    public init(_ string: String) throws {
        try self.init(Array(string.utf8))
    }

    // MARK: Scanning

    private static func scan(_ b: [UInt8]) throws -> [XMLTag] {
        var tags: [XMLTag] = []
        var stack: [Int] = []
        let n = b.count
        var i = 0
        while i < n {
            guard b[i] == lt else { i += 1; continue }
            if has(b, "<!--", at: i) { i = try skip(b, past: "-->", from: i + 4, tagStart: i); continue }
            if has(b, "<![CDATA[", at: i) { i = try skip(b, past: "]]>", from: i + 9, tagStart: i); continue }
            if has(b, "<?", at: i) { i = try skip(b, past: "?>", from: i + 2, tagStart: i); continue }
            if has(b, "<!", at: i) { i = try skip(b, past: ">", from: i + 2, tagStart: i); continue }

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
        tags.indices.filter { tags[$0].kind != .close && tags[$0].name == name }
    }

    /// Value of an attribute in the element's opening tag, entity-decoded.
    public func attribute(_ name: String, of i: Int) -> String? {
        let range = tags[i].attributes
        guard !range.isEmpty else { return nil }
        let b = bytes
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

    /// Entity-decoded character content of an element that holds text only
    /// (such as `w:t` or `w:instrText`).
    public func text(of i: Int) -> String {
        XMLText.decode(string(contentRange(i)))
    }
}

/// XML 1.0 text helpers shared by the scanner and the operations.
public enum XMLText {
    public static func decode(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var out = ""
        var rest = Substring(s)
        while let amp = rest.firstIndex(of: "&") {
            out += rest[rest.startIndex..<amp]
            guard let semi = rest[amp...].firstIndex(of: ";") else {
                out += rest[amp...]
                return out
            }
            let entity = rest[rest.index(after: amp)..<semi]
            if let decoded = decodeEntity(entity) {
                out += decoded
            } else {
                out += rest[amp...semi]
            }
            rest = rest[rest.index(after: semi)...]
        }
        out += rest
        return out
    }

    private static func decodeEntity(_ e: Substring) -> String? {
        switch e {
        case "amp": return "&"
        case "lt": return "<"
        case "gt": return ">"
        case "quot": return "\""
        case "apos": return "'"
        default:
            guard e.hasPrefix("#") else { return nil }
            let digits = e.dropFirst()
            let value: UInt32?
            if digits.hasPrefix("x") || digits.hasPrefix("X") {
                value = UInt32(digits.dropFirst(), radix: 16)
            } else {
                value = UInt32(digits, radix: 10)
            }
            guard let v = value, let scalar = Unicode.Scalar(v) else { return nil }
            return String(Character(scalar))
        }
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
