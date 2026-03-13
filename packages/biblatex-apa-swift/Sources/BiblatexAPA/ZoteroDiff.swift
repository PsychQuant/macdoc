// Sources/CheBiblatexMCPCore/ZoteroDiff.swift
// Compare .bib entries against Zotero SQLite database with field mapping awareness.

import Foundation
import SQLite3

// MARK: - Zotero Lite Reader (minimal, just for diff)

public struct ZoteroLiteItem {
    public let key: String
    public let itemType: String
    public let title: String
    public let doi: String?
    public let date: String?
    public let creators: [String]  // "Last, First" format
    public let fields: [String: String]  // all fields
}

public struct ZoteroLiteReader {

    /// Find the Zotero SQLite database path.
    public static func findDatabase() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/Zotero/zotero.sqlite",
            "\(home)/Library/Application Support/Zotero/Profiles",
        ]

        if FileManager.default.fileExists(atPath: candidates[0]) {
            return candidates[0]
        }

        // Search in profiles
        let profilesDir = candidates[1]
        if let profiles = try? FileManager.default.contentsOfDirectory(atPath: profilesDir) {
            for profile in profiles where profile.hasSuffix(".default") {
                let dbPath = "\(profilesDir)/\(profile)/zotero/zotero.sqlite"
                if FileManager.default.fileExists(atPath: dbPath) {
                    return dbPath
                }
            }
        }

        return nil
    }

    /// Read items from Zotero SQLite (read-only, using immutable mode).
    public static func readItems(dbPath: String) throws -> [ZoteroLiteItem] {
        var db: OpaquePointer?
        let uri = "file:\(dbPath)?mode=ro&immutable=1"

        guard sqlite3_open_v2(uri, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK else {
            let msg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            throw ZoteroDiffError.databaseError("Cannot open: \(msg)")
        }
        defer { sqlite3_close(db) }

        // Get items with their types
        let itemsSQL = """
            SELECT i.key, it.typeName, iv.value AS title
            FROM items i
            JOIN itemTypes it ON i.itemTypeID = it.itemTypeID
            LEFT JOIN itemData id ON i.itemID = id.itemID
            LEFT JOIN itemDataValues iv ON id.valueID = iv.valueID
            LEFT JOIN fields f ON id.fieldID = f.fieldID AND f.fieldName = 'title'
            WHERE it.typeName NOT IN ('attachment', 'note')
            AND i.libraryID = 1
            ORDER BY i.dateModified DESC
        """

        var items: [String: (type: String, title: String, fields: [String: String], creators: [String])] = [:]
        try query(db: db!, sql: itemsSQL) { row in
            let key = String(cString: sqlite3_column_text(row, 0))
            let type = String(cString: sqlite3_column_text(row, 1))
            let title = sqlite3_column_text(row, 2).map { String(cString: $0) } ?? ""
            if items[key] == nil {
                items[key] = (type: type, title: title, fields: [:], creators: [])
            }
        }

        // Get all fields for each item
        let fieldsSQL = """
            SELECT i.key, f.fieldName, iv.value
            FROM items i
            JOIN itemData id ON i.itemID = id.itemID
            JOIN fields f ON id.fieldID = f.fieldID
            JOIN itemDataValues iv ON id.valueID = iv.valueID
            WHERE i.key IN (\(items.keys.map { "'\($0)'" }.joined(separator: ",")))
        """

        if !items.isEmpty {
            try query(db: db!, sql: fieldsSQL) { row in
                let key = String(cString: sqlite3_column_text(row, 0))
                let field = String(cString: sqlite3_column_text(row, 1))
                let value = String(cString: sqlite3_column_text(row, 2))
                items[key]?.fields[field] = value
            }
        }

        // Get creators
        let creatorsSQL = """
            SELECT i.key, c.firstName, c.lastName
            FROM items i
            JOIN itemCreators ic ON i.itemID = ic.itemID
            JOIN creators c ON ic.creatorID = c.creatorID
            WHERE i.key IN (\(items.keys.map { "'\($0)'" }.joined(separator: ",")))
            ORDER BY ic.orderIndex
        """

        if !items.isEmpty {
            try query(db: db!, sql: creatorsSQL) { row in
                let key = String(cString: sqlite3_column_text(row, 0))
                let first = sqlite3_column_text(row, 1).map { String(cString: $0) } ?? ""
                let last = sqlite3_column_text(row, 2).map { String(cString: $0) } ?? ""
                items[key]?.creators.append("\(last), \(first)")
            }
        }

        return items.map { (key, data) in
            ZoteroLiteItem(
                key: key,
                itemType: data.type,
                title: data.fields["title"] ?? data.title,
                doi: data.fields["DOI"],
                date: data.fields["date"],
                creators: data.creators,
                fields: data.fields
            )
        }
    }

    private static func query(db: OpaquePointer, sql: String, handler: (OpaquePointer) -> Void) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            let msg = String(cString: sqlite3_errmsg(db))
            throw ZoteroDiffError.databaseError("Query failed: \(msg)")
        }
        defer { sqlite3_finalize(stmt) }

        while sqlite3_step(stmt) == SQLITE_ROW {
            handler(stmt!)
        }
    }
}

// MARK: - Diff Engine

public struct BibZoteroDiffResult {
    public let onlyInBib: [BibEntry]           // In .bib but not in Zotero
    public let onlyInZotero: [ZoteroLiteItem]  // In Zotero but not in .bib
    public let matched: [(bib: BibEntry, zotero: ZoteroLiteItem, issues: [String])]

    public var summary: String {
        var lines: [String] = []
        lines.append("## Diff Summary")
        lines.append("- Matched: \(matched.count)")
        lines.append("- Only in .bib: \(onlyInBib.count)")
        lines.append("- Only in Zotero: \(onlyInZotero.count)")

        if !onlyInBib.isEmpty {
            lines.append("\n### Only in .bib")
            for e in onlyInBib {
                lines.append("- [\(e.key)] \(e.title ?? "untitled")")
            }
        }

        if !onlyInZotero.isEmpty {
            lines.append("\n### Only in Zotero")
            for z in onlyInZotero {
                let authors = z.creators.prefix(2).joined(separator: ", ")
                let etAl = z.creators.count > 2 ? " et al." : ""
                lines.append("- [\(z.key)] \(z.title) — \(authors)\(etAl)")
            }
        }

        let withIssues = matched.filter { !$0.issues.isEmpty }
        if !withIssues.isEmpty {
            lines.append("\n### Field Mismatches")
            for m in withIssues {
                lines.append("- [\(m.bib.key)]")
                for issue in m.issues {
                    lines.append("  - \(issue)")
                }
            }
        }

        return lines.joined(separator: "\n")
    }
}

public struct BibZoteroDiff {

    /// Field mapping: Zotero field name → biblatex field name
    private static let fieldMapping: [String: String] = [
        "title": "TITLE",
        "DOI": "DOI",
        "date": "DATE",
        "publicationTitle": "JOURNALTITLE",
        "volume": "VOLUME",
        "issue": "NUMBER",
        "pages": "PAGES",
        "url": "URL",
        "abstractNote": "ABSTRACT",
        "meetingName": "EVENTTITLE",
        "conferenceName": "EVENTTITLE",
        "place": "VENUE",
        "presentationType": "TITLEADDON",
        "institution": "INSTITUTION",
    ]

    /// Compare a .bib file against Zotero items.
    /// Matching strategy: DOI (exact) → title similarity (fuzzy).
    public static func diff(bibFile: BibFile, zoteroItems: [ZoteroLiteItem]) -> BibZoteroDiffResult {
        var matched: [(bib: BibEntry, zotero: ZoteroLiteItem, issues: [String])] = []
        var unmatchedBib = bibFile.entries
        var unmatchedZotero = zoteroItems

        // Pass 1: Match by DOI (most reliable)
        for bibEntry in bibFile.entries {
            guard let bibDOI = bibEntry.doi?.lowercased().trimmingCharacters(in: .whitespaces),
                  !bibDOI.isEmpty else { continue }

            if let zIdx = unmatchedZotero.firstIndex(where: {
                $0.doi?.lowercased().trimmingCharacters(in: .whitespaces) == bibDOI
            }) {
                let zItem = unmatchedZotero[zIdx]
                let issues = compareFields(bib: bibEntry, zotero: zItem)
                matched.append((bib: bibEntry, zotero: zItem, issues: issues))
                unmatchedBib.removeAll { $0.key == bibEntry.key }
                unmatchedZotero.remove(at: zIdx)
            }
        }

        // Pass 2: Match by normalized title
        for bibEntry in Array(unmatchedBib) {
            guard let bibTitle = bibEntry.title else { continue }
            let normalizedBib = normalizeTitle(bibTitle)
            if normalizedBib.isEmpty { continue }

            if let zIdx = unmatchedZotero.firstIndex(where: {
                normalizeTitle($0.title) == normalizedBib
            }) {
                let zItem = unmatchedZotero[zIdx]
                let issues = compareFields(bib: bibEntry, zotero: zItem)
                matched.append((bib: bibEntry, zotero: zItem, issues: issues))
                unmatchedBib.removeAll { $0.key == bibEntry.key }
                unmatchedZotero.remove(at: zIdx)
            }
        }

        return BibZoteroDiffResult(
            onlyInBib: unmatchedBib,
            onlyInZotero: unmatchedZotero,
            matched: matched
        )
    }

    // MARK: - Helpers

    /// Compare mapped fields between bib and Zotero.
    private static func compareFields(bib: BibEntry, zotero: ZoteroLiteItem) -> [String] {
        var issues: [String] = []

        for (zField, bibField) in fieldMapping {
            guard let zValue = zotero.fields[zField], !zValue.isEmpty else { continue }
            let bibValue = bib.fields.values[bibField] ?? bib.fields.values[bibField.lowercased()]

            if bibValue == nil {
                // Field exists in Zotero but not in .bib
                issues.append("\(bibField): missing in .bib (Zotero has: \(zValue.prefix(60)))")
            } else if let bv = bibValue {
                // Compare (strip LaTeX formatting for comparison)
                let cleanBib = stripLaTeX(bv).lowercased()
                let cleanZ = zValue.lowercased()
                if cleanBib != cleanZ && !cleanBib.contains(cleanZ) && !cleanZ.contains(cleanBib) {
                    issues.append("\(bibField): bib='\(bv.prefix(40))' vs zotero='\(zValue.prefix(40))'")
                }
            }
        }

        return issues
    }

    /// Normalize title for matching: strip LaTeX, lowercase, remove punctuation.
    private static func normalizeTitle(_ title: String) -> String {
        var s = stripLaTeX(title)
        s = s.lowercased()
        s = s.replacingOccurrences(of: "[^a-z0-9 ]", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// Strip common LaTeX commands for comparison purposes.
    private static func stripLaTeX(_ text: String) -> String {
        var s = text
        // Remove braces used for protection: {Bayesian} → Bayesian
        s = s.replacingOccurrences(of: "{", with: "")
        s = s.replacingOccurrences(of: "}", with: "")
        // Remove common LaTeX commands
        s = s.replacingOccurrences(of: "\\textbf", with: "")
        s = s.replacingOccurrences(of: "\\textit", with: "")
        s = s.replacingOccurrences(of: "\\emph", with: "")
        s = s.replacingOccurrences(of: "\\textsuperscript", with: "")
        // Accents: \'{e} → e
        s = s.replacingOccurrences(of: "\\'\\{([a-zA-Z])\\}", with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\'([a-zA-Z])", with: "$1", options: .regularExpression)
        return s
    }
}

public enum ZoteroDiffError: Error, LocalizedError {
    case databaseError(String)
    case databaseNotFound

    public var errorDescription: String? {
        switch self {
        case .databaseError(let msg): return "Zotero database error: \(msg)"
        case .databaseNotFound: return "Zotero database not found. Is Zotero installed?"
        }
    }
}
