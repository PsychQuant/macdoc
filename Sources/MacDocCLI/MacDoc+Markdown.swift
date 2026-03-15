import ArgumentParser
import Foundation
import MDToHTMLSwift
import MDToWordSwift
import CommonConverterSwift

// MARK: - Markdown 子命令群
extension MacDoc {
    struct Markdown: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "markdown",
            abstract: "轉換 Markdown 到 HTML / Word",
            subcommands: [ToHTML.self, ToWord.self],
            defaultSubcommand: ToHTML.self
        )
    }
}

// MARK: - markdown to-html
extension MacDoc.Markdown {
    struct ToHTML: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "to-html",
            abstract: "將 Markdown (.md) 轉換為 HTML"
        )

        @Argument(help: "輸入 .md 檔案路徑")
        var input: String

        @Option(name: [.short, .long], help: "輸出 .html 檔案路徑（預設為 stdout）")
        var output: String?

        @Flag(name: .long, help: "輸出完整 HTML 文件")
        var full: Bool = false

        mutating func run() async throws {
            let inputURL = URL(fileURLWithPath: input)
            guard FileManager.default.fileExists(atPath: inputURL.path) else {
                throw ValidationError("找不到輸入檔案: \(input)")
            }

            let converter = MarkdownConverter()
            let html = try converter.convert(
                input: inputURL,
                options: HTMLOptions(fullDocument: full)
            )

            if let outputPath = output {
                let outputURL = URL(fileURLWithPath: outputPath)
                try html.write(to: outputURL, atomically: true, encoding: .utf8)
            } else {
                print(html)
            }
        }
    }
}

// MARK: - markdown to-word
extension MacDoc.Markdown {
    struct ToWord: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "to-word",
            abstract: "將 Markdown (.md) 轉換為 Word (.docx)"
        )

        @Argument(help: "輸入 .md 檔案路徑")
        var input: String

        @Option(name: [.short, .long], help: "輸出 .docx 檔案路徑（預設為與輸入同名）")
        var output: String?

        @Flag(name: .long, help: "將 soft break 轉為 Word line break")
        var hardBreaks: Bool = false

        mutating func run() async throws {
            let inputURL = URL(fileURLWithPath: input)
            guard FileManager.default.fileExists(atPath: inputURL.path) else {
                throw ValidationError("找不到輸入檔案: \(input)")
            }

            var options = ConversionOptions.default
            options.hardLineBreaks = hardBreaks

            let converter = MarkdownToWordConverter()
            let outputURL = resolvedOutputURL(for: inputURL)
            try converter.convertToFile(input: inputURL, output: outputURL, options: options)
            print("已寫入: \(outputURL.path)")
        }

        private func resolvedOutputURL(for inputURL: URL) -> URL {
            if let output {
                return URL(fileURLWithPath: output)
            }
            return inputURL.deletingPathExtension().appendingPathExtension("docx")
        }
    }
}
