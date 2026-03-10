import ArgumentParser
import Foundation
import APABibToHTML
import APABibToMD
import BiblatexAPA

// MARK: - Bib 子命令群
extension MacDoc {
    struct Bib: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "bib",
            abstract: "BibLaTeX (.bib) → APA 7 格式轉換",
            subcommands: [ToHTML.self, ToMarkdown.self, List.self]
        )
    }
}

// MARK: - bib to-html
extension MacDoc.Bib {
    struct ToHTML: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "to-html",
            abstract: "將 .bib 轉換為 APA 7 HTML 參考文獻列表"
        )

        @Argument(help: "輸入 .bib 檔案路徑")
        var input: String

        @Option(name: [.short, .long], help: "輸出 .html 檔案路徑（預設為 stdout）")
        var output: String?

        @Flag(name: .long, help: "輸出完整 HTML 文件（含 <html>, <head>, CSS）")
        var full: Bool = false

        @Option(name: .long, help: "CSS 風格：minimal（學術）或 web（現代）")
        var css: CSSStyle = .web

        @Option(name: .long, help: "只輸出指定 entry key（可多次使用）")
        var key: [String] = []

        mutating func run() throws {
            let entries = try loadEntries(from: input, filterKeys: key)

            let html: String
            if full {
                html = buildFullHTML(entries: entries)
            } else {
                let cssString = css == .minimal ? APACSS.minimal : APACSS.web
                html = BibToAPAHTMLFormatter.formatReferenceListWithCSS(entries, css: cssString)
            }

            try writeOutput(html, to: output)
        }

        private func buildFullHTML(entries: [BibEntry]) -> String {
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
    }
}

// MARK: - bib to-md
extension MacDoc.Bib {
    struct ToMarkdown: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "to-md",
            abstract: "將 .bib 轉換為 APA 7 Markdown 參考文獻列表"
        )

        @Argument(help: "輸入 .bib 檔案路徑")
        var input: String

        @Option(name: [.short, .long], help: "輸出 .md 檔案路徑（預設為 stdout）")
        var output: String?

        @Flag(name: .long, help: "加入 '## References' 標題")
        var heading: Bool = false

        @Option(name: .long, help: "只輸出指定 entry key（可多次使用）")
        var key: [String] = []

        mutating func run() throws {
            let entries = try loadEntries(from: input, filterKeys: key)

            var md = BibToAPAFormatter.formatReferenceList(entries)
            if heading {
                md = "## References\n\n" + md
            }

            try writeOutput(md, to: output)
        }
    }
}

// MARK: - bib list
extension MacDoc.Bib {
    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "列出 .bib 檔案中的所有 entry keys"
        )

        @Argument(help: "輸入 .bib 檔案路徑")
        var input: String

        @Flag(name: .long, help: "顯示 entry type")
        var showType: Bool = false

        mutating func run() throws {
            let inputURL = URL(fileURLWithPath: input)
            guard FileManager.default.fileExists(atPath: inputURL.path) else {
                throw ValidationError("找不到輸入檔案: \(input)")
            }

            let bibFile = try BibParser.parse(filePath: inputURL.path)
            for entry in bibFile.entries {
                if showType {
                    print("\(entry.key)\t\(entry.entryType)")
                } else {
                    print(entry.key)
                }
            }
            FileHandle.standardError.write(
                Data("\n共 \(bibFile.entries.count) 筆 entries\n".utf8)
            )
        }
    }
}

// MARK: - CSS Style Enum
enum CSSStyle: String, ExpressibleByArgument, CaseIterable {
    case minimal
    case web
}

// MARK: - Shared Helpers

private func loadEntries(from path: String, filterKeys: [String]) throws -> [BibEntry] {
    let inputURL = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: inputURL.path) else {
        throw ValidationError("找不到輸入檔案: \(path)")
    }

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

private func writeOutput(_ content: String, to outputPath: String?) throws {
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
