// FormClassifier.swift — paragraph kinds for form normalization (macdoc#249).
//
// The kinds are a closed enumeration decided by structure only. Instruction
// ("hint") paragraphs are deliberately not a kind: they look like body text,
// and guessing them from wording would delete content an applicant has to
// fill. Removal is always explicit by paragraph id.

import Foundation

public enum ParagraphKind: String, CaseIterable, Equatable {
    /// The paragraph's own `w:numPr` points at a numbering level whose text is a box glyph.
    case listCheckbox = "list-checkbox"
    /// The paragraph's own visible text contains a box glyph.
    case checkboxLine = "checkbox-line"
    /// The paragraph sits inside a table cell.
    case tableField = "table-field"
    /// Anything else.
    case body
}

/// The `word form apply` option that tidies a paragraph of one kind (#255).
/// `ParagraphKind.applyOption` is the one place this mapping lives: the
/// `word reverse --slot` hints read it, and a test keeps the swiftify skill's
/// kind table in step with it.
public struct ApplyOption: Equatable {
    public enum Argument: Equatable {
        /// The option takes the paragraph's own id.
        case paraId
        /// The option takes a value the caller chooses, shown by this placeholder.
        case placeholder(String)
    }

    public let flag: String
    public let argument: Argument

    public init(flag: String, argument: Argument) {
        self.flag = flag
        self.argument = argument
    }

    /// The option as written for one paragraph, e.g. `--field 0000A001`.
    public func usage(paraId: String) -> String {
        switch argument {
        case .paraId: return "\(flag) \(paraId)"
        case .placeholder(let value): return "\(flag) \(value)"
        }
    }
}

extension ParagraphKind {
    /// The option that tidies this kind after render, or nil when the kind has
    /// none (`body`: its content is changed with `--insert-after`, not tidied).
    public var applyOption: ApplyOption? {
        switch self {
        case .tableField: return ApplyOption(flag: "--field", argument: .paraId)
        case .checkboxLine: return ApplyOption(flag: "--checkbox-font", argument: .placeholder("<字型>"))
        case .listCheckbox: return ApplyOption(flag: "--tick-list", argument: .paraId)
        case .body: return nil
        }
    }
}

public struct ClassifiedParagraph: Equatable {
    public let paraId: String
    public let kind: ParagraphKind
    public let text: String
}

public enum FormClassifier {
    /// Exactly these five scalars count as box glyphs: □ ■ ☐ ☑ ☒.
    public static let boxGlyphs: Set<Unicode.Scalar> = ["\u{25A1}", "\u{25A0}", "\u{2610}", "\u{2611}", "\u{2612}"]

    public static func containsBoxGlyph(_ s: String) -> Bool {
        s.unicodeScalars.contains { boxGlyphs.contains($0) }
    }

    /// False when `word/numbering.xml` cannot be parsed; classification then
    /// runs with list-checkbox detection disabled instead of failing.
    public static func isReadableNumbering(_ xml: [UInt8]) -> Bool {
        numberingLevels(xml) != nil
    }

    /// The numbering levels, or nil when the part cannot be read: the tag scan
    /// refuses it (unpaired tags, a DOCTYPE, more nesting or tags than the
    /// scan limits, #252) or a real XML parser does (duplicate attributes, bad
    /// entities and the like). The tag index only checks tag pairing, so the
    /// part goes through the parser as well.
    static func numberingLevels(_ xml: [UInt8]?) -> NumberingLevels? {
        // The tag index runs first so a DOCTYPE (and with it any entity
        // definition) is refused before a real XML parser ever sees the part,
        // the same order the main part goes through.
        guard let xml, (try? XMLTagIndex(xml)) != nil else { return nil }
        let parser = XMLParser(data: Data(xml))
        parser.shouldResolveExternalEntities = false
        guard parser.parse() else { return nil }
        return try? NumberingLevels(xml: xml)
    }

    /// Every paragraph that carries a `w14:paraId`, in document order. An
    /// unreadable numbering part disables list-checkbox detection only.
    public static func classify(documentXML: [UInt8], numberingXML: [UInt8]?) throws -> [ClassifiedParagraph] {
        let index = try XMLTagIndex(documentXML)
        let numbering = numberingLevels(numberingXML)
        var out: [ClassifiedParagraph] = []
        for p in index.elements(named: "w:p") {
            guard let id = index.attribute("w14:paraId", of: p) else { continue }
            out.append(ClassifiedParagraph(paraId: id,
                                           kind: kind(of: p, in: index, numbering: numbering),
                                           text: ownText(of: p, in: index)))
        }
        return out
    }

    /// Kind of each requested paragraph id that is carried by exactly one `w:p`.
    /// Ids that are missing or ambiguous are left out.
    public static func kinds(of paraIds: [String], documentXML: [UInt8], numberingXML: [UInt8]?) throws -> [String: ParagraphKind] {
        let index = try XMLTagIndex(documentXML)
        let numbering = numberingLevels(numberingXML)
        var out: [String: ParagraphKind] = [:]
        for id in paraIds {
            if case .found(let p) = FormLocator.paragraph(withId: id, in: index) {
                out[id] = kind(of: p, in: index, numbering: numbering)
            }
        }
        return out
    }

    static func kind(of p: Int, in index: XMLTagIndex, numbering: NumberingLevels?) -> ParagraphKind {
        if let numbering, let reference = FormLocator.ownNumbering(of: p, in: index),
           let levelText = numbering.levelText(numId: reference.numId, ilvl: reference.ilvl),
           containsBoxGlyph(levelText) {
            return .listCheckbox
        }
        if containsBoxGlyph(ownText(of: p, in: index)) { return .checkboxLine }
        if enclosingCell(of: p, in: index) != nil { return .tableField }
        return .body
    }

    /// The cell a paragraph belongs to: its nearest container, looking
    /// through content-control and custom-XML wrappers, when that is a
    /// `w:tc`. A paragraph in a text box anchored in a cell belongs to the
    /// text box, not the cell.
    static func enclosingCell(of p: Int, in index: XMLTagIndex) -> Int? {
        guard let container = FormOperations.blockContainer(of: p, in: index),
              index.tags[container].name == "w:tc" else { return nil }
        return container
    }

    /// Visible text of the paragraph itself (not of paragraphs nested in text boxes).
    static func ownText(of p: Int, in index: XMLTagIndex) -> String {
        FormLocator.ownElements(named: "w:t", of: p, in: index)
            .map { index.text(of: $0) }
            .joined()
    }
}

/// `word/numbering.xml` reduced to the level texts the classifier needs.
struct NumberingLevels {
    /// abstractNumId → (ilvl → lvlText)
    private var abstractLevels: [String: [String: String]] = [:]
    /// numId → abstractNumId
    private var numToAbstract: [String: String] = [:]
    /// numId → (ilvl → lvlText) from `w:lvlOverride/w:lvl`
    private var overrides: [String: [String: String]] = [:]

    init(xml: [UInt8]) throws {
        let index = try XMLTagIndex(xml)
        for a in index.elements(named: "w:abstractNum") {
            guard let id = index.attribute("w:abstractNumId", of: a) else { continue }
            abstractLevels[id] = Self.levelTexts(in: a, index: index)
        }
        for n in index.elements(named: "w:num") {
            guard let numId = index.attribute("w:numId", of: n) else { continue }
            if let abstract = index.child(of: n, named: "w:abstractNumId"),
               let value = index.attribute("w:val", of: abstract) {
                numToAbstract[numId] = value
            }
            var levelOverrides: [String: String] = [:]
            for o in index.children(of: n) where index.tags[o].name == "w:lvlOverride" {
                guard let ilvl = index.attribute("w:ilvl", of: o) else { continue }
                if let lvl = index.child(of: o, named: "w:lvl"),
                   let text = index.child(of: lvl, named: "w:lvlText"),
                   let value = index.attribute("w:val", of: text) {
                    levelOverrides[ilvl] = value
                }
            }
            if !levelOverrides.isEmpty { overrides[numId] = levelOverrides }
        }
    }

    private static func levelTexts(in abstract: Int, index: XMLTagIndex) -> [String: String] {
        var out: [String: String] = [:]
        for lvl in index.children(of: abstract) where index.tags[lvl].name == "w:lvl" {
            guard let ilvl = index.attribute("w:ilvl", of: lvl),
                  let text = index.child(of: lvl, named: "w:lvlText"),
                  let value = index.attribute("w:val", of: text) else { continue }
            out[ilvl] = value
        }
        return out
    }

    func levelText(numId: String, ilvl: String) -> String? {
        if let value = overrides[numId]?[ilvl] { return value }
        guard let abstract = numToAbstract[numId] else { return nil }
        return abstractLevels[abstract]?[ilvl]
    }
}

/// Structural lookups shared by the classifier and the operations.
enum FormLocator {
    enum Lookup: Equatable {
        case found(Int)
        case notFound
        case ambiguous(count: Int)
        case notOnParagraph(carrier: String)
    }

    /// Looks the id up in the index's paraId table (#252); the carriers come
    /// in document order, so the first non-paragraph carrier is reported as
    /// before the table existed.
    static func paragraph(withId id: String, in index: XMLTagIndex) -> Lookup {
        var paragraphs: [Int] = []
        var otherCarrier: String?
        for i in index.tags(withParaId: id) {
            let tag = index.tags[i]
            if tag.name == "w:p" {
                paragraphs.append(i)
            } else if otherCarrier == nil {
                otherCarrier = tag.name
            }
        }
        switch paragraphs.count {
        case 1: return .found(paragraphs[0])
        case 0: return otherCarrier.map { .notOnParagraph(carrier: $0) } ?? .notFound
        default: return .ambiguous(count: paragraphs.count)
        }
    }

    /// Elements named `name` whose nearest enclosing `w:p` is `p` itself.
    static func ownElements(named name: String, of p: Int, in index: XMLTagIndex) -> [Int] {
        index.descendants(of: p).filter {
            index.tags[$0].name == name && index.ancestor(of: $0, named: "w:p") == p
        }
    }

    /// `w:numId` / `w:ilvl` from the paragraph's own `w:pPr/w:numPr`.
    /// numId "0" means "numbering removed" and counts as no numbering.
    static func ownNumbering(of p: Int, in index: XMLTagIndex) -> (numId: String, ilvl: String)? {
        guard let pPr = index.child(of: p, named: "w:pPr"),
              let numPr = index.child(of: pPr, named: "w:numPr"),
              let numIdElement = index.child(of: numPr, named: "w:numId"),
              let numId = index.attribute("w:val", of: numIdElement),
              numId != "0" else { return nil }
        let ilvl = index.child(of: numPr, named: "w:ilvl").flatMap { index.attribute("w:val", of: $0) } ?? "0"
        return (numId, ilvl)
    }

    /// The paragraph's own runs (not runs of paragraphs nested in text boxes).
    static func ownRuns(of p: Int, in index: XMLTagIndex) -> [Int] {
        ownElements(named: "w:r", of: p, in: index)
    }

    /// Visible text held directly by a run's `w:t` children.
    static func runText(_ r: Int, in index: XMLTagIndex) -> String {
        index.children(of: r).filter { index.tags[$0].name == "w:t" }.map { index.text(of: $0) }.joined()
    }

    /// First own run whose direct `w:t` text is not empty.
    static func firstTextRun(of p: Int, in index: XMLTagIndex) -> Int? {
        ownRuns(of: p, in: index).first { !runText($0, in: index).isEmpty }
    }
}
