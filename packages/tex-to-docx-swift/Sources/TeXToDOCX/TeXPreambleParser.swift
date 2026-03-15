import Foundation

/// Parses LaTeX preamble to extract style definitions (colors, commands)
/// so the converter doesn't hardcode formatting values.
struct TeXPreambleParser {

    /// Parsed color definitions from \definecolor
    struct ColorTable {
        private var colors: [String: String] = [:]  // name → RGB hex

        /// Register a color name → hex mapping
        mutating func define(_ name: String, hex: String) {
            // Strip # prefix if present, uppercase
            let cleaned = hex.replacingOccurrences(of: "#", with: "").uppercased()
            colors[name] = cleaned
        }

        /// Resolve a color name to RGB hex, returns nil if unknown
        func resolve(_ name: String) -> String? {
            colors[name]
        }

        /// Resolve with fallback
        func resolve(_ name: String, fallback: String) -> String {
            colors[name] ?? fallback
        }
    }

    /// Parsed \fontsize from inline formatting
    struct FontSpec {
        let sizePt: Int         // in points
        let leadingPt: Int      // line spacing in points
    }

    /// Parse the full source (preamble + body) and extract color definitions
    static func parseColors(from source: String) -> ColorTable {
        var table = ColorTable()

        // \definecolor{name}{HTML}{RRGGBB}
        let htmlPattern = #"\\definecolor\{([^}]+)\}\{HTML\}\{([^}]+)\}"#
        if let regex = try? NSRegularExpression(pattern: htmlPattern) {
            let matches = regex.matches(in: source, range: NSRange(source.startIndex..., in: source))
            for match in matches {
                if let nameRange = Range(match.range(at: 1), in: source),
                   let hexRange = Range(match.range(at: 2), in: source) {
                    table.define(String(source[nameRange]), hex: String(source[hexRange]))
                }
            }
        }

        // \definecolor{name}{rgb}{r,g,b} (0.0-1.0)
        let rgbPattern = #"\\definecolor\{([^}]+)\}\{rgb\}\{([^}]+)\}"#
        if let regex = try? NSRegularExpression(pattern: rgbPattern) {
            let matches = regex.matches(in: source, range: NSRange(source.startIndex..., in: source))
            for match in matches {
                if let nameRange = Range(match.range(at: 1), in: source),
                   let valRange = Range(match.range(at: 2), in: source) {
                    let name = String(source[nameRange])
                    let components = String(source[valRange]).split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                    if components.count == 3 {
                        let hex = String(format: "%02X%02X%02X",
                                         Int(components[0] * 255),
                                         Int(components[1] * 255),
                                         Int(components[2] * 255))
                        table.define(name, hex: hex)
                    }
                }
            }
        }

        // \colorlet{name}{value} (simple alias)
        let colorletPattern = #"\\colorlet\{([^}]+)\}\{([^}]+)\}"#
        if let regex = try? NSRegularExpression(pattern: colorletPattern) {
            let matches = regex.matches(in: source, range: NSRange(source.startIndex..., in: source))
            for match in matches {
                if let nameRange = Range(match.range(at: 1), in: source),
                   let valRange = Range(match.range(at: 2), in: source) {
                    let name = String(source[nameRange])
                    let value = String(source[valRange])
                    // If the value references another color, resolve it
                    if let resolved = table.resolve(value) {
                        table.define(name, hex: resolved)
                    }
                }
            }
        }

        return table
    }

    /// Parse \fontsize{Xpt}{Ypt} from a line, returns (size, leading) in points
    static func parseFontSize(from line: String) -> FontSpec? {
        let pattern = #"\\fontsize\{(\d+)pt\}\{(\d+)pt\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let sizeRange = Range(match.range(at: 1), in: line),
              let leadRange = Range(match.range(at: 2), in: line),
              let size = Int(line[sizeRange]),
              let lead = Int(line[leadRange]) else {
            return nil
        }
        return FontSpec(sizePt: size, leadingPt: lead)
    }

    /// Detect \color{name} in a line, resolve via color table
    static func parseColor(from line: String, colorTable: ColorTable) -> String? {
        let pattern = #"\\color\{([^}]+)\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let nameRange = Range(match.range(at: 1), in: line) else {
            return nil
        }
        let name = String(line[nameRange])
        return colorTable.resolve(name)
    }

    /// Detect if line contains \bfseries
    static func isBold(_ line: String) -> Bool {
        line.contains("\\bfseries")
    }

    /// Extract plain text from a line with inline formatting commands
    static func extractText(from line: String) -> String {
        var result = line
        // Remove formatting commands
        let commands = [
            #"\\songti"#, #"\\rmfamily"#, #"\\sffamily"#,
            #"\\fontsize\{[^}]*\}\{[^}]*\}\\selectfont"#,
            #"\\selectfont"#, #"\\bfseries"#, #"\\itshape"#,
            #"\\color\{[^}]*\}"#, #"\\centering"#,
            #"\\\\\[.*?\]"#,    // \\[1cm] etc.
            #"\\\\"#,           // \\
        ]
        for pattern in commands {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
            }
        }
        // Clean up LaTeX escapes
        result = result
            .replacingOccurrences(of: "\\&", with: "&")
            .replacingOccurrences(of: "\\%", with: "%")
            .replacingOccurrences(of: "\\$", with: "$")
            .replacingOccurrences(of: "\\#", with: "#")
            .replacingOccurrences(of: "\\_", with: "_")
            .replacingOccurrences(of: "\\{", with: "{")
            .replacingOccurrences(of: "\\}", with: "}")
            .replacingOccurrences(of: "~", with: " ")
            .replacingOccurrences(of: "--", with: "–")  // en-dash
            .trimmingCharacters(in: .whitespaces)
        return result
    }
}
