import ArgumentParser
import Foundation
import CommonConverterSwift
import TeXToDOCX

// MARK: - tex-to-docx (top-level command)
extension MacDoc {
    struct TeXToWord: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "tex-to-docx",
            abstract: "將 LaTeX (.tex) 轉換為 Word (.docx)（支援逐字稿自訂命令）"
        )

        @Argument(help: "輸入 .tex 檔案路徑")
        var input: String

        @Option(name: [.short, .long], help: "輸出 .docx 檔案路徑（預設與輸入同名）")
        var output: String?

        mutating func run() async throws {
            let inputURL = URL(fileURLWithPath: input)
            guard FileManager.default.fileExists(atPath: inputURL.path) else {
                throw ValidationError("找不到輸入檔案: \(input)")
            }

            let outputURL: URL
            if let output {
                outputURL = URL(fileURLWithPath: output)
            } else {
                outputURL = inputURL.deletingPathExtension().appendingPathExtension("docx")
            }

            try TeXToDOCXConverter().convertToFile(input: inputURL, output: outputURL)
            print("已寫入: \(outputURL.path)")
        }
    }
}
