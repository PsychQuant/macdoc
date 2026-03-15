import ArgumentParser
import Foundation
import CommonConverterSwift
import PDFToMD
import PDFToLaTeXCore

extension ChapterStrategy: @retroactive ExpressibleByArgument {}

// MARK: - PDF 子命令組
extension MacDoc {
    struct PDF: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "pdf",
            abstract: "PDF 工具（直接轉 Markdown + PDF→LaTeX pipeline）",
            subcommands: [
                ToMarkdown.self,
                ToDOCX.self,
                Init.self,
                Segment.self,
                Render.self,
                Blocks.self,
                Transcribe.self,
                TranscribePages.self,
                Resume.self,
                Chapters.self,
                Assemble.self,
                Normalize.self,
                FixEnvs.self,
                CompileCheck.self,
                Consolidate.self,
                Compare.self,
                DetectSource.self,
                Status.self,
            ],
            defaultSubcommand: Status.self
        )

        // MARK: macdoc pdf to-md
        struct ToMarkdown: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "to-md",
                abstract: "將 PDF (.pdf) 直接轉換為 Markdown"
            )

            @Argument(help: "輸入 .pdf 檔案路徑")
            var input: String

            @Option(name: [.short, .long], help: "輸出 .md 檔案路徑（預設為 stdout）")
            var output: String?

            @Flag(name: .long, help: "包含來源檔名與頁數作為 YAML frontmatter")
            var frontmatter: Bool = false

            @Flag(name: .long, help: "保留 PDF 換行為 Markdown hard break")
            var hardBreaks: Bool = false

            mutating func run() async throws {
                let inputURL = URL(fileURLWithPath: input)
                guard FileManager.default.fileExists(atPath: inputURL.path) else {
                    throw ValidationError("找不到輸入檔案: \(input)")
                }

                let options = ConversionOptions(
                    includeFrontmatter: frontmatter,
                    hardLineBreaks: hardBreaks,
                    tableStyle: .pipe,
                    headingStyle: .atx
                )

                let converter = PDFConverter()
                if let outputPath = output {
                    let outputURL = URL(fileURLWithPath: outputPath)
                    try converter.convertToFile(input: inputURL, output: outputURL, options: options)
                } else {
                    try converter.convertToStdout(input: inputURL, options: options)
                }
            }
        }

        // MARK: macdoc pdf init
        struct Init: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "init",
                abstract: "建立 PDF 轉 LaTeX 專案資料夾與 manifest。"
            )

            @Option(name: .long, help: "來源 PDF 路徑。")
            var pdf: String

            @Option(name: .long, help: "專案輸出資料夾。")
            var output: String?

            mutating func run() throws {
                let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                let pdfURL = Support.absoluteURL(from: pdf, relativeTo: cwd)
                let root = output.map { Support.absoluteURL(from: $0, relativeTo: cwd) }
                    ?? ProjectBootstrap().defaultProjectRoot(for: pdfURL)
                let manifestURL = ProjectLayout.manifestURL(for: root)
                let store = ManifestStore()

                guard FileManager.default.fileExists(atPath: pdfURL.path) else {
                    throw ValidationError("找不到來源 PDF: \(pdfURL.path)")
                }

                try ProjectLayout.create(at: root)

                guard !FileManager.default.fileExists(atPath: manifestURL.path) else {
                    throw ValidationError("專案已存在 manifest: \(manifestURL.path)")
                }

                let manifest = Support.bootstrapManifest(projectRoot: root, sourcePDF: pdfURL)
                try store.save(manifest, to: manifestURL)

                print("已建立專案: \(root.path)")
                print("manifest: \(manifestURL.path)")
            }
        }

        // MARK: macdoc pdf segment
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
                        number: $0.number, width: $0.width, height: $0.height,
                        rotation: $0.rotation, renderedImagePath: nil, renderedDPI: nil
                    )
                }
                manifest.updatedAt = Support.nowISO8601()
                try store.save(manifest, to: manifestURL)

                print("已掃描 \(manifest.pages.count) 頁。")
            }
        }

        // MARK: macdoc pdf render
        struct Render: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "render",
                abstract: "把來源 PDF 每頁渲染成 PNG。"
            )

            @Option(name: .long, help: "專案資料夾。")
            var project: String = "."

            @Option(name: .long, help: "輸出 DPI。")
            var dpi: Double = 144

            @Option(name: .long, help: "起始頁碼。")
            var firstPage: Int?

            @Option(name: .long, help: "結束頁碼。")
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
                    pdfAt: pdfURL, outputDirectory: outputDirectory,
                    dpi: dpi, firstPage: firstPage, lastPage: lastPage
                )

                if manifest.pages.isEmpty {
                    manifest.pages = try PDFScanner().scan(pdfAt: pdfURL).map {
                        PageRecord(
                            number: $0.number, width: $0.width, height: $0.height,
                            rotation: $0.rotation, renderedImagePath: nil, renderedDPI: nil
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

                print("已渲染 \(renderedPages.count) 頁到: \(outputDirectory.path)")
            }
        }

        // MARK: macdoc pdf blocks
        struct Blocks: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "blocks",
                abstract: "以 Vision OCR 偵測頁面文字區塊。"
            )

            @Option(name: .long, help: "專案資料夾。")
            var project: String?

            @Option(name: .long, help: "來源 PDF。")
            var pdf: String?

            @Option(name: .long, help: "輸出資料夾。")
            var output: String?

            @Option(name: .long, help: "起始頁碼。")
            var firstPage: Int?

            @Option(name: .long, help: "結束頁碼。")
            var lastPage: Int?

            @Option(name: .long, help: "頁面渲染 DPI。")
            var pageDPI: Double = 144

            mutating func run() throws {
                let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                let resolver = ProjectResolver()
                let pipeline = BlockSegmentationPipeline()
                var resolvedProject = try resolver.resolve(project: project, pdf: pdf, output: output, cwd: cwd)
                try pipeline.ensurePageRecords(in: &resolvedProject)
                let pageNumbers = try pipeline.resolvePageNumbers(total: resolvedProject.manifest.pages.count, firstPage: firstPage, lastPage: lastPage)
                let blocks = try pipeline.segmentBlocks(in: &resolvedProject, pageNumbers: pageNumbers, pageDPI: pageDPI)

                print("已產生 \(blocks.count) 個 blocks")
                print("project: \(resolvedProject.root.path)")
            }
        }

        // MARK: macdoc pdf transcribe
        struct Transcribe: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "transcribe",
                abstract: "用 AI 將 block 圖轉成 LaTeX snippet。"
            )

            @Option(name: .long, help: "專案資料夾。")
            var project: String?

            @Option(name: .long, help: "來源 PDF。")
            var pdf: String?

            @Option(name: .long, help: "輸出資料夾。")
            var output: String?

            @Option(name: .long, help: "起始頁碼。")
            var firstPage: Int?

            @Option(name: .long, help: "結束頁碼。")
            var lastPage: Int?

            @Option(name: .long, help: "頁面渲染 DPI。")
            var pageDPI: Double = 144

            @Option(name: .long, help: "AI 模型。")
            var model: String = "gpt-5.4"

            @Option(name: .long, help: "AI CLI 後端 (codex|claude|gemini)。預設從 model 名稱自動偵測。")
            var backend: String?

            @Option(name: .long, help: "最多轉寫幾個 blocks。")
            var maxBlocks: Int?

            @Option(name: .long, parsing: .upToNextOption, help: "指定 block id。")
            var blockID: [String] = []

            @Option(name: .long, help: "並行數。")
            var concurrency: Int = 1

            @Option(name: .long, help: "節流秒數。")
            var throttleSeconds: Double = 0

            @Option(name: .long, help: "超時秒數。")
            var timeoutSeconds: Double = 90

            @Flag(name: .long, help: "重新轉寫。")
            var overwrite: Bool = false

            mutating func run() async throws {
                let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                let resolver = ProjectResolver()
                let pipeline = BlockSegmentationPipeline()
                let store = ManifestStore()
                let resolvedBackend = backend.flatMap { TranscriptionBackend(rawValue: $0) }
                    ?? TranscriptionBackend.detect(from: model)
                let transcriber = CLITranscriber(backend: resolvedBackend)

                var resolvedProject = try resolver.resolve(project: project, pdf: pdf, output: output, cwd: cwd)
                recoverInterruptedBlocks(in: &resolvedProject, store: store)
                try pipeline.ensurePageRecords(in: &resolvedProject)
                let pageNumbers = try pipeline.resolvePageNumbers(total: resolvedProject.manifest.pages.count, firstPage: firstPage, lastPage: lastPage)
                _ = try pipeline.ensureBlocks(in: &resolvedProject, pageNumbers: pageNumbers, pageDPI: pageDPI)
                resolvedProject.manifest.schemaVersion = max(resolvedProject.manifest.schemaVersion, 2)

                let selectedSet = Set(pageNumbers)
                var blocks = resolvedProject.manifest.blocks
                    .filter { selectedSet.contains($0.page) }
                    .filter { overwrite || $0.status.isRunnableWithoutOverwrite }
                    .sorted { $0.page != $1.page ? $0.page < $1.page : $0.id < $1.id }

                if !blockID.isEmpty {
                    let ids = Set(blockID)
                    blocks = blocks.filter { ids.contains($0.id) }
                }
                if let maxBlocks { blocks = Array(blocks.prefix(maxBlocks)) }

                guard !blocks.isEmpty else {
                    print("沒有需要轉寫的 blocks。")
                    return
                }

                let schemaURL = resolvedProject.root.appendingPathComponent("tmp/codex-transcription.schema.json")
                try transcriber.writeSchema(to: schemaURL)

                let workerCount = max(1, concurrency)
                let projectRoot = resolvedProject.root
                let modelName = model
                let requestTimeout = timeoutSeconds
                let throttle = throttleSeconds
                let workerBackend = resolvedBackend
                var transcribedCount = 0

                await withTaskGroup(of: TranscriptionOutcome.self) { group in
                    var nextIndex = 0

                    func queueNext() async {
                        guard nextIndex < blocks.count else { return }
                        let queuedBlock = blocks[nextIndex]
                        nextIndex += 1
                        guard let idx = resolvedProject.manifest.blocks.firstIndex(where: { $0.id == queuedBlock.id }) else { return }
                        resolvedProject.manifest.blocks[idx].status = .transcribing
                        resolvedProject.manifest.blocks[idx].attemptCount = (resolvedProject.manifest.blocks[idx].attemptCount ?? 0) + 1
                        resolvedProject.manifest.blocks[idx].lastAttemptAt = Support.nowISO8601()
                        resolvedProject.manifest.blocks[idx].lastModel = modelName
                        resolvedProject.manifest.blocks[idx].lastReasoningEffort = "low"
                        resolvedProject.manifest.blocks[idx].lastTimeoutSeconds = requestTimeout
                        resolvedProject.manifest.updatedAt = Support.nowISO8601()
                        try? store.save(resolvedProject.manifest, to: resolvedProject.manifestURL)
                        let block = resolvedProject.manifest.blocks[idx]
                        group.addTask {
                            TranscriptionWorker.run(block: block, projectRoot: projectRoot, model: modelName, timeoutSeconds: requestTimeout, schemaURL: schemaURL, backend: workerBackend)
                        }
                        if throttle > 0 { try? await Task.sleep(nanoseconds: UInt64(throttle * 1_000_000_000)) }
                    }

                    for _ in 0..<min(workerCount, blocks.count) { await queueNext() }

                    while let outcome = await group.next() {
                        if let idx = resolvedProject.manifest.blocks.firstIndex(where: { $0.id == outcome.blockID }) {
                            resolvedProject.manifest.blocks[idx].status = outcome.status
                            resolvedProject.manifest.blocks[idx].notes = outcome.notes
                            resolvedProject.manifest.blocks[idx].completedAt = Support.nowISO8601()
                            if let sp = outcome.snippetPath { resolvedProject.manifest.blocks[idx].latexPath = sp }
                        }
                        if outcome.status.countsAsSuccess { transcribedCount += 1; print("ok \(outcome.blockID)") }
                        else { print("failed \(outcome.blockID)"); if let n = outcome.notes { print(n) } }
                        resolvedProject.manifest.updatedAt = Support.nowISO8601()
                        try? store.save(resolvedProject.manifest, to: resolvedProject.manifestURL)
                        await queueNext()
                    }
                }

                try store.save(resolvedProject.manifest, to: resolvedProject.manifestURL)
                print("已處理 \(blocks.count) 個 blocks，成功轉寫 \(transcribedCount) 個。")
            }

            private func recoverInterruptedBlocks(in project: inout ResolvedProject, store: ManifestStore) {
                var didRecover = false
                for i in project.manifest.blocks.indices where project.manifest.blocks[i].status == .transcribing {
                    project.manifest.blocks[i].status = .queued
                    didRecover = true
                }
                if didRecover {
                    project.manifest.schemaVersion = max(project.manifest.schemaVersion, 2)
                    project.manifest.updatedAt = Support.nowISO8601()
                    try? store.save(project.manifest, to: project.manifestURL)
                }
            }
        }

        // MARK: macdoc pdf transcribe-pages
        struct TranscribePages: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "transcribe-pages",
                abstract: "Page-level 轉寫：整頁送 AI，搭配 LaTeX context sliding window。"
            )

            @Option(name: .long, help: "專案資料夾。")
            var project: String?

            @Option(name: .long, help: "來源 PDF。")
            var pdf: String?

            @Option(name: .long, help: "輸出資料夾。")
            var output: String?

            @Option(name: .long, help: "起始頁碼。")
            var firstPage: Int?

            @Option(name: .long, help: "結束頁碼。")
            var lastPage: Int?

            @Option(name: .long, help: "頁面渲染 DPI。")
            var pageDPI: Double = 144

            @Option(name: .long, help: "AI 模型名稱（預設依 backend: claude=claude-sonnet-4-6, codex=gpt-5.4, gemini=gemini-3.1-pro-preview）。")
            var model: String?

            @Option(name: .long, help: "AI CLI 後端 (codex|claude|gemini)。預設從 model 名稱自動偵測，未指定 model 時預設 claude。")
            var backend: String?

            @Option(name: .long, help: "每次送幾頁（預設 2）。")
            var pagesPerRequest: Int?

            @Option(name: .long, help: "Reasoning effort (none|low|medium|high|xhigh)。")
            var reasoningEffort: String = "medium"

            @Option(name: .long, help: "單次請求超時秒數。")
            var timeoutSeconds: Double = 600

            @Option(name: .long, help: "PDF 來源格式覆蓋 (latex|word|typst|scanned|designer)。未指定時自動偵測。")
            var source: String?

            mutating func run() async throws {
                let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                let resolver = ProjectResolver()
                let pipeline = BlockSegmentationPipeline()

                var resolvedProject = try resolver.resolve(
                    project: project, pdf: pdf, output: output, cwd: cwd
                )
                try pipeline.ensurePageRecords(in: &resolvedProject)
                let pageNumbers = try pipeline.resolvePageNumbers(
                    total: resolvedProject.manifest.pages.count,
                    firstPage: firstPage, lastPage: lastPage
                )

                try pipeline.ensureRenderedPages(
                    in: &resolvedProject, pageNumbers: pageNumbers, dpi: pageDPI
                )

                let resolvedBackend: TranscriptionBackend
                if let b = backend.flatMap({ TranscriptionBackend(rawValue: $0) }) {
                    resolvedBackend = b
                } else if let m = model {
                    resolvedBackend = TranscriptionBackend.detect(from: m)
                } else {
                    resolvedBackend = .codex
                }
                let resolvedModel = model ?? resolvedBackend.defaultModel
                let resolvedEffort = ReasoningEffort(rawValue: reasoningEffort) ?? .medium

                let resolvedSource = source.flatMap { PDFSourceFormat(rawValue: $0) }

                let transcriber = PageTranscriber()
                let results = try transcriber.transcribe(
                    project: &resolvedProject,
                    pageNumbers: pageNumbers,
                    pagesPerRequest: pagesPerRequest,
                    backend: resolvedBackend,
                    model: resolvedModel,
                    reasoningEffort: resolvedEffort,
                    timeoutSeconds: timeoutSeconds,
                    sourceFormat: resolvedSource
                )

                let figureCount = results.reduce(0) { $0 + $1.figures.count }
                print("已轉寫 \(results.count) 頁，裁切 \(figureCount) 個 figures。")
                print("project: \(resolvedProject.root.path)")
            }
        }

        // MARK: macdoc pdf resume
        struct Resume: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "resume",
                abstract: "從 checkpoint 續跑轉寫。"
            )

            @Option(name: .long, help: "專案資料夾。")
            var project: String = "."

            @Option(name: .long, help: "起始頁碼。")
            var firstPage: Int?

            @Option(name: .long, help: "結束頁碼。")
            var lastPage: Int?

            @Option(name: .long, help: "頁面渲染 DPI。")
            var pageDPI: Double = 144

            @Option(name: .long, help: "AI 模型。")
            var model: String = "gpt-5.4"

            @Option(name: .long, help: "AI CLI 後端 (codex|claude|gemini)。預設從 model 名稱自動偵測。")
            var backend: String?

            @Option(name: .long, parsing: .upToNextOption, help: "指定 block id。")
            var blockID: [String] = []

            @Option(name: .long, help: "最多續跑幾個 blocks。")
            var maxBlocks: Int?

            @Option(name: .long, help: "並行數。")
            var concurrency: Int = 1

            @Option(name: .long, help: "節流秒數。")
            var throttleSeconds: Double = 0

            @Option(name: .long, help: "超時秒數。")
            var timeoutSeconds: Double = 90

            mutating func run() async throws {
                var command = Transcribe()
                command.project = project
                command.pdf = nil
                command.output = nil
                command.firstPage = firstPage
                command.lastPage = lastPage
                command.pageDPI = pageDPI
                command.model = model
                command.backend = backend
                command.maxBlocks = maxBlocks
                command.blockID = blockID
                command.concurrency = concurrency
                command.throttleSeconds = throttleSeconds
                command.timeoutSeconds = timeoutSeconds
                command.overwrite = false
                try await command.run()
            }
        }

        // MARK: macdoc pdf chapters
        struct Chapters: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "chapters",
                abstract: "自動偵測章節切法。"
            )

            @Option(name: .long, help: "專案資料夾。")
            var project: String?

            @Option(name: .long, help: "來源 PDF。")
            var pdf: String?

            @Option(name: .long, help: "輸出資料夾。")
            var output: String?

            @Option(name: .long, help: "起始頁碼。")
            var firstPage: Int?

            @Option(name: .long, help: "結束頁碼。")
            var lastPage: Int?

            @Option(name: .long, help: "偵測策略。")
            var chapterStrategy: ChapterStrategy = .auto

            @Option(name: .long, help: "頁碼範圍，例如 1-24,25-60。")
            var pageRanges: String?

            @Option(name: .long, help: "輸出路徑。")
            var outputConfig: String?

            mutating func run() throws {
                if chapterStrategy == .custom {
                    throw ValidationError("chapters 不接受 `custom` 策略。")
                }

                let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                let resolver = ProjectResolver()
                let pipeline = BlockSegmentationPipeline()
                let planner = ChapterPlanner()
                let configStore = ChapterConfigStore()

                var resolvedProject = try resolver.resolve(project: project, pdf: pdf, output: output, cwd: cwd)
                try pipeline.ensurePageRecords(in: &resolvedProject)
                let pageNumbers = try pipeline.resolvePageNumbers(total: resolvedProject.manifest.pages.count, firstPage: firstPage, lastPage: lastPage)
                let chapters = try planner.plan(
                    strategy: chapterStrategy, project: resolvedProject,
                    pageNumbers: pageNumbers, pageRanges: pageRanges, chapterConfig: nil
                )

                let outputURL = outputConfig.map { Support.absoluteURL(from: $0, relativeTo: cwd) }
                    ?? configStore.defaultURL(for: resolvedProject.root, strategy: chapterStrategy)
                try configStore.save(chapters: chapters, strategy: chapterStrategy, sourcePDF: resolvedProject.pdfURL, to: outputURL)

                print("chapter_config: \(outputURL.path)")
                print("chapters_detected: \(chapters.count)")
                for ch in chapters { print("\(ch.id): \(ch.startPage)-\(ch.endPage) \(ch.title)") }
            }
        }

        // MARK: macdoc pdf assemble
        struct Assemble: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "assemble",
                abstract: "組裝已轉寫的 snippets 成可編譯的 TeX。"
            )

            @Option(name: .long, help: "專案資料夾。")
            var project: String?

            @Option(name: .long, help: "來源 PDF。")
            var pdf: String?

            @Option(name: .long, help: "輸出資料夾。")
            var output: String?

            @Option(name: .long, help: "起始頁碼。")
            var firstPage: Int?

            @Option(name: .long, help: "結束頁碼。")
            var lastPage: Int?

            @Option(name: .long, help: "頁面背景渲染 DPI。")
            var pageDPI: Double = 216

            @Option(name: .long, help: "章節切法。")
            var chapterStrategy: ChapterStrategy = .auto

            @Option(name: .long, help: "頁碼範圍。")
            var pageRanges: String?

            @Option(name: .long, help: "chapter config JSON 路徑。")
            var chapterConfig: String?

            @Flag(name: .long, help: "只產生 TeX，不編譯。")
            var skipCompile: Bool = false

            mutating func run() throws {
                let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                let resolver = ProjectResolver()
                let pipeline = BlockSegmentationPipeline()
                let assembler = TexAssembler()
                let planner = ChapterPlanner()
                let configStore = ChapterConfigStore()

                var resolvedProject = try resolver.resolve(project: project, pdf: pdf, output: output, cwd: cwd)
                try pipeline.ensurePageRecords(in: &resolvedProject)
                let pageNumbers = try pipeline.resolvePageNumbers(total: resolvedProject.manifest.pages.count, firstPage: firstPage, lastPage: lastPage)
                try pipeline.ensureRenderedPages(in: &resolvedProject, pageNumbers: pageNumbers, dpi: pageDPI)
                let chapterConfigURL = chapterConfig.map { Support.absoluteURL(from: $0, relativeTo: cwd) }
                let chapters = try planner.plan(
                    strategy: chapterStrategy, project: resolvedProject,
                    pageNumbers: pageNumbers, pageRanges: pageRanges, chapterConfig: chapterConfigURL
                )
                let resolvedConfigURL = chapterConfigURL ?? configStore.defaultURL(for: resolvedProject.root, strategy: chapterStrategy)
                try configStore.save(chapters: chapters, strategy: chapterStrategy, sourcePDF: resolvedProject.pdfURL, to: resolvedConfigURL)

                let assembled = try assembler.assembleSemanticDocument(project: resolvedProject, chapters: chapters)

                print("main_tex: \(assembled.mainTexURL.path)")
                for url in assembled.chapterTexURLs { print("chapter: \(url.path)") }

                if !skipCompile {
                    let pdfURL = try TexCompiler().compile(mainTexURL: assembled.mainTexURL)
                    print("pdf: \(pdfURL.path)")
                }
            }
        }

        // MARK: macdoc pdf compare
        struct Compare: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "compare",
                abstract: "比較原始 PDF 和重製 PDF 的相似度（章節對齊、詞彙覆蓋、序列相似度）。"
            )

            @Option(name: .long, help: "原始 PDF 路徑。")
            var original: String

            @Option(name: .long, help: "重製 PDF 路徑。")
            var reproduced: String

            @Option(name: .shortAndLong, help: "輸出目錄（存放 JSON 報告）。")
            var output: String?

            mutating func run() throws {
                let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                let origURL = Support.absoluteURL(from: original, relativeTo: cwd)
                let reprURL = Support.absoluteURL(from: reproduced, relativeTo: cwd)

                guard FileManager.default.fileExists(atPath: origURL.path) else {
                    throw ValidationError("找不到原始 PDF: \(origURL.path)")
                }
                guard FileManager.default.fileExists(atPath: reprURL.path) else {
                    throw ValidationError("找不到重製 PDF: \(reprURL.path)")
                }

                let outDir: URL?
                if let outPath = output {
                    outDir = Support.absoluteURL(from: outPath, relativeTo: cwd)
                } else {
                    outDir = nil
                }

                print("Original:   \(origURL.path)")
                print("Reproduced: \(reprURL.path)")
                print(String(repeating: "=", count: 80))

                let comparator = PDFComparator()
                _ = try comparator.compare(
                    originalURL: origURL,
                    reproducedURL: reprURL,
                    outputDir: outDir
                )

                print("\n" + String(repeating: "=", count: 80))
            }
        }

        // MARK: macdoc pdf detect-source
        struct DetectSource: ParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "detect-source",
                abstract: "偵測 PDF 的來源格式（LaTeX、Word、掃描件等）。"
            )

            @Argument(help: "PDF 檔案路徑。")
            var pdf: String

            @Flag(name: .long, help: "以 JSON 格式輸出。")
            var json: Bool = false

            func run() throws {
                let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                let url = Support.absoluteURL(from: pdf, relativeTo: cwd)
                guard FileManager.default.fileExists(atPath: url.path) else {
                    throw ValidationError("找不到 PDF: \(url.path)")
                }

                let detector = PDFSourceDetector()
                let result = detector.detect(from: url)

                if json {
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    let data = try encoder.encode(result)
                    print(String(data: data, encoding: .utf8)!)
                } else {
                    print("detect-source: \(url.lastPathComponent)")
                    print("─────────────────────────────────────")
                    print("  Format:     \(result.format.rawValue)")
                    if let engine = result.engine {
                        print("  Engine:     \(engine.rawValue)")
                    }
                    print("  Confidence: \(String(format: "%.0f%%", result.confidence * 100))")
                    if let c = result.creator {
                        print("  Creator:    \(c)")
                    }
                    if let p = result.producer {
                        print("  Producer:   \(p)")
                    }
                    print("")
                    print("  Evidence:")
                    for e in result.evidence {
                        print("    - \(e)")
                    }
                }
            }
        }

        // MARK: macdoc pdf status
        struct Status: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "status",
                abstract: "顯示 PDF 轉 LaTeX 專案狀態。"
            )

            @Option(name: .long, help: "專案資料夾。")
            var project: String = "."

            mutating func run() throws {
                let root = Support.absoluteURL(from: project, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
                let manifestURL = ProjectLayout.manifestURL(for: root)
                let store = ManifestStore()

                guard FileManager.default.fileExists(atPath: manifestURL.path) else {
                    print("尚未初始化專案。")
                    print("請先執行: macdoc pdf init --pdf /path/to/book.pdf")
                    return
                }

                let manifest = try store.load(from: manifestURL)
                let grouped = Dictionary(grouping: manifest.blocks, by: \.status)

                print("project: \(manifest.projectName)")
                print("root: \(manifest.projectRoot)")
                print("source_pdf: \(manifest.sourcePDF)")
                print("pages: \(manifest.pages.count)")
                print("blocks: \(manifest.blocks.count)")
                print("updated_at: \(manifest.updatedAt)")

                if !manifest.blocks.isEmpty {
                    for status in BlockStatus.allCases {
                        print("\(status.rawValue): \(grouped[status, default: []].count)")
                    }
                }
            }
        }

    }
}
