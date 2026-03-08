import ArgumentParser
import Foundation
import PDFToLaTeXCore

// MARK: - Config 子命令組
extension MacDoc {
    struct Config: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "config",
            abstract: "macdoc 設定管理",
            subcommands: [AI.self]
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
    }
}
