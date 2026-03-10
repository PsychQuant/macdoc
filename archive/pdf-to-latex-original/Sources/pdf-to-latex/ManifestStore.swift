import Foundation

struct ManifestStore {
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

        decoder = JSONDecoder()
    }

    func load(from url: URL) throws -> ProjectManifest {
        let data = try Data(contentsOf: url)
        return try decoder.decode(ProjectManifest.self, from: data)
    }

    func save(_ manifest: ProjectManifest, to url: URL) throws {
        let data = try encoder.encode(manifest)
        try data.write(to: url, options: .atomic)
    }
}
