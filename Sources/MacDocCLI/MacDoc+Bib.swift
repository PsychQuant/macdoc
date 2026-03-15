import ArgumentParser
import Foundation
import BibAPAToHTML
import BibAPAToJSON
import BibAPAToMD
import BiblatexAPA

// MARK: - Bib 子命令群
extension MacDoc {
    struct Bib: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "bib",
            abstract: "BibLaTeX (.bib) → APA 7 格式轉換",
            subcommands: [ToHTML.self, ToJSON.self, ToMarkdown.self, List.self]
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
            let entries = try loadBibEntries(from: input, filterKeys: key)

            let html: String
            if full {
                html = buildAPAFullHTML(entries: entries, css: css)
            } else {
                let cssString = css == .minimal ? APACSS.minimal : APACSS.web
                html = BibToAPAHTMLFormatter.formatReferenceListWithCSS(entries, css: cssString)
            }

            try writeStringOutput(html, to: output)
        }
    }
}

// MARK: - bib to-json
extension MacDoc.Bib {
    struct ToJSON: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "to-json",
            abstract: "將 .bib 轉換為 APA 7 JSON（含 pre-rendered HTML）"
        )

        @Argument(help: "輸入 .bib 檔案路徑")
        var input: String

        @Option(name: [.short, .long], help: "輸出 .json 檔案路徑（預設為 stdout）")
        var output: String?

        @Option(name: .long, help: "只輸出指定 entry key（可多次使用）")
        var key: [String] = []

        @Flag(name: .long, help: "壓縮輸出（不換行）")
        var compact: Bool = false

        mutating func run() throws {
            let entries = try loadBibEntries(from: input, filterKeys: key)
            let json = try BibToAPAJSONFormatter.formatJSON(entries, prettyPrint: !compact)
            try writeStringOutput(json, to: output)
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
            let entries = try loadBibEntries(from: input, filterKeys: key)

            var md = BibToAPAFormatter.formatReferenceList(entries)
            if heading {
                md = "## References\n\n" + md
            }

            try writeStringOutput(md, to: output)
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
            let inputURL = try validatedInputURL(input)

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
