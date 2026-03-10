import ArgumentParser
import Foundation

struct InitProject: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init-project",
        abstract: "建立 PDF 轉 LaTeX 專案資料夾與 manifest。"
    )

    @Option(name: .long, help: "來源 PDF 路徑。")
    var pdf: String

    @Option(name: .long, help: "專案輸出資料夾；未提供時預設為來源 PDF 同資料夾下的同名資料夾。")
    var output: String?

    mutating func run() throws {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let pdfURL = Support.absoluteURL(from: pdf, relativeTo: cwd)
        let root = output.map { Support.absoluteURL(from: $0, relativeTo: cwd) }
            ?? ProjectBootstrap().defaultProjectRoot(for: pdfURL)
        let manifestURL = ProjectLayout.manifestURL(for: root)
        let store = ManifestStore()

        if !FileManager.default.fileExists(atPath: pdfURL.path) {
            throw ValidationError("找不到來源 PDF: \(pdfURL.path)")
        }

        try ProjectLayout.create(at: root)

        if FileManager.default.fileExists(atPath: manifestURL.path) {
            throw ValidationError("專案已存在 manifest: \(manifestURL.path)")
        }

        let manifest = Support.bootstrapManifest(projectRoot: root, sourcePDF: pdfURL)
        try store.save(manifest, to: manifestURL)

        print("已建立專案:")
        print(root.path)
        print("manifest:")
        print(manifestURL.path)
    }
}
