import ArgumentParser
import Foundation
import PDFToLaTeXCore

/// `config ocr` 各子命令與 `pdf ocr`（#218）共用的設定檔路徑選項。
/// 預設讀寫 `~/.config/macdoc/config.json`；`--config` 可指到別的路徑，
/// 測試用它指向暫存檔，不必動使用者真正的設定檔。
struct OCRConfigOptions: ParsableArguments {
    @Option(help: "設定檔路徑（預設 ~/.config/macdoc/config.json）")
    var config: String?

    var configURL: URL {
        config.map { URL(fileURLWithPath: $0) } ?? AIConfig.defaultConfigURL
    }

    func load() throws -> AIConfig {
        try AIConfig.load(from: configURL)
    }

    func save(_ config: AIConfig) throws {
        try config.save(to: configURL)
    }
}

// MARK: - Config 子命令組
extension MacDoc {
    struct Config: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "config",
            abstract: "macdoc 設定管理",
            subcommands: [AI.self, OCR.self, Document.self]
        )

        // MARK: config ai
        struct AI: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "ai",
                abstract: "AI CLI 工具設定",
                subcommands: [Detect.self, List.self, Set.self]
            )

            // MARK: config ai detect
            struct Detect: AsyncParsableCommand {
                static let configuration = CommandConfiguration(
                    commandName: "detect",
                    abstract: "自動偵測已安裝的 AI CLI 工具，寫入設定檔。"
                )

                mutating func run() throws {
                    let config = AIConfig.detect()
                    try config.save()
                    print("偵測完成:")
                    print("  available: \(config.available.joined(separator: ", "))")
                    print("  transcription: \(config.transcription)")
                    print("  agent: \(config.agent)")
                    print("  config: \(AIConfig.defaultConfigURL.path)")
                }
            }

            // MARK: config ai list
            struct List: AsyncParsableCommand {
                static let configuration = CommandConfiguration(
                    commandName: "list",
                    abstract: "顯示目前的 AI 設定。"
                )

                mutating func run() throws {
                    let config = try AIConfig.load()
                    print("available: \(config.available.joined(separator: ", "))")
                    print("transcription: \(config.transcription)")
                    print("agent: \(config.agent)")
                    print("config: \(AIConfig.defaultConfigURL.path)")
                }
            }

            // MARK: config ai set
            struct Set: AsyncParsableCommand {
                static let configuration = CommandConfiguration(
                    commandName: "set",
                    abstract: "設定 AI 參數（如 transcription、agent）。"
                )

                @Argument(help: "設定鍵（transcription 或 agent）。")
                var key: String

                @Argument(help: "設定值（codex、claude 或 gemini）。")
                var value: String

                mutating func run() throws {
                    var config = try AIConfig.load()

                    switch key {
                    case "transcription":
                        config.transcription = value
                    case "agent":
                        config.agent = value
                    default:
                        throw ValidationError("未知的設定鍵: \(key)。可用: transcription, agent")
                    }

                    try config.save()
                    print("已設定 \(key) = \(value)")
                }
            }
        }

        // MARK: config ocr
        struct OCR: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "ocr",
                abstract: "OCR Ollama host 與模型設定",
                subcommands: [List.self, AddHost.self, RemoveHost.self, SetDefault.self, SetModel.self, SetBackend.self]
            )

            // MARK: config ocr list
            struct List: AsyncParsableCommand {
                static let configuration = CommandConfiguration(
                    commandName: "list",
                    abstract: "顯示目前的 OCR 設定。"
                )

                @OptionGroup var options: OCRConfigOptions

                mutating func run() throws {
                    let config = try options.load()
                    print("=== OCR 設定 ===")
                    print("backend: \(config.ocrDefaultBackend)")
                    print("model:   \(config.ocrDefaultModel)")
                    if let def = config.ocrDefaultHost {
                        let resolved = config.ocrHosts[def] ?? "(profile 不存在!)"
                        print("default host: \(def) → \(resolved)")
                    } else {
                        print("default host: (none, fallback localhost:11434)")
                    }
                    print("")
                    print("=== Host Profiles ===")
                    if config.ocrHosts.isEmpty {
                        print("(none — 用 'macdoc config ocr add-host <name> <address>' 加)")
                    } else {
                        for (name, addr) in config.ocrHosts.sorted(by: { $0.key < $1.key }) {
                            let marker = (name == config.ocrDefaultHost) ? " ★" : ""
                            print("  \(name) → \(addr)\(marker)")
                        }
                    }
                    print("")
                    print("config: \(options.configURL.path)")
                }
            }

            // MARK: config ocr add-host
            struct AddHost: AsyncParsableCommand {
                static let configuration = CommandConfiguration(
                    commandName: "add-host",
                    abstract: "新增或更新具名 host profile（如 kyle → localhost:11435）。"
                )

                @Argument(help: "Profile 名稱（如 kyle、local、production）。")
                var name: String

                @Argument(help: "Ollama 伺服器地址（如 localhost:11435 或 192.168.1.100:11434）。")
                var address: String

                @OptionGroup var options: OCRConfigOptions

                mutating func run() throws {
                    var config = try options.load()
                    let isUpdate = config.ocrHosts[name] != nil
                    config.ocrHosts[name] = address
                    try options.save(config)
                    print("\(isUpdate ? "已更新" : "已新增") profile: \(name) → \(address)")
                    if config.ocrDefaultHost == nil {
                        print("(目前無 default host，可用 'macdoc config ocr set-default \(name)' 設為預設)")
                    }
                }
            }

            // MARK: config ocr remove-host
            struct RemoveHost: AsyncParsableCommand {
                static let configuration = CommandConfiguration(
                    commandName: "remove-host",
                    abstract: "移除具名 host profile。"
                )

                @Argument(help: "要移除的 profile 名稱。")
                var name: String

                @OptionGroup var options: OCRConfigOptions

                mutating func run() throws {
                    var config = try options.load()
                    guard config.ocrHosts.removeValue(forKey: name) != nil else {
                        throw ValidationError("找不到 profile: \(name)")
                    }
                    if config.ocrDefaultHost == name {
                        config.ocrDefaultHost = nil
                        print("(已清除 default host，因為剛好是被移除的 profile)")
                    }
                    try options.save(config)
                    print("已移除 profile: \(name)")
                }
            }

            // MARK: config ocr set-default
            struct SetDefault: AsyncParsableCommand {
                static let configuration = CommandConfiguration(
                    commandName: "set-default",
                    abstract: "設定預設 host profile（之後 pdf ocr 不傳 --host 就用這個，見 #218）。"
                )

                @Argument(help: "已存在的 profile 名稱。傳空字串清除。")
                var name: String

                @OptionGroup var options: OCRConfigOptions

                mutating func run() throws {
                    var config = try options.load()
                    if name.isEmpty {
                        config.ocrDefaultHost = nil
                        try options.save(config)
                        print("已清除 default host")
                        return
                    }
                    guard config.ocrHosts[name] != nil else {
                        throw ValidationError("找不到 profile: \(name)。先用 'add-host' 新增。")
                    }
                    config.ocrDefaultHost = name
                    try options.save(config)
                    print("已設定 default host: \(name) → \(config.ocrHosts[name]!)")
                }
            }

            // MARK: config ocr set-model
            struct SetModel: AsyncParsableCommand {
                static let configuration = CommandConfiguration(
                    commandName: "set-model",
                    abstract: "設定預設 OCR 模型名稱（--mode ollama 時 pdf ocr 的 --model 預設值，見 #218）。"
                )

                @Argument(help: "模型名稱（如 glm-ocr）。")
                var model: String

                @OptionGroup var options: OCRConfigOptions

                mutating func run() throws {
                    var config = try options.load()
                    config.ocrDefaultModel = model
                    try options.save(config)
                    print("已設定 default model: \(model)")
                }
            }

            // MARK: config ocr set-backend
            struct SetBackend: AsyncParsableCommand {
                static let configuration = CommandConfiguration(
                    commandName: "set-backend",
                    abstract: "設定預設 OCR 後端（ollama 或 mlx）。目前 pdf ocr 的 --mode 不會讀這個設定：--mode 本身仍照舊維持自己的內建預設 local，只有想用 Ollama 時才需要自己傳 --mode ollama（見 #218）。"
                )

                @Argument(help: "後端名稱（ollama 或 mlx）。")
                var backend: String

                @OptionGroup var options: OCRConfigOptions

                mutating func run() throws {
                    guard ["ollama", "mlx"].contains(backend) else {
                        throw ValidationError("未知的後端: \(backend)。可用: ollama, mlx")
                    }
                    var config = try options.load()
                    config.ocrDefaultBackend = backend
                    try options.save(config)
                    print("已設定 default backend: \(backend)")
                }
            }
        }
    }
}
