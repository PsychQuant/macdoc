import ArgumentParser
import Foundation

struct DetectChapters: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "detect-chapters",
        abstract: "自動偵測章節切法並輸出 chapters JSON 設定檔。"
    )

    @Option(name: .long, help: "專案資料夾。")
    var project: String?

    @Option(name: .long, help: "來源 PDF；提供後可自動建專案與補頁面渲染。")
    var pdf: String?

    @Option(name: .long, help: "輸出資料夾；只在搭配 --pdf 時使用。")
    var output: String?

    @Option(name: .long, help: "起始頁碼，從 1 開始。")
    var firstPage: Int?

    @Option(name: .long, help: "結束頁碼，含該頁。")
    var lastPage: Int?

    @Option(name: .long, help: "偵測策略：auto, outline, headings, pages, single。")
    var chapterStrategy: ChapterStrategy = .auto

    @Option(name: .long, help: "搭配 pages 策略使用，例如 1-24,25-60。")
    var pageRanges: String?

    @Option(name: .long, help: "輸出的 chapter config 路徑。")
    var outputConfig: String?

    mutating func run() throws {
        if chapterStrategy == .custom {
            throw ValidationError("detect-chapters 不接受 `custom` 策略。")
        }

        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let resolver = ProjectResolver()
        let pipeline = BlockSegmentationPipeline()
        let planner = ChapterPlanner()
        let store = ChapterConfigStore()

        var project = try resolver.resolve(project: project, pdf: pdf, output: output, cwd: cwd)
        try pipeline.ensurePageRecords(in: &project)
        let pageNumbers = try pipeline.resolvePageNumbers(total: project.manifest.pages.count, firstPage: firstPage, lastPage: lastPage)
        let chapters = try planner.plan(
            strategy: chapterStrategy,
            project: project,
            pageNumbers: pageNumbers,
            pageRanges: pageRanges,
            chapterConfig: nil
        )

        let outputURL = outputConfig.map { Support.absoluteURL(from: $0, relativeTo: cwd) }
            ?? store.defaultURL(for: project.root, strategy: chapterStrategy)
        try store.save(
            chapters: chapters,
            strategy: chapterStrategy,
            sourcePDF: project.pdfURL,
            to: outputURL
        )

        print("chapter_config:")
        print(outputURL.path)
        print("chapters_detected: \(chapters.count)")
        for chapter in chapters {
            print("\(chapter.id): \(chapter.startPage)-\(chapter.endPage) \(chapter.title)")
        }
    }
}
