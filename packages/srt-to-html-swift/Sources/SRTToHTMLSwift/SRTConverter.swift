import Foundation
import DocConverterSwift

public struct SRTConverter: DocumentConverter {
    public static let sourceFormat = "srt"

    public init() {}

    public func convert<W: DocConverterSwift.StreamingOutput>(
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

        try output.writeLine("<!DOCTYPE html>")
        try output.writeLine("<html lang=\"en\">")
        try output.writeLine("<head>")
        try output.writeLine("  <meta charset=\"utf-8\" />")
        try output.writeLine("  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />")
        try output.writeLine("  <title>\(escapeHTML(title))</title>")
        try output.writeLine("  <style>")
        try output.writeLine(css)
        try output.writeLine("  </style>")
        try output.writeLine("</head>")
        try output.writeLine("<body>")
        try output.writeLine("  <main class=\"transcript\">")
        try output.writeLine("    <header class=\"transcript-header\">")
        try output.writeLine("      <h1>\(escapeHTML(title))</h1>")
        try output.writeLine("      <p>\(subtitles.count) subtitle entries</p>")
        try output.writeLine("    </header>")

        for subtitle in subtitles {
            try output.writeLine("    <div class=\"subtitle\" data-index=\"\(subtitle.index)\" data-start=\"\(escapeHTML(subtitle.startTime))\" data-end=\"\(escapeHTML(subtitle.endTime))\">")
            try output.writeLine("      <div class=\"subtitle-meta\">")
            try output.writeLine("        <span class=\"subtitle-index\">#\(subtitle.index)</span>")
            try output.writeLine("        <span class=\"timestamp\">\(escapeHTML(subtitle.timestamp))</span>")
            try output.writeLine("      </div>")
            try output.writeLine("      <div class=\"subtitle-text\">")
            if let speaker = subtitle.speaker {
                try output.writeLine("        <span class=\"speaker\">\(escapeHTML(speaker))</span>")
            }
            try output.writeLine("        <span class=\"text\">\(subtitle.htmlText)</span>")
            try output.writeLine("      </div>")
            try output.writeLine("    </div>")
        }

        try output.writeLine("  </main>")
        try output.writeLine("</body>")
        try output.writeLine("</html>")
    }

    private func loadSource(from input: URL) throws -> String {
        if let utf8 = try? String(contentsOf: input, encoding: .utf8) { return utf8 }
        if let utf16 = try? String(contentsOf: input, encoding: .utf16) { return utf16 }
        if let latin1 = try? String(contentsOf: input, encoding: .isoLatin1) { return latin1 }
        return try String(contentsOf: input, encoding: .utf8)
    }

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
                if let speaker, line.hasPrefix("\(speaker):") {
                    let trimmed = line.dropFirst(speaker.count + 1).trimmingCharacters(in: .whitespaces)
                    return escapeHTML(trimmed)
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

    private func detectSpeaker(in line: String?) -> String? {
        guard let line else { return nil }
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let prefix = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
        guard !prefix.isEmpty, prefix.count <= 40 else { return nil }
        guard prefix.range(of: #"^[A-Za-z0-9 _\-]+$"#, options: .regularExpression) != nil else { return nil }
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

    private let css = """
    body {
      margin: 0;
      font-family: -apple-system, BlinkMacSystemFont, \"Segoe UI\", sans-serif;
      background: #0b1020;
      color: #e5e7eb;
    }
    .transcript {
      max-width: 900px;
      margin: 0 auto;
      padding: 32px 20px 48px;
    }
    .transcript-header {
      margin-bottom: 24px;
    }
    .transcript-header h1 {
      margin: 0 0 8px;
      font-size: 2rem;
    }
    .transcript-header p {
      margin: 0;
      color: #94a3b8;
    }
    .subtitle {
      padding: 16px;
      margin-bottom: 12px;
      border: 1px solid #1f2937;
      border-radius: 12px;
      background: #111827;
      box-shadow: 0 8px 24px rgba(0, 0, 0, 0.18);
    }
    .subtitle-meta {
      display: flex;
      gap: 12px;
      align-items: center;
      margin-bottom: 8px;
      font-size: 0.9rem;
    }
    .subtitle-index {
      color: #93c5fd;
      font-weight: 600;
    }
    .timestamp {
      color: #fca5a5;
      font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
    }
    .subtitle-text {
      line-height: 1.65;
      font-size: 1rem;
    }
    .speaker {
      display: inline-block;
      margin-right: 8px;
      padding: 2px 8px;
      border-radius: 999px;
      background: #1d4ed8;
      color: white;
      font-size: 0.85rem;
      font-weight: 600;
      vertical-align: middle;
    }
    .text {
      vertical-align: middle;
    }
    """
}

private struct Subtitle {
    let index: Int
    let startTime: String
    let endTime: String
    let timestamp: String
    let speaker: String?
    let htmlText: String
}
