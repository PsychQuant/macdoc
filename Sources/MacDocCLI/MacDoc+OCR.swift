import ArgumentParser
import Foundation
import OCRCore

extension MacDoc {
    struct OCR: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "ocr",
            abstract: "GLM-OCR 神經網路 OCR（PDF 和圖片 → Markdown）"
        )

        @Argument(help: "輸入檔案（PDF、PNG、JPG）")
        var input: String

        @Option(name: .long, help: "輸出檔案路徑（預設 stdout）")
        var output: String?

        @Option(name: .long, help: "PDF 頁碼範圍（例如 1-3）")
        var pages: String?

        @Option(name: .long, help: "HuggingFace 模型 repo")
        var model: String = "EZCon/GLM-OCR-8bit-mlx"

        @Option(name: .long, help: "最大生成 token 數")
        var maxTokens: Int = 4096

        func run() async throws {
            let inputURL = try validatedInputURL(input)

            // Parse page range
            let pageRange: ClosedRange<Int>?
            if let pages {
                pageRange = try parsePageRange(pages)
            } else {
                pageRange = nil
            }

            // Initialize pipeline
            let pipeline = OCRPipeline(maxTokens: maxTokens)

            FileHandle.standardError.write(Data("正在載入模型 \(model)...\n".utf8))

            try await pipeline.loadModel(repo: model) { filename, progress in
                let percent = Int(progress * 100)
                FileHandle.standardError.write(
                    Data("\r下載: \(filename) (\(percent)%)".utf8)
                )
            }

            FileHandle.standardError.write(Data("\n模型載入完成\n".utf8))

            // Process file
            let result = try await pipeline.processFile(
                path: inputURL.path,
                pageRange: pageRange
            ) { current, total in
                FileHandle.standardError.write(
                    Data("\r處理頁面 \(current)/\(total)".utf8)
                )
            }

            if pageRange != nil {
                FileHandle.standardError.write(Data("\n".utf8))
            }

            // Output
            try writeStringOutput(result, to: output)
        }

        private func parsePageRange(_ rangeStr: String) throws -> ClosedRange<Int> {
            let parts = rangeStr.split(separator: "-").map(String.init)
            if parts.count == 1, let page = Int(parts[0]) {
                return page...page
            } else if parts.count == 2, let start = Int(parts[0]), let end = Int(parts[1]) {
                guard start <= end else {
                    throw ValidationError("頁碼範圍無效: \(rangeStr)（起始頁必須 ≤ 結束頁）")
                }
                return start...end
            } else {
                throw ValidationError("頁碼範圍格式無效: \(rangeStr)（應為 N 或 N-M）")
            }
        }
    }
}
