import ArgumentParser
import Foundation
import CommonConverterSwift
import SRTToHTMLSwift

// MARK: - SRT 子命令群
extension MacDoc {
    struct SRT: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "srt",
            abstract: "轉換 SRT 到 HTML",
            subcommands: [ToHTML.self],
            defaultSubcommand: ToHTML.self
        )
    }
}

// MARK: - srt to-html
extension MacDoc.SRT {
    struct ToHTML: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "to-html",
            abstract: "將 SRT (.srt) 轉換為 HTML"
        )

        @Argument(help: "輸入 .srt 檔案路徑")
        var input: String

        @Option(name: [.short, .long], help: "輸出 .html 檔案路徑（預設為 stdout）")
        var output: String?

        @Flag(name: .long, help: "輸出前加入 HTML comment frontmatter")
        var frontmatter: Bool = false

        mutating func run() async throws {
            let inputURL = try validatedInputURL(input)

            var options = ConversionOptions.default
            options.includeFrontmatter = frontmatter

            let converter = SRTConverter()
            if let outputPath = output {
                let outputURL = URL(fileURLWithPath: outputPath)
                try converter.convertToFile(input: inputURL, output: outputURL, options: options)
            } else {
                try converter.convertToStdout(input: inputURL, options: options)
            }
        }
    }
}
