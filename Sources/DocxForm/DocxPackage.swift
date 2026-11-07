// DocxPackage.swift — zip-level read and atomic rewrite for form
// normalization (macdoc#249, change docx-form-normalization).
//
// Only `word/document.xml` changes; every other entry is copied with its
// uncompressed content unchanged and in its original order. The output is
// written to a temporary file in a private directory next to the destination
// and renamed into place, so a failure never leaves a half-written file at the
// output path.

import Foundation
import ZIPFoundation

public enum DocxPackageError: Error, Equatable, CustomStringConvertible {
    case unreadable(String)
    case missingPart(String)
    case tooLarge(limit: Int64)
    /// More entries than `DocxPackage.maxEntries` (#252).
    case tooManyEntries(limit: Int)
    /// An entry name that is absolute (`/`, `\` or a drive letter) or has a
    /// `..` segment (#252).
    case suspiciousEntryName(String)
    case outputExists(String)
    case writeFailed(String)

    public var description: String {
        switch self {
        case .unreadable(let detail): return "無法讀取 .docx 封裝：\(detail)"
        case .missingPart(let path): return "封裝裡沒有 \(path)"
        case .tooLarge(let limit): return "封裝解壓後超過 \(limit / 1_048_576) MB，拒絕處理"
        case .tooManyEntries(let limit): return "封裝有超過 \(limit) 個 entry，拒絕處理"
        case .suspiciousEntryName(let path):
            return "封裝裡的 entry 名稱 \(path) 是絕對路徑或含 ..，拒絕處理（輸出會原樣保留這個名稱，交給下一個解壓它的程式）"
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

    /// Exclusive rename (fails with EEXIST when the destination exists). A seam
    /// so tests can simulate filesystems without RENAME_EXCL support.
    static var exclusiveRename: (String, String) -> Int32 = { from, to in
        renamex_np(from, to, UInt32(RENAME_EXCL))
    }

    /// Total uncompressed bytes accepted when reading a package.
    public static let maxTotalBytes: Int64 = 512 * 1_048_576
    /// Entries accepted in one package. A Word document has tens to a few
    /// hundred; the cap keeps a package of countless tiny entries from being
    /// held and walked in memory (#252).
    public static let maxEntries = 10_000

    /// Entry names refused outright (closed list, #252; nothing is refused by
    /// resemblance): a name starting with `/` or `\`, a name starting with an
    /// ASCII letter and `:` (a Windows drive), and a name with a `..` segment
    /// between `/` or `\` separators. The rewrite copies names as they are, so
    /// the output would hand such a name to whatever extracts it next.
    ///
    /// The name is read as Unicode scalars, not as Characters: a combining
    /// mark after a separator joins it into one Character that equals neither
    /// `/` nor `\`, while an extractor reading the bytes still sees the
    /// separator (#252 verify R1).
    static func isSuspicious(_ path: String) -> Bool {
        let scalars = Array(path.unicodeScalars)
        guard let first = scalars.first else { return false }
        if first == "/" || first == "\\" { return true }
        if scalars.count >= 2, scalars[1] == ":", ("A"..."Z").contains(first) || ("a"..."z").contains(first) {
            return true
        }
        let dotDot: [Unicode.Scalar] = [".", "."]
        return scalars.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "/" || $0 == "\\" })
            .contains { $0.elementsEqual(dotDot) }
    }

    /// Every entry, in archive order.
    public static func read(from url: URL, limit: Int64 = maxTotalBytes, maxEntries: Int = maxEntries) throws -> [Entry] {
        try read(from: url, only: nil, limit: limit, maxEntries: maxEntries)
    }

    /// Only the entries named in `paths`, in archive order; a name that is not
    /// in the package is absent from the result. The entry-count and name
    /// checks cover the whole archive; the size limit counts only what is
    /// extracted (#252, used by `word form classify`).
    public static func readParts(from url: URL, paths: [String], limit: Int64 = maxTotalBytes,
                                 maxEntries: Int = maxEntries) throws -> [Entry] {
        try read(from: url, only: Set(paths), limit: limit, maxEntries: maxEntries)
    }

    private static func read(from url: URL, only wanted: Set<String>?, limit: Int64, maxEntries: Int) throws -> [Entry] {
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
        var count = 0
        for entry in archive {
            count += 1
            if count > maxEntries { throw DocxPackageError.tooManyEntries(limit: maxEntries) }
            if isSuspicious(entry.path) { throw DocxPackageError.suspiciousEntryName(entry.path) }
            if let wanted, !wanted.contains(entry.path) { continue }
            let (sum, overflow) = declared.addingReportingOverflow(entry.uncompressedSize)
            if overflow || sum > cap { throw DocxPackageError.tooLarge(limit: limit) }
            declared = sum
        }
        var entries: [Entry] = []
        var actual: Int64 = 0
        for entry in archive {
            if let wanted, !wanted.contains(entry.path) { continue }
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

    /// True when anything occupies `path`, including a symbolic link whose
    /// target is missing (lstat does not follow the link).
    static func pathExists(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0
    }

    /// Without force the rename itself refuses an existing destination
    /// (RENAME_EXCL), so a file created after the first check is never replaced.
    /// Filesystems without exclusive rename (exFAT, FAT, some network volumes)
    /// return ENOTSUP or EINVAL; there an existence check immediately before a
    /// plain rename is the best available, and the race window remains.
    static func moveIntoPlace(_ temp: URL, _ output: URL, force: Bool) throws {
        if force {
            guard rename(temp.path, output.path) == 0 else {
                throw DocxPackageError.writeFailed(String(cString: strerror(errno)))
            }
            return
        }
        if exclusiveRename(temp.path, output.path) == 0 { return }
        let code = errno
        if code == EEXIST { throw DocxPackageError.outputExists(output.path) }
        guard code == ENOTSUP || code == EINVAL else {
            throw DocxPackageError.writeFailed(String(cString: strerror(code)))
        }
        if pathExists(output.path) { throw DocxPackageError.outputExists(output.path) }
        guard rename(temp.path, output.path) == 0 else {
            throw DocxPackageError.writeFailed(String(cString: strerror(errno)))
        }
    }

    /// Reads `input`, replaces `word/document.xml` with `transform`'s result,
    /// and writes the package to `output` atomically. Without `force` an
    /// existing output is refused before any work and again just before the
    /// rename. On any failure the output path is left as it was.
    public static func rewriteDocument(input: URL, output: URL, force: Bool,
                                       transform: (_ documentXML: Data, _ entries: [Entry]) throws -> Data) throws {
        let fm = FileManager.default
        if !force, pathExists(output.path) { throw DocxPackageError.outputExists(output.path) }
        // The permission bits are taken once, before the package is read, and
        // only the rwx bits: setuid, setgid and sticky are never copied.
        let mode = (try? fm.attributesOfItem(atPath: input.path)[.posixPermissions] as? NSNumber)
            .map { $0.intValue & 0o777 }
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
        // The package is written inside a private staging directory next to
        // the output: created 0700, so the content is never readable by other
        // users while it is written, and the file inside has a short fixed
        // name, so a long output name cannot push it past the name limit. It
        // sits on the output's filesystem, so the final rename stays atomic.
        let staging = output.deletingLastPathComponent().appendingPathComponent(".macdoc-form-\(UUID().uuidString)")
        guard mkdir(staging.path, 0o700) == 0 else {
            throw DocxPackageError.writeFailed(String(cString: strerror(errno)))
        }
        defer { try? fm.removeItem(at: staging) }
        let temp = staging.appendingPathComponent("out.docx")
        try write(rewritten, to: temp)
        // The output keeps the input's permission bits (a 0600 form stays 0600).
        if let mode {
            do {
                try fm.setAttributes([.posixPermissions: mode], ofItemAtPath: temp.path)
            } catch {
                throw DocxPackageError.writeFailed(error.localizedDescription)
            }
        }
        try moveIntoPlace(temp, output, force: force)
    }
}
