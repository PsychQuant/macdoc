import ArgumentParser
import Foundation

struct TranscribeBlocks: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "transcribe-blocks",
        abstract: "用 codex exec -i 將 block 圖轉成 LaTeX snippet。"
    )

    @Option(name: .long, help: "專案資料夾。")
    var project: String?

    @Option(name: .long, help: "來源 PDF；提供後可自動建專案與切塊。")
    var pdf: String?

    @Option(name: .long, help: "輸出資料夾；只在搭配 --pdf 時使用。")
    var output: String?

    @Option(name: .long, help: "起始頁碼，從 1 開始。")
    var firstPage: Int?

    @Option(name: .long, help: "結束頁碼，含該頁。")
    var lastPage: Int?

    @Option(name: .long, help: "頁面渲染 DPI。")
    var pageDPI: Double = 144

    @Option(name: .long, help: "指定 Codex 使用的模型。")
    var model: String = "gpt-5.4"

    @Option(name: .long, help: "最多轉寫幾個 blocks，用於 smoke test。")
    var maxBlocks: Int?

    @Option(name: .long, parsing: .upToNextOption, help: "只轉寫指定 block id，可重複提供。")
    var blockID: [String] = []

    @Option(name: .long, help: "同時最多跑幾個 blocks。")
    var concurrency: Int = 1

    @Option(name: .long, help: "每次送出新 block 前等待幾秒。")
    var throttleSeconds: Double = 0

    @Option(name: .long, help: "單一 block 最多等待幾秒。")
    var timeoutSeconds: Double = 90

    @Flag(name: .long, help: "忽略既有 transcribed 狀態，重新轉寫。")
    var overwrite: Bool = false

    mutating func run() async throws {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let resolver = ProjectResolver()
        let pipeline = BlockSegmentationPipeline()
        let store = ManifestStore()
        let codex = CodexCLI()

        var project = try resolver.resolve(project: project, pdf: pdf, output: output, cwd: cwd)
        recoverInterruptedBlocks(in: &project, store: store)
        try pipeline.ensurePageRecords(in: &project)
        let pageNumbers = try pipeline.resolvePageNumbers(total: project.manifest.pages.count, firstPage: firstPage, lastPage: lastPage)
        _ = try pipeline.ensureBlocks(in: &project, pageNumbers: pageNumbers, pageDPI: pageDPI)
        project.manifest.schemaVersion = max(project.manifest.schemaVersion, 2)

        let selectedSet = Set(pageNumbers)
        var blocks = project.manifest.blocks
            .filter { selectedSet.contains($0.page) }
            .filter { block in
                if overwrite {
                    return true
                }
                return block.status.isRunnableWithoutOverwrite
            }
            .sorted { lhs, rhs in
                if lhs.page != rhs.page {
                    return lhs.page < rhs.page
                }
                return lhs.id < rhs.id
            }

        if !blockID.isEmpty {
            let selectedIDs = Set(blockID)
            blocks = blocks.filter { selectedIDs.contains($0.id) }
        }

        if let maxBlocks {
            blocks = Array(blocks.prefix(maxBlocks))
        }

        guard !blocks.isEmpty else {
            print("沒有需要轉寫的 blocks。")
            print("project:")
            print(project.root.path)
            return
        }

        let schemaURL = project.root.appendingPathComponent("tmp/codex-transcription.schema.json")
        try codex.writeSchema(to: schemaURL)

        let workerCount = max(1, concurrency)
        let projectRoot = project.root
        let modelName = model
        let requestTimeout = timeoutSeconds
        let throttle = throttleSeconds
        let reasoningEffort = "low"
        var transcribedCount = 0

        await withTaskGroup(of: TranscriptionOutcome.self) { group in
            var nextIndex = 0

            func queueNext() async {
                guard nextIndex < blocks.count else { return }
                let queuedBlock = blocks[nextIndex]
                nextIndex += 1
                guard let manifestIndex = project.manifest.blocks.firstIndex(where: { $0.id == queuedBlock.id }) else { return }
                project.manifest.blocks[manifestIndex].status = .transcribing
                project.manifest.blocks[manifestIndex].attemptCount = (project.manifest.blocks[manifestIndex].attemptCount ?? 0) + 1
                project.manifest.blocks[manifestIndex].lastAttemptAt = Support.nowISO8601()
                project.manifest.blocks[manifestIndex].lastModel = modelName
                project.manifest.blocks[manifestIndex].lastReasoningEffort = reasoningEffort
                project.manifest.blocks[manifestIndex].lastTimeoutSeconds = requestTimeout
                project.manifest.updatedAt = Support.nowISO8601()
                try? store.save(project.manifest, to: project.manifestURL)
                let block = project.manifest.blocks[manifestIndex]
                group.addTask {
                    TranscriptionWorker.run(
                        block: block,
                        projectRoot: projectRoot,
                        model: modelName,
                        timeoutSeconds: requestTimeout,
                        schemaURL: schemaURL
                    )
                }
                if throttle > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(throttle * 1_000_000_000))
                }
            }

            for _ in 0..<min(workerCount, blocks.count) {
                await queueNext()
            }

            while let outcome = await group.next() {
                if let index = project.manifest.blocks.firstIndex(where: { $0.id == outcome.blockID }) {
                    project.manifest.blocks[index].status = outcome.status
                    project.manifest.blocks[index].notes = outcome.notes
                    project.manifest.blocks[index].completedAt = Support.nowISO8601()
                    if let snippetPath = outcome.snippetPath {
                        project.manifest.blocks[index].latexPath = snippetPath
                    }
                }

                if outcome.status.countsAsSuccess {
                    transcribedCount += 1
                    print("ok \(outcome.blockID)")
                } else {
                    print("failed \(outcome.blockID)")
                    if let notes = outcome.notes {
                        print(notes)
                    }
                }

                project.manifest.updatedAt = Support.nowISO8601()
                try? store.save(project.manifest, to: project.manifestURL)
                await queueNext()
            }
        }

        try store.save(project.manifest, to: project.manifestURL)

        print("已處理 \(blocks.count) 個 blocks，成功轉寫 \(transcribedCount) 個。")
        print("project:")
        print(project.root.path)
    }

    private func recoverInterruptedBlocks(in project: inout ResolvedProject, store: ManifestStore) {
        var didRecover = false
        for index in project.manifest.blocks.indices {
            if project.manifest.blocks[index].status == .transcribing {
                project.manifest.blocks[index].status = .queued
                didRecover = true
            }
        }
        if didRecover {
            project.manifest.schemaVersion = max(project.manifest.schemaVersion, 2)
            project.manifest.updatedAt = Support.nowISO8601()
            try? store.save(project.manifest, to: project.manifestURL)
        }
    }
}
