import ArgumentParser
import Foundation
import DocConverterSwift
import HTMLToMDSwift

// MARK: - HTML 子命令群
extension MacDoc {
    struct HTML: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "html",
            abstract: "轉換 HTML 到 Markdown"
        )

        @Argument(help: "輸入 .html / .htm 檔案路徑")
        var input: String

        @Option(name: [.short, .long], help: "輸出 .md 檔案路徑（預設為 stdout）")
        var output: String?

        @Flag(name: .long, help: "包含 HTML <title> 與來源檔名作為 YAML frontmatter")
        var frontmatter: Bool = false

        @Flag(name: .long, help: "將 <br> 轉為 Markdown hard break")
        var hardBreaks: Bool = false

        @Flag(name: .long, help: "保留 <u>/<sup>/<sub>/<mark> 為 raw HTML extension")
        var htmlExtensions: Bool = false

        mutating func run() async throws {
            let inputURL = URL(fileURLWithPath: input)
            guard FileManager.default.fileExists(atPath: inputURL.path) else {
                throw ValidationError("找不到輸入檔案: \(input)")
            }

            let options = ConversionOptions(
                includeFrontmatter: frontmatter,
                hardLineBreaks: hardBreaks,
                tableStyle: .pipe,
                headingStyle: .atx,
                useHTMLExtensions: htmlExtensions
            )

            let converter = HTMLConverter()
            if let outputPath = output {
                let outputURL = URL(fileURLWithPath: outputPath)
                try converter.convertToFile(input: inputURL, output: outputURL, options: options)
            } else {
                try converter.convertToStdout(input: inputURL, options: options)
            }
        }
    }
}
