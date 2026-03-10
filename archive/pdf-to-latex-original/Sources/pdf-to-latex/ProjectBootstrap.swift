import ArgumentParser
import Foundation

struct ProjectBootstrap {
    let store = ManifestStore()

    func defaultProjectRoot(for pdfURL: URL) -> URL {
        pdfURL.deletingPathExtension()
    }

    func ensureProject(pdfURL: URL, projectRoot: URL) throws -> (manifest: ProjectManifest, manifestURL: URL) {
        try ProjectLayout.create(at: projectRoot)
        let manifestURL = ProjectLayout.manifestURL(for: projectRoot)

        if FileManager.default.fileExists(atPath: manifestURL.path) {
            let manifest = try store.load(from: manifestURL)
            if manifest.sourcePDF != pdfURL.path {
                throw ValidationError("現有專案的 source_pdf 與指定 PDF 不一致: \(manifest.sourcePDF)")
            }
            return (manifest, manifestURL)
        }

        let manifest = Support.bootstrapManifest(projectRoot: projectRoot, sourcePDF: pdfURL)
        try store.save(manifest, to: manifestURL)
        return (manifest, manifestURL)
    }

    func pageRecords(from snapshots: [PDFPageSnapshot]) -> [PageRecord] {
        snapshots.map {
            PageRecord(
                number: $0.number,
                width: $0.width,
                height: $0.height,
                rotation: $0.rotation,
                renderedImagePath: nil,
                renderedDPI: nil
            )
        }
    }
}
