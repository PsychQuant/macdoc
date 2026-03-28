import ArgumentParser
import Foundation

@main
struct MacDoc: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "macdoc",
        abstract: "原生 macOS 文件處理工具",
        version: "0.4.0",
        subcommands: [Convert.self, PDF.self, Bib.self, Config.self, OCR.self]
    )
}
