import ArgumentParser
import Foundation
import CommonConverterSwift
import PDFToDOCX

// MARK: - pdf to-docx
extension MacDoc.PDF {
    struct ToDOCX: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "to-docx",
            abstract: "將 PDF (.pdf) 直接轉換為 Word (.docx)"
        )

        @Argument(help: "輸入 .pdf 檔案路徑")
        var input: String

        @Option(name: [.short, .long], help: "輸出 .docx 檔案路徑（預設為與輸入同名）")
        var output: String?

        @Flag(name: .long, help: "保留 PDF 段內換行為 Word line break")
        var hardBreaks: Bool = false

        mutating func run() async throws {
            let inputURL = URL(fileURLWithPath: input)
            guard FileManager.default.fileExists(atPath: inputURL.path) else {
                throw ValidationError("找不到輸入檔案: \(input)")
            }

            var options = ConversionOptions.default
            options.hardLineBreaks = hardBreaks

            let outputURL = resolvedOutputURL(for: inputURL)
            try PDFToDOCXConverter().convertToFile(input: inputURL, output: outputURL, options: options)
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
