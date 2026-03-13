// Sources/CheBiblatexMCPCore/BibWriter.swift
// Write/modify .bib files while preserving formatting of untouched entries.

import Foundation

public struct BibWriter {

    /// Serialize a single entry to biblatex format.
    public static func serialize(_ entry: BibEntry, indent: String = "  ") -> String {
        var lines: [String] = []
        lines.append("@\(entry.entryType.uppercased()){\(entry.key),")
        for pair in entry.fields.pairs {
            let value = needsBraces(pair.value) ? "{\(pair.value)}" : pair.value
            lines.append("\(indent)\(pair.key.uppercased()) = \(value),")
        }
        lines.append("}")
        return lines.joined(separator: "\n")
    }

    /// Result of an add operation, indicating whether a new entry was created or skipped (duplicate).
    public struct AddEntryResult {
        public let entry: BibEntry
        public let isDuplicate: Bool
    }

    /// Add a new entry to a .bib file (appends at the end).
    /// Idempotent: if a citation key already exists, skips the write and returns the existing entry.
    @discardableResult
    public static func addEntry(
        to filePath: String,
        entry: BibEntry
    ) throws -> AddEntryResult {
        var content = try String(contentsOfFile: filePath, encoding: .utf8)

        // Idempotency check: parse file and look for existing key
        let bibFile = BibParser.parse(content: content, filePath: filePath)
        if let existing = bibFile.entry(forKey: entry.key) {
            return AddEntryResult(entry: existing, isDuplicate: true)
        }

        // Ensure trailing newline
        if !content.hasSuffix("\n") { content += "\n" }

        // Append new entry
        content += "\n" + serialize(entry) + "\n"

        try content.write(toFile: filePath, atomically: true, encoding: .utf8)
        return AddEntryResult(entry: entry, isDuplicate: false)
    }

    /// Update fields on an existing entry in the .bib file.
    /// Preserves the original entry's formatting for unchanged fields.
    public static func updateEntry(
        in filePath: String,
        key: String,
        updatedFields: [String: String]
    ) throws {
        let content = try String(contentsOfFile: filePath, encoding: .utf8)
        let bibFile = BibParser.parse(content: content, filePath: filePath)

        guard let existing = bibFile.entry(forKey: key) else {
            throw BibWriterError.entryNotFound(key)
        }

        // Build updated entry (normalize field keys to UPPERCASE per biblatex-apa convention)
        var newFields = existing.fields
        for (k, v) in updatedFields {
            newFields[k.uppercased()] = v
        }

        let updatedEntry = BibEntry(
            entryType: existing.entryType.uppercased(),
            key: key,
            fields: newFields,
            rawText: "",
            lineNumber: existing.lineNumber
        )

        let newEntryText = serialize(updatedEntry)
        let newContent = content.replacingOccurrences(of: existing.rawText, with: newEntryText)

        try newContent.write(toFile: filePath, atomically: true, encoding: .utf8)
    }

    /// Delete an entry from a .bib file by key.
    public static func deleteEntry(in filePath: String, key: String) throws {
        let content = try String(contentsOfFile: filePath, encoding: .utf8)
        let bibFile = BibParser.parse(content: content, filePath: filePath)

        guard let existing = bibFile.entry(forKey: key) else {
            throw BibWriterError.entryNotFound(key)
        }

        // Remove the entry text and any leading blank lines
        var newContent = content.replacingOccurrences(of: existing.rawText, with: "")
        // Clean up double blank lines
        while newContent.contains("\n\n\n") {
            newContent = newContent.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }

        try newContent.write(toFile: filePath, atomically: true, encoding: .utf8)
    }

    // MARK: - Helpers

    private static func needsBraces(_ value: String) -> Bool {
        // Numeric values don't need braces
        if Int(value) != nil { return false }
        return true
    }
}

public enum BibWriterError: Error, LocalizedError {
    case entryNotFound(String)
    case fileNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .entryNotFound(let key): return "Entry not found: \(key)"
        case .fileNotFound(let path): return "File not found: \(path)"
        }
    }
}
