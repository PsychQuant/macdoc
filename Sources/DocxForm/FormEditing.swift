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
    /// Several `--remove` paragraphs that each could go alone but together
    /// take every paragraph of one cell or text box (#253 verify R2).
    case removalsLeaveNoParagraph([String])
    /// Several `--remove` paragraphs after the last block that stays, whose
    /// removal together leaves a cell or text box ending with a table.
    case removalsEndWithoutParagraph([String])
    /// A range marker that would be kept, where the marker itself, an element
    /// removed around it, or the paragraph it would move into is or carries
    /// Markup Compatibility markup (#253 verify R4, R5).
    case markerUnderCompatibilityRules(String)
    /// Every content block before the `--truncate-from` paragraph is named by
    /// `--remove` (#253 verify R4).
    case removalsLeaveNothingBeforeCut(String)
    /// `--remove-table` named a paragraph that is in no table (#250).
    case notInTable(String)
    /// `--remove-table` named a paragraph whose nearest table is not a
    /// body-level block (a nested table, or one in a text box) (#250).
    case tableNotBodyLevel(String)
    /// `--remove-table` named a paragraph inside a text box that sits in a
    /// table; the table around the text box is not the paragraph's table
    /// (#250 verify R1).
    case inTextBox(String)
    /// `--remove-table` named a paragraph whose table holds a paragraph with
    /// its own section break (#250 verify R1); named by the caller's id.
    case tableCarriesSectionBreak(String)
    /// The deletions leave two tables adjacent that something other than a
    /// table separated before; Word would join them (#250). Names, in
    /// document order, what is deleted between them.
    case tablesWouldJoin([String])
    /// The deletions take every content block of the body (#250).
    case removalsLeaveEmptyBody([String])
    /// The deletions leave the last section with no content: the last kept
    /// block carries its own section break and the body has its own final
    /// section properties (#250).
    case lastSectionWouldBeEmpty([String])
    /// `--table-defaults` written in a form the parser does not accept
    /// (#250 requirement 1); carries the value as written.
    case invalidTableDefaults(String, detail: String)
    /// `--table-defaults` named a paragraph that is in no table.
    case tableDefaultsNotInTable(String)
    /// `--table-defaults` named a paragraph in a text box inside a table.
    case tableDefaultsInTextBox(String)
    /// The named table's grid cannot be read (see `TableGrid.Unreadable`).
    case tableGridUnreadable(String, detail: String)
    /// A column or row number beyond the named table.
    case tableSelectionOutOfRange(String, detail: String)
    /// No cell lies wholly inside the selection.
    case noFillCells(String)
    /// A paragraph with content in a selected fill cell carries no `w14:paraId`.
    case fillCellWithoutParaId(String, cell: String)
    /// Every fill cell of the selection is one that cannot be named (no
    /// paragraph, or only empty paragraphs without an id) (verify R1).
    case noTidyableFillCells(String, cells: [String])
    /// A `GridSelection` built directly, not through the parser, with an
    /// empty list, a number below 1 or a reversed range (verify R1).
    case invalidGridSelection(String)
    case conflictingOperations(String, detail: String)
    case carriesSectionBreak(String)
    case splitsField(String)
    case splitsComment(String)
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
        case .removalsLeaveNoParagraph(let ids):
            return "段落 \(ids.joined(separator: "、")) 是所在儲存格（或文字方塊）裡全部的段落，一起刪掉會讓它失效；請至少留下一段"
        case .removalsEndWithoutParagraph(let ids):
            return "一起刪掉段落 \(ids.joined(separator: "、")) 後，所在儲存格（或文字方塊）會以表格結尾；Word 要求最後一個元素是段落，請至少留下表格之後的一段"
        case .markerUnderCompatibilityRules(let id):
            return "從段落 \(id) 刪除的範圍裡有要保留的範圍標記（書籤等），但標記本身、它外層被刪的元素或要移入的段落帶有 Markup Compatibility 標記（mc:Ignorable 等屬性，或 mc:AlternateContent 這類元素，Word 的文字方塊就包在裡面）；搬移會改變這些規則套用的對象，因此不刪。請把標記的另一半也列入刪除範圍，或先在 Word 裡移除這個標記"
        case .removalsLeaveNothingBeforeCut(let id):
            return "從段落 \(id) 截斷時，它之前的內容都列在 --remove 裡，刪完後本文不會留下任何內容"
        case .notInTable(let id):
            return "段落 \(id) 不在表格裡，不能用 --remove-table"
        case .inTextBox(let id):
            return "段落 \(id) 在文字方塊裡，文字方塊外面的表格不算它的表格，不能用 --remove-table；請點名表格儲存格本身的段落"
        case .tableCarriesSectionBreak(let id):
            return "段落 \(id) 所在的表格裡有段落帶有分節符（w:sectPr），刪掉表格會改變分節設定"
        case .tableNotBodyLevel(let id):
            return "段落 \(id) 所在的表格不是本文層的表格（巢狀在儲存格或文字方塊裡），不能用 --remove-table"
        case .tablesWouldJoin(let ids):
            return "刪掉 \(ids.joined(separator: "、")) 後，前後兩張表格會緊鄰，Word 會把它們併成一張；請至少留下兩張表之間的一段，或改用 --remove-table 刪掉其中一張表"
        case .removalsLeaveEmptyBody(let ids):
            return "刪掉 \(ids.joined(separator: "、")) 後，本文不會留下任何內容；請至少留下一段"
        case .lastSectionWouldBeEmpty(let ids):
            return "刪掉 \(ids.joined(separator: "、")) 後，最後一節沒有任何內容（保留的最後一段帶有分節符），Word 會多出一頁空白；請留下分節符之後的一段，或改用 --truncate-from"
        case .invalidTableDefaults(let value, let detail):
            return "無效的 --table-defaults: \(value)（\(detail)）。格式為 <paraId>=col:<欄>、<paraId>=row:<列> 或 <paraId>=col:<欄>/row:<列>；欄列號從 1 開始，以逗號分隔，可寫範圍，例如 col:2,4-5 或 row:3-"
        case .tableDefaultsNotInTable(let id):
            return "段落 \(id) 不在表格裡，不能用 --table-defaults"
        case .tableDefaultsInTextBox(let id):
            return "段落 \(id) 在文字方塊裡，文字方塊外面的表格不算它的表格，不能用 --table-defaults；請點名表格儲存格本身的段落"
        case .tableGridUnreadable(let id, let detail):
            return "段落 \(id) 所在表格的欄列位置無法判讀：\(detail)；請改用 --field 逐欄點名"
        case .tableSelectionOutOfRange(let id, let detail):
            return "--table-defaults \(id) 點名了\(detail)。欄號是格線欄，可用 macdoc word form classify --grid 查看每一格的欄列範圍"
        case .noFillCells(let id):
            return "--table-defaults \(id) 沒有選到任何填寫欄：沒有一格整個落在點名的欄列之內。可用 macdoc word form classify --grid 查看每一格的欄列範圍"
        case .fillCellWithoutParaId(let id, let cell):
            return "--table-defaults \(id) 選到的儲存格 \(cell) 裡有內容的段落沒有 w14:paraId，無法定位；請先用 Word 存一次檔（Word 會補上 paraId）"
        case .noTidyableFillCells(let id, let cells):
            return "--table-defaults \(id) 選到的填寫欄 \(cells.joined(separator: "、")) 都沒有可以定位的段落（沒有段落，或只有空段落且沒有 w14:paraId），沒有任何一格可以處理"
        case .invalidGridSelection(let detail):
            return "無效的欄列選取：\(detail)"
        case .conflictingOperations(let id, let detail):
            return "段落 \(id) 同時被互相衝突的操作點名：\(detail)"
        case .carriesSectionBreak(let id):
            return "段落 \(id) 帶有分節符（w:sectPr），刪掉它會改變分節設定"
        case .splitsField(let id):
            return "從段落 \(id) 刪除的範圍只含一個欄位（w:fldChar 的開頭、分隔、結尾）的一部分，刪掉會讓欄位斷掉；請把開頭、分隔、結尾所在的段落都列入 --remove（或一起截斷），或先在 Word 裡把欄位轉成一般文字"
        case .splitsComment(let id):
            return "從段落 \(id) 刪除的範圍含有註解的引用（w:commentReference），但這個註解的範圍標記留在範圍外；刪掉會讓註解失去錨點。請把註解範圍所在的段落一起列入 --remove，或先在 Word 裡刪除或移動這個註解"
        case .notBodyChild(let id):
            return "段落 \(id) 不是 w:body 的直屬段落（可能在表格或內容控制項裡），不能用 --truncate-from"
        case .firstBodyChild(let id):
            return "段落 \(id) 之前沒有任何內容（是本文第一個元素，或前面只有書籤之類的標記），從這裡截斷會刪掉整份本文"
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
