// FormEditing.swift — byte-range splicing and element-fragment rewriting used
// by the form operations (macdoc#249).
//
// Every edit is a byte range in the current part plus a replacement string.
// A batch of non-overlapping edits is applied from the end backwards and the
// tag index is rebuilt once, so nothing outside the edited ranges changes.

import Foundation

public enum FormError: Error, Equatable, CustomStringConvertible {
    case paragraphNotFound(String)
    case paragraphAmbiguous(String, count: Int)
    case notOnParagraph(String, carrier: String)
    case notInTableCell(String)
    case noOwnNumbering(String)
    case onlyParagraphInCell(String)
    case cellWouldEndWithoutParagraph(String)
    case conflictingOperations(String, detail: String)
    case carriesSectionBreak(String)
    case notBodyChild(String)
    case firstBodyChild(String)
    case noFieldSize
    case invalidFieldSize(String)
    case invalidText(String)
    case invalidFont(String)
    case malformedPart(String)
    case malformedResult(String)

    public var description: String {
        switch self {
        case .paragraphNotFound(let id):
            return "找不到段落 \(id)（沒有任何 w:p 帶這個 w14:paraId）"
        case .paragraphAmbiguous(let id, let count):
            return "段落 \(id) 出現在 \(count) 個 w:p 上，無法確定是哪一個"
        case .notOnParagraph(let id, let carrier):
            return "\(id) 不是段落的 id，它在 <\(carrier)> 上"
        case .notInTableCell(let id):
            return "段落 \(id) 不在表格儲存格內，不能用 --field"
        case .noOwnNumbering(let id):
            return "段落 \(id) 沒有自己的清單編號（w:numPr），不能用 --tick-list"
        case .onlyParagraphInCell(let id):
            return "段落 \(id) 是儲存格裡唯一的段落，刪掉它會讓儲存格失效"
        case .cellWouldEndWithoutParagraph(let id):
            return "刪掉段落 \(id) 後，所在儲存格會以表格結尾；Word 要求儲存格最後一個元素是段落"
        case .conflictingOperations(let id, let detail):
            return "段落 \(id) 同時被互相衝突的操作點名：\(detail)"
        case .carriesSectionBreak(let id):
            return "段落 \(id) 帶有分節符（w:sectPr），刪掉它會改變分節設定"
        case .notBodyChild(let id):
            return "段落 \(id) 不是 w:body 的直屬段落（可能在表格或內容控制項裡），不能用 --truncate-from"
        case .firstBodyChild(let id):
            return "段落 \(id) 是本文第一個元素，從這裡截斷會刪掉整份本文"
        case .noFieldSize:
            return "指定的填寫欄都沒有明確字級，無法決定統一字級；請用 --field-size 指定（單位 pt）"
        case .invalidFieldSize(let value):
            return "無效的 --field-size: \(value)（須為 1 到 1638 之間、以 0.5 為單位的點數）"
        case .invalidText(let id):
            return "--insert-after \(id) 的文字含有 XML 1.0 不允許的字元"
        case .invalidFont(let value):
            return "無效的 --checkbox-font: \(value)（字型名稱不能是空的，也不能含 XML 1.0 不允許的字元）"
        case .malformedPart(let detail):
            return "word/document.xml 不是可解析的 XML：\(detail)"
        case .malformedResult(let detail):
            return "整理後的 word/document.xml 不是合格的 XML（未寫出任何檔案）：\(detail)"
        }
    }
}

struct Edit {
    let range: Range<Int>
    let replacement: String

    static func insert(_ s: String, at offset: Int) -> Edit { Edit(range: offset..<offset, replacement: s) }
    static func replace(_ range: Range<Int>, with s: String) -> Edit { Edit(range: range, replacement: s) }
    static func remove(_ range: Range<Int>) -> Edit { Edit(range: range, replacement: "") }
}

struct XMLEditor {
    private(set) var index: XMLTagIndex
    var bytes: [UInt8] { index.bytes }

    init(_ bytes: [UInt8]) throws {
        do {
            index = try XMLTagIndex(bytes)
        } catch let error as XMLScanError {
            throw FormError.malformedPart(error.description)
        }
    }

    /// Applies non-overlapping edits. Ties at the same offset apply the
    /// replacement first and the zero-length insert after it, so an insert
    /// lands before the replaced element.
    mutating func apply(_ edits: [Edit]) throws {
        guard !edits.isEmpty else { return }
        let ascending = edits.sorted {
            $0.range.lowerBound != $1.range.lowerBound
                ? $0.range.lowerBound < $1.range.lowerBound
                : $0.range.isEmpty && !$1.range.isEmpty
        }
        for (a, b) in zip(ascending, ascending.dropFirst()) where a.range.upperBound > b.range.lowerBound {
            throw FormError.malformedResult("overlapping edits \(a.range) and \(b.range)")
        }
        var out = index.bytes
        for edit in ascending.reversed() {
            out.replaceSubrange(edit.range, with: Array(edit.replacement.utf8))
        }
        do {
            index = try XMLTagIndex(out)
        } catch let error as XMLScanError {
            throw FormError.malformedResult(error.description)
        }
    }
}

/// Rewrites a single element given as an XML fragment string. Used for small
/// property elements (`w:pPr`, `w:rPr`, `w:tcPr`) so a change to one property
/// becomes one replacement of the element's byte range.
enum Fragment {
    // ECMA-376 child order: the elements that must come AFTER the one being inserted.
    static let afterJc = ["w:textDirection", "w:textAlignment", "w:textboxTightWrap", "w:outlineLvl",
                          "w:divId", "w:cnfStyle", "w:rPr", "w:sectPr", "w:pPrChange"]
    static let afterParagraphMarkRPr = ["w:sectPr", "w:pPrChange"]
    static let afterSize = ["w:highlight", "w:u", "w:effect", "w:bdr", "w:shd", "w:fitText", "w:vertAlign",
                            "w:rtl", "w:cs", "w:em", "w:lang", "w:eastAsianLayout", "w:specVanish",
                            "w:oMath", "w:rPrChange"]
    static let afterRFonts = ["w:b", "w:bCs", "w:i", "w:iCs", "w:caps", "w:smallCaps", "w:strike",
                              "w:dstrike", "w:outline", "w:shadow", "w:emboss", "w:imprint", "w:noProof",
                              "w:snapToGrid", "w:vanish", "w:webHidden", "w:color", "w:spacing", "w:w",
                              "w:kern", "w:position", "w:sz", "w:szCs"] + afterSize
    static let afterVAlign = ["w:hideMark", "w:headers", "w:cellIns", "w:cellDel", "w:cellMerge", "w:tcPrChange"]

    /// Removes the root's direct children named in `removing`, then inserts
    /// `snippet` before the first remaining direct child named in `followers`
    /// (or before the root's closing tag). A self-closing root is expanded.
    static func setChild(_ fragment: String, removing: Set<String>, insert snippet: String,
                         followers: [String]) throws -> String {
        let index = try XMLTagIndex(fragment)
        guard let root = index.tags.indices.first else { return fragment }
        let tag = index.tags[root]
        if tag.kind == .selfClosing {
            let head = index.string(tag.start..<tag.attributes.upperBound)
            return head + ">" + snippet + "</" + tag.name + ">"
        }
        var edits: [Edit] = index.children(of: root)
            .filter { removing.contains(index.tags[$0].name) }
            .map { .remove(index.elementRange($0)) }
        let followerSet = Set(followers)
        let survivors = index.children(of: root).filter { !removing.contains(index.tags[$0].name) }
        // Extension elements (w14:, w15:, …) come after every schema element,
        // so they follow whatever is inserted whenever there is an order to keep.
        let position = survivors.first {
            let name = index.tags[$0].name
            return followerSet.contains(name) || (!followers.isEmpty && !name.hasPrefix("w:"))
        }
            .map { index.tags[$0].start }
            ?? index.tags[tag.match!].start
        if !snippet.isEmpty { edits.append(.insert(snippet, at: position)) }
        var editor = try XMLEditor(index.bytes)
        try editor.apply(edits)
        return String(decoding: editor.bytes, as: UTF8.self)
    }

    /// Removes the root's direct children named in `removing`.
    static func removeChildren(_ fragment: String, named removing: Set<String>) throws -> String {
        try setChild(fragment, removing: removing, insert: "", followers: [])
    }

    /// The direct child named `name` of the fragment root, as a string.
    static func child(_ fragment: String, named name: String) throws -> String? {
        let index = try XMLTagIndex(fragment)
        guard let root = index.tags.indices.first else { return nil }
        return index.child(of: root, named: name).map { index.elementString($0) }
    }

    /// Replaces the root's direct child named `name` with `transform(child)`,
    /// or inserts `transform(nil)` before the first follower when absent.
    static func updateChild(_ fragment: String, named name: String, followers: [String],
                            _ transform: (String?) throws -> String) throws -> String {
        let index = try XMLTagIndex(fragment)
        guard let root = index.tags.indices.first else { return fragment }
        if let existing = index.child(of: root, named: name) {
            var editor = try XMLEditor(index.bytes)
            try editor.apply([.replace(index.elementRange(existing), with: try transform(index.elementString(existing)))])
            return String(decoding: editor.bytes, as: UTF8.self)
        }
        return try setChild(fragment, removing: [], insert: try transform(nil), followers: followers)
    }

    static func sizeElements(_ halfPoints: Int) -> String {
        "<w:sz w:val=\"\(halfPoints)\"/><w:szCs w:val=\"\(halfPoints)\"/>"
    }

    /// A run or paragraph-mark `w:rPr` with `w:sz`/`w:szCs` set.
    static func rPrWithSize(_ rPr: String?, halfPoints: Int) throws -> String {
        guard let rPr else { return "<w:rPr>" + sizeElements(halfPoints) + "</w:rPr>" }
        return try setChild(rPr, removing: ["w:sz", "w:szCs"], insert: sizeElements(halfPoints), followers: afterSize)
    }

    /// A run `w:rPr` with `w:rFonts` replaced by one font for all four scripts.
    static func rPrWithFont(_ rPr: String?, font: String) throws -> String {
        let f = XMLText.escapeAttribute(font)
        let fonts = "<w:rFonts w:ascii=\"\(f)\" w:hAnsi=\"\(f)\" w:eastAsia=\"\(f)\" w:cs=\"\(f)\"/>"
        guard let rPr else { return "<w:rPr>" + fonts + "</w:rPr>" }
        return try setChild(rPr, removing: ["w:rFonts"], insert: fonts, followers: afterRFonts)
    }
}
