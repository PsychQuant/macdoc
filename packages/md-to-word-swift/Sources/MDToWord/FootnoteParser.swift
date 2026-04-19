import Foundation

/// 解析 Markdown footnote definitions（非 CommonMark 標準）
///
/// 格式：`[^id]: footnote text`
/// swift-markdown 不支援 footnotes，需要單獨解析。
struct FootnoteParser {

    struct FootnoteDefinition {
        let id: String
        let text: String
    }

    struct FootnoteReference {
        let id: String
        let range: Range<String.Index>
    }

    /// 從 Markdown 文字中提取所有 footnote definitions
    static func parseDefinitions(from markdown: String) -> [FootnoteDefinition] {
        var results: [FootnoteDefinition] = []
        let pattern = #"^\[\^([^\]]+)\]:\s*(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines) else {
            return results
        }

        let nsString = markdown as NSString
        let matches = regex.matches(in: markdown, range: NSRange(location: 0, length: nsString.length))

        for match in matches {
            guard match.numberOfRanges >= 3 else { continue }
            let id = nsString.substring(with: match.range(at: 1))
            let text = nsString.substring(with: match.range(at: 2))
            results.append(FootnoteDefinition(id: id, text: text))
        }

        return results
    }

    /// 從 Markdown 文字中找出所有 footnote references [^id]
    static func parseReferences(from markdown: String) -> [FootnoteReference] {
        var results: [FootnoteReference] = []
        let pattern = #"\[\^([^\]]+)\](?!:)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return results
        }

        let nsString = markdown as NSString
        let matches = regex.matches(in: markdown, range: NSRange(location: 0, length: nsString.length))

        for match in matches {
            guard match.numberOfRanges >= 2,
                  let range = Range(match.range, in: markdown) else { continue }
            let id = nsString.substring(with: match.range(at: 1))
            results.append(FootnoteReference(id: id, range: range))
        }

        return results
    }

    /// 移除 markdown 中的 footnote definitions（這些不進 AST）
    static func stripDefinitions(from markdown: String) -> String {
        let pattern = #"^\[\^[^\]]+\]:\s*.+$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines) else {
            return markdown
        }

        let nsString = markdown as NSString
        let result = regex.stringByReplacingMatches(
            in: markdown,
            range: NSRange(location: 0, length: nsString.length),
            withTemplate: ""
        )

        // 清理多餘空行
        return result
            .components(separatedBy: "\n")
            .reduce(into: [String]()) { acc, line in
                if line.trimmingCharacters(in: .whitespaces).isEmpty && acc.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
                    return // 跳過連續空行
                }
                acc.append(line)
            }
            .joined(separator: "\n")
    }
}
