import ArgumentParser
import Foundation

struct ResolvedProject {
    var root: URL
    var manifestURL: URL
    var manifest: ProjectManifest
    var pdfURL: URL
}

struct ProjectResolver {
    let bootstrap = ProjectBootstrap()
    let store = ManifestStore()

    func resolve(project: String?, pdf: String?, output: String?, cwd: URL) throws -> ResolvedProject {
        if let pdf {
            let pdfURL = Support.absoluteURL(from: pdf, relativeTo: cwd)
            guard FileManager.default.fileExists(atPath: pdfURL.path) else {
                throw ValidationError("找不到來源 PDF: \(pdfURL.path)")
            }

            let root: URL
            if let output {
                root = Support.absoluteURL(from: output, relativeTo: cwd)
            } else if let project {
                root = Support.absoluteURL(from: project, relativeTo: cwd)
            } else {
                root = bootstrap.defaultProjectRoot(for: pdfURL)
            }

            let ensured = try bootstrap.ensureProject(pdfURL: pdfURL, projectRoot: root)
            return ResolvedProject(
                root: root,
                manifestURL: ensured.manifestURL,
                manifest: ensured.manifest,
                pdfURL: pdfURL
            )
        }

        guard let project else {
            throw ValidationError("請提供 --project 或 --pdf。")
        }

        let root = Support.absoluteURL(from: project, relativeTo: cwd)
        let manifestURL = ProjectLayout.manifestURL(for: root)
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw ValidationError("找不到 manifest: \(manifestURL.path)")
        }

        let manifest = try store.load(from: manifestURL)
        return ResolvedProject(
            root: root,
            manifestURL: manifestURL,
            manifest: manifest,
            pdfURL: URL(fileURLWithPath: manifest.sourcePDF)
        )
    }
}
