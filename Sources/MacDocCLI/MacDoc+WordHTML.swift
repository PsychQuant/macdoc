import ArgumentParser
import Foundation
import CommonConverterSwift
import WordToHTML

// MARK: - word-to-html
extension MacDoc {
    struct WordToHTML: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "word-to-html",
            abstract: "轉換 Word (.docx) 到 HTML"
        )

        @Argument(help: "輸入 .docx 檔案路徑")
        var input: String

        @Option(name: [.short, .long], help: "輸出 .html 檔案路徑（預設為 stdout）")
        var output: String?

        @Flag(name: .long, help: "輸出前加入 HTML comment frontmatter")
        var frontmatter: Bool = false

        @Option(name: .long, help: "抽取圖片到指定目錄，並在 HTML 中使用相對路徑")
        var figuresDirectory: String?

        mutating func run() async throws {
            let inputURL = URL(fileURLWithPath: input)
            guard FileManager.default.fileExists(atPath: inputURL.path) else {
                throw ValidationError("找不到輸入檔案: \(input)")
            }

            var options = ConversionOptions.default
            options.includeFrontmatter = frontmatter
            options.figuresDirectory = figuresDirectory.map { URL(fileURLWithPath: $0) }
            if options.figuresDirectory != nil {
                options.fidelity = .markdownWithFigures
            }

            let converter = WordHTMLConverter()
            if let outputPath = output {
                let outputURL = URL(fileURLWithPath: outputPath)
                try converter.convertToFile(input: inputURL, output: outputURL, options: options)
            } else {
                try converter.convertToStdout(input: inputURL, options: options)
            }
        }
    }
}
