import Foundation
import ArgumentParser
import BibAPAToHTML

// MARK: - File Validation

/// Validate that a file exists and return its URL.
func validatedInputURL(_ path: String) throws -> URL {
    let url = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw ValidationError("找不到輸入檔案: \(path)")
    }
    return url
}

// MARK: - String Output

/// Write a string to a file or stdout.
/// Status message is written to stderr when writing to a file.
func writeStringOutput(_ content: String, to outputPath: String?) throws {
    if let outputPath = outputPath {
        let outputURL = URL(fileURLWithPath: outputPath)
        try content.write(to: outputURL, atomically: true, encoding: .utf8)
        FileHandle.standardError.write(
            Data("已寫入: \(outputURL.path)\n".utf8)
        )
    } else {
        print(content)
    }
}

// MARK: - Bib Helpers

/// Load and optionally filter bib entries from a .bib file.
func loadBibEntries(from path: String, filterKeys: [String] = []) throws -> [BibEntry] {
    let inputURL = try validatedInputURL(path)
    let bibFile = try BibParser.parse(filePath: inputURL.path)
    var entries = bibFile.entries

    if !filterKeys.isEmpty {
        let keySet = Set(filterKeys)
        entries = entries.filter { keySet.contains($0.key) }
        if entries.isEmpty {
            throw ValidationError("找不到指定的 entry keys: \(filterKeys.joined(separator: ", "))")
        }
    }

    return entries
}

/// Build a full APA 7 HTML document with DOCTYPE, head, CSS, and body.
func buildAPAFullHTML(entries: [BibEntry], css: CSSStyle) -> String {
    let cssString = css == .minimal ? APACSS.minimal : APACSS.web
    let body = BibToAPAHTMLFormatter.formatReferenceList(entries)
    return """
    <!DOCTYPE html>
    <html lang="en">
    <head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>APA 7 References</title>
    <style>
    \(cssString)
    </style>
    </head>
    <body>
    <div class="apa-reference-list">
    \(body)
    </div>
    </body>
    </html>
    """
}

// MARK: - CSS Style Enum

/// Unified CSS style for all HTML-outputting converters.
/// - bib: `minimal` (academic) or `web` (modern)
/// - srt: `dark` (dark theme) or `light` (print-friendly)
enum CSSStyle: String, ExpressibleByArgument, CaseIterable {
    case minimal
    case web
    case dark
    case light
}
