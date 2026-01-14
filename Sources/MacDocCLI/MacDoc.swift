import ArgumentParser
import Foundation
import MacDocCore
import WordToMD

@main
struct MacDoc: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "macdoc",
        abstract: "原生 macOS 文件轉 Markdown 工具",
        version: "0.1.0",
        subcommands: [Word.self]
    )
}

// MARK: - Word 子命令
extension MacDoc {
    struct Word: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "word",
            abstract: "轉換 Word (.docx) 到 Markdown"
        )

        @Argument(help: "輸入 .docx 檔案路徑")
        var input: String

        @Option(name: [.short, .long], help: "輸出檔案路徑（預設：stdout）")
        var output: String?

        @Flag(name: .long, help: "包含文件屬性作為 YAML frontmatter")
        var frontmatter: Bool = false

        @Flag(name: .long, help: "將軟換行轉為硬換行")
        var hardBreaks: Bool = false

        mutating func run() throws {
            let inputURL = URL(fileURLWithPath: input)

            guard FileManager.default.fileExists(atPath: inputURL.path) else {
                throw ValidationError("找不到輸入檔案: \(input)")
            }

            let options = ConversionOptions(
                includeFrontmatter: frontmatter,
                hardLineBreaks: hardBreaks,
                tableStyle: .pipe,
                headingStyle: .atx
            )

            let converter = WordConverter()

            if let outputPath = output {
                let outputURL = URL(fileURLWithPath: outputPath)
                try converter.convertToFile(input: inputURL, output: outputURL, options: options)
            } else {
                try converter.convertToStdout(input: inputURL, options: options)
            }
        }
    }
}
