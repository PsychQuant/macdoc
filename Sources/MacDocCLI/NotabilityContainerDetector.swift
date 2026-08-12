import Foundation
import ZIPFoundation

enum NotabilityContainerGeneration: Equatable {
    case legacy
    case modernFlatBuffers
    case unknown
}

enum NotabilityContainerDetector {
    static let modernContainerDiagnostic =
        "偵測到新版 Notability .ntb 容器（noteBundle／FlatBuffers）；目前僅支援舊版 plist-based .note（Session.plist）"

    static func classify(at archiveURL: URL) -> NotabilityContainerGeneration {
        do {
            let archive = try Archive(url: archiveURL, accessMode: .read)
            let regularEntryPaths = archive.lazy
                .filter { $0.type == .file }
                .map(\.path)
            return classify(regularEntryPaths: regularEntryPaths)
        } catch {
            return .unknown
        }
    }

    static func classify<EntryPaths: Sequence>(
        regularEntryPaths: EntryPaths
    ) -> NotabilityContainerGeneration where EntryPaths.Element == String {
        var foundModernMarker = false

        for path in regularEntryPaths {
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

    private static func finalComponent(of path: String) -> String? {
        path
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/", omittingEmptySubsequences: true)
            .filter { $0 != "." }
            .last
            .map(String.init)
    }
}
