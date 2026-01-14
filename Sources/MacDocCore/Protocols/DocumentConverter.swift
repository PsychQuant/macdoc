import Foundation

/// 文件轉換器協定 - streaming 模式，不建立中間 AST
public protocol DocumentConverter {
    /// 來源格式標識符（如 "docx", "html"）
    static var sourceFormat: String { get }

    /// 轉換文件到 Markdown
    func convert<W: StreamingOutput>(
        input: URL,
        output: inout W,
        options: ConversionOptions
    ) throws
}

// MARK: - 便利方法
public extension DocumentConverter {
    /// 轉換為字串（用於測試）
    func convertToString(
        input: URL,
        options: ConversionOptions = .default
    ) throws -> String {
        var writer = StringOutput()
        try convert(input: input, output: &writer, options: options)
        return writer.content
    }

    /// 轉換到檔案
    func convertToFile(
        input: URL,
        output: URL,
        options: ConversionOptions = .default
    ) throws {
        var writer = try FileHandleOutput(outputPath: output)
        try convert(input: input, output: &writer, options: options)
        try writer.flush()
    }

    /// 轉換到 stdout
    func convertToStdout(
        input: URL,
        options: ConversionOptions = .default
    ) throws {
        var writer = FileHandleOutput(fileHandle: .standardOutput)
        try convert(input: input, output: &writer, options: options)
        try writer.flush()
    }
}
