import Foundation

struct ChapterConfigStore {
    func defaultURL(for projectRoot: URL, strategy: ChapterStrategy) -> URL {
        projectRoot
            .appendingPathComponent("reports", isDirectory: true)
            .appendingPathComponent("chapters", isDirectory: true)
            .appendingPathComponent("\(strategy.rawValue).json")
    }

    func save(
        chapters: [ChapterSpec],
        strategy: ChapterStrategy,
        sourcePDF: URL,
        to url: URL
    ) throws {
        let payload = ChapterConfigFile(
            strategy: strategy.rawValue,
            generatedAt: Support.nowISO8601(),
            sourcePDF: sourcePDF.path,
            chapters: chapters
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(payload)
        try data.write(to: url, options: .atomic)
    }
}
