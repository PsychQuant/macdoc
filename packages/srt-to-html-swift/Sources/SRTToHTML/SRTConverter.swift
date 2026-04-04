import Foundation
import CommonConverterSwift

public struct SRTConverter: DocumentConverter {
    public static let sourceFormat = "srt"

    public init() {}

    /// Default: outputs HTML fragment (just the transcript `<main>` block).
    /// Use `convertFull(input:css:)` for a complete HTML document with CSS.
    public func convert<W: CommonConverterSwift.StreamingOutput>(
        input: URL,
        output: inout W,
        options: ConversionOptions
    ) throws {
        let source = try loadSource(from: input)
        let subtitles = parseSRT(source)
        let title = input.deletingPathExtension().lastPathComponent

        if options.includeFrontmatter {
            try output.writeLine("<!--")
            try output.writeLine("source: \(input.lastPathComponent)")
            try output.writeLine("format: srt")
            try output.writeLine("subtitle_count: \(subtitles.count)")
            try output.writeLine("-->")
        }

        try emitTranscriptBody(&output, title: title, subtitles: subtitles)
    }

    /// Output a complete HTML document with embedded CSS.
    public func convertFull(input: URL, css: String? = nil) throws -> String {
        let source = try loadSource(from: input)
        let subtitles = parseSRT(source)
        let title = input.deletingPathExtension().lastPathComponent
        let selectedCSS = css ?? SRTCSS.dark

        var writer = StringOutput()
        try writer.writeLine("<!DOCTYPE html>")
        try writer.writeLine("<html lang=\"en\">")
        try writer.writeLine("<head>")
        try writer.writeLine("  <meta charset=\"utf-8\" />")
        try writer.writeLine("  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />")
        try writer.writeLine("  <title>\(escapeHTML(title))</title>")
        try writer.writeLine("  <style>")
        try writer.writeLine(selectedCSS)
        try writer.writeLine("  </style>")
        try writer.writeLine("</head>")
        try writer.writeLine("<body>")
        try emitTranscriptBody(&writer, title: title, subtitles: subtitles)
        try writer.writeLine("</body>")
        try writer.writeLine("</html>")
        return writer.content
    }

    // MARK: - Shared Body

    private func emitTranscriptBody<W: StreamingOutput>(
        _ output: inout W,
        title: String,
        subtitles: [Subtitle]
    ) throws {
        try output.writeLine("<main class=\"transcript\">")
        try output.writeLine("  <header class=\"transcript-header\">")
        try output.writeLine("    <h1>\(escapeHTML(title))</h1>")
        try output.writeLine("    <p>\(subtitles.count) subtitle entries</p>")
        try output.writeLine("  </header>")

        for subtitle in subtitles {
            let speakerAttr = subtitle.speakerNumber.map { " data-speaker=\"\($0)\"" } ?? ""
            try output.writeLine("  <div class=\"subtitle\" data-index=\"\(subtitle.index)\" data-start=\"\(escapeHTML(subtitle.startTime))\" data-end=\"\(escapeHTML(subtitle.endTime))\"\(speakerAttr)>")
            try output.writeLine("    <div class=\"subtitle-meta\">")
            try output.writeLine("      <span class=\"subtitle-index\">#\(subtitle.index)</span>")
            try output.writeLine("      <span class=\"timestamp\">\(escapeHTML(subtitle.timestamp))</span>")
            try output.writeLine("    </div>")
            try output.writeLine("    <div class=\"subtitle-text\">")
            if let speaker = subtitle.speaker {
                let displayName = subtitle.speakerDisplay ?? speaker
                try output.writeLine("      <span class=\"speaker\">\(escapeHTML(displayName))</span>")
            }
            try output.writeLine("      <span class=\"text\">\(subtitle.htmlText)</span>")
            try output.writeLine("    </div>")
            try output.writeLine("  </div>")
        }

        try output.writeLine("</main>")
    }

    // MARK: - File Loading

    private func loadSource(from input: URL) throws -> String {
        do {
            return try String(contentsOf: input, encoding: .utf8)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileReadNoPermission || error.code == .fileNoSuchFile {
            throw error
        } catch {
            if let utf16 = try? String(contentsOf: input, encoding: .utf16) { return utf16 }
            if let latin1 = try? String(contentsOf: input, encoding: .isoLatin1) { return latin1 }
            return try String(contentsOf: input, encoding: .utf8)
        }
    }

    // MARK: - SRT Parsing

    private func parseSRT(_ source: String) -> [Subtitle] {
        let normalized = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return [] }

        return normalized
            .components(separatedBy: "\n\n")
            .compactMap(parseBlock)
    }

    private func parseBlock(_ block: String) -> Subtitle? {
        let lines = block
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard lines.count >= 2 else { return nil }

        let index = Int(lines[0]) ?? 0
        let timestamp = lines[1]
        let parts = timestamp.components(separatedBy: " --> ")
        let startTime = parts.first ?? timestamp
        let endTime = parts.count > 1 ? parts[1] : timestamp
        let textLines = Array(lines.dropFirst(2))

        let speaker = detectSpeaker(in: textLines.first)
        let htmlText = textLines
            .map { line in
                if let speaker {
                    if speaker.hasPrefix("[") {
                        // Bracket format: [Speaker 1] text
                        if line.hasPrefix(speaker) {
                            let trimmed = line.dropFirst(speaker.count).trimmingCharacters(in: .whitespaces)
                            return escapeHTML(trimmed)
                        }
                    } else if line.hasPrefix("\(speaker):") {
                        // Colon format: Speaker 1: text
                        let trimmed = line.dropFirst(speaker.count + 1).trimmingCharacters(in: .whitespaces)
                        return escapeHTML(trimmed)
                    }
                }
                return escapeHTML(line)
            }
            .joined(separator: "<br />")

        return Subtitle(
            index: index,
            startTime: startTime,
            endTime: endTime,
            timestamp: timestamp,
            speaker: speaker,
            htmlText: htmlText
        )
    }

    private static let speakerPattern: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"^[A-Za-z0-9 _\-]+$"#)
    }()

    /// Matches `[Speaker Name] text` — brackets around the speaker label.
    /// Supports ASCII and non-ASCII (CJK, etc.) speaker names.
    private static let bracketSpeakerPattern: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"^\[([^\]\n]{1,40})\]\s*"#)
    }()

    /// Detect speaker from either `Name: text` (colon) or `[Name] text` (bracket) format.
    private func detectSpeaker(in line: String?) -> String? {
        guard let line else { return nil }

        // Try bracket format first: [Speaker 1] text
        let nsLine = line as NSString
        let lineRange = NSRange(location: 0, length: nsLine.length)
        if let match = Self.bracketSpeakerPattern.firstMatch(in: line, range: lineRange) {
            let speakerRange = match.range(at: 1)
            let speaker = nsLine.substring(with: speakerRange)
            return "[\(speaker)]"
        }

        // Fall back to colon format: Speaker 1: text
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let prefix = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
        guard !prefix.isEmpty, prefix.count <= 40 else { return nil }
        let range = NSRange(prefix.startIndex..., in: prefix)
        guard Self.speakerPattern.firstMatch(in: prefix, range: range) != nil else { return nil }
        return prefix
    }

    private func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}

// MARK: - CSS Styles

public struct SRTCSS {
    /// Dark theme (default) — dark background, card-style subtitle entries.
    public static let dark = """
    body {
      margin: 0;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      background: #0b1020;
      color: #e5e7eb;
    }
    .transcript { max-width: 900px; margin: 0 auto; padding: 32px 20px 48px; }
    .transcript-header { margin-bottom: 24px; }
    .transcript-header h1 { margin: 0 0 8px; font-size: 2rem; }
    .transcript-header p { margin: 0; color: #94a3b8; }
    .subtitle {
      padding: 16px; margin-bottom: 12px;
      border: 1px solid #1f2937; border-radius: 12px;
      background: #111827; box-shadow: 0 8px 24px rgba(0, 0, 0, 0.18);
    }
    .subtitle-meta { display: flex; gap: 12px; align-items: center; margin-bottom: 8px; font-size: 0.9rem; }
    .subtitle-index { color: #93c5fd; font-weight: 600; }
    .timestamp { color: #fca5a5; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
    .subtitle-text { line-height: 1.65; font-size: 1rem; }
    .speaker {
      display: inline-block; margin-right: 8px; padding: 2px 8px;
      border-radius: 999px; background: #1d4ed8; color: white;
      font-size: 0.85rem; font-weight: 600; vertical-align: middle;
    }
    .text { vertical-align: middle; }
    """

    /// Light theme — clean white background, suitable for printing or embedding.
    public static let light = """
    body {
      margin: 0;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      background: #ffffff;
      color: #1f2937;
    }
    .transcript { max-width: 900px; margin: 0 auto; padding: 32px 20px 48px; }
    .transcript-header { margin-bottom: 24px; border-bottom: 1px solid #e5e7eb; padding-bottom: 16px; }
    .transcript-header h1 { margin: 0 0 8px; font-size: 1.75rem; }
    .transcript-header p { margin: 0; color: #6b7280; }
    .subtitle { padding: 12px 0; border-bottom: 1px solid #f3f4f6; }
    .subtitle-meta { display: flex; gap: 12px; align-items: center; margin-bottom: 4px; font-size: 0.85rem; }
    .subtitle-index { color: #6b7280; }
    .timestamp { color: #9ca3af; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 0.8rem; }
    .subtitle-text { line-height: 1.65; font-size: 1rem; }
    .speaker {
      display: inline-block; margin-right: 8px; padding: 1px 6px;
      border-radius: 4px; background: #dbeafe; color: #1e40af;
      font-size: 0.85rem; font-weight: 600; vertical-align: middle;
    }
    .text { vertical-align: middle; }
    """
}

private struct Subtitle {
    let index: Int
    let startTime: String
    let endTime: String
    let timestamp: String
    let speaker: String?       // Raw: "Speaker 1" or "[Speaker 1]"
    let htmlText: String

    /// Extract numeric speaker ID if present (e.g. "Speaker 1" → "1", "[Speaker 2]" → "2").
    var speakerNumber: String? {
        guard let speaker else { return nil }
        let cleaned = speaker.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        // Match trailing digits
        if let range = cleaned.range(of: #"\d+$"#, options: .regularExpression) {
            return String(cleaned[range])
        }
        return nil
    }

    /// Display name without brackets for the badge.
    var speakerDisplay: String? {
        guard let speaker else { return nil }
        if speaker.hasPrefix("[") && speaker.hasSuffix("]") {
            return String(speaker.dropFirst().dropLast())
        }
        return speaker
    }
}
