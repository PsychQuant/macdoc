// Verifier.swift — §5.1–§5.5 of macdoc-docx-workflow-cli.
//
// Phase 1 post-condition catalog:
// - expected_images        — count <a:blip>-equivalent ImageReferences
// - expected_paragraphs_min — minimum paragraph count
// - expected_bookmarks_min  — minimum bookmark count (sum across paragraphs)
// - libxml2_valid          — Foundation XMLParser cleanliness check
// - byte_preserved_parts   — raw-byte equality on listed OOXML parts (Phase 1
//                            uses raw bytes; c14n is a Phase 2 follow-up)

import Foundation

public enum VerifyError: Error, Equatable {
    case imageCountMismatch(expected: Int, observed: Int)
    case paragraphCountBelowMin(expected: Int, observed: Int)
    case bookmarkCountBelowMin(expected: Int, observed: Int)
    case libxml2InvalidPart(partName: String, message: String)
    case bytePreservedPartChanged(partName: String, baselineSize: Int, outputSize: Int, diffOffset: Int)
}

public struct Verifier {

    public init() {}

    public func verify(
        _ assertions: VerifyAssertions,
        baselineURL: URL,
        outputURL: URL
    ) throws {
        let outputDoc = try DocxReader.read(from: outputURL, wireTreeBackedViews: false)

        if let expected = assertions.expectedImages {
            let observed = outputDoc.images.count
            if observed != expected {
                throw VerifyError.imageCountMismatch(expected: expected, observed: observed)
            }
        }

        if let min = assertions.expectedParagraphsMin {
            let observed = countParagraphs(outputDoc)
            if observed < min {
                throw VerifyError.paragraphCountBelowMin(expected: min, observed: observed)
            }
        }

        if let min = assertions.expectedBookmarksMin {
            let observed = countBookmarks(outputDoc)
            if observed < min {
                throw VerifyError.bookmarkCountBelowMin(expected: min, observed: observed)
            }
        }

        if let shouldValidate = assertions.libxml2Valid, shouldValidate {
            try checkLibxml2Valid(outputURL: outputURL)
        }

        if let patterns = assertions.bytePreservedParts, !patterns.isEmpty {
            try checkBytePreservedParts(patterns: patterns, baselineURL: baselineURL, outputURL: outputURL)
        }
    }

    // MARK: - §5.2 expected_images / §5.3 paragraph + bookmark counts

    private func countParagraphs(_ doc: WordDocument) -> Int {
        var count = 0
        for child in doc.body.children {
            if case .paragraph = child {
                count += 1
            }
        }
        return count
    }

    private func countBookmarks(_ doc: WordDocument) -> Int {
        var count = 0
        for child in doc.body.children {
            if case .paragraph(let paragraph) = child {
                count += paragraph.bookmarks.count
            }
        }
        return count
    }

    // MARK: - §5.4 libxml2_valid (Phase 1: Foundation XMLParser)

    private func checkLibxml2Valid(outputURL: URL) throws {
        let unzippedRoot = try ZipHelper.unzip(outputURL)
        defer { ZipHelper.cleanup(unzippedRoot) }

        // Parts whose schema is OOXML-defined (must be valid XML).
        let candidateParts = [
            "word/document.xml",
            "word/numbering.xml",
            "word/styles.xml",
            "word/settings.xml",
            "word/fontTable.xml",
            "word/comments.xml",
            "word/footnotes.xml",
            "word/endnotes.xml",
        ]

        for partName in candidateParts {
            let partURL = unzippedRoot.appendingPathComponent(partName)
            guard FileManager.default.fileExists(atPath: partURL.path) else {
                continue  // Optional part absent — not an error.
            }
            let data = try Data(contentsOf: partURL)
            let parser = XMLParser(data: data)
            let delegate = SilentXMLParserDelegate()
            parser.delegate = delegate
            if !parser.parse() {
                let msg = parser.parserError?.localizedDescription ?? "unknown parse error"
                throw VerifyError.libxml2InvalidPart(partName: partName, message: msg)
            }
        }

        // header*.xml and footer*.xml — glob over the word/ directory.
        try checkHeaderFooterValid(inside: unzippedRoot)
    }

    private func checkHeaderFooterValid(inside root: URL) throws {
        let wordDir = root.appendingPathComponent("word")
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: wordDir.path) else {
            return
        }
        for entry in entries where entry.hasPrefix("header") || entry.hasPrefix("footer") {
            guard entry.hasSuffix(".xml") else { continue }
            let partURL = wordDir.appendingPathComponent(entry)
            let data = try Data(contentsOf: partURL)
            let parser = XMLParser(data: data)
            let delegate = SilentXMLParserDelegate()
            parser.delegate = delegate
            if !parser.parse() {
                let msg = parser.parserError?.localizedDescription ?? "unknown parse error"
                throw VerifyError.libxml2InvalidPart(partName: "word/\(entry)", message: msg)
            }
        }
    }

    // MARK: - §5.5 byte_preserved_parts (Phase 1: raw bytes; c14n in Phase 2)

    private func checkBytePreservedParts(
        patterns: [String],
        baselineURL: URL,
        outputURL: URL
    ) throws {
        let baselineRoot = try ZipHelper.unzip(baselineURL)
        let outputRoot = try ZipHelper.unzip(outputURL)
        defer {
            ZipHelper.cleanup(baselineRoot)
            ZipHelper.cleanup(outputRoot)
        }

        let matchedParts = try gatherMatchingParts(patterns: patterns, root: baselineRoot)
        for partName in matchedParts {
            let baselinePart = baselineRoot.appendingPathComponent(partName)
            let outputPart = outputRoot.appendingPathComponent(partName)

            let baselineData = (try? Data(contentsOf: baselinePart)) ?? Data()
            let outputData = (try? Data(contentsOf: outputPart)) ?? Data()

            if baselineData != outputData {
                let diffOffset = firstDifferingOffset(baselineData, outputData)
                throw VerifyError.bytePreservedPartChanged(
                    partName: partName,
                    baselineSize: baselineData.count,
                    outputSize: outputData.count,
                    diffOffset: diffOffset
                )
            }
        }
    }

    /// Walks the unzipped baseline tree and returns the relative paths of
    /// files whose path matches any of the glob patterns. Supports simple
    /// `*` and `**` wildcards (POSIX `fnmatch`-style).
    private func gatherMatchingParts(patterns: [String], root: URL) throws -> [String] {
        let fm = FileManager.default
        // Canonicalize root path so symlink resolution (/var → /private/var on
        // macOS temp dirs) doesn't break the prefix strip below.
        let canonicalRoot = root.resolvingSymlinksInPath().path
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return []
        }
        var matches: [String] = []
        for case let fileURL as URL in enumerator {
            let isRegular = (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile ?? false
            guard isRegular else { continue }
            let canonicalFilePath = fileURL.resolvingSymlinksInPath().path
            guard canonicalFilePath.hasPrefix(canonicalRoot + "/") else { continue }
            let relativePath = String(canonicalFilePath.dropFirst(canonicalRoot.count + 1))
            for pattern in patterns where fnmatch(pattern: pattern, path: relativePath) {
                matches.append(relativePath)
                break
            }
        }
        return matches.sorted()
    }

    private func fnmatch(pattern: String, path: String) -> Bool {
        // Minimal glob implementation — supports `*` (any segment chars
        // except `/`) and `**` (any chars including `/`). Sufficient for
        // OOXML part patterns like `word/header*.xml`, `word/theme/*.xml`.
        let regexPattern = pattern
            .replacingOccurrences(of: ".", with: "\\.")
            .replacingOccurrences(of: "**", with: ".*")
            .replacingOccurrences(of: "*", with: "[^/]*")
        guard let regex = try? NSRegularExpression(pattern: "^\(regexPattern)$") else {
            return false
        }
        let range = NSRange(path.startIndex..., in: path)
        return regex.firstMatch(in: path, range: range) != nil
    }

    private func firstDifferingOffset(_ a: Data, _ b: Data) -> Int {
        let minLen = Swift.min(a.count, b.count)
        for i in 0..<minLen where a[i] != b[i] {
            return i
        }
        return minLen
    }
}

// MARK: - SilentXMLParserDelegate

/// XMLParser swallows-everything delegate used for cleanliness-only checks.
private final class SilentXMLParserDelegate: NSObject, XMLParserDelegate {
    // All methods default to no-op; XMLParser still surfaces parse errors
    // via parseErrorOccurred / parser.parserError.
}
