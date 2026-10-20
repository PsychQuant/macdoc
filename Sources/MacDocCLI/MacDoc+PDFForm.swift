import ArgumentParser
import CoreGraphics
import Foundation
import PDFFormFill
import PDFVisualDiff

extension PageMode: @retroactive ExpressibleByArgument {}

// MARK: - 表單疊印與逐像素比對（PsychQuant/macdoc#240）
extension MacDoc.PDF {

    // MARK: macdoc pdf visual-diff
    struct VisualDiff: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "visual-diff",
            abstract: "逐像素比較兩份 PDF 的第一頁（有號 RGB 差值，不設門檻）。",
            discussion: """
            兩份 PDF 用 CoreGraphics 以同一解析度算繪、對齊左上角，逐像素逐通道相減（D = output − original）。
            給 --overlay（單獨算繪的疊印層）時跑四項疊印檢查；給 --preserve 時檢查這些區域 D 全為 0；
            兩者都沒給時，檢查「沒有任何像素不同」。所有檢查都通過才以 0 結束。
            """
        )

        @Option(name: .long, help: "原始 PDF。")
        var original: String

        @Option(name: .long, help: "要檢查的 PDF。")
        var output: String

        @Option(name: .long, help: "單獨算繪的疊印層 PDF；給了才跑四項疊印檢查。")
        var overlay: String?

        @Option(name: .long, help: "必須完全不變的區域 x0,y0,x1,y1（bp，原點左上），可重複。")
        var preserve: [String] = []

        @Option(name: .long, help: "算繪解析度（dpi）。")
        var dpi: Double = 144

        @Option(name: .long, help: "寫出 diff_signed.png、diff_abs.png、diff.bin、report.json 的資料夾。")
        var diffDir: String?

        mutating func run() throws {
            let originalURL = try FormCommandSupport.existingFile(original, label: "原始 PDF")
            let outputURL = try FormCommandSupport.existingFile(output, label: "要檢查的 PDF")
            let overlayURL = try overlay.map { try FormCommandSupport.existingFile($0, label: "疊印層 PDF") }
            let regions = try preserve.map(FormCommandSupport.parseRect)

            let originalRaster = try PageRaster.render(url: originalURL, pageIndex: 0, dpi: dpi)
            let outputRaster = try PageRaster.render(url: outputURL, pageIndex: 0, dpi: dpi)
            print("Original: \(originalURL.path) (\(FormCommandSupport.size(originalRaster.pageSize)))")
            print("Output:   \(outputURL.path) (\(FormCommandSupport.size(outputRaster.pageSize)))")

            var passed = true
            let diff: SignedDiff
            var checks: [CheckResult]?
            if let overlayURL {
                let verification = try OverlayVerifier.verify(
                    original: originalRaster, output: outputRaster,
                    overlay: PageRaster.render(url: overlayURL, pageIndex: 0, dpi: dpi))
                diff = verification.diff
                checks = verification.report.checks
            } else {
                diff = try SignedDiff(original: originalRaster, output: outputRaster)
            }
            FormCommandSupport.printDiffSummary(diff)
            if let checks {
                passed = FormCommandSupport.printChecks(checks) && passed
            }
            let preserved = regions.isEmpty ? nil : PreservedRegions.check(regions, diff: diff)
            if let preserved {
                for result in preserved {
                    print(String(format: "%@ preserved region %d (%.1f, %.1f)–(%.1f, %.1f) bp: %d px",
                                 result.passed ? "✓" : "✗", result.index, result.left, result.top,
                                 result.right, result.bottom, result.changedPixels))
                    passed = passed && result.passed
                }
            }
            if overlayURL == nil && regions.isEmpty {
                let identical = diff.changedPixelCount == 0
                print("\(identical ? "✓" : "✗") identical: \(diff.changedPixelCount) px differ")
                passed = identical
            }
            if let diffDir {
                let directory = FormCommandSupport.absoluteURL(diffDir)
                try DiffArtifacts.write(diff: diff, checks: checks, preserved: preserved, to: directory)
                print("Diff artifacts: \(directory.path)")
            }
            if !passed { throw ExitCode.failure }
        }
    }

    // MARK: macdoc pdf form-skeleton
    struct FormSkeletonCommand: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "form-skeleton",
            abstract: "從空白 PDF 表單產生 .tex 疊印骨架（bp、原點左上，每個印刷標籤一行註解）。"
        )

        @Option(name: .long, help: "空白 PDF 表單。")
        var pdf: String

        @Option(name: .long, help: "要寫出的 .tex；已存在時不覆寫。")
        var output: String

        mutating func run() throws {
            let form = try FormCommandSupport.existingFile(pdf, label: "空白 PDF 表單")
            let tex = FormCommandSupport.absoluteURL(output)
            guard !FileManager.default.fileExists(atPath: tex.path) else {
                throw ValidationError("輸出檔已存在，不覆寫：\(tex.path)")
            }
            let reference = FormCommandSupport.relativePath(of: form, from: tex.deletingLastPathComponent())
            let skeleton = try FormSkeleton.generate(blankForm: form, reference: reference)
            try FileManager.default.createDirectory(at: tex.deletingLastPathComponent(), withIntermediateDirectories: true)
            try skeleton.write(to: tex, atomically: true, encoding: .utf8)
            let labels = skeleton.split(separator: "\n").filter { $0.hasPrefix("% \\at{") }.count
            print("Skeleton: \(tex.path) (\(labels) label\(labels == 1 ? "" : "s"); \\BlankForm = \(reference))")
        }
    }

    // MARK: macdoc pdf form-fill
    struct FormFillCommand: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "form-fill",
            abstract: "編譯疊印層、1:1 蓋到空白表單副本上，並與原表逐像素比對（四項檢查）。",
            discussion: """
            空白表單取自 .tex 的 \\BlankForm（相對路徑以 .tex 所在資料夾為準）。原表不經過 TeX：
            疊印層以 xelatex 編兩次後，用 CoreGraphics 1:1 蓋到原表副本上。--page a4（預設）把接近 A4 的原表
            對齊左上校正成精確 A4（210×297 mm），不縮放；裁掉的邊條若有墨則拒絕。四項檢查都是 0 才以 0 結束；
            即使檢查失敗，成品仍會寫出供檢視。
            """
        )

        @Argument(help: "疊印層 .tex。")
        var tex: String

        @Option(name: .long, help: "成品 PDF（預設：.tex 同名的 .pdf）。")
        var out: String?

        @Option(name: .long, help: "頁面尺寸：a4（預設）或 original。")
        var page: PageMode = .a4

        @Option(name: .long, help: "驗證用的算繪解析度（dpi）。")
        var dpi: Double = 144

        @Option(name: .long, help: "TeX 引擎名稱或路徑。")
        var engine: String = "xelatex"

        @Option(name: .long, help: "寫出差值產物的資料夾。")
        var diffDir: String?

        mutating func run() throws {
            let texURL = try FormCommandSupport.existingFile(tex, label: ".tex")
            let output = out.map(FormCommandSupport.absoluteURL) ?? texURL.deletingPathExtension().appendingPathExtension("pdf")
            let result: FillResult
            do {
                result = try FormFiller.fill(tex: texURL, output: output, pageMode: page, dpi: dpi, engine: engine,
                                             diffDirectory: diffDir.map(FormCommandSupport.absoluteURL))
            } catch let error as FormFillError {
                FileHandle.standardError.write(Data("error: \(error)\n".utf8))
                throw ExitCode.failure
            }
            print("Output: \(result.output.path) (\(FormCommandSupport.size(result.pageSize)), \(PageGeometry.classify(result.pageSize).rawValue))")
            print(String(format: "Changed pixels: %d at %.0f dpi", result.report.changedPixelCount, result.report.dpi))
            let passed = FormCommandSupport.printChecks(result.report.checks)
            if let diffDir { print("Diff artifacts: \(FormCommandSupport.absoluteURL(diffDir).path)") }
            if !passed { throw ExitCode.failure }
        }
    }
}

/// Shared formatting and path handling for the form commands.
enum FormCommandSupport {
    static func absoluteURL(_ path: String) -> URL {
        let expanded = (path as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") { return URL(fileURLWithPath: expanded).standardizedFileURL }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(expanded).standardizedFileURL
    }

    static func existingFile(_ path: String, label: String) throws -> URL {
        let url = absoluteURL(path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ValidationError("找不到\(label)：\(url.path)")
        }
        return url
    }

    /// "x0,y0,x1,y1" in bp → rectangle with a top-left origin.
    static func parseRect(_ text: String) throws -> CGRect {
        let values = text.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard values.count == 4, let x0 = values[0], let y0 = values[1], let x1 = values[2], let y1 = values[3],
              x1 > x0, y1 > y0 else {
            throw ValidationError("--preserve 需要 x0,y0,x1,y1（bp，x1 > x0、y1 > y0），收到：\(text)")
        }
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    /// Path of `file` relative to `directory` when `file` lies inside it, otherwise absolute.
    static func relativePath(of file: URL, from directory: URL) -> String {
        let fileParts = file.standardizedFileURL.pathComponents
        let dirParts = directory.standardizedFileURL.pathComponents
        guard fileParts.count > dirParts.count, Array(fileParts.prefix(dirParts.count)) == dirParts else {
            return file.standardizedFileURL.path
        }
        return fileParts.dropFirst(dirParts.count).joined(separator: "/")
    }

    static func size(_ size: CGSize) -> String {
        String(format: "%.2f × %.2f bp", size.width, size.height)
    }

    static func printDiffSummary(_ diff: SignedDiff) {
        let ranges = (0..<3).map { "\(["R", "G", "B"][$0]) \(diff.channelMin[$0])..\(diff.channelMax[$0])" }
        print(String(format: "Changed pixels: %d of %d × %d at %.0f dpi; D %@",
                     diff.changedPixelCount, diff.width, diff.height, diff.dpi, ranges.joined(separator: ", ")))
    }

    /// Prints one line per check plus its bands; returns true when all are 0.
    @discardableResult
    static func printChecks(_ checks: [CheckResult]) -> Bool {
        for check in checks {
            print("\(check.count == 0 ? "✓" : "✗") \(check.check.rawValue): \(check.count) px")
            for band in check.bands.prefix(10) {
                print(String(format: "    y %.1f–%.1f  x %.1f–%.1f bp  %d px",
                             band.top, band.bottom, band.left, band.right, band.pixels))
            }
        }
        return checks.allSatisfy { $0.count == 0 }
    }
}
