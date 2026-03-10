import Foundation

enum ProjectLayout {
    static let manifestFileName = "manifest.json"

    static let requiredDirectories = [
        "input",
        "pages",
        "blocks",
        "snippets",
        "lossless",
        "semantic",
        "reports",
        "tmp",
    ]

    static func create(at root: URL, fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        for directory in requiredDirectories {
            try fileManager.createDirectory(
                at: root.appendingPathComponent(directory, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
    }

    static func manifestURL(for root: URL) -> URL {
        root.appendingPathComponent(manifestFileName)
    }
}
