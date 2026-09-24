import ArgumentParser
import Foundation
import OOXMLSwift

enum DocumentProfileOption: String, CaseIterable, ExpressibleByArgument {
    case inherit
    case official

    var kind: DocumentFormattingProfile.Kind {
        switch self {
        case .inherit: return .inherit
        case .official: return .official
        }
    }
}

struct DocumentConfigOptions: ParsableArguments {
    @Option(help: "文件設定檔路徑（預設 ~/.config/macdoc/config.json）")
    var config: String?

    var store: DocumentProfileStore {
        DocumentProfileStore(configURL: config.map { URL(fileURLWithPath: $0) } ?? DocumentProfileStore.defaultConfigURL)
    }
}

extension MacDoc.Config {
    struct Document: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "document", abstract: "文件格式設定與範本快照",
            subcommands: [Show.self, SetDefault.self, ImportOfficial.self, Gc.self])

        struct Show: ParsableCommand {
            static let configuration = CommandConfiguration(commandName: "show", abstract: "顯示文件格式設定")
            @OptionGroup var options: DocumentConfigOptions

            func run() throws {
                let settings = try options.store.settings()
                print("defaultProfile: \(settings.defaultProfile.rawValue)")
                print("officialSnapshot: \(settings.officialSnapshot ?? "(尚未匯入)")")
            }
        }

        struct SetDefault: ParsableCommand {
            static let configuration = CommandConfiguration(commandName: "set-default", abstract: "設定新文件的預設格式")
            @Argument(help: "inherit 或 official") var profile: DocumentProfileOption
            @OptionGroup var options: DocumentConfigOptions

            func run() throws {
                try options.store.setDefaultProfile(profile.kind)
                print("已設定 defaultProfile = \(profile.rawValue)")
            }
        }

        struct ImportOfficial: ParsableCommand {
            static let configuration = CommandConfiguration(commandName: "import-official", abstract: "從 Normal 範本匯入安全格式快照；不變更新文件預設值")
            @Option(help: "範本路徑（省略時使用目前帳號的 Word Normal.dotm）") var template: String?
            @OptionGroup var options: DocumentConfigOptions

            func run() throws {
                let url = template.map { URL(fileURLWithPath: $0) } ?? FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/Group Containers/UBF8T346G9.Office/User Content.localized/Templates.localized/Normal.dotm")
                try options.store.importOfficial(from: url)
                print("已匯入 official 格式快照；defaultProfile 未變更。")
            }
        }

        struct Gc: ParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "gc", abstract: "清理未被引用的 official 格式快照；預設只列出，加 --force 才刪除")
            @Flag(help: "實際刪除列出的快照（預設只預覽）") var force = false
            @OptionGroup var options: DocumentConfigOptions

            func run() throws {
                let paths = try options.store.garbageCollectOfficialSnapshots(dryRun: !force)
                guard !paths.isEmpty else {
                    print("沒有需要清理的快照。")
                    return
                }
                print(force ? "已刪除 \(paths.count) 個未被引用的快照：" : "以下 \(paths.count) 個快照未被引用（預覽，未刪除）：")
                for path in paths { print("  \(path)") }
                if !force { print("加上 --force 才會刪除。") }
            }
        }
    }
}
