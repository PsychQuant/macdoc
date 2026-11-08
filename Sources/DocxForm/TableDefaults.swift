// TableDefaults.swift — `--table-defaults <paraId>=col:…/row:…` (macdoc#250
// requirement 1).
//
// The caller names a table (by any of its paragraphs) and its fill columns,
// rows, or both, on the table's grid (see `TableGrid`). The tool does not
// guess which cells are fill cells: a cell lying wholly inside the selection
// is one, a cell wholly outside is a label cell and is left alone, and a cell
// only partly inside is left alone and reported. Each fill cell's paragraphs
// are then tidied exactly as `--field` tidies one paragraph.

import Foundation

/// The columns or rows one `--table-defaults` names, counted from 1.
public struct GridSelection: Equatable {
    public enum Item: Equatable {
        /// `N`
        case single(Int)
        /// `A-B`
        case range(Int, Int)
        /// `A-`: from A to the last column or row.
        case from(Int)
    }

    public let items: [Item]

    /// Refuses what the parser refuses (verify R1): an empty list, a number
    /// below 1, and a range whose start is past its end. A selection that
    /// exists is therefore always safe to turn into ranges.
    public init(items: [Item]) throws {
        guard !items.isEmpty else { throw FormError.invalidGridSelection("清單是空的") }
        for item in items {
            switch item {
            case .single(let n) where n < 1, .from(let n) where n < 1:
                throw FormError.invalidGridSelection("欄列號從 1 開始，\(n) 不合法")
            case .range(let a, let b) where a < 1 || a > b:
                throw FormError.invalidGridSelection("範圍 \(a)-\(b) 不合法（須從 1 開始，起點不大於終點）")
            default:
                continue
            }
        }
        self.items = items
    }

    /// The largest number the selection writes; `A-` writes A.
    var largestNamed: Int {
        items.map { item -> Int in
            switch item {
            case .single(let n): return n
            case .range(_, let b): return b
            case .from(let a): return a
            }
        }.max() ?? 0
    }

    /// Sorted, merged intervals over 1...count; adjacent intervals are joined,
    /// so `2,3` covers a cell spanning columns 2–3. No set of numbers is
    /// built: a crafted span can be enormous.
    func intervals(upTo count: Int) -> [ClosedRange<Int>] {
        let raw = items.compactMap { item -> ClosedRange<Int>? in
            switch item {
            case .single(let n): return n...n
            case .range(let a, let b): return a...b
            case .from(let a): return a <= count ? a...count : nil
            }
        }.sorted { $0.lowerBound < $1.lowerBound }
        var merged: [ClosedRange<Int>] = []
        for interval in raw {
            if let last = merged.last, interval.lowerBound <= last.upperBound &+ 1 {
                merged[merged.count - 1] = last.lowerBound...max(last.upperBound, interval.upperBound)
            } else {
                merged.append(interval)
            }
        }
        return merged
    }
}

/// One `--table-defaults`: a table, named by any of its paragraphs, and its
/// fill columns and rows. A missing axis means all of it.
public struct TableDefaults: Equatable {
    public let anchor: String
    public let columns: GridSelection?
    public let rows: GridSelection?

    public init(anchor: String, columns: GridSelection?, rows: GridSelection?) {
        self.anchor = anchor
        self.columns = columns
        self.rows = rows
    }

    /// `<paraId>=col:<list>`, `<paraId>=row:<list>` or both joined by `/`
    /// in either order. A list is comma-separated `N`, `A-B` or `A-`, from 1.
    public static func parse(_ raw: String) throws -> TableDefaults {
        func refuse(_ detail: String) -> FormError { .invalidTableDefaults(raw, detail: detail) }
        guard let equals = raw.firstIndex(of: "=") else { throw refuse("缺少 =") }
        let anchor = String(raw[..<equals])
        let selector = raw[raw.index(after: equals)...]
        guard !anchor.isEmpty else { throw refuse("= 前面要寫表格裡任一段落的 paraId") }
        guard !selector.isEmpty else { throw refuse("= 後面要寫 col: 或 row:") }
        let parts = selector.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count <= 2 else { throw refuse("最多寫一個 col: 與一個 row:") }
        var columns: GridSelection?
        var rows: GridSelection?
        for part in parts {
            if part.hasPrefix("col:") {
                guard columns == nil else { throw refuse("col: 只能寫一次") }
                columns = try list(part.dropFirst(4), refuse: refuse)
            } else if part.hasPrefix("row:") {
                guard rows == nil else { throw refuse("row: 只能寫一次") }
                rows = try list(part.dropFirst(4), refuse: refuse)
            } else {
                throw refuse("每一段要以 col: 或 row: 開頭")
            }
        }
        return TableDefaults(anchor: anchor, columns: columns, rows: rows)
    }

    private static func list(_ text: Substring, refuse: (String) -> FormError) throws -> GridSelection {
        guard !text.isEmpty else { throw refuse("col: 或 row: 後面的清單是空的") }
        return try GridSelection(items: try text.split(separator: ",", omittingEmptySubsequences: false).map { item in
            func number(_ digits: Substring) throws -> Int {
                guard !digits.isEmpty, digits.utf8.allSatisfy({ (0x30...0x39).contains($0) }),
                      let value = Int(digits), value >= 1 else {
                    throw refuse("「\(item)」不是從 1 開始的欄列號")
                }
                return value
            }
            guard let dash = item.firstIndex(of: "-") else { return .single(try number(item)) }
            let start = try number(item[..<dash])
            let tail = item[item.index(after: dash)...]
            if tail.isEmpty { return .from(start) }
            let end = try number(tail)
            guard start <= end else { throw refuse("「\(item)」的起點大於終點") }
            return .range(start, end)
        })
    }
}

/// What one `--table-defaults` did (#250 requirement 1).
public struct TableDefaultsReport: Equatable {
    public let anchor: String
    /// Cells wholly inside this selection.
    public let fillCells: Int
    /// Cells only partly inside this selection, left alone, as `r1c1-4`
    /// labels in document order; a cell another selection tidies is not
    /// listed.
    public let partialCells: [String]
    /// Fill cells left alone because no paragraph of theirs can be named:
    /// a cell with no paragraph of its own, or one whose paragraphs are all
    /// empty and whose first carries no `w14:paraId` (verify R1). Listed once,
    /// under the first selection that reaches them.
    public let skippedCells: [String]

    public init(anchor: String, fillCells: Int, partialCells: [String], skippedCells: [String] = []) {
        self.anchor = anchor
        self.fillCells = fillCells
        self.partialCells = partialCells
        self.skippedCells = skippedCells
    }
}

struct TableDefaultsExpansion {
    /// Paragraph ids to tidy as `--field` does, without duplicates, in plan order.
    let fields: [String]
    let reports: [TableDefaultsReport]
}

extension FormOperations {
    /// The fill paragraphs every `--table-defaults` selects, judged on the
    /// original part. Each selection must find a fill cell of its own.
    static func expandTableDefaults(_ specs: [TableDefaults], in index: XMLTagIndex) throws -> TableDefaultsExpansion {
        var grids: [Int: TableGrid] = [:]
        var selections: [(spec: TableDefaults, fill: [TableGrid.Cell], partial: [TableGrid.Cell])] = []
        var fillTags: Set<Int> = []
        for spec in specs {
            let p = try locate(spec.anchor, in: index)
            let table: Int
            switch enclosingTable(of: p, in: index) {
            case .table(let t): table = t
            case .notInTable: throw FormError.tableDefaultsNotInTable(spec.anchor)
            case .inTextBox: throw FormError.tableDefaultsInTextBox(spec.anchor)
            }
            let grid: TableGrid
            if let cached = grids[table] {
                grid = cached
            } else {
                do {
                    grid = try TableGrid(table: table, in: index)
                } catch let unreadable as TableGrid.Unreadable {
                    throw FormError.tableGridUnreadable(spec.anchor, detail: unreadable.detail)
                }
                grids[table] = grid
            }
            try checkInRange(spec.columns, count: grid.columnCount, axis: "欄", anchor: spec.anchor)
            try checkInRange(spec.rows, count: grid.rowCount, axis: "列", anchor: spec.anchor)
            let columns = spec.columns.map { $0.intervals(upTo: grid.columnCount) } ?? whole(grid.columnCount)
            let rows = spec.rows.map { $0.intervals(upTo: grid.rowCount) } ?? whole(grid.rowCount)
            var fill: [TableGrid.Cell] = []
            var partial: [TableGrid.Cell] = []
            for cell in grid.cells {
                if covers(columns, cell.columns), covers(rows, cell.rows) {
                    fill.append(cell)
                } else if touches(columns, cell.columns), touches(rows, cell.rows) {
                    partial.append(cell)
                }
            }
            guard !fill.isEmpty else { throw FormError.noFillCells(spec.anchor) }
            fillTags.formUnion(fill.map(\.tc))
            selections.append((spec, fill, partial))
        }

        var fields: [String] = []
        var seen: Set<String> = []
        var listedSkips: Set<Int> = []
        var reports: [TableDefaultsReport] = []
        for selection in selections {
            var tidied = 0
            var skipped: [TableGrid.Cell] = []
            for cell in selection.fill {
                switch try fieldParagraphs(of: cell, anchor: selection.spec.anchor, in: index) {
                case .paragraphs(let ids):
                    tidied += 1
                    for id in ids where seen.insert(id).inserted { fields.append(id) }
                case .unaddressable:
                    skipped.append(cell)
                }
            }
            // Doing nothing while reporting success is the silent failure the
            // no-fill-cell refusal exists to stop, so it stops this too.
            guard tidied > 0 else { throw FormError.noTidyableFillCells(selection.spec.anchor, cells: skipped.map(\.label)) }
            reports.append(TableDefaultsReport(
                anchor: selection.spec.anchor, fillCells: tidied,
                partialCells: selection.partial.filter { !fillTags.contains($0.tc) }.map(\.label),
                skippedCells: skipped.filter { listedSkips.insert($0.tc).inserted }.map(\.label)))
        }
        return TableDefaultsExpansion(fields: fields, reports: reports)
    }

    enum FieldParagraphs: Equatable {
        case paragraphs([String])
        /// Nothing of the cell can be named: no paragraph of its own, or only
        /// empty paragraphs and the first carries no `w14:paraId`.
        case unaddressable
    }

    /// The paragraphs of a fill cell that `--field` tidies: the cell's own
    /// paragraphs (not those of a nested table or a text box) that hold
    /// content, or the first one when none does. Every later step finds
    /// paragraphs by id, so a paragraph with content and no `w14:paraId` is
    /// refused; an empty cell that cannot be named holds nothing to tidy and
    /// is left alone (verify R1).
    static func fieldParagraphs(of cell: TableGrid.Cell, anchor: String, in index: XMLTagIndex) throws -> FieldParagraphs {
        let own = index.descendants(of: cell.tc).filter {
            index.tags[$0].name == "w:p" && FormClassifier.enclosingCell(of: $0, in: index) == cell.tc
        }
        guard let first = own.first else { return .unaddressable }
        let filled = own.filter { hasContent($0, in: index) }
        if filled.isEmpty, index.attribute("w14:paraId", of: first) == nil { return .unaddressable }
        return .paragraphs(try (filled.isEmpty ? [first] : filled).map { p in
            guard let id = index.attribute("w14:paraId", of: p) else {
                throw FormError.fillCellWithoutParaId(anchor, cell: cell.label)
            }
            _ = try locate(id, in: index)   // an id carried by two paragraphs is refused, not guessed
            return id
        })
    }

    private static func checkInRange(_ selection: GridSelection?, count: Int, axis: String, anchor: String) throws {
        guard let selection, selection.largestNamed > count else { return }
        throw FormError.tableSelectionOutOfRange(anchor, detail: "第 \(selection.largestNamed) \(axis)，但這張表只有 \(count) \(axis)")
    }

    private static func whole(_ count: Int) -> [ClosedRange<Int>] { count >= 1 ? [1...count] : [] }

    private static func covers(_ intervals: [ClosedRange<Int>], _ range: ClosedRange<Int>) -> Bool {
        intervals.contains { $0.lowerBound <= range.lowerBound && range.upperBound <= $0.upperBound }
    }

    private static func touches(_ intervals: [ClosedRange<Int>], _ range: ClosedRange<Int>) -> Bool {
        intervals.contains { $0.overlaps(range) }
    }
}
