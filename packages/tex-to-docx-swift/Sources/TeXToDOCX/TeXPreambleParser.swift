import Foundation

/// Parses LaTeX preamble to extract style definitions (colors, fonts, titleformat)
/// so the converter maps source format settings → target format settings.
struct TeXPreambleParser {

    // MARK: - Color Table

    struct ColorTable {
        private var colors: [String: String] = [:]  // name → RGB hex

        mutating func define(_ name: String, hex: String) {
            let cleaned = hex.replacingOccurrences(of: "#", with: "").uppercased()
            colors[name] = cleaned
        }

        func resolve(_ name: String) -> String? {
            // Handle xcolor mixing syntax: "black!40" → 40% black = BF(hex)
            if name.contains("!") {
                return resolveXColorMix(name)
            }
            return colors[name]
        }

        func resolve(_ name: String, fallback: String) -> String {
            resolve(name) ?? fallback
        }

        /// Resolve xcolor mixing: "black!40" = 40% black + 60% white
        private func resolveXColorMix(_ expr: String) -> String? {
            let parts = expr.split(separator: "!")
            guard parts.count == 2,
                  let percent = Int(parts[1]) else { return nil }

            let baseName = String(parts[0])
            let baseRGB: (Int, Int, Int)

            switch baseName {
            case "black": baseRGB = (0, 0, 0)
            case "white": baseRGB = (255, 255, 255)
            case "red": baseRGB = (255, 0, 0)
            case "blue": baseRGB = (0, 0, 255)
            case "green": baseRGB = (0, 128, 0)
            default:
                if let hex = colors[baseName] { baseRGB = hexToRGB(hex) }
                else { return nil }
            }

            // Mix with white: result = base * percent/100 + white * (100-percent)/100
            let r = baseRGB.0 * percent / 100 + 255 * (100 - percent) / 100
            let g = baseRGB.1 * percent / 100 + 255 * (100 - percent) / 100
            let b = baseRGB.2 * percent / 100 + 255 * (100 - percent) / 100
            return String(format: "%02X%02X%02X", min(r, 255), min(g, 255), min(b, 255))
        }

        private func hexToRGB(_ hex: String) -> (Int, Int, Int) {
            let chars = Array(hex)
            guard chars.count >= 6 else { return (0, 0, 0) }
            let r = Int(String(chars[0...1]), radix: 16) ?? 0
            let g = Int(String(chars[2...3]), radix: 16) ?? 0
            let b = Int(String(chars[4...5]), radix: 16) ?? 0
            return (r, g, b)
        }
    }

    // MARK: - Font Spec

    struct FontSpec {
        let sizePt: Int
        let leadingPt: Int
    }

    // MARK: - Title Format (parsed from \titleformat)

    struct TitleFormatSpec {
        var fontSizePt: Int?
        var colorName: String?
        var bold: Bool = false
        var alignment: String?      // "center", "left"
        var fontFamily: String?     // e.g. "songti"
    }

    // MARK: - Font Mapping

    struct FontTable {
        private var fonts: [String: String] = [:]  // LaTeX command → system font name

        mutating func define(_ command: String, systemName: String) {
            fonts[command] = systemName
        }

        func resolve(_ command: String) -> String? {
            fonts[command]
        }
    }

    // MARK: - Parse All

    struct PreambleConfig {
        var colors: ColorTable
        var fonts: FontTable
        var sectionFormat: TitleFormatSpec?
        var subsectionFormat: TitleFormatSpec?
        var subsubsectionFormat: TitleFormatSpec?
    }

    static func parse(from source: String) -> PreambleConfig {
        var config = PreambleConfig(
            colors: parseColors(from: source),
            fonts: parseFonts(from: source)
        )

        let formats = parseTitleFormats(from: source, colors: config.colors)
        config.sectionFormat = formats["section"]
        config.subsectionFormat = formats["subsection"]
        config.subsubsectionFormat = formats["subsubsection"]

        return config
    }

    // MARK: - Color Parsing

    static func parseColors(from source: String) -> ColorTable {
        var table = ColorTable()

        // \definecolor{name}{HTML}{RRGGBB}
        let htmlPattern = #"\\definecolor\{([^}]+)\}\{HTML\}\{([^}]+)\}"#
        if let regex = try? NSRegularExpression(pattern: htmlPattern) {
            for match in regex.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
                if let nr = Range(match.range(at: 1), in: source),
                   let hr = Range(match.range(at: 2), in: source) {
                    table.define(String(source[nr]), hex: String(source[hr]))
                }
            }
        }

        // \definecolor{name}{rgb}{r,g,b}
        let rgbPattern = #"\\definecolor\{([^}]+)\}\{rgb\}\{([^}]+)\}"#
        if let regex = try? NSRegularExpression(pattern: rgbPattern) {
            for match in regex.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
                if let nr = Range(match.range(at: 1), in: source),
                   let vr = Range(match.range(at: 2), in: source) {
                    let comps = String(source[vr]).split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                    if comps.count == 3 {
                        let hex = String(format: "%02X%02X%02X",
                                         Int(comps[0] * 255), Int(comps[1] * 255), Int(comps[2] * 255))
                        table.define(String(source[nr]), hex: hex)
                    }
                }
            }
        }

        // \definecolor{name}{gray}{value} (0.0-1.0)
        let grayPattern = #"\\definecolor\{([^}]+)\}\{gray\}\{([^}]+)\}"#
        if let regex = try? NSRegularExpression(pattern: grayPattern) {
            for match in regex.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
                if let nr = Range(match.range(at: 1), in: source),
                   let vr = Range(match.range(at: 2), in: source),
                   let val = Double(source[vr]) {
                    let component = Int(val * 255)
                    let hex = String(format: "%02X%02X%02X", component, component, component)
                    table.define(String(source[nr]), hex: hex)
                }
            }
        }

        // \colorlet{name}{value}
        let colorletPattern = #"\\colorlet\{([^}]+)\}\{([^}]+)\}"#
        if let regex = try? NSRegularExpression(pattern: colorletPattern) {
            for match in regex.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
                if let nr = Range(match.range(at: 1), in: source),
                   let vr = Range(match.range(at: 2), in: source) {
                    let name = String(source[nr])
                    let value = String(source[vr])
                    if let resolved = table.resolve(value) {
                        table.define(name, hex: resolved)
                    }
                }
            }
        }

        return table
    }

    // MARK: - Font Parsing

    static func parseFonts(from source: String) -> FontTable {
        var table = FontTable()

        // \newCJKfontfamily\songti[...]{NotoSerifTC-SemiBold.otf}
        // Extract the font file name and map command → readable name
        let pattern = #"\\newCJKfontfamily\\(\w+)\[[\s\S]*?\]\{([^}]+)\}"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators) {
            for match in regex.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
                if let cmdRange = Range(match.range(at: 1), in: source),
                   let fileRange = Range(match.range(at: 2), in: source) {
                    let cmd = String(source[cmdRange])
                    let file = String(source[fileRange])
                    // Map font file → system-readable name
                    let systemName = fontFileToName(file)
                    table.define(cmd, systemName: systemName)
                }
            }
        }

        // \setCJKmainfont[...]{creamfont-3.3.otf}
        let mainPattern = #"\\setCJKmainfont\[[\s\S]*?\]\{([^}]+)\}"#
        if let regex = try? NSRegularExpression(pattern: mainPattern, options: .dotMatchesLineSeparators) {
            if let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
               let fileRange = Range(match.range(at: 1), in: source) {
                let file = String(source[fileRange])
                table.define("mainfont", systemName: fontFileToName(file))
            }
        }

        return table
    }

    /// Map font file names to human-readable font names
    private static func fontFileToName(_ file: String) -> String {
        let lower = file.lowercased()
        if lower.contains("notoserif") && lower.contains("tc") { return "Noto Serif TC" }
        if lower.contains("notosans") && lower.contains("tc") { return "Noto Sans TC" }
        if lower.contains("creamfont") { return "凝書體" }
        if lower.contains("mingliu") { return "MingLiU" }
        // Fallback: strip extension
        return file.replacingOccurrences(of: ".otf", with: "")
            .replacingOccurrences(of: ".ttf", with: "")
            .replacingOccurrences(of: ".ttc", with: "")
    }

    // MARK: - TitleFormat Parsing

    /// Parse \titleformat{\section}[block]{formatting}{}{0pt}{wrapper}
    /// Uses brace-depth counting instead of regex for nested {} support
    static func parseTitleFormats(from source: String, colors: ColorTable) -> [String: TitleFormatSpec] {
        var formats: [String: TitleFormatSpec] = [:]

        // Find each \titleformat occurrence
        var searchStart = source.startIndex
        while let range = source.range(of: "\\titleformat", range: searchStart..<source.endIndex) {
            searchStart = range.upperBound

            // Extract brace groups: \titleformat{level}[block]{fmt}{num}{indent}{wrapper}
            var groups: [String] = []
            var pos = range.upperBound
            while groups.count < 4 && pos < source.endIndex {
                // Skip whitespace and [block]
                while pos < source.endIndex && (source[pos].isWhitespace || source[pos].isNewline) {
                    pos = source.index(after: pos)
                }
                if pos < source.endIndex && source[pos] == "[" {
                    // Skip [block] or [hang] etc.
                    while pos < source.endIndex && source[pos] != "]" {
                        pos = source.index(after: pos)
                    }
                    if pos < source.endIndex { pos = source.index(after: pos) }
                    continue
                }
                if pos < source.endIndex && source[pos] == "{" {
                    // Extract balanced brace content
                    if let content = extractBalancedBraces(from: source, at: pos) {
                        groups.append(content.text)
                        pos = content.end
                    } else {
                        break
                    }
                } else {
                    break
                }
            }

            guard groups.count >= 2 else { continue }

            // groups[0] = \section, groups[1] = formatting
            let levelStr = groups[0].replacingOccurrences(of: "\\", with: "")
            let fmt = groups[1]

            var spec = TitleFormatSpec()
            spec.bold = fmt.contains("\\bfseries")
            if let font = parseFontSize(from: fmt) { spec.fontSizePt = font.sizePt }

            let colorPattern = #"\\color\{([^}]+)\}"#
            if let colorRegex = try? NSRegularExpression(pattern: colorPattern),
               let colorMatch = colorRegex.firstMatch(in: fmt, range: NSRange(fmt.startIndex..., in: fmt)),
               let cr = Range(colorMatch.range(at: 1), in: fmt) {
                spec.colorName = String(fmt[cr])
            }

            if fmt.contains("\\filcenter") { spec.alignment = "center" }
            if fmt.contains("\\songti") { spec.fontFamily = "songti" }

            formats[levelStr] = spec
        }

        return formats
    }

    /// Extract content between balanced {} starting at the given position
    private static func extractBalancedBraces(from source: String, at start: String.Index) -> (text: String, end: String.Index)? {
        guard start < source.endIndex && source[start] == "{" else { return nil }
        var depth = 0
        var contentStart = source.index(after: start)
        var pos = start
        while pos < source.endIndex {
            if source[pos] == "{" { depth += 1 }
            else if source[pos] == "}" {
                depth -= 1
                if depth == 0 {
                    let content = String(source[contentStart..<pos])
                    return (content, source.index(after: pos))
                }
            }
            pos = source.index(after: pos)
        }
        return nil
    }

    // MARK: - Inline Helpers

    static func parseFontSize(from line: String) -> FontSpec? {
        let pattern = #"\\fontsize\{(\d+)pt\}\{(\d+)pt\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let sr = Range(match.range(at: 1), in: line),
              let lr = Range(match.range(at: 2), in: line),
              let size = Int(line[sr]),
              let lead = Int(line[lr]) else {
            return nil
        }
        return FontSpec(sizePt: size, leadingPt: lead)
    }

    static func parseColor(from line: String, colorTable: ColorTable) -> String? {
        let pattern = #"\\color\{([^}]+)\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let r = Range(match.range(at: 1), in: line) else { return nil }
        return colorTable.resolve(String(line[r]))
    }

    static func isBold(_ line: String) -> Bool {
        line.contains("\\bfseries")
    }

    /// Extract plain text from a line, removing all LaTeX formatting commands
    static func extractText(from line: String) -> String {
        var result = line
        let commands = [
            #"\\songti"#, #"\\rmfamily"#, #"\\sffamily"#, #"\\filcenter"#,
            #"\\fontsize\{[^}]*\}\{[^}]*\}\\selectfont"#,
            #"\\selectfont"#, #"\\bfseries"#, #"\\itshape"#,
            #"\\color\{[^}]*\}"#, #"\\centering"#,
            #"\\needspace\{[^}]*\}"#,
            #"\\\\\[.*?\]"#,
            #"\\\\"#,
        ]
        for pattern in commands {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
            }
        }
        result = result
            .replacingOccurrences(of: "\\&", with: "&")
            .replacingOccurrences(of: "\\%", with: "%")
            .replacingOccurrences(of: "\\$", with: "$")
            .replacingOccurrences(of: "\\#", with: "#")
            .replacingOccurrences(of: "\\_", with: "_")
            .replacingOccurrences(of: "\\{", with: "\u{FFFC}")
            .replacingOccurrences(of: "\\}", with: "\u{FFFD}")
            .replacingOccurrences(of: "{", with: "")
            .replacingOccurrences(of: "}", with: "")
            .replacingOccurrences(of: "\u{FFFC}", with: "{")
            .replacingOccurrences(of: "\u{FFFD}", with: "}")
            .replacingOccurrences(of: "~", with: " ")
            .replacingOccurrences(of: "--", with: "–")
            .trimmingCharacters(in: .whitespaces)
        return result
    }
}
