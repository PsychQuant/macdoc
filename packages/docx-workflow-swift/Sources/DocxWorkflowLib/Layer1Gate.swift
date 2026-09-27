// Layer1Gate.swift — macdoc#137 Layer 1 (docx-mutation-certification-layer1).
//
// Proves package and byte preservation between a baseline and a candidate
// .docx: the part set must match, every part outside the mutation intent's
// allowed set must be byte-identical, and the candidate must be a
// well-formed, internally-consistent OPC package. See design.md "Compare
// non-target parts by exact bytes, not canonical XML" and spec.md "Layer 1
// gate proves package and byte preservation".
//
// Deliberately simple string/XMLParser-level checks, not a schema validator:
// this is the first slice (Layer 1). Canonical-XML comparison and sub-part
// preservation are explicitly out of scope (design.md Non-Goals).

import Foundation

/// One breach of Layer 1's package/byte-preservation guarantee. A closed
/// enum — see design.md's Implementation Contract "Interface".
///
/// `Codable` is hand-written: Swift does not auto-synthesize `Codable` for
/// an enum with associated values. The JSON shape is a `kind` discriminator
/// plus the case's own fields (flat, not nested under the case name), so a
/// consumer can `switch` on `kind` without unwrapping an extra container.
public enum Layer1Violation: Equatable, Codable {
    case partAdded(String)
    case partRemoved(String)
    case unexpectedChange(part: String, baselineSize: Int, candidateSize: Int, firstDifferingOffset: Int)
    case unreadablePackage(String)
    case malformedXML(part: String, message: String)
    case missingContentType(part: String)
    case danglingRelationship(source: String, target: String)

    private enum Kind: String, Codable {
        case partAdded, partRemoved, unexpectedChange, unreadablePackage
        case malformedXML, missingContentType, danglingRelationship
    }

    private enum CodingKeys: String, CodingKey {
        case kind, part, baselineSize, candidateSize, firstDifferingOffset, message, source, target
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .partAdded:
            self = .partAdded(try container.decode(String.self, forKey: .part))
        case .partRemoved:
            self = .partRemoved(try container.decode(String.self, forKey: .part))
        case .unexpectedChange:
            self = .unexpectedChange(
                part: try container.decode(String.self, forKey: .part),
                baselineSize: try container.decode(Int.self, forKey: .baselineSize),
                candidateSize: try container.decode(Int.self, forKey: .candidateSize),
                firstDifferingOffset: try container.decode(Int.self, forKey: .firstDifferingOffset)
            )
        case .unreadablePackage:
            self = .unreadablePackage(try container.decode(String.self, forKey: .message))
        case .malformedXML:
            self = .malformedXML(
                part: try container.decode(String.self, forKey: .part),
                message: try container.decode(String.self, forKey: .message)
            )
        case .missingContentType:
            self = .missingContentType(part: try container.decode(String.self, forKey: .part))
        case .danglingRelationship:
            self = .danglingRelationship(
                source: try container.decode(String.self, forKey: .source),
                target: try container.decode(String.self, forKey: .target)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .partAdded(let part):
            try container.encode(Kind.partAdded, forKey: .kind)
            try container.encode(part, forKey: .part)
        case .partRemoved(let part):
            try container.encode(Kind.partRemoved, forKey: .kind)
            try container.encode(part, forKey: .part)
        case .unexpectedChange(let part, let baselineSize, let candidateSize, let firstDifferingOffset):
            try container.encode(Kind.unexpectedChange, forKey: .kind)
            try container.encode(part, forKey: .part)
            try container.encode(baselineSize, forKey: .baselineSize)
            try container.encode(candidateSize, forKey: .candidateSize)
            try container.encode(firstDifferingOffset, forKey: .firstDifferingOffset)
        case .unreadablePackage(let message):
            try container.encode(Kind.unreadablePackage, forKey: .kind)
            try container.encode(message, forKey: .message)
        case .malformedXML(let part, let message):
            try container.encode(Kind.malformedXML, forKey: .kind)
            try container.encode(part, forKey: .part)
            try container.encode(message, forKey: .message)
        case .missingContentType(let part):
            try container.encode(Kind.missingContentType, forKey: .kind)
            try container.encode(part, forKey: .part)
        case .danglingRelationship(let source, let target):
            try container.encode(Kind.danglingRelationship, forKey: .kind)
            try container.encode(source, forKey: .source)
            try container.encode(target, forKey: .target)
        }
    }
}

/// The outcome of `Layer1Gate.evaluate`.
public struct Layer1Result: Equatable {
    public let passed: Bool
    /// Every part whose bytes differ between baseline and candidate,
    /// whether or not the change was allowed.
    public let changedParts: [String]
    public let violations: [Layer1Violation]

    public init(passed: Bool, changedParts: [String], violations: [Layer1Violation]) {
        self.passed = passed
        self.changedParts = changedParts
        self.violations = violations
    }
}

public enum Layer1Gate {

    /// Evaluates the six checks from spec.md's "Layer 1 gate proves package
    /// and byte preservation" Requirement. Never throws — an unreadable
    /// package is itself a violation (`unreadablePackage`), not a Swift
    /// error, so a caller always gets a `Layer1Result` to put in the
    /// certificate.
    public static func evaluate(baseline: URL, candidate: URL, intent: MutationIntent) -> Layer1Result {
        guard let baselineParts = try? readParts(baseline) else {
            return Layer1Result(passed: false, changedParts: [],
                                 violations: [.unreadablePackage("baseline package could not be extracted: \(baseline.lastPathComponent)")])
        }
        guard let candidateParts = try? readParts(candidate) else {
            return Layer1Result(passed: false, changedParts: [],
                                 violations: [.unreadablePackage("candidate package could not be extracted: \(candidate.lastPathComponent)")])
        }

        var violations: [Layer1Violation] = []
        let baselineNames = Set(baselineParts.keys)
        let candidateNames = Set(candidateParts.keys)

        for removed in baselineNames.subtracting(candidateNames).sorted() {
            violations.append(.partRemoved(removed))
        }
        for added in candidateNames.subtracting(baselineNames).sorted() {
            violations.append(.partAdded(added))
        }

        var changedParts: [String] = []
        for name in baselineNames.intersection(candidateNames).sorted() {
            let baselineData = baselineParts[name]!
            let candidateData = candidateParts[name]!
            guard baselineData != candidateData else { continue }
            changedParts.append(name)
            guard !intent.allowedParts.contains(name) else { continue }
            violations.append(.unexpectedChange(
                part: name,
                baselineSize: baselineData.count,
                candidateSize: candidateData.count,
                firstDifferingOffset: firstDifferingOffset(baselineData, candidateData)
            ))
        }

        // The candidate must re-open through DocxReader.
        do {
            _ = try DocxReader.read(from: candidate, wireTreeBackedViews: false)
        } catch {
            violations.append(.unreadablePackage("\(error)"))
        }

        // Every `.xml`/`.rels` part must be well-formed.
        for name in candidateNames.sorted() where name.hasSuffix(".xml") || name.hasSuffix(".rels") {
            if let message = malformedXMLMessage(candidateParts[name]!) {
                violations.append(.malformedXML(part: name, message: message))
            }
        }

        // `[Content_Types].xml` must cover every part.
        let contentTypes = parseContentTypes(candidateParts["[Content_Types].xml"])
        for name in candidateNames.sorted() where name != "[Content_Types].xml" {
            if !hasContentType(partName: name, contentTypes: contentTypes) {
                violations.append(.missingContentType(part: name))
            }
        }

        // Every internal relationship target must resolve to an existing part.
        for relsName in candidateNames.sorted() where relsName.hasSuffix(".rels") {
            let ownerDir = ownerDirectory(ofRelsPart: relsName)
            for relationship in parseRelationships(candidateParts[relsName]!) {
                guard relationship.targetMode?.caseInsensitiveCompare("External") != .orderedSame else { continue }
                let resolved = resolveTarget(relationship.target, ownerDirectory: ownerDir)
                if !candidateNames.contains(resolved) {
                    violations.append(.danglingRelationship(source: relsName, target: relationship.target))
                }
            }
        }

        return Layer1Result(passed: violations.isEmpty, changedParts: changedParts, violations: violations)
    }

    // MARK: - Package extraction

    /// Path → bytes for every regular file in the unzipped package, keyed
    /// by its path relative to the archive root (forward-slash separated).
    private static func readParts(_ url: URL) throws -> [String: Data] {
        let dir = try ZipHelper.unzip(url)
        defer { ZipHelper.cleanup(dir) }
        var parts: [String: Data] = [:]
        guard let enumerator = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return parts
        }
        let rootPath = dir.standardizedFileURL.path
        while let file = enumerator.nextObject() as? URL {
            guard (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            let name = file.standardizedFileURL.path.replacingOccurrences(of: rootPath + "/", with: "")
            parts[name] = try Data(contentsOf: file)
        }
        return parts
    }

    private static func firstDifferingOffset(_ a: Data, _ b: Data) -> Int {
        let minLen = Swift.min(a.count, b.count)
        for i in 0..<minLen where a[i] != b[i] {
            return i
        }
        return minLen
    }

    // MARK: - Well-formedness

    private static func malformedXMLMessage(_ data: Data) -> String? {
        let parser = XMLParser(data: data)
        let delegate = SilentXMLParserDelegate()
        parser.delegate = delegate
        if parser.parse() { return nil }
        return parser.parserError?.localizedDescription ?? "unknown parse error"
    }

    // MARK: - [Content_Types].xml

    private struct ContentTypes {
        var defaults: [String: String] = [:]   // extension -> content type
        var overrides: [String: String] = [:]   // "/part/name" -> content type
    }

    private static func parseContentTypes(_ data: Data?) -> ContentTypes {
        var types = ContentTypes()
        guard let data else { return types }
        let parser = XMLParser(data: data)
        let delegate = ContentTypesCollector()
        parser.delegate = delegate
        _ = parser.parse()
        types.defaults = delegate.defaults
        types.overrides = delegate.overrides
        return types
    }

    private static func hasContentType(partName: String, contentTypes: ContentTypes) -> Bool {
        if contentTypes.overrides["/" + partName] != nil { return true }
        let ext = fileExtension(of: partName)
        return contentTypes.defaults[ext] != nil
    }

    /// Extension after the LAST "." in the last path component, including
    /// a component that starts with ".": OPC's `.rels` parts are literally
    /// named `.rels` (e.g. `_rels/.rels`), and `NSString.pathExtension`
    /// treats a leading dot as marking a hidden file with NO extension —
    /// the opposite of what OPC's `Default Extension="rels"` means here.
    private static func fileExtension(of name: String) -> String {
        let last = (name as NSString).lastPathComponent
        guard let dotIndex = last.lastIndex(of: ".") else { return "" }
        return String(last[last.index(after: dotIndex)...])
    }

    private final class ContentTypesCollector: NSObject, XMLParserDelegate {
        var defaults: [String: String] = [:]
        var overrides: [String: String] = [:]

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String]) {
            switch elementName {
            case "Default":
                if let ext = attributes["Extension"], let contentType = attributes["ContentType"] {
                    defaults[ext] = contentType
                }
            case "Override":
                if let partName = attributes["PartName"], let contentType = attributes["ContentType"] {
                    overrides[partName] = contentType
                }
            default:
                break
            }
        }
    }

    // MARK: - Relationships

    private struct RelationshipEntry {
        let id: String
        let target: String
        let targetMode: String?
    }

    private static func parseRelationships(_ data: Data) -> [RelationshipEntry] {
        let parser = XMLParser(data: data)
        let delegate = RelationshipsCollector()
        parser.delegate = delegate
        _ = parser.parse()
        return delegate.entries
    }

    private final class RelationshipsCollector: NSObject, XMLParserDelegate {
        var entries: [RelationshipEntry] = []

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String]) {
            guard elementName == "Relationship" else { return }
            entries.append(RelationshipEntry(
                id: attributes["Id"] ?? "",
                target: attributes["Target"] ?? "",
                targetMode: attributes["TargetMode"]
            ))
        }
    }

    /// The directory a `.rels` part's targets are resolved against:
    /// `word/_rels/document.xml.rels` → `word`; `_rels/.rels` (root) → "".
    private static func ownerDirectory(ofRelsPart relsPath: String) -> String {
        // `<dir>/_rels/<name>.rels` → `<dir>`. The root form is `_rels/.rels`
        // with no `<dir>` prefix.
        guard let relsRange = relsPath.range(of: "_rels/", options: .backwards) else { return "" }
        let dir = relsPath[relsPath.startIndex..<relsRange.lowerBound]
        return dir.isEmpty ? "" : String(dir.dropLast())   // drop trailing "/"
    }

    /// Resolves a relationship `Target` against its owner directory,
    /// per OPC: a target starting with "/" is package-root-relative;
    /// otherwise it is relative to `ownerDirectory`. `.` and `..`
    /// components are normalized.
    private static func resolveTarget(_ target: String, ownerDirectory: String) -> String {
        let base: [String]
        var rest: Substring
        if target.hasPrefix("/") {
            base = []
            rest = target.dropFirst()
        } else {
            base = ownerDirectory.isEmpty ? [] : ownerDirectory.split(separator: "/").map(String.init)
            rest = Substring(target)
        }
        var components = base
        for component in rest.split(separator: "/", omittingEmptySubsequences: false) {
            switch component {
            case "", ".":
                continue
            case "..":
                if !components.isEmpty { components.removeLast() }
            default:
                components.append(String(component))
            }
        }
        return components.joined(separator: "/")
    }
}

// MARK: - SilentXMLParserDelegate

/// XMLParser swallows-everything delegate used for well-formedness-only
/// checks — same pattern as `Verifier`'s private delegate, duplicated here
/// because it is `private` there.
private final class SilentXMLParserDelegate: NSObject, XMLParserDelegate {
    // All methods default to no-op; XMLParser still surfaces parse errors
    // via parseErrorOccurred / parser.parserError.
}
