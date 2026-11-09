// TableGrid.swift — a table's cells as rectangles on its grid (macdoc#250
// requirement 1, `--table-defaults`).
//
// The number of `w:tc` in a row changes with merged cells, so "the second
// cell of a row" is no coordinate across rows. The grid columns of
// `w:tblGrid` are: a row starts after `w:gridBefore` grid columns, each cell
// covers `w:gridSpan` of them, and a vertically merged cell (`w:vMerge`)
// covers every row its continuation cells sit in. Rows and cells are counted
// through content-control and custom-XML wrappers. Anything that cannot be
// read this way is refused, never guessed (closed list in `Unreadable`).

import Foundation

struct TableGrid {
    /// One cell that holds content: a plain cell, or the first cell of a
    /// vertical merge. Rows and columns count from 1.
    struct Cell: Equatable {
        /// The cell's `w:tc` tag.
        let tc: Int
        let rows: ClosedRange<Int>
        let columns: ClosedRange<Int>

        /// `r2c3`, or `r2-4c2-3` for a merged cell.
        var label: String { TableGrid.label(rows: rows, columns: columns) }
    }

    /// The grid cannot be read: a span or offset that is not a valid number
    /// (or that overflows), the legacy `w:hMerge`, an unknown `w:vMerge`
    /// value, or a continuation cell with no merged cell of the same columns
    /// directly above it.
    struct Unreadable: Error, Equatable {
        let detail: String
    }

    let table: Int
    /// Cells with content, in document order. Continuation cells are not
    /// listed; `cell(containing:)` maps them to the cell they continue.
    let cells: [Cell]
    /// Widest row, in grid columns.
    let columnCount: Int
    let rowCount: Int
    private let owner: [Int: Int]

    init(table: Int, in index: XMLTagIndex) throws {
        self.table = table
        let rows = Self.flatten(index.children(of: table), keeping: "w:tr", in: index)
        var cells: [Cell] = []
        var rowEnds: [Int] = []
        var owner: [Int: Int] = [:]
        var mergeable: [ClosedRange<Int>: Int] = [:]
        var width = 0
        for (offset, tr) in rows.enumerated() {
            let r = offset + 1
            let (first, overflow) = try Self.gridBefore(of: tr, row: r, in: index).addingReportingOverflow(1)
            guard !overflow else { throw Unreadable(detail: "第 \(r) 列的 w:gridBefore 超出可計算的範圍") }
            var column = first
            var nextMergeable: [ClosedRange<Int>: Int] = [:]
            for tc in Self.flatten(index.children(of: tr), keeping: "w:tc", in: index) {
                let span = try Self.gridSpan(of: tc, row: r, in: index)
                let (last, overflow) = column.addingReportingOverflow(span - 1)
                guard !overflow, last < Int.max else {
                    throw Unreadable(detail: "第 \(r) 列的欄位數超出可計算的範圍")
                }
                let columns = column...last
                switch try Self.verticalMerge(of: tc, at: Self.label(rows: r...r, columns: columns), in: index) {
                case .none:
                    owner[tc] = cells.count
                    cells.append(Cell(tc: tc, rows: r...r, columns: columns))
                    rowEnds.append(r)
                case .restart:
                    owner[tc] = cells.count
                    nextMergeable[columns] = cells.count
                    cells.append(Cell(tc: tc, rows: r...r, columns: columns))
                    rowEnds.append(r)
                case .continuation:
                    guard let k = mergeable[columns] else {
                        throw Unreadable(detail: "\(Self.label(rows: r...r, columns: columns)) 是垂直合併的延續格，但上一列沒有欄位範圍相同的合併格")
                    }
                    owner[tc] = k
                    nextMergeable[columns] = k
                    rowEnds[k] = r
                }
                column = last + 1
            }
            width = max(width, column - 1)
            mergeable = nextMergeable
        }
        self.cells = cells.enumerated().map { k, cell in
            Cell(tc: cell.tc, rows: cell.rows.lowerBound...rowEnds[k], columns: cell.columns)
        }
        self.columnCount = width
        self.rowCount = rows.count
        self.owner = owner
    }

    /// The cell a `w:tc` belongs to: itself, or for a continuation cell the
    /// merged cell it continues.
    func cell(containing tc: Int) -> Cell? {
        owner[tc].map { cells[$0] }
    }

    static func label(rows: ClosedRange<Int>, columns: ClosedRange<Int>) -> String {
        "r\(span(rows))c\(span(columns))"
    }

    private static func span(_ range: ClosedRange<Int>) -> String {
        range.count == 1 ? "\(range.lowerBound)" : "\(range.lowerBound)-\(range.upperBound)"
    }

    // MARK: Reading the grid

    private enum VerticalMerge { case none, restart, continuation }

    /// Elements named `name` among `elements`, looking through content
    /// controls and custom XML, in document order.
    private static func flatten(_ elements: [Int], keeping name: String, in index: XMLTagIndex) -> [Int] {
        var out: [Int] = []
        for e in elements {
            switch index.tags[e].name {
            case name: out.append(e)
            case "w:sdt":
                out += flatten(index.children(of: e).filter { index.tags[$0].name == "w:sdtContent" }, keeping: name, in: index)
            case "w:sdtContent", "w:customXml": out += flatten(index.children(of: e), keeping: name, in: index)
            default: break
            }
        }
        return out
    }

    private static func gridBefore(of tr: Int, row: Int, in index: XMLTagIndex) throws -> Int {
        guard let trPr = index.child(of: tr, named: "w:trPr"),
              let element = index.child(of: trPr, named: "w:gridBefore") else { return 0 }
        guard let value = index.attribute("w:val", of: element).flatMap(number), value >= 0 else {
            throw Unreadable(detail: "第 \(row) 列的 w:gridBefore 不是非負整數")
        }
        return value
    }

    private static func gridSpan(of tc: Int, row: Int, in index: XMLTagIndex) throws -> Int {
        guard let tcPr = index.child(of: tc, named: "w:tcPr") else { return 1 }
        if index.child(of: tcPr, named: "w:hMerge") != nil {
            throw Unreadable(detail: "第 \(row) 列有舊式的水平合併（w:hMerge）")
        }
        guard let element = index.child(of: tcPr, named: "w:gridSpan") else { return 1 }
        guard let value = index.attribute("w:val", of: element).flatMap(number), value >= 1 else {
            throw Unreadable(detail: "第 \(row) 列有 w:gridSpan 不是正整數的儲存格")
        }
        return value
    }

    private static func verticalMerge(of tc: Int, at label: String, in index: XMLTagIndex) throws -> VerticalMerge {
        guard let tcPr = index.child(of: tc, named: "w:tcPr"),
              let element = index.child(of: tcPr, named: "w:vMerge") else { return .none }
        switch index.attribute("w:val", of: element) {
        case nil, "continue": return .continuation
        case "restart": return .restart
        default: throw Unreadable(detail: "\(label) 的 w:vMerge 值無法辨識")
        }
    }

    /// ASCII digits only; nil for anything else or a value too large for Int.
    private static func number(_ raw: String) -> Int? {
        guard !raw.isEmpty, raw.utf8.allSatisfy({ (0x30...0x39).contains($0) }) else { return nil }
        return Int(raw)
    }
}
