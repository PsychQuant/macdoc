import ArgumentParser
import Foundation

struct RenderPages: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "render-pages",
        abstract: "把來源 PDF 每頁渲染成 PNG。"
    )

    @Option(name: .long, help: "專案資料夾。")
    var project: String = "."

    @Option(name: .long, help: "輸出 DPI。")
    var dpi: Double = 144

    @Option(name: .long, help: "起始頁碼，從 1 開始。")
    var firstPage: Int?

    @Option(name: .long, help: "結束頁碼，含該頁。")
    var lastPage: Int?

    mutating func run() throws {
        let root = Support.absoluteURL(from: project, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        let manifestURL = ProjectLayout.manifestURL(for: root)
        let store = ManifestStore()

        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw ValidationError("找不到 manifest: \(manifestURL.path)")
        }

        var manifest = try store.load(from: manifestURL)
        let pdfURL = URL(fileURLWithPath: manifest.sourcePDF)
        let outputDirectory = root.appendingPathComponent("pages", isDirectory: true)
        let renderedPages = try PageRenderer().renderPages(
            pdfAt: pdfURL,
            outputDirectory: outputDirectory,
            dpi: dpi,
            firstPage: firstPage,
            lastPage: lastPage
        )

        if manifest.pages.isEmpty {
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
        }

        let renderedByPage = Dictionary(uniqueKeysWithValues: renderedPages.map { ($0.pageNumber, $0.imagePath) })

        manifest.pages = manifest.pages.map { page in
            var updated = page
            if let imagePath = renderedByPage[page.number] {
                updated.renderedImagePath = imagePath
                updated.renderedDPI = dpi
            }
            return updated
        }
        manifest.updatedAt = Support.nowISO8601()

        try store.save(manifest, to: manifestURL)

        print("已渲染 \(renderedPages.count) 頁到:")
        print(outputDirectory.path)
    }
}
