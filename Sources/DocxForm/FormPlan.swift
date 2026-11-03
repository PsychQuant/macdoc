// FormPlan.swift — the all-or-nothing plan behind `macdoc word form apply`
// (macdoc#249, change docx-form-normalization).
//
// Every named paragraph id is checked against the original part before any
// edit. Operations then run in a fixed order — field, tick-list, insert,
// checkbox-font, remove, truncate — each re-checking its own preconditions,
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

public struct FormResult {
    public let documentXML: [UInt8]
    /// The size applied to `--field` paragraphs, when any were named.
    public let fieldSize: FieldSize?
    /// True when the size was derived from the fields rather than given.
    public let fieldSizeWasDerived: Bool
    /// Runs holding a box glyph that were left alone because they carry other content.
    public let skippedCheckboxRuns: Int
}

public struct FormPlan: Equatable {
    public var fields: [String]
    public var fieldSize: FieldSize?
    public var checkboxFont: String?
    public var tickList: [String]
    public var insertions: [FormInsertion]
    public var removals: [String]
    public var truncateFrom: String?

    public init(fields: [String] = [], fieldSize: FieldSize? = nil, checkboxFont: String? = nil,
                tickList: [String] = [], insertions: [FormInsertion] = [], removals: [String] = [],
                truncateFrom: String? = nil) {
        self.fields = fields
        self.fieldSize = fieldSize
        self.checkboxFont = checkboxFont
        self.tickList = tickList
        self.insertions = insertions
        self.removals = removals
        self.truncateFrom = truncateFrom
    }

    public var hasOperations: Bool {
        !fields.isEmpty || checkboxFont != nil || !tickList.isEmpty || !insertions.isEmpty
            || !removals.isEmpty || truncateFrom != nil
    }

    /// Every paragraph id the plan names, without duplicates, in plan order.
    var namedIds: [String] {
        unique(fields + tickList + insertions.map(\.anchor) + removals + (truncateFrom.map { [$0] } ?? []))
    }

    public func apply(toDocumentXML input: [UInt8]) throws -> FormResult {
        var editor = try XMLEditor(input)
        let fields = unique(self.fields)
        let ticks = unique(self.tickList)
        let removals = unique(self.removals)

        // 1. Validate everything against the original part.
        if let font = checkboxFont, font.isEmpty || !XMLText.isAllowed(font) { throw FormError.invalidFont(font) }
        for insertion in insertions where !XMLText.isAllowed(insertion.text) {
            throw FormError.invalidText(insertion.anchor)
        }
        for id in namedIds { _ = try FormOperations.locate(id, in: editor.index) }
        try checkConflicts(fields: fields, ticks: ticks, removals: removals, index: editor.index)
        for id in fields { try FormOperations.checkField(id, in: editor.index) }
        for id in ticks { try FormOperations.checkTick(id, in: editor.index) }
        for id in removals { try FormOperations.checkRemove(id, in: editor.index) }
        if let id = truncateFrom { _ = try FormOperations.checkTruncate(id, in: editor.index) }

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

        // 2. Run the operations in the fixed order.
        let protected = Set(namedIds)
        if let size {
            for id in fields {
                try FormOperations.normalizeField(id, halfPoints: size.halfPoints, protected: protected, editor: &editor)
            }
        }
        for id in ticks { try FormOperations.tickList(id, editor: &editor) }
        for anchor in unique(insertions.map(\.anchor)) {
            let texts = insertions.filter { $0.anchor == anchor }.map(\.text)
            try FormOperations.insertParagraphs(after: anchor, texts: texts, editor: &editor)
        }
        var skipped = 0
        if let font = checkboxFont { skipped = try FormOperations.uniformCheckboxes(font: font, editor: &editor) }
        for id in removals { try FormOperations.remove(id, editor: &editor) }
        if let id = truncateFrom { try FormOperations.truncate(from: id, editor: &editor) }

        // 3. The result must be well-formed XML.
        try Self.checkWellFormed(editor.bytes)
        return FormResult(documentXML: editor.bytes, fieldSize: size, fieldSizeWasDerived: derived,
                          skippedCheckboxRuns: skipped)
    }

    /// Refuses plans whose later steps would silently undo earlier ones: a
    /// removed paragraph that another operation also names, and any named
    /// paragraph inside the range `--truncate-from` cuts away.
    func checkConflicts(fields: [String], ticks: [String], removals: [String], index: XMLTagIndex) throws {
        let edited = Set(fields + ticks + insertions.map(\.anchor))
        if let id = removals.first(where: { edited.contains($0) }) {
            throw FormError.conflictingOperations(id, detail: "--remove 會刪掉 --field / --tick-list / --insert-after 處理過的段落")
        }
        guard let cutId = truncateFrom else { return }
        if edited.contains(cutId) || removals.contains(cutId) {
            throw FormError.conflictingOperations(cutId, detail: "--truncate-from 會把這一段一起截掉")
        }
        let cut = index.tags[try FormOperations.locate(cutId, in: index)].start
        for id in namedIds where id != cutId {
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
