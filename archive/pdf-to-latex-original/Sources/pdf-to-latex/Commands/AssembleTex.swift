import ArgumentParser
import Foundation

struct AssembleTex: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "assemble-tex",
        abstract: "把已切塊與已轉寫的 snippets 組成可編譯的 book/chapter TeX。"
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

    @Option(name: .long, help: "頁面背景渲染 DPI。")
    var pageDPI: Double = 216

    @Option(name: .long, help: "章節切法：auto, outline, headings, pages, single, custom。")
    var chapterStrategy: ChapterStrategy = .auto

    @Option(name: .long, help: "搭配 pages 策略使用，例如 1-24,25-60。")
    var pageRanges: String?

    @Option(name: .long, help: "搭配 custom 策略使用的 chapter config JSON 路徑。")
    var chapterConfig: String?

    @Flag(name: .long, help: "只產生 TeX，不執行 latexmk。")
    var skipCompile: Bool = false

    mutating func run() throws {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let resolver = ProjectResolver()
        let pipeline = BlockSegmentationPipeline()
        let assembler = TexAssembler()
        let planner = ChapterPlanner()
        let configStore = ChapterConfigStore()

        var project = try resolver.resolve(project: project, pdf: pdf, output: output, cwd: cwd)
        try pipeline.ensurePageRecords(in: &project)
        let pageNumbers = try pipeline.resolvePageNumbers(total: project.manifest.pages.count, firstPage: firstPage, lastPage: lastPage)
        try pipeline.ensureRenderedPages(in: &project, pageNumbers: pageNumbers, dpi: pageDPI)
        let chapterConfigURL = chapterConfig.map { Support.absoluteURL(from: $0, relativeTo: cwd) }
        let chapters = try planner.plan(
            strategy: chapterStrategy,
            project: project,
            pageNumbers: pageNumbers,
            pageRanges: pageRanges,
            chapterConfig: chapterConfigURL
        )
        let resolvedConfigURL = chapterConfigURL
            ?? configStore.defaultURL(for: project.root, strategy: chapterStrategy)
        try configStore.save(
            chapters: chapters,
            strategy: chapterStrategy,
            sourcePDF: project.pdfURL,
            to: resolvedConfigURL
        )

        let assembled = try assembler.assembleSemanticDocument(project: project, chapters: chapters)

        print("chapter_config:")
        print(resolvedConfigURL.path)
        print("main_tex:")
        print(assembled.mainTexURL.path)
        print("chapters:")
        for url in assembled.chapterTexURLs {
            print(url.path)
        }

        if !skipCompile {
            let pdfURL = try TexCompiler().compile(mainTexURL: assembled.mainTexURL)
            print("pdf:")
            print(pdfURL.path)
        }
    }
}
