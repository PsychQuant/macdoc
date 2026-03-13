// Sources/CheBiblatexMCPCore/BibValidator.swift
// Validate biblatex entries against APA 7 field requirements.

import Foundation

public struct ValidationIssue: CustomStringConvertible {
    public enum Severity: String {
        case error = "ERROR"
        case warning = "WARNING"
    }

    public let key: String
    public let severity: Severity
    public let message: String

    public var description: String {
        "[\(severity.rawValue)] [\(key)] \(message)"
    }
}

public struct BibValidator {

    // Required fields per entry type (APA 7 biblatex)
    private static let requiredFields: [String: [String]] = [
        "ARTICLE": ["AUTHOR", "TITLE", "JOURNALTITLE", "DATE"],
        "PRESENTATION": ["AUTHOR", "TITLE", "EVENTTITLE", "DATE"],
        "REPORT": ["AUTHOR", "TITLE", "DATE"],
        "BOOK": ["AUTHOR", "TITLE", "DATE"],
        "INCOLLECTION": ["AUTHOR", "TITLE", "BOOKTITLE", "DATE"],
        "INPROCEEDINGS": ["AUTHOR", "TITLE", "BOOKTITLE", "DATE"],
        "THESIS": ["AUTHOR", "TITLE", "INSTITUTION", "DATE"],
    ]

    // Recommended fields (warnings if missing)
    private static let recommendedFields: [String: [String]] = [
        "ARTICLE": ["DOI", "VOLUME"],
        "PRESENTATION": ["VENUE"],
    ]

    /// Validate all entries in a BibFile.
    public static func validate(_ bibFile: BibFile) -> [ValidationIssue] {
        bibFile.entries.flatMap { validate(entry: $0) }
    }

    /// Validate a single entry.
    public static func validate(entry: BibEntry) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        let type = entry.normalizedType

        // Check required fields (case-insensitive)
        if let required = requiredFields[type] {
            for field in required {
                if !hasField(entry, field) {
                    issues.append(ValidationIssue(
                        key: entry.key,
                        severity: .error,
                        message: "Missing required field: \(field)"
                    ))
                }
            }
        }

        // Check recommended fields (context-aware for PRESENTATION)
        let recommended: [String]
        if type == "PRESENTATION" {
            let hasMainTitle = hasField(entry, "MAINTITLE")
            recommended = APADataModel.presentationRecommendedFields(
                hasMainTitle: hasMainTitle
            )
        } else {
            recommended = recommendedFields[type] ?? []
        }
        for field in recommended {
            if !hasField(entry, field) {
                issues.append(ValidationIssue(
                    key: entry.key,
                    severity: .warning,
                    message: "Missing recommended field: \(field)"
                ))
            }
        }

        // Check for empty title
        if let title = entry.title, title.trimmingCharacters(in: .whitespaces).isEmpty {
            issues.append(ValidationIssue(
                key: entry.key,
                severity: .error,
                message: "Title is empty"
            ))
        }

        // Check CV type field
        if entry.bibType == nil {
            issues.append(ValidationIssue(
                key: entry.key,
                severity: .warning,
                message: "Missing 'type' field for CV categorization (e.g., 'Journal Article', 'Conference Presentation')"
            ))
        }

        // Check author format: should use "and" separator
        if let authors = entry.authors {
            if authors.contains(";") {
                issues.append(ValidationIssue(
                    key: entry.key,
                    severity: .error,
                    message: "Authors should use 'and' separator, not ';'"
                ))
            }
            // Check for full name format (Last, First)
            let authorList = authors.components(separatedBy: " and ")
            for author in authorList {
                let trimmed = author.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty && !trimmed.contains(",") {
                    issues.append(ValidationIssue(
                        key: entry.key,
                        severity: .warning,
                        message: "Author '\(trimmed)' should use 'Last, First' format"
                    ))
                }
            }
        }

        return issues
    }

    private static func hasField(_ entry: BibEntry, _ fieldName: String) -> Bool {
        // Case-insensitive field lookup
        let lower = fieldName.lowercased()
        return entry.fields.keys.contains { $0.lowercased() == lower }
    }
}
