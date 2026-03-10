import Foundation

enum Support {
    static func nowISO8601() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    static func absoluteURL(from path: String, relativeTo base: URL? = nil) -> URL {
        let expanded = NSString(string: path).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)
        if url.path.hasPrefix("/") {
            return url.standardizedFileURL.resolvingSymlinksInPath()
        }

        if let base {
            return base.appendingPathComponent(expanded).standardizedFileURL.resolvingSymlinksInPath()
        }

        return url.standardizedFileURL.resolvingSymlinksInPath()
    }

    static func bootstrapManifest(projectRoot: URL, sourcePDF: URL) -> ProjectManifest {
        let timestamp = nowISO8601()
        return ProjectManifest(
            schemaVersion: 2,
            createdAt: timestamp,
            updatedAt: timestamp,
            projectName: projectRoot.lastPathComponent,
            sourcePDF: sourcePDF.path,
            projectRoot: projectRoot.path,
            pages: [],
            blocks: []
        )
    }
}
