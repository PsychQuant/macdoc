import ArgumentParser
import Foundation
import HTMLToWordSwift

// MARK: - html-to-word
extension MacDoc {
    struct HTMLToWord: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "html-to-word",
            abstract: "轉換 HTML 到 Word (.docx)"
        )

        @Argument(help: "輸入 .html / .htm 檔案路徑")
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

            try HTMLToWordConverter().convertToFile(input: inputURL, output: outputURL)
            print("已寫入: \(outputURL.path)")
        }
    }
}
