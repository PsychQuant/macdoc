// MacDoc+Word.swift
// word-aligned-state-sync Phase 4 task 5.7 — `macdoc word reverse`
// (`mdocx-grammar` Requirement "Reverse CLI shape — macdoc word reverse").
//
// Produces an `.mdocx.swift` source file from an existing docx:
// - with an oplog sidecar (default when present, forced by --from-oplog):
//   the sidecar log IS the state — export it directly (ScriptExporter's
//   canonical form; DSL-representable ops become result-builder blocks,
//   everything else the `// @op` raw escape, both replayable).
// - without a sidecar: reverse-engineer an authoring log from the docx
//   typed views (one appendParagraph per body paragraph, preserving
//   w14:paraId and pStyle). Non-paragraph block content (tables, sectPr
//   details) is reported to stderr, not silently dropped.

import ArgumentParser
import Foundation
import OOXMLSwift

extension MacDoc {
    struct Word: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "word",
            abstract: "Word 文件工具（.mdocx 腳本轉換）",
            subcommands: [Reverse.self]
        )
    }
}

extension MacDoc.Word {
    struct Reverse: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "reverse",
            abstract: "從 docx 反向生成 .mdocx.swift 腳本"
        )

        @Argument(help: "輸入的 .docx 檔案")
        var input: String

        @Option(name: .customLong("to-mdocx"), help: "輸出的 .mdocx.swift 路徑")
        var toMdocx: String

        @Flag(name: .customLong("from-oplog"),
              help: "強制使用 oplog sidecar（<stem>.oplog.jsonl；找不到時報錯）")
        var fromOplog = false

        @Flag(help: "覆寫既有的輸出檔案")
        var force = false

        func run() throws {
            let inputURL = try validatedInputURL(input)
            let outputURL = URL(fileURLWithPath: toMdocx)

            guard !FileManager.default.fileExists(atPath: outputURL.path) || force else {
                throw ValidationError("輸出檔案已存在: \(toMdocx)（使用 --force 覆寫）")
            }

            let log: OperationLog
            if let sidecarLog = try SidecarStore.loadLog(alongside: inputURL) {
                log = sidecarLog
                FileHandle.standardError.write(Data(
                    "使用 oplog sidecar（\(log.entries.count) 個操作）\n".utf8))
            } else if fromOplog {
                throw ValidationError(
                    "找不到 oplog sidecar: \(SidecarStore.oplogURL(for: inputURL).path)")
            } else {
                log = try Self.reverseEngineer(from: inputURL)
            }

            let source = ScriptExporter.exportSwift(log: log)
            try source.write(to: outputURL, atomically: true, encoding: .utf8)
            FileHandle.standardError.write(Data("已寫入: \(toMdocx)\n".utf8))
        }

        /// Builds an authoring log from the docx typed views (no oplog input).
        static func reverseEngineer(from url: URL) throws -> OperationLog {
            let document = try DocxReader.read(from: url, wireTreeBackedViews: true)
            var log = OperationLog()
            var skipped: [String] = []

            var paragraphIndex = 0
            for child in document.body.children {
                switch child {
                case .paragraph(let paragraph):
                    paragraphIndex += 1
                    var paraId: String?
                    if let raw = paragraph.elementID?.raw,
                       raw.hasPrefix("w14:paraId=") {
                        paraId = String(raw.dropFirst("w14:paraId=".count))
                    }
                    // Paragraphs without a w14:paraId (docx from Word or
                    // other converters) get a synthesized sequential id so
                    // the emitted source uses DSL-form Paragraph blocks —
                    // the whole point of reverse-engineering. Re-execution
                    // stamps these ids into the rebuilt docx (content-
                    // equivalent, not byte-equal to a paraId-less input).
                    log.append(.appendParagraph(in: nil, paragraph: ParagraphPayload(
                        text: paragraph.text,
                        styleId: paragraph.properties.style,
                        paraId: paraId ?? "p\(paragraphIndex)")), source: .swift)
                case .table:
                    skipped.append("table")
                default:
                    skipped.append(String(describing: child).prefix(30).description)
                }
            }

            if !skipped.isEmpty {
                FileHandle.standardError.write(Data(
                    "警告: 以下 block 內容尚無反向工程通道，已略過: \(skipped.joined(separator: ", "))\n".utf8))
            }
            return log
        }
    }
}
