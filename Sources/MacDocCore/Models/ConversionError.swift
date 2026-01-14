import Foundation

/// 轉換錯誤
public enum ConversionError: LocalizedError {
    case fileNotFound(String)
    case cannotCreateOutput(String)
    case encodingError
    case unsupportedFormat(String)
    case parsingError(String)
    case invalidDocument(String)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "找不到檔案: \(path)"
        case .cannotCreateOutput(let path):
            return "無法建立輸出檔案: \(path)"
        case .encodingError:
            return "編碼錯誤"
        case .unsupportedFormat(let format):
            return "不支援的格式: \(format)"
        case .parsingError(let message):
            return "解析錯誤: \(message)"
        case .invalidDocument(let message):
            return "無效的文件: \(message)"
        }
    }
}
