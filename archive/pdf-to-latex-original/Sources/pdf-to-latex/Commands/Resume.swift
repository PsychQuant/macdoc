import ArgumentParser
import Foundation

struct Resume: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "resume",
        abstract: "從既有專案的 checkpoint 狀態續跑轉寫。"
    )

    @Option(name: .long, help: "專案資料夾。")
    var project: String = "."

    @Option(name: .long, help: "起始頁碼，從 1 開始。")
    var firstPage: Int?

    @Option(name: .long, help: "結束頁碼，含該頁。")
    var lastPage: Int?

    @Option(name: .long, help: "頁面渲染 DPI。")
    var pageDPI: Double = 144

    @Option(name: .long, help: "指定 Codex 使用的模型。")
    var model: String = "gpt-5.4"

    @Option(name: .long, parsing: .upToNextOption, help: "只續跑指定 block id，可重複提供。")
    var blockID: [String] = []

    @Option(name: .long, help: "最多續跑幾個 blocks，用於 smoke test。")
    var maxBlocks: Int?

    @Option(name: .long, help: "同時最多跑幾個 blocks。")
    var concurrency: Int = 1

    @Option(name: .long, help: "每次送出新 block 前等待幾秒。")
    var throttleSeconds: Double = 0

    @Option(name: .long, help: "單一 block 最多等待幾秒。")
    var timeoutSeconds: Double = 90

    mutating func run() async throws {
        var command = TranscribeBlocks()
        command.project = project
        command.pdf = nil
        command.output = nil
        command.firstPage = firstPage
        command.lastPage = lastPage
        command.pageDPI = pageDPI
        command.model = model
        command.maxBlocks = maxBlocks
        command.blockID = blockID
        command.concurrency = concurrency
        command.throttleSeconds = throttleSeconds
        command.timeoutSeconds = timeoutSeconds
        command.overwrite = false
        try await command.run()
    }
}
