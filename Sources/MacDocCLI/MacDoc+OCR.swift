import ArgumentParser
import Foundation
import OCRCore
import PDFToLaTeXCore

extension MacDoc {
    struct OCR: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "ocr",
            abstract: "VLM OCR（PDF 和圖片 → 文字，支援 MLX 本地 / Ollama）"
        )

        @Argument(help: "輸入檔案（PDF、PNG、JPG）")
        var input: String

        @Option(name: .long, help: "輸出檔案路徑（預設 stdout）")
        var output: String?

        @Option(name: .long, help: "PDF 頁碼範圍（例如 1-3）")
        var pages: String?

        @Option(name: .long, help: "OCR 後端：ollama 或 mlx（預設讀 config，再 fallback ollama）")
        var backend: String?

        @Option(name: .long, help: "模型名稱（預設讀 config，再 fallback glm-ocr / mlx-community/Qwen3-VL-4B-Instruct-4bit）")
        var model: String?

        @Option(name: .long, help: "Ollama 伺服器地址或 host profile 名稱（預設用 config 的 default host）")
        var host: String?

        @Option(name: .long, help: "最大生成 token 數")
        var maxTokens: Int = 4096

        func run() async throws {
            let inputURL = try validatedInputURL(input)

            let pageRange: ClosedRange<Int>?
            if let pages {
                pageRange = try parsePageRange(pages)
            } else {
                pageRange = nil
            }

            // Load config (沒設定檔也 OK，會回傳預設值)
            let config = (try? AIConfig.load()) ?? AIConfig()

            // Resolve backend: --backend > config.ocrDefaultBackend > "ollama"
            let resolvedBackend = backend ?? config.ocrDefaultBackend

            // Build backend
            let ocrBackend: any OCRBackend
            switch resolvedBackend {
            case "ollama":
                let modelName = model ?? config.ocrDefaultModel
                let resolvedHost = config.resolveOCRHost(host)
                FileHandle.standardError.write(
                    Data("使用 Ollama 後端（\(resolvedHost), 模型: \(modelName)）\n".utf8))
                ocrBackend = OllamaBackend(host: resolvedHost, model: modelName)

            case "mlx":
                let repo = model ?? (config.ocrDefaultModel == "glm-ocr"
                    ? "mlx-community/Qwen3-VL-4B-Instruct-4bit"
                    : config.ocrDefaultModel)
                FileHandle.standardError.write(Data("正在載入模型 \(repo)...\n".utf8))
                ocrBackend = try await MLXBackend.load(
                    repo: repo, maxTokens: maxTokens
                ) { filename, progress in
                    let percent = Int(progress * 100)
                    FileHandle.standardError.write(
                        Data("\r下載: \(filename) (\(percent)%)".utf8))
                }
                FileHandle.standardError.write(Data("\n模型載入完成\n".utf8))

            default:
                throw ValidationError("未知的後端: \(resolvedBackend)（支援: ollama, mlx）")
            }

            // Run OCR
            let pipeline = OCRPipeline(backend: ocrBackend)

            let result = try await pipeline.processFile(
                path: inputURL.path,
                pageRange: pageRange
            ) { current, total in
                FileHandle.standardError.write(
                    Data("\r處理頁面 \(current)/\(total)".utf8))
            }

            if pageRange != nil {
                FileHandle.standardError.write(Data("\n".utf8))
            }

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
