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
            subcommands: [Reverse.self, Render.self]
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

        // Optional so `--coverage` can run as a pure diagnostic (#177).
        // The report is the documented step for deciding *whether* to
        // produce the script; requiring the output path forced the caller
        // to produce the very artifact they were still deciding about.
        @Option(name: .customLong("to-mdocx"), help: "輸出的 .mdocx.swift 路徑（省略時須搭配 --coverage）")
        var toMdocx: String?

        @Flag(name: .customLong("from-oplog"),
              help: "強制使用 oplog sidecar（<stem>.oplog.jsonl；找不到時報錯）")
        var fromOplog = false

        @Flag(help: "覆寫既有的輸出檔案")
        var force = false

        // Default false so presence toggles it on — swift-argument-parser's
        // default-true `@Flag` can never become false (the flag would be a
        // no-op). Report is opt-in; no report unless --coverage is passed.
        @Flag(help: "印出 per-part DSL/raw 覆蓋率報告（dual-track coverage metric）")
        var coverage = false

        // format-alignment-engine Phase C (task 3.1): full-fidelity
        // (all-parts, byte-equal floor) is the DEFAULT; this opts out to the
        // old paragraphs-only reverse (text + styleId, no sibling parts).
        @Flag(name: .customLong("paragraphs-only"),
              help: "只反向工程段落（舊行為）；預設為 full-fidelity 全 parts byte-equal 腳本")
        var paragraphsOnly = false

        // format-alignment-engine Phase D (task 4.1): named content slots —
        // strict mode, explicit designation only (no inference).
        @Option(name: .customLong("slot"),
                help: ArgumentHelp(
                    "具名內容 slot：<name>=<paragraph-id>（可重複）。指定段落的文字成為腳本的 Swift 函式參數，其餘內容逐字重建",
                    valueName: "name=paraId"))
        var slots: [String] = []

        func run() throws {
            let inputURL = try validatedInputURL(input)

            guard toMdocx != nil || coverage else {
                throw ValidationError(
                    "需要 --to-mdocx（產生腳本）或 --coverage（只印報告）至少其一")
            }

            let outputURL = toMdocx.map { URL(fileURLWithPath: $0) }
            if let outputURL, let toMdocx {
                guard !FileManager.default.fileExists(atPath: outputURL.path) || force else {
                    throw ValidationError("輸出檔案已存在: \(toMdocx)（使用 --force 覆寫）")
                }
            }

            let log: OperationLog
            var dslParts: Set<String> = []
            var rawReasons: [String: String] = [:]
            if let sidecarLog = try SidecarStore.loadLog(alongside: inputURL) {
                log = sidecarLog
                FileHandle.standardError.write(Data(
                    "使用 oplog sidecar（\(log.entries.count) 個操作）\n".utf8))
            } else if fromOplog {
                throw ValidationError(
                    "找不到 oplog sidecar: \(SidecarStore.oplogURL(for: inputURL).path)")
            } else if paragraphsOnly {
                log = try Self.reverseEngineer(from: inputURL)
            } else {
                // Full-fidelity default (Phase C): all parts ride the script —
                // raw channel floor + typed DSL upgrades where byte-equal
                // permits (ReverseExtractor's trial-rebuild gate).
                let parts = try RawPartChannel.readAllParts(from: inputURL)
                let result = try ReverseExtractor.reverse(parts: parts)
                log = result.log
                dslParts = result.dslParts
                rawReasons = result.rawReasons
            }

            // Coverage BEFORE the write (#177). The report is a decision input
            // for whether to produce the script at all — printing it afterwards
            // meant the artifact already existed by the time you could judge it.
            if coverage {
                try Self.reportCoverage(for: inputURL,
                                        dslParts: dslParts,
                                        rawReasons: rawReasons)
            }

            // Coverage-only: report printed, nothing to write.
            guard let outputURL, let toMdocx else { return }

            // Parse --slot name=paraId designations (strict: malformed
            // designations fail loudly, never degrade silently).
            var designations: [SlotDesignation] = []
            for raw in slots {
                let pieces = raw.split(separator: "=", maxSplits: 1)
                guard pieces.count == 2, !pieces[0].isEmpty, !pieces[1].isEmpty else {
                    throw ValidationError("無效的 slot 指定: \(raw)（格式為 <name>=<paragraph-id>）")
                }
                designations.append(SlotDesignation(
                    name: String(pieces[0]), paraId: String(pieces[1])))
            }

            let source: String
            do {
                source = try ScriptExporter.exportSwift(log: log, slots: designations)
            } catch let TranscodeError.slotDesignationFailure(name, reason) {
                throw ValidationError("slot「\(name)」無法建立: \(reason)")
            }
            try source.write(to: outputURL, atomically: true, encoding: .utf8)
            FileHandle.standardError.write(Data("已寫入: \(toMdocx)\n".utf8))
        }

        /// Prints the dual-track coverage report to stdout: per-part DSL/raw
        /// split + aggregate %. `dslParts` comes from the full-fidelity
        /// reverse (parts whose typed rebuild proved byte-equal); sidecar and
        /// paragraphs-only paths report all-raw — those modes carry no
        /// byte-equal DSL claim.
        static func reportCoverage(for url: URL,
                                   dslParts: Set<String> = [],
                                   rawReasons: [String: String] = [:]) throws {
            let parts = try RawPartChannel.readAllParts(from: url)
            let report = RawPartChannel.partLevelCoverage(parts: parts, dslParts: dslParts)
            var lines = ["=== Coverage report: \(url.lastPathComponent) ==="]
            for part in report.parts {
                let channel = part.dslBytes > 0 ? "dsl" : "raw"
                let pad = String(repeating: " ", count: max(1, 34 - part.partPath.count))
                lines.append("\(part.partPath)\(pad)\(channel)  \(part.totalBytes) B   "
                    + "DSL \(String(format: "%.1f", part.coverageRatio * 100))%")
            }
            lines.append(String(
                format: "--- Aggregate: %.1f%% DSL (%d / %d XML bytes across %d parts) ---",
                report.aggregateRatio * 100,
                report.aggregateDSLBytes,
                report.aggregateTotalBytes,
                report.parts.count))
            lines.append(contentsOf: Self.rawReasonNote(rawReasons))
            print(lines.joined(separator: "\n"))
        }

        /// Names the root cause when `word/document.xml` fell to the raw channel
        /// for a reason the caller can act on, and points at the trade-off (#176).
        ///
        /// Only `paragraph-no-paraId` gets a note: it is the one raw reason with
        /// a documented alternative path. Other reasons (`table`, `byte-mismatch`,
        /// `parse-error`, …) have no such escape hatch, and emitting the hint for
        /// them would send the caller down a road that does not help.
        static func rawReasonNote(_ rawReasons: [String: String]) -> [String] {
            guard rawReasons["word/document.xml"] == "paragraph-no-paraId" else { return [] }
            return [
                "",
                "note: word/document.xml 落 raw 的根因是 paragraph-no-paraId —— 檔案中有段落不帶",
                "      w14:paraId（部分 Word 版本的產物即如此）。DSL 升級是 part-level 全有全無，",
                "      一個段落缺 id 就整份降 raw，所以上面的 DSL 百分比對這份檔案不具參考性。",
                "",
                "      這個數字不代表 swiftify 對本檔無能為力，只代表「預設的 full-fidelity 路徑」",
                "      無能為力。二選一：",
                "        · 預設（full-fidelity）：byte-equal 可驗證，但腳本不可讀、slot 需真 paraId",
                "        · --paragraphs-only     ：可讀的 DSL、--slot 可用（為缺 id 的段落合成 id），",
                "                                  代價是重播只保證 content-equivalent，不再 byte-equal",
            ]
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
