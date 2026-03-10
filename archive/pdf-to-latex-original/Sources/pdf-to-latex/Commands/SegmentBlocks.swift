import ArgumentParser
import Foundation

struct SegmentBlocks: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "segment-blocks",
        abstract: "以 Vision OCR 偵測頁面文字區塊，並裁成 block 圖；也可直接從 PDF 自動建專案。"
    )

    @Option(name: .long, help: "專案資料夾。")
    var project: String?

    @Option(name: .long, help: "來源 PDF；提供後可自動初始化專案。")
    var pdf: String?

    @Option(name: .long, help: "輸出資料夾；只在搭配 --pdf 時使用。")
    var output: String?

    @Option(name: .long, help: "起始頁碼，從 1 開始。")
    var firstPage: Int?

    @Option(name: .long, help: "結束頁碼，含該頁。")
    var lastPage: Int?

    @Option(name: .long, help: "頁面渲染 DPI。")
    var pageDPI: Double = 144

    mutating func run() throws {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let resolver = ProjectResolver()
        let pipeline = BlockSegmentationPipeline()
        var project = try resolver.resolve(project: project, pdf: pdf, output: output, cwd: cwd)
        try pipeline.ensurePageRecords(in: &project)
        let selectedPageNumbers = try pipeline.resolvePageNumbers(total: project.manifest.pages.count, firstPage: firstPage, lastPage: lastPage)
        let generatedBlocks = try pipeline.segmentBlocks(in: &project, pageNumbers: selectedPageNumbers, pageDPI: pageDPI)

        print("已產生 \(generatedBlocks.count) 個 blocks，頁碼範圍: \(selectedPageNumbers.first ?? 0)-\(selectedPageNumbers.last ?? 0)")
        print("project:")
        print(project.root.path)
    }
}
