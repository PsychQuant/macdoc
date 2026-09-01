import Foundation
import ZIPFoundation

package enum NotabilityContainerGeneration: Equatable {
    case legacy
    case modernFlatBuffers
    case unknown
}

package enum NotabilityContainerDetector {
    package static let modernContainerDiagnostic =
        "偵測到新版 Notability .ntb 容器（noteBundle／FlatBuffers）；目前僅支援舊版 plist-based .note（Session.plist）"
    package static let unrecognizedNTBContainerDiagnostic =
        "無法安全辨識 Notability .ntb 容器；目前僅支援舊版 plist-based .note（Session.plist）"

    private static let maximumInspectedEntries = 4_096
    private static let maximumEntryPathByteCount = 4_096
    private static let maximumCentralDirectoryByteCount = 16 * 1_024 * 1_024
    private static let endOfCentralDirectorySize = 22
    private static let centralDirectoryHeaderSize = 46
    private static let maximumZIPCommentByteCount = 65_535
    private static let endOfCentralDirectorySignature: [UInt8] = [0x50, 0x4b, 0x05, 0x06]
    private static let centralDirectorySignature: [UInt8] = [0x50, 0x4b, 0x01, 0x02]

    private struct ArchiveDirectoryMetadata {
        let entryCount: Int
    }

    package static func classify(at archiveURL: URL) -> NotabilityContainerGeneration {
        do {
            guard let metadata = try boundedDirectoryMetadata(at: archiveURL),
                  metadata.entryCount <= maximumInspectedEntries else {
                return .unknown
            }
            let archive = try Archive(url: archiveURL, accessMode: .read)
            var visitedEntryCount = 0
            var regularEntryPaths: [String] = []

            for entry in archive {
                visitedEntryCount += 1
                guard visitedEntryCount <= metadata.entryCount else { return .unknown }
                let path = entry.path
                guard path.utf8.count <= maximumEntryPathByteCount else { return .unknown }
                if entry.type == .file {
                    regularEntryPaths.append(path)
                }
            }

            // ZIPFoundation's iterator silently stops when a later local header is
            // malformed. Compare against the bounded EOCD count so a partial walk
            // cannot hide a trailing legacy marker or misclassify a damaged ZIP.
            guard visitedEntryCount == metadata.entryCount else { return .unknown }
            return classify(regularEntryPaths: regularEntryPaths)
        } catch {
            return .unknown
        }
    }

    package static func classify<EntryPaths: Sequence>(
        regularEntryPaths: EntryPaths
    ) -> NotabilityContainerGeneration where EntryPaths.Element == String {
        var foundModernMarker = false
        var inspectedEntryCount = 0

        for path in regularEntryPaths {
            inspectedEntryCount += 1
            guard inspectedEntryCount <= maximumInspectedEntries,
                  path.utf8.count <= maximumEntryPathByteCount else {
                return .unknown
            }
            switch finalComponent(of: path) {
            case "Session.plist":
                return .legacy
            case "noteBundle":
                foundModernMarker = true
            default:
                continue
            }
        }

        return foundModernMarker ? .modernFlatBuffers : .unknown
    }

    /// Reads only the bounded ZIP tail and validates the classic EOCD record.
    /// ZIP64 and multi-disk archives are rejected as unknown: neither is needed
    /// for a Notability container marker and accepting them would reintroduce an
    /// attacker-controlled entry count.
    private static func boundedDirectoryMetadata(
        at archiveURL: URL
    ) throws -> ArchiveDirectoryMetadata? {
        let handle = try FileHandle(forReadingFrom: archiveURL)
        defer { try? handle.close() }

        let fileSize = try handle.seekToEnd()
        guard fileSize >= UInt64(endOfCentralDirectorySize) else { return nil }
        let maximumTailSize = endOfCentralDirectorySize + maximumZIPCommentByteCount
        let tailSize = Int(min(fileSize, UInt64(maximumTailSize)))
        try handle.seek(toOffset: fileSize - UInt64(tailSize))
        guard let tail = try handle.read(upToCount: tailSize),
              tail.count == tailSize else {
            return nil
        }

        var candidateOffsets: [Int] = []
        var zipFoundationCandidateOffset: Int?
        let lastCandidate = tail.count - endOfCentralDirectorySize
        for offset in stride(from: lastCandidate, through: 0, by: -1) {
            guard hasEOCDSignature(tail, at: offset) else { continue }

            // ZIPFoundation selects the first complete signature encountered
            // while scanning backward, without checking that commentLength
            // consumes the remaining bytes. Track that exact choice so our
            // independently validated record cannot diverge from its parser.
            if zipFoundationCandidateOffset == nil {
                zipFoundationCandidateOffset = offset
            }

            let commentLength = Int(readUInt16(tail, at: offset + 20))
            guard offset + endOfCentralDirectorySize + commentLength == tail.count else {
                continue
            }

            candidateOffsets.append(offset)
            // A ZIP comment may contain a second syntactically valid EOCD.
            // ZIPFoundation trusts the last one, which lets its entry count hide
            // a later legacy marker. Ambiguity is therefore unsafe, not a tie to
            // resolve heuristically.
            guard candidateOffsets.count == 1 else { return nil }
        }

        guard let offset = candidateOffsets.first,
              let zipFoundationCandidateOffset,
              offset == zipFoundationCandidateOffset else {
            return nil
        }

        let diskNumber = readUInt16(tail, at: offset + 4)
        let centralDirectoryDisk = readUInt16(tail, at: offset + 6)
        let entriesOnDisk = readUInt16(tail, at: offset + 8)
        let totalEntries = readUInt16(tail, at: offset + 10)
        let centralDirectorySize = readUInt32(tail, at: offset + 12)
        let centralDirectoryOffset = readUInt32(tail, at: offset + 16)

        // 0xffff / 0xffffffff are ZIP64 sentinels.
        guard diskNumber == 0,
              centralDirectoryDisk == 0,
              entriesOnDisk == totalEntries,
              totalEntries != .max,
              Int(totalEntries) <= maximumInspectedEntries,
              centralDirectorySize != .max,
              Int(centralDirectorySize) <= maximumCentralDirectoryByteCount,
              centralDirectoryOffset != .max else {
            return nil
        }

        let absoluteEOCDOffset = fileSize - UInt64(tail.count) + UInt64(offset)
        let centralDirectoryEnd = UInt64(centralDirectoryOffset) + UInt64(centralDirectorySize)
        guard centralDirectoryEnd == absoluteEOCDOffset else { return nil }

        try handle.seek(toOffset: UInt64(centralDirectoryOffset))
        let directorySize = Int(centralDirectorySize)
        guard let directory = try handle.read(upToCount: directorySize),
              directory.count == directorySize,
              validateCentralDirectory(directory, entryCount: Int(totalEntries)) else {
            return nil
        }

        return ArchiveDirectoryMetadata(entryCount: Int(totalEntries))
    }

    private static func hasEOCDSignature(_ data: Data, at offset: Int) -> Bool {
        endOfCentralDirectorySignature.indices.allSatisfy {
            data[offset + $0] == endOfCentralDirectorySignature[$0]
        }
    }

    private static func validateCentralDirectory(_ data: Data, entryCount: Int) -> Bool {
        var offset = 0
        for _ in 0..<entryCount {
            guard offset + centralDirectoryHeaderSize <= data.count,
                  centralDirectorySignature.indices.allSatisfy({
                      data[offset + $0] == centralDirectorySignature[$0]
                  }) else {
                return false
            }

            let pathByteCount = Int(readUInt16(data, at: offset + 28))
            let extraByteCount = Int(readUInt16(data, at: offset + 30))
            let commentByteCount = Int(readUInt16(data, at: offset + 32))
            let versionNeededToExtract = readUInt16(data, at: offset + 6)
            let compressedSize = readUInt32(data, at: offset + 20)
            let uncompressedSize = readUInt32(data, at: offset + 24)
            let diskNumberStart = readUInt16(data, at: offset + 34)
            let localHeaderOffset = readUInt32(data, at: offset + 42)
            guard versionNeededToExtract < 45,
                  compressedSize != .max,
                  uncompressedSize != .max,
                  diskNumberStart == 0,
                  localHeaderOffset != .max,
                  pathByteCount <= maximumEntryPathByteCount else {
                return false
            }

            let recordSize = centralDirectoryHeaderSize
                + pathByteCount
                + extraByteCount
                + commentByteCount
            guard recordSize <= data.count - offset else { return false }

            let extraStart = offset + centralDirectoryHeaderSize + pathByteCount
            let extraEnd = extraStart + extraByteCount
            guard validateExtraFieldsWithoutZIP64(data, from: extraStart, to: extraEnd) else {
                return false
            }
            offset += recordSize
        }
        return offset == data.count
    }

    private static func validateExtraFieldsWithoutZIP64(
        _ data: Data,
        from start: Int,
        to end: Int
    ) -> Bool {
        var offset = start
        while offset < end {
            guard offset + 4 <= end else { return false }
            let headerID = readUInt16(data, at: offset)
            let fieldSize = Int(readUInt16(data, at: offset + 2))
            guard fieldSize <= end - offset - 4,
                  headerID != 0x0001 else {
                return false
            }
            offset += 4 + fieldSize
        }
        return offset == end
    }

    private static func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    private static func finalComponent(of path: String) -> String? {
        path
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/", omittingEmptySubsequences: true)
            .filter { $0 != "." }
            .last
            .map(String.init)
    }
}
