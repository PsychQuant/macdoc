import ArgumentParser
import Foundation
import PDFToLaTeXCore

// MARK: - PDF Phase 2 consolidation commands
extension MacDoc.PDF {

    // MARK: macdoc pdf normalize
    struct Normalize: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "normalize",
            abstract: "機械式清理 accumulated.tex（document class、符號、跨頁去重、數學運算子、貨幣符號、紙張/字型校正）。"
        )

        @Option(name: .long, help: "專案資料夾。")
        var project: String = "."

        @Flag(name: .long, help: "移除頁面標記 (%% === Page N ===)。")
        var stripMarkers: Bool = false

        @Option(name: .long, help: "原始 PDF 路徑（用於提取紙張大小和字型 metadata）。")
        var sourcePdf: String?

        mutating func run() throws {
            let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            let root = Support.absoluteURL(from: project, relativeTo: cwd)
            let texURL = root.appendingPathComponent("accumulated.tex")
            guard FileManager.default.fileExists(atPath: texURL.path) else {
                throw ValidationError("找不到 accumulated.tex: \(texURL.path)")
            }

            // 解析原始 PDF 路徑
            let pdfURL: URL?
            if let pdfPath = sourcePdf {
                let url = Support.absoluteURL(from: pdfPath, relativeTo: cwd)
                guard FileManager.default.fileExists(atPath: url.path) else {
                    throw ValidationError("找不到原始 PDF: \(url.path)")
                }
                pdfURL = url
            } else {
                pdfURL = nil
            }

            // Backup（不覆蓋既有的 .bak）
            let backupURL = texURL.appendingPathExtension("bak")
            if !FileManager.default.fileExists(atPath: backupURL.path) {
                let source = try String(contentsOf: texURL, encoding: .utf8)
                try source.write(to: backupURL, atomically: true, encoding: .utf8)
                print("backup: \(backupURL.path)")
            }

            let normalizer = LaTeXNormalizer(
                symbolRules: ["\\bm{": "\\boldsymbol{"],
                stripPageMarkers: stripMarkers
            )

            let report = try normalizer.normalizeProject(
                mainTexURL: texURL,
                sourcePDFURL: pdfURL
            )

            print("normalize 完成: \(texURL.path)")
            if report.documentClassFixed {
                print("  document class: article → book")
            }
            if report.paperSizeFixed {
                print("  paper size: fixed from PDF metadata")
            }
            if report.fontPackageFixed {
                print("  font package: fixed from PDF metadata")
            }
            if report.fontSizeFixed {
                print("  font size: fixed from PDF metadata")
            }
            if report.marginsFixed {
                print("  margins: fixed from PDF metadata")
            }
            if !report.mathOperatorsAdded.isEmpty {
                print("  math operators: \(report.mathOperatorsAdded.joined(separator: ", "))")
            }
            if report.currencyDollarsEscaped > 0 {
                print("  currency $: \(report.currencyDollarsEscaped) escaped")
            }
            if let preambleURL = report.preambleURL, report.preambleFileChanged {
                print("  preamble: \(preambleURL.lastPathComponent) (modified)")
            }
            Self.pageAndFigureSummary(report).forEach { print($0) }
            if !report.mainFileChanged && !report.preambleFileChanged {
                print("  (no changes needed)")
            }
        }

        /// 頁碼還原（#9）與圖片寬度還原（#10）的摘要。例行結果只計數；原始碼因故保持原樣的
        /// 項目逐筆列出，因為那些是使用者要自己回頭處理的。沒有任何紀錄時回傳空陣列。
        static func pageAndFigureSummary(_ report: NormalizeProjectReport) -> [String] {
            var lines: [String] = []
            var inserted = 0, moved = 0
            var pageProblems: [String] = []
            for note in report.pageCounterNotes {
                switch note.kind {
                case .counterInserted: inserted += 1
                case .legacyCounterMoved: moved += 1
                case .conflictingCounterBeforeChapter(let existing, let expected):
                    pageProblems.append("  ⚠ page counter line \(note.line): 既有 \\setcounter{page}{\(existing)} 與 marker 推得的 \(expected) 不同，該章未插入")
                case .chapterTitleNotFound:
                    pageProblems.append("  ⚠ page counter line \(note.line): 找不到 \\chapter 章名的結尾大括號，頁碼未還原")
                }
            }
            if !report.pageCounterNotes.isEmpty {
                lines.append("  page counters: \(inserted) inserted, \(moved) legacy moved")
                lines += pageProblems
            }

            var applied = 0, sized = 0, noContext = 0
            var figureProblems: [String] = []
            for figure in report.figureWidthResolutions {
                let reason: String
                switch figure.outcome {
                case .widthApplied: applied += 1; continue
                case .explicitSizePreserved: sized += 1; continue
                case .noPageContext: noContext += 1; continue
                case .noMatchingFigure: reason = "responses 沒有這張圖"
                case .ambiguousFigure: reason = "同一頁有多筆互相矛盾的 bbox"
                case .invalidBoundingBox(let box): reason = "bbox 不合法 \(box)"
                case .widthNotRepresentable(let width): reason = "寬度太小無法表示（\(width)）"
                case .missingPageRecord: reason = "manifest.json 沒有該頁或頁寬無效"
                case .missingImageFile: reason = "圖檔不存在"
                case .metadataUnavailable(let why): reason = "metadata 無法讀取：\(why)"
                }
                let page = figure.page.map { "page \($0)" } ?? "no page"
                figureProblems.append("  ⚠ figure \(figure.path) (\(page), line \(figure.line)): \(reason)，未改寫")
            }
            if !report.figureWidthResolutions.isEmpty {
                lines.append("  figure widths: \(applied) applied, \(sized) already sized, \(noContext) without page context")
                lines += figureProblems
            }
            lines += report.unreadableResponseFiles.map { "  ⚠ unreadable: \($0)" }
            return lines
        }
    }

    // MARK: macdoc pdf fix-envs
    struct FixEnvs: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "fix-envs",
            abstract: "偵測（並可選修復）LaTeX 環境配對問題。"
        )

        @Option(name: .long, help: "專案資料夾。")
        var project: String = "."

        @Flag(name: .long, help: "自動修復。")
        var fix: Bool = false

        mutating func run() throws {
            let root = Support.absoluteURL(from: project, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
            let texURL = root.appendingPathComponent("accumulated.tex")
            guard FileManager.default.fileExists(atPath: texURL.path) else {
                throw ValidationError("找不到 accumulated.tex: \(texURL.path)")
            }

            let source = try String(contentsOf: texURL, encoding: .utf8)
            let checker = LaTeXEnvChecker()
            let issues = checker.check(source)

            if issues.isEmpty {
                print("沒有環境配對問題。")
                return
            }

            print("發現 \(issues.count) 個問題:")
            for issue in issues {
                print("  [\(issue.kind.rawValue)] \\(\(issue.environment)) at line \(issue.line)")
            }

            if fix {
                let fixed = checker.fix(source)
                try fixed.write(to: texURL, atomically: true, encoding: .utf8)
                print("已修復並寫回: \(texURL.path)")
            }
        }
    }

    // MARK: macdoc pdf compile-check
    struct CompileCheck: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "compile-check",
            abstract: "執行 pdflatex 編譯並產生結構化錯誤報告。"
        )

        @Option(name: .long, help: "專案資料夾。")
        var project: String = "."

        mutating func run() throws {
            let root = Support.absoluteURL(from: project, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
            let texURL = root.appendingPathComponent("accumulated.tex")
            guard FileManager.default.fileExists(atPath: texURL.path) else {
                throw ValidationError("找不到 accumulated.tex: \(texURL.path)")
            }

            let checker = TexCompileChecker()
            let report = try checker.compile(texFileURL: texURL)

            let reportURL = root.appendingPathComponent("compile-report.json")
            try checker.writeReport(report, to: reportURL)

            print("errors: \(report.errors.count)")
            print("warnings: \(report.warningCount)")
            print("success: \(report.success)")
            print("report: \(reportURL.path)")

            if !report.errors.isEmpty {
                for error in report.errors {
                    let lineInfo = error.line.map { "line \($0)" } ?? "?"
                    print("  [\(error.category.rawValue)] \(error.message) at \(lineInfo)")
                }
            }
        }
    }

    // MARK: macdoc pdf consolidate
    struct Consolidate: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "consolidate",
            abstract: "機械清理 + AI agent 修復剩餘編譯錯誤。"
        )

        @Option(name: .long, help: "專案資料夾。")
        var project: String = "."

        @Option(name: .long, help: "AI agent 後端 (codex|claude|gemini)。")
        var agent: String?

        @Flag(name: .long, help: "只跑機械步驟，不呼叫 agent。")
        var dryRun: Bool = false

        @Option(name: .long, help: "PDF 來源格式覆蓋 (latex|word|typst|scanned|designer)。影響正規化策略。")
        var source: String?

        mutating func run() throws {
            let root = Support.absoluteURL(from: project, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
            let texURL = root.appendingPathComponent("accumulated.tex")
            guard FileManager.default.fileExists(atPath: texURL.path) else {
                throw ValidationError("找不到 accumulated.tex: \(texURL.path)")
            }

            let resolvedSource = source.flatMap { PDFSourceFormat(rawValue: $0) }

            // 如果沒手動指定，嘗試從 structure.json 讀取
            let effectiveSource: PDFSourceFormat
            if let s = resolvedSource {
                effectiveSource = s
            } else {
                let structureStore = StructureStore(projectRoot: root)
                effectiveSource = (try? structureStore.loadStructure())?.sourceDetection?.format ?? .unknown
            }

            if effectiveSource != .unknown {
                print("來源格式: \(effectiveSource.rawValue)")
            }

            let resolvedAgent: TranscriptionBackend
            if let a = agent.flatMap({ TranscriptionBackend(rawValue: $0) }) {
                resolvedAgent = a
            } else {
                let config = try AIConfig.load()
                resolvedAgent = TranscriptionBackend(rawValue: config.agent) ?? .claude
            }

            let consolidator = Consolidator()
            let result = try consolidator.consolidate(
                texFileURL: texURL,
                agent: resolvedAgent,
                dryRun: dryRun,
                sourceFormat: effectiveSource
            )

            print("normalize: \(result.mechanicalResult.normalizeApplied)")
            print("env_fix: \(result.mechanicalResult.envCheckApplied)")
            print("env_issues: \(result.mechanicalResult.envIssuesFound.count)")
            print("compile_errors: \(result.finalErrors.count)")
            print("agent_invoked: \(result.agentInvoked)")
            print("agent_iterations: \(result.agentIterations)")
            print("success: \(result.success)")

            if !result.finalErrors.isEmpty {
                print("\n剩餘錯誤:")
                for error in result.finalErrors {
                    let lineInfo = error.line.map { "line \($0)" } ?? "?"
                    print("  [\(error.category.rawValue)] \(error.message) at \(lineInfo)")
                }
            }
        }
    }
}
