// FormPlan.swift — the all-or-nothing plan behind `macdoc word form apply`
// (macdoc#249, change docx-form-normalization).
//
// Every named paragraph id is checked against the original part before any
// edit. Operations then run in a fixed order — field, tick-list, insert,
// checkbox-font, remove (paragraphs and tables), truncate — each re-checking
// its own preconditions,
// and the edited part must parse as XML before it is returned.

import Foundation

public struct FieldSize: Equatable {
    /// OOXML size in half-points (`w:sz w:val`).
    public let halfPoints: Int

    public init(halfPoints: Int) { self.halfPoints = halfPoints }

    /// Points from 1 to 1638 in steps of 0.5 (e.g. "12", "10.5").
    public static func parse(points raw: String) throws -> FieldSize {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        // Whole-string match: Decimal(string:) accepts the longest valid
        // prefix, so "12.5.3" would otherwise come back as 12.5.
        guard trimmed.range(of: #"^[0-9]+(\.[0-9]+)?$"#, options: .regularExpression) != nil,
              let value = Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX")) else {
            throw FormError.invalidFieldSize(raw)
        }
        let doubled = value * 2
        var rounded = Decimal()
        var copy = doubled
        NSDecimalRound(&rounded, &copy, 0, .plain)
        guard rounded == doubled, value >= 1, value <= 1638 else { throw FormError.invalidFieldSize(raw) }
        return FieldSize(halfPoints: NSDecimalNumber(decimal: rounded).intValue)
    }

    /// "12 pt", "10.5 pt".
    public var pointsDescription: String {
        halfPoints % 2 == 0 ? "\(halfPoints / 2) pt" : "\(halfPoints / 2).5 pt"
    }
}

public struct FormInsertion: Equatable {
    public let anchor: String
    public let text: String

    public init(anchor: String, text: String) {
        self.anchor = anchor
        self.text = text
    }
}

/// A `--field` whose cell was not cleaned of empty sibling paragraphs, and the
/// structures in the cell that caused the skip (macdoc#253).
public struct CleanupSkip: Equatable {
    public enum Reason: Equatable, CaseIterable {
        case nestedTable, contentControl, customXML

        /// The element whose presence in the cell causes the skip.
        public var elementName: String {
            switch self {
            case .nestedTable: return "w:tbl"
            case .contentControl: return "w:sdt"
            case .customXML: return "w:customXml"
            }
        }
    }

    public let paragraphId: String
    /// In the fixed order of `Reason.allCases`.
    public let reasons: [Reason]

    public init(paragraphId: String, reasons: [Reason]) {
        self.paragraphId = paragraphId
        self.reasons = reasons
    }
}

public struct FormResult {
    public let documentXML: [UInt8]
    /// The size applied to `--field` paragraphs, when any were named.
    public let fieldSize: FieldSize?
    /// True when the size was derived from the fields rather than given.
    public let fieldSizeWasDerived: Bool
    /// Runs holding a box glyph that were left alone because they carry other content.
    public let skippedCheckboxRuns: Int
    /// Fields whose cell cleanup was skipped, in plan order.
    public let skippedCleanups: [CleanupSkip]
    /// True when the deletions left the body ending with a table (or another
    /// block that is not a paragraph) and an empty final paragraph was added (#250).
    public let addedFinalParagraph: Bool
    /// What each `--table-defaults` did, in plan order (#250 requirement 1).
    public let tableDefaultsReports: [TableDefaultsReport]
}

public struct FormPlan: Equatable {
    public var fields: [String]
    public var fieldSize: FieldSize?
    public var checkboxFont: String?
    public var tickList: [String]
    public var insertions: [FormInsertion]
    public var removals: [String]
    /// Paragraph ids whose body-level table `--remove-table` deletes (#250).
    public var removedTables: [String]
    public var truncateFrom: String?
    /// Tables whose fill columns or rows are tidied as `--field` tidies one
    /// paragraph (#250 requirement 1).
    public var tableDefaults: [TableDefaults]

    public init(fields: [String] = [], fieldSize: FieldSize? = nil, checkboxFont: String? = nil,
                tickList: [String] = [], insertions: [FormInsertion] = [], removals: [String] = [],
                removedTables: [String] = [], truncateFrom: String? = nil, tableDefaults: [TableDefaults] = []) {
        self.fields = fields
        self.fieldSize = fieldSize
        self.checkboxFont = checkboxFont
        self.tickList = tickList
        self.insertions = insertions
        self.removals = removals
        self.removedTables = removedTables
        self.truncateFrom = truncateFrom
        self.tableDefaults = tableDefaults
    }

    public var hasOperations: Bool {
        !fields.isEmpty || checkboxFont != nil || !tickList.isEmpty || !insertions.isEmpty
            || !removals.isEmpty || !removedTables.isEmpty || truncateFrom != nil || !tableDefaults.isEmpty
    }

    /// Every paragraph id the plan names, without duplicates, in plan order.
    var namedIds: [String] {
        unique(fields + tableDefaults.map(\.anchor) + tickList + insertions.map(\.anchor) + removals + removedTables
            + (truncateFrom.map { [$0] } ?? []))
    }

    public func apply(toDocumentXML input: [UInt8]) throws -> FormResult {
        var editor = try XMLEditor(input)
        let ticks = unique(self.tickList)
        let removals = unique(self.removals)
        let tables = unique(self.removedTables)

        // 1. Validate everything against the original part.
        if let font = checkboxFont, font.isEmpty || !XMLText.isAllowed(font) { throw FormError.invalidFont(font) }
        for insertion in insertions where !XMLText.isAllowed(insertion.text) {
            throw FormError.invalidText(insertion.anchor)
        }
        for id in namedIds { _ = try FormOperations.locate(id, in: editor.index) }
        for id in tables { _ = try FormOperations.tableToRemove(id, in: editor.index) }
        // A table's fill paragraphs join the fields and go through every check
        // a --field goes through (#250 requirement 1).
        let expansion = try FormOperations.expandTableDefaults(tableDefaults, in: editor.index)
        let fields = unique(self.fields + expansion.fields)
        try checkConflicts(fields: fields, ticks: ticks, removals: removals,
                           named: unique(namedIds + expansion.fields), index: editor.index)
        for id in fields { try FormOperations.checkField(id, in: editor.index) }
        for id in ticks { try FormOperations.checkTick(id, in: editor.index) }
        for id in removals { try FormOperations.checkRemove(id, in: editor.index) }
        if let id = truncateFrom { _ = try FormOperations.checkTruncate(id, in: editor.index) }

        // Fields, comment references and range markers pair across paragraphs,
        // and a cell's remaining blocks depend on every paragraph that goes, so
        // the deletions are judged once as a whole before anything is written
        // (#253 verify R1, R2). The deletion step judges them again on the part
        // the earlier steps left, so no caller can bypass the checks (R3).
        _ = try FormOperations.checkDeletions(removals, tables: tables, truncateFrom: truncateFrom, in: editor.index)

        var size: FieldSize?
        var derived = false
        if !fields.isEmpty {
            if let given = fieldSize {
                size = given
            } else {
                guard let half = FormOperations.mode(try FormOperations.collectFieldSizes(fields, in: editor.index)) else {
                    throw FormError.noFieldSize
                }
                size = FieldSize(halfPoints: half)
                derived = true
            }
        }

        // 2. Run the operations in the fixed order. A --table-defaults anchor
        // only says which table is meant, so it is not kept from cleanup.
        let protected = Set(fields + ticks + insertions.map(\.anchor) + removals + tables + (truncateFrom.map { [$0] } ?? []))
        var cleanupSkips: [CleanupSkip] = []
        if let size {
            for id in fields {
                if let skip = try FormOperations.normalizeField(id, halfPoints: size.halfPoints,
                                                                protected: protected, editor: &editor) {
                    cleanupSkips.append(skip)
                }
            }
        }
        for id in ticks { try FormOperations.tickList(id, editor: &editor) }
        for anchor in unique(insertions.map(\.anchor)) {
            let texts = insertions.filter { $0.anchor == anchor }.map(\.text)
            try FormOperations.insertParagraphs(after: anchor, texts: texts, editor: &editor)
        }
        var skipped = 0
        if let font = checkboxFont { skipped = try FormOperations.uniformCheckboxes(font: font, editor: &editor) }
        let addedFinalParagraph = try FormOperations.deleteAll(removals, tables: tables, truncateFrom: truncateFrom,
                                                               editor: &editor)

        // 3. The result must be well-formed XML.
        try Self.checkWellFormed(editor.bytes)
        return FormResult(documentXML: editor.bytes, fieldSize: size, fieldSizeWasDerived: derived,
                          skippedCheckboxRuns: skipped, skippedCleanups: cleanupSkips,
                          addedFinalParagraph: addedFinalParagraph, tableDefaultsReports: expansion.reports)
    }

    /// Refuses plans whose later steps would silently undo earlier ones: a
    /// removed paragraph that another operation also names, a paragraph that
    /// another operation names inside a table `--remove-table` deletes, and
    /// any named paragraph inside the range `--truncate-from` cuts away.
    /// `named` is every id the plan names plus the fields `--table-defaults` selects.
    func checkConflicts(fields: [String], ticks: [String], removals: [String], named: [String],
                        index: XMLTagIndex) throws {
        let edited = Set(fields + ticks + insertions.map(\.anchor))
        if let id = removals.first(where: { edited.contains($0) }) {
            throw FormError.conflictingOperations(id, detail: "--remove 會刪掉 --field / --tick-list / --insert-after 處理過的段落")
        }
        // A named paragraph nested inside a removed one (for example in a
        // text box) would disappear with it while the command reports success.
        for removed in removals {
            let range = index.elementRange(try FormOperations.locate(removed, in: index))
            for id in named where id != removed {
                let start = index.tags[try FormOperations.locate(id, in: index)].start
                if range.contains(start) {
                    throw FormError.conflictingOperations(id, detail: "位在 --remove \(removed) 會刪掉的段落裡（例如文字方塊）")
                }
            }
        }
        // A paragraph another operation names inside a removed table would
        // vanish with it while the command reports success (#250).
        // A --table-defaults anchor comes first, so a conflict names the id the caller wrote.
        let others = unique(tableDefaults.map(\.anchor) + fields + ticks + insertions.map(\.anchor) + removals
            + (truncateFrom.map { [$0] } ?? []))
        for tableId in unique(removedTables) {
            let range = index.elementRange(try FormOperations.tableToRemove(tableId, in: index))
            for id in others where range.contains(index.tags[try FormOperations.locate(id, in: index)].start) {
                throw FormError.conflictingOperations(id, detail: "位在 --remove-table \(tableId) 會刪掉的表格裡")
            }
        }
        guard let cutId = truncateFrom else { return }
        if edited.contains(cutId) || removals.contains(cutId) {
            throw FormError.conflictingOperations(cutId, detail: "--truncate-from 會把這一段一起截掉")
        }
        let cut = index.tags[try FormOperations.locate(cutId, in: index)].start
        for id in named where id != cutId {
            if index.tags[try FormOperations.locate(id, in: index)].start >= cut {
                throw FormError.conflictingOperations(id, detail: "位在 --truncate-from \(cutId) 會截掉的範圍內")
            }
        }
    }

    static func checkWellFormed(_ bytes: [UInt8]) throws {
        let parser = XMLParser(data: Data(bytes))
        parser.shouldProcessNamespaces = false
        if !parser.parse() {
            let detail = parser.parserError.map { String(describing: $0.localizedDescription) } ?? "unknown"
            throw FormError.malformedResult("line \(parser.lineNumber): \(detail)")
        }
    }
}

private func unique(_ ids: [String]) -> [String] {
    var seen: Set<String> = []
    return ids.filter { seen.insert($0).inserted }
}
