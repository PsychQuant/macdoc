import ArgumentParser
import Foundation

struct Segment: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "segment",
        abstract: "掃描來源 PDF 頁面資訊，更新 manifest。"
    )

    @Option(name: .long, help: "專案資料夾。")
    var project: String = "."

    mutating func run() throws {
        let root = Support.absoluteURL(from: project, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        let manifestURL = ProjectLayout.manifestURL(for: root)
        let store = ManifestStore()

        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw ValidationError("找不到 manifest: \(manifestURL.path)")
        }

        var manifest = try store.load(from: manifestURL)
        let pdfURL = URL(fileURLWithPath: manifest.sourcePDF)
        let pages = try PDFScanner().scan(pdfAt: pdfURL)

        manifest.pages = pages.map {
                PageRecord(
                    number: $0.number,
                    width: $0.width,
                    height: $0.height,
                    rotation: $0.rotation,
                    renderedImagePath: nil,
                    renderedDPI: nil
                )
            }
        manifest.updatedAt = Support.nowISO8601()

        try store.save(manifest, to: manifestURL)

        print("已掃描 \(manifest.pages.count) 頁。")
        if let first = manifest.pages.first {
            print("第 1 頁尺寸: \(format(first.width)) x \(format(first.height)) pt")
        }
    }

    private func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
