// Deterministic YAML subset emitter for cli-spec.yaml (PsychQuant/macdoc#72).
//
// Spectra change `cli-spec-yaml`, requirement "Deterministic YAML
// serialization". The emitter prints an ordered node tree — mapping entries
// are arrays, never dictionaries — so the byte output depends only on the
// tree, never on hashing or JSON key order. It deliberately supports a small
// subset of YAML: block mappings, block sequences, flow sequences of scalars,
// strings (plain or double-quoted), booleans and integers.

/// One node of the ordered document tree handed to `YAMLEmitter`.
public indirect enum YAMLNode: Equatable, Sendable {
    case string(String)
    case int(Int)
    case bool(Bool)
    /// A sequence of scalars written in flow style: `[a, "b c"]`.
    case flow([String])
    /// A sequence written in block style: one `- ` item per line.
    case sequence([YAMLNode])
    /// A mapping whose entries keep the given order.
    case mapping([YAMLEntry])
}

/// A key/value pair of a `YAMLNode.mapping`, kept in declaration order.
public struct YAMLEntry: Equatable, Sendable {
    public let key: String
    public let value: YAMLNode

    public init(_ key: String, _ value: YAMLNode) {
        self.key = key
        self.value = value
    }
}

public enum YAMLEmitter {

    /// Prints `root` as YAML: two-space indentation, LF line endings, no
    /// trailing whitespace, exactly one newline at the end. Header comments
    /// are split at line breaks; each physical line becomes its own `# ` line
    /// (`#` when empty) — see `commentLines(_:)`.
    public static func emit(_ root: YAMLNode, headerComments: [String] = []) -> String {
        var lines: [String] = headerComments.flatMap(commentLines)
        switch root {
        case .mapping(let entries) where !entries.isEmpty:
            appendMapping(entries, indent: 0, into: &lines)
        case .sequence(let items) where !items.isEmpty:
            appendSequence(items, indent: 0, into: &lines)
        default:
            lines.append(inline(root))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Formats one string scalar. A string is written plain only when it
    /// starts with an ASCII letter or `_`, contains only ASCII letters,
    /// digits, `_`, `.` and `-`, and is not a YAML 1.1 boolean/null word;
    /// every other string is double-quoted with escapes.
    public static func scalar(_ value: String) -> String {
        isPlainSafe(value) ? value : doubleQuoted(value)
    }

    /// One comment text → YAML comment lines. Line breaks (LF, CR, CRLF,
    /// U+0085, U+2028, U+2029) start a new `# ` line; trailing spaces and tabs
    /// are removed; a character YAML does not allow in a comment (C0 controls
    /// other than tab, DEL, C1 controls, U+FFFE, U+FFFF) is written as the
    /// visible text `\uXXXX`, so a comment can never break out of itself.
    static func commentLines(_ text: String) -> [String] {
        var physical: [String] = []
        var current = ""
        var previousWasCR = false
        for scalar in text.unicodeScalars {
            let value = scalar.value
            if value == 0x0A && previousWasCR {
                previousWasCR = false
                continue   // CRLF: the CR already ended the line
            }
            previousWasCR = value == 0x0D
            if value == 0x0A || value == 0x0D || value == 0x85 || value == 0x2028 || value == 0x2029 {
                physical.append(current)
                current = ""
            } else if value != 0x09 && needsUnicodeEscape(scalar) {
                current += "\\u" + hex4(value)
            } else {
                current.unicodeScalars.append(scalar)
            }
        }
        physical.append(current)
        return physical.map { line in
            var trimmed = Substring(line)
            while let last = trimmed.last, last == " " || last == "\t" {
                trimmed = trimmed.dropLast()
            }
            return trimmed.isEmpty ? "#" : "# " + trimmed
        }
    }

    // MARK: - Block layout

    private static func appendMapping(_ entries: [YAMLEntry], indent: Int, into lines: inout [String]) {
        let pad = String(repeating: " ", count: indent)
        for entry in entries {
            let key = scalar(entry.key)
            if let block = blockChildren(of: entry.value) {
                lines.append(pad + key + ":")
                appendBlock(block, indent: indent + 2, into: &lines)
            } else {
                lines.append(pad + key + ": " + inline(entry.value))
            }
        }
    }

    private static func appendSequence(_ items: [YAMLNode], indent: Int, into lines: inout [String]) {
        let pad = String(repeating: " ", count: indent)
        for item in items {
            switch item {
            case .mapping(let entries) where !entries.isEmpty:
                // First entry shares the `- ` line; the rest align under it.
                var itemLines: [String] = []
                appendMapping(entries, indent: indent + 2, into: &itemLines)
                let first = itemLines.removeFirst()
                lines.append(pad + "- " + first.dropFirst(indent + 2))
                lines.append(contentsOf: itemLines)
            case .sequence(let nested) where !nested.isEmpty:
                lines.append(pad + "-")
                appendSequence(nested, indent: indent + 2, into: &lines)
            default:
                lines.append(pad + "- " + inline(item))
            }
        }
    }

    private enum Block {
        case mapping([YAMLEntry])
        case sequence([YAMLNode])
    }

    /// Non-empty mappings and block sequences open a nested block; every
    /// other node fits on the key's line.
    private static func blockChildren(of node: YAMLNode) -> Block? {
        switch node {
        case .mapping(let entries) where !entries.isEmpty: return .mapping(entries)
        case .sequence(let items) where !items.isEmpty: return .sequence(items)
        default: return nil
        }
    }

    private static func appendBlock(_ block: Block, indent: Int, into lines: inout [String]) {
        switch block {
        case .mapping(let entries): appendMapping(entries, indent: indent, into: &lines)
        case .sequence(let items): appendSequence(items, indent: indent, into: &lines)
        }
    }

    private static func inline(_ node: YAMLNode) -> String {
        switch node {
        case .string(let value): return scalar(value)
        case .int(let value): return String(value)
        case .bool(let value): return value ? "true" : "false"
        case .flow(let values): return "[" + values.map(scalar).joined(separator: ", ") + "]"
        case .sequence: return "[]"   // only reached when empty
        case .mapping: return "{}"    // only reached when empty
        }
    }

    // MARK: - Scalars

    private static let reservedWords: Set<String> = [
        "true", "false", "yes", "no", "on", "off", "null", "y", "n",
    ]

    private static func isPlainSafe(_ value: String) -> Bool {
        guard let first = value.unicodeScalars.first, isASCIILetter(first) || first == "_" else {
            return false
        }
        for scalar in value.unicodeScalars {
            let allowed = isASCIILetter(scalar) || ("0"..."9").contains(scalar)
                || scalar == "_" || scalar == "." || scalar == "-"
            if !allowed { return false }
        }
        return !reservedWords.contains(value.lowercased())
    }

    private static func isASCIILetter(_ scalar: Unicode.Scalar) -> Bool {
        ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar)
    }

    private static func doubleQuoted(_ value: String) -> String {
        var out = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if needsUnicodeEscape(scalar) {
                    out += "\\u" + hex4(scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }

    /// Characters YAML does not allow unescaped: C0 controls, DEL, C1
    /// controls (U+0080–U+009F, including U+0085 NEL), the line/paragraph
    /// separators U+2028 and U+2029, and the noncharacters U+FFFE / U+FFFF.
    private static func needsUnicodeEscape(_ scalar: Unicode.Scalar) -> Bool {
        let value = scalar.value
        return value < 0x20 || (0x7F...0x9F).contains(value)
            || value == 0x2028 || value == 0x2029 || value == 0xFFFE || value == 0xFFFF
    }

    private static func hex4(_ value: UInt32) -> String {
        let digits = String(value, radix: 16, uppercase: true)
        return String(repeating: "0", count: max(0, 4 - digits.count)) + digits
    }
}
