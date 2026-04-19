import Foundation
import OOXMLSwift

/// 圖片匯入器：從 figures/ 目錄載入圖片資料
public struct FigureImporter {
    let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// 載入目錄中所有圖片 → [filename: Data]
    public func loadAll() throws -> [String: Data] {
        var result: [String: Data] = [:]

        guard FileManager.default.fileExists(atPath: directory.path) else {
            return result
        }

        let contents = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )

        let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "tif", "webp"]

        for fileURL in contents {
            let ext = fileURL.pathExtension.lowercased()
            guard imageExtensions.contains(ext) else { continue }
            let data = try Data(contentsOf: fileURL)
            result[fileURL.lastPathComponent] = data
        }

        return result
    }

    /// 根據 Markdown image path 建立 ImageReference
    ///
    /// - Parameters:
    ///   - path: Markdown 中的圖片路徑（如 "figures/image1.png" 或 "image1.png"）
    ///   - id: 關係 ID (rId)
    ///   - figures: 已載入的圖片 [filename: Data]
    public func createImageReference(
        path: String,
        id: String,
        figures: [String: Data]
    ) -> ImageReference? {
        // 嘗試直接匹配 filename
        let fileName = URL(fileURLWithPath: path).lastPathComponent

        guard let data = figures[fileName] else { return nil }

        let ext = (fileName as NSString).pathExtension.lowercased()
        let contentType = mimeType(for: ext)

        return ImageReference(
            id: id,
            fileName: fileName,
            contentType: contentType,
            data: data
        )
    }

    private func mimeType(for ext: String) -> String {
        switch ext {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "bmp": return "image/bmp"
        case "tiff", "tif": return "image/tiff"
        case "webp": return "image/webp"
        default: return "image/png"
        }
    }
}
