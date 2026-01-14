import Foundation

/// 串流輸出協定 - 逐段寫入 Markdown，不需要完整文件樹
public protocol StreamingOutput {
    /// 寫入文字
    mutating func write(_ text: String) throws

    /// 寫入一行（含換行符）
    mutating func writeLine(_ text: String) throws

    /// 寫入空行
    mutating func writeBlankLine() throws

    /// 刷新緩衝區
    mutating func flush() throws
}

// MARK: - 預設實作
public extension StreamingOutput {
    mutating func writeLine(_ text: String) throws {
        try write(text + "\n")
    }

    mutating func writeBlankLine() throws {
        try write("\n")
    }
}

// MARK: - FileHandle 輸出（支援 stdout）
public struct FileHandleOutput: StreamingOutput {
    private let fileHandle: FileHandle

    public init(fileHandle: FileHandle = .standardOutput) {
        self.fileHandle = fileHandle
    }

    public init(outputPath: URL) throws {
        FileManager.default.createFile(atPath: outputPath.path, contents: nil)
        guard let handle = FileHandle(forWritingAtPath: outputPath.path) else {
            throw ConversionError.cannotCreateOutput(outputPath.path)
        }
        self.fileHandle = handle
    }

    public func write(_ text: String) throws {
        guard let data = text.data(using: .utf8) else {
            throw ConversionError.encodingError
        }
        try fileHandle.write(contentsOf: data)
    }

    public func flush() throws {
        try fileHandle.synchronize()
    }
}

// MARK: - String 輸出（用於測試或小檔案）
public struct StringOutput: StreamingOutput {
    public private(set) var content: String = ""

    public init() {}

    public mutating func write(_ text: String) throws {
        content += text
    }

    public func flush() throws {
        // 無需操作
    }
}
