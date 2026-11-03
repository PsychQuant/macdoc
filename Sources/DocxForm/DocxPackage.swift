// DocxPackage.swift — zip-level read and atomic rewrite for form
// normalization (macdoc#249, change docx-form-normalization).
//
// Only `word/document.xml` changes; every other entry is copied with its
// uncompressed content unchanged and in its original order. The output is
// written to a temporary file next to the destination and renamed into place,
// so a failure never leaves a half-written file at the output path.

import Foundation
import ZIPFoundation

public enum DocxPackageError: Error, Equatable, CustomStringConvertible {
    case unreadable(String)
    case missingPart(String)
    case tooLarge(limit: Int64)
    case outputExists(String)
    case writeFailed(String)

    public var description: String {
        switch self {
        case .unreadable(let detail): return "無法讀取 .docx 封裝：\(detail)"
        case .missingPart(let path): return "封裝裡沒有 \(path)"
        case .tooLarge(let limit): return "封裝解壓後超過 \(limit / 1_048_576) MB，拒絕處理"
        case .outputExists(let path): return "輸出檔案已存在: \(path)（使用 --force 覆寫）"
        case .writeFailed(let detail): return "寫出失敗（未留下任何輸出）：\(detail)"
        }
    }
}

public enum DocxPackage {
    public struct Entry: Equatable {
        public let path: String
        public let data: Data
        public let isDirectory: Bool
        public let modificationDate: Date?

        public init(path: String, data: Data, isDirectory: Bool = false, modificationDate: Date? = nil) {
            self.path = path
            self.data = data
            self.isDirectory = isDirectory
            self.modificationDate = modificationDate
        }
    }

    public static let documentPart = "word/document.xml"
    public static let numberingPart = "word/numbering.xml"

    /// Total uncompressed bytes accepted when reading a package.
    public static let maxTotalBytes: Int64 = 512 * 1_048_576

    /// Entries in archive order.
    public static func read(from url: URL, limit: Int64 = maxTotalBytes) throws -> [Entry] {
        let archive: Archive
        do {
            archive = try Archive(url: url, accessMode: .read)
        } catch {
            throw DocxPackageError.unreadable(error.localizedDescription)
        }
        // Declared sizes come from the archive and can be forged; add them
        // with overflow detection so a huge value cannot wrap below the cap.
        let cap = UInt64(max(0, limit))
        var declared: UInt64 = 0
        for entry in archive {
            let (sum, overflow) = declared.addingReportingOverflow(entry.uncompressedSize)
            if overflow || sum > cap { throw DocxPackageError.tooLarge(limit: limit) }
            declared = sum
        }
        var entries: [Entry] = []
        var actual: Int64 = 0
        for entry in archive {
            let date = entry.fileAttributes[.modificationDate] as? Date
            if entry.type == .directory {
                entries.append(Entry(path: entry.path, data: Data(), isDirectory: true, modificationDate: date))
                continue
            }
            // A symbolic-link entry cannot be copied faithfully; refusing beats
            // silently dropping it from an output that claims to keep every part.
            guard entry.type == .file else {
                throw DocxPackageError.unreadable("不支援的 entry 類型（\(entry.type)）：\(entry.path)")
            }
            var data = Data()
            do {
                _ = try archive.extract(entry, skipCRC32: false) { chunk in
                    actual += Int64(chunk.count)
                    if actual > limit { throw DocxPackageError.tooLarge(limit: limit) }
                    data.append(chunk)
                }
            } catch let error as DocxPackageError {
                throw error
            } catch {
                throw DocxPackageError.unreadable(error.localizedDescription)
            }
            entries.append(Entry(path: entry.path, data: data, modificationDate: date))
        }
        return entries
    }

    /// Writes a new archive at `url`, which must not exist.
    public static func write(_ entries: [Entry], to url: URL) throws {
        let archive: Archive
        do {
            archive = try Archive(url: url, accessMode: .create)
        } catch {
            throw DocxPackageError.writeFailed(error.localizedDescription)
        }
        do {
            for entry in entries {
                let date = entry.modificationDate ?? Date()
                if entry.isDirectory {
                    try archive.addEntry(with: entry.path, type: .directory, uncompressedSize: Int64(0),
                                         modificationDate: date, provider: { _, _ in Data() })
                    continue
                }
                let data = entry.data
                try archive.addEntry(with: entry.path, type: .file, uncompressedSize: Int64(data.count),
                                     modificationDate: date, compressionMethod: .deflate,
                                     provider: { position, size in
                                         let start = Int(position)
                                         return data.subdata(in: start..<min(start + size, data.count))
                                     })
            }
        } catch {
            throw DocxPackageError.writeFailed(error.localizedDescription)
        }
    }

    /// Reads `input`, replaces `word/document.xml` with `transform`'s result,
    /// and writes the package to `output` atomically. Without `force` an
    /// existing output is refused before any work and again just before the
    /// rename. On any failure the output path is left as it was.
    public static func rewriteDocument(input: URL, output: URL, force: Bool,
                                       transform: (_ documentXML: Data, _ entries: [Entry]) throws -> Data) throws {
        let fm = FileManager.default
        if !force, fm.fileExists(atPath: output.path) { throw DocxPackageError.outputExists(output.path) }
        let entries = try read(from: input)
        guard let document = entries.first(where: { $0.path == documentPart }) else {
            throw DocxPackageError.missingPart(documentPart)
        }
        let newDocument = try transform(document.data, entries)
        let rewritten = entries.map { entry in
            entry.path == documentPart
                ? Entry(path: entry.path, data: newDocument, isDirectory: false, modificationDate: entry.modificationDate)
                : entry
        }
        let temp = output.deletingLastPathComponent()
            .appendingPathComponent(".\(output.lastPathComponent).\(UUID().uuidString).tmp")
        do {
            try write(rewritten, to: temp)
            // Without --force the rename itself refuses an existing destination
            // (RENAME_EXCL), so a file created after the first check is never
            // replaced; with --force a plain rename replaces it atomically.
            let status = force
                ? rename(temp.path, output.path)
                : renamex_np(temp.path, output.path, UInt32(RENAME_EXCL))
            guard status == 0 else {
                if !force, errno == EEXIST { throw DocxPackageError.outputExists(output.path) }
                throw DocxPackageError.writeFailed(String(cString: strerror(errno)))
            }
        } catch {
            try? fm.removeItem(at: temp)
            throw error
        }
    }
}
