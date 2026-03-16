import ArgumentParser
import Foundation
import CommonConverterSwift
import SRTToHTML

// MARK: - SRT 子命令群
extension MacDoc {
    struct SRT: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "srt",
            abstract: "轉換 SRT 到 HTML（建議改用 macdoc convert --to html）",
            subcommands: [ToHTML.self],
            defaultSubcommand: ToHTML.self
        )
    }
}

// MARK: - srt to-html
extension MacDoc.SRT {
    struct ToHTML: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "to-html",
            abstract: "將 SRT (.srt) 轉換為 HTML"
        )

        @Argument(help: "輸入 .srt 檔案路徑")
        var input: String

        @Option(name: [.short, .long], help: "輸出 .html 檔案路徑（預設為 stdout）")
        var output: String?

        @Flag(name: .long, help: "輸出完整 HTML 文件（含 CSS）")
        var full: Bool = false

        @Option(name: .long, help: "CSS 風格：dark（深色）或 light（淺色）")
        var css: SRTCSSStyle = .dark

        @Flag(name: .long, help: "輸出前加入 HTML comment frontmatter")
        var frontmatter: Bool = false

        mutating func run() throws {
            let inputURL = try validatedInputURL(input)
            let converter = SRTConverter()

            if full {
                let cssString = css == .light ? SRTCSS.light : SRTCSS.dark
                let html = try converter.convertFull(input: inputURL, css: cssString)
                try writeStringOutput(html, to: output)
            } else {
                var options = ConversionOptions.default
                options.includeFrontmatter = frontmatter

                if let outputPath = output {
                    let outputURL = URL(fileURLWithPath: outputPath)
                    try converter.convertToFile(input: inputURL, output: outputURL, options: options)
                } else {
                    try converter.convertToStdout(input: inputURL, options: options)
                }
            }
        }
    }
}

enum SRTCSSStyle: String, ExpressibleByArgument, CaseIterable {
    case dark
    case light
}
