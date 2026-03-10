import ArgumentParser
import Foundation

struct Status: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "顯示專案狀態。"
    )

    @Option(name: .long, help: "專案資料夾。")
    var project: String = "."

    mutating func run() throws {
        let root = Support.absoluteURL(from: project, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        let manifestURL = ProjectLayout.manifestURL(for: root)
        let store = ManifestStore()

        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            print("尚未初始化專案。")
            print("請先執行: pdf-to-latex init-project --pdf /path/to/book.pdf")
            return
        }

        let manifest = try store.load(from: manifestURL)
        let grouped = Dictionary(grouping: manifest.blocks, by: \.status)
        let pageCount = manifest.pages.count
        let blockCount = manifest.blocks.count

        print("project: \(manifest.projectName)")
        print("root: \(manifest.projectRoot)")
        print("source_pdf: \(manifest.sourcePDF)")
        print("pages: \(pageCount)")
        print("blocks: \(blockCount)")
        print("updated_at: \(manifest.updatedAt)")

        if blockCount > 0 {
            for status in BlockStatus.allCases {
                let count = grouped[status, default: []].count
                print("\(status.rawValue): \(count)")
            }
        }
    }
}
