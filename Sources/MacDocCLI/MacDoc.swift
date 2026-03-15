import ArgumentParser
import Foundation
import CommonConverterSwift
import WordToMDSwift
import MarkerWordConverter
import PDFToLaTeXCore

@main
struct MacDoc: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "macdoc",
        abstract: "原生 macOS 文件處理工具",
        version: "0.4.0",
        subcommands: [Convert.self, Word.self, WordToHTML.self, HTML.self, SRT.self, PDF.self, Bib.self, Config.self]
    )
}

// MARK: - Word 子命令
extension MacDoc {
    struct Word: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "word",
            abstract: "轉換 Word (.docx) 到 Markdown"
        )

        @Argument(help: "輸入 .docx 檔案路徑")
        var input: String

        @Option(name: [.short, .long], help: "輸出路徑（檔案或目錄）")
        var output: String?

        @Flag(name: .long, help: "包含文件屬性作為 YAML frontmatter")
        var frontmatter: Bool = false

        @Flag(name: .long, help: "將軟換行轉為硬換行")
        var hardBreaks: Bool = false

        @Flag(name: .long, help: "使用 Marker 格式輸出（MD + JSON + images）")
        var marker: Bool = false

        mutating func run() async throws {
            let inputURL = try validatedInputURL(input)

            let options = ConversionOptions(
                includeFrontmatter: frontmatter,
                hardLineBreaks: hardBreaks,
                tableStyle: .pipe,
                headingStyle: .atx
            )

            if marker {
                try await runMarkerMode(inputURL: inputURL, options: options)
            } else {
                try runStandardMode(inputURL: inputURL, options: options)
            }
        }

        private func runStandardMode(inputURL: URL, options: ConversionOptions) throws {
            let converter = WordConverter()

            if let outputPath = output {
                let outputURL = URL(fileURLWithPath: outputPath)
                try converter.convertToFile(input: inputURL, output: outputURL, options: options)
            } else {
                try converter.convertToStdout(input: inputURL, options: options)
            }
        }

        private func runMarkerMode(inputURL: URL, options: ConversionOptions) async throws {
            let outputDir: URL
            if let outputPath = output {
                outputDir = URL(fileURLWithPath: outputPath)
            } else {
                let inputDir = inputURL.deletingLastPathComponent()
                let baseName = inputURL.deletingPathExtension().lastPathComponent
                outputDir = inputDir.appendingPathComponent("\(baseName)_output")
            }

            let converter = MarkerWordConverter()
            let result = try await converter.convert(
                input: inputURL,
                outputDirectory: outputDir,
                options: options
            )

            print("✓ 轉換完成")
            print("  Markdown: \(result.markdownURL.path)")
            print("  Metadata: \(result.metadataURL.path)")
            print("  Images:   \(result.imagesDirectory.path)")
        }
    }
}
