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
            兩份 PDF 用 CoreGraphics 以同一解析度算繪、對齊左上角，逐像素逐通道相減（D = reproduced − original）。
            給 --overlay（單獨算繪的疊印層）時跑五項疊印檢查；給 --preserve 時檢查這些區域 D 全為 0，
            且區域整個落在比對範圍內；兩者都沒給時，檢查兩頁尺寸相同且沒有任何像素不同。所有檢查都通過才以 0 結束。
            """
        )

        @Option(name: .long, help: "原始 PDF。")
        var original: String

        @Option(name: .long, help: "由原始 PDF 產生、要檢查的 PDF。")
        var reproduced: String

        @Option(name: .long, help: "單獨算繪的疊印層 PDF；給了才跑五項疊印檢查。")
        var overlay: String?

        @Option(name: .long, help: "必須完全不變的區域 x0,y0,x1,y1（bp，原點左上），可重複。")
        var preserve: [String] = []

        @Option(name: .long, help: "算繪解析度（dpi）。")
        var dpi: Double = 144

        @Option(name: .long, help: "寫出 diff_signed.png、diff_abs.png、diff.bin、report.json 的資料夾。")
        var diffDir: String?

        mutating func run() throws {
            let originalURL = try FormCommandSupport.inputURL(original)
            let reproducedURL = try FormCommandSupport.inputURL(reproduced)
            let overlayURL = try overlay.map(FormCommandSupport.inputURL)
            let regions = try preserve.map(FormCommandSupport.parseRect)
            if let diffDir {
                // The artifacts must not replace a PDF this command reads.
                let inputs = [(originalURL, "原始 PDF"), (reproducedURL, "要檢查的 PDF")] + (overlayURL.map { [($0, "疊印層 PDF")] } ?? [])
                try FormCommandSupport.refuseArtifactCollisions(in: FormCommandSupport.absoluteURL(diffDir), inputs: inputs)
            }
            let passed = try FormCommandSupport.reportingErrors {
                try compare(originalURL, reproducedURL, overlayURL, regions)
            }
            if !passed { throw ExitCode.failure }
        }

        /// Prints the comparison and returns whether every applicable check passed.
        private func compare(_ originalURL: URL, _ reproducedURL: URL, _ overlayURL: URL?, _ regions: [CGRect]) throws -> Bool {
            // One bitmap height for every render compared: anti-aliasing is
            // not invariant under the height, and the pages may differ in size.
            let pages = try ([originalURL, reproducedURL] + (overlayURL.map { [$0] } ?? [])).map {
                try PageRaster.page(url: $0, index: 0)
            }
            let canvas = PageRaster.canvasHeight(heights: pages.map { $0.getBoxRect(.cropBox).height }, dpi: dpi)
            let originalRaster = try PageRaster.render(page: pages[0], dpi: dpi, canvasHeight: canvas)
            let reproducedRaster = try PageRaster.render(page: pages[1], dpi: dpi, canvasHeight: canvas)
            print("Original:   \(originalURL.path) (\(FormCommandSupport.size(originalRaster.pageSize)))")
            print("Reproduced: \(reproducedURL.path) (\(FormCommandSupport.size(reproducedRaster.pageSize)))")

            var passed = true
            let diff: SignedDiff
            var checks: [CheckResult]?
            if let overlayURL {
                let verification = try OverlayVerifier.verify(
                    original: originalRaster, output: reproducedRaster,
                    overlay: PageRaster.render(url: overlayURL, pageIndex: 0, dpi: dpi, canvasHeight: canvas))
                diff = verification.diff
                checks = verification.report.checks
            } else {
                diff = try SignedDiff(original: originalRaster, output: reproducedRaster)
            }
            FormCommandSupport.printDiffSummary(diff)
            if let checks {
                passed = FormCommandSupport.printChecks(checks) && passed
            }
            let preserved = regions.isEmpty ? nil : try PreservedRegions.check(regions, diff: diff)
            for result in preserved ?? [] {
                var line = String(format: "%@ preserved region %d (%.1f, %.1f)–(%.1f, %.1f) bp: %d px",
                                  result.passed ? "✓" : "✗", result.index, result.left, result.top,
                                  result.right, result.bottom, result.changedPixels)
                if result.uncheckedPixels > 0 {
                    line += ", \(result.uncheckedPixels) px outside the compared area"
                }
                print(line)
                passed = passed && result.passed
            }
            var identical: Bool?
            if overlayURL == nil && regions.isEmpty {
                let same = diff.changedPixelCount == 0 && diff.sizesMatch
                let sizes = FormCommandSupport.distinctSizes(originalRaster.pageSize, reproducedRaster.pageSize)
                let reason = diff.sizesMatch
                    ? "\(diff.changedPixelCount) px differ"
                    : "page sizes differ (\(sizes.0) vs \(sizes.1)); "
                        + "\(diff.changedPixelCount) px differ in the common region"
                print("\(same ? "✓" : "✗") identical: \(reason)")
                identical = same
                passed = same
            }
            if let diffDir {
                let directory = FormCommandSupport.absoluteURL(diffDir)
                try DiffArtifacts.write(diff: diff, checks: checks, preserved: preserved, identical: identical, to: directory)
                FormCommandSupport.reportWritten(directory)
            }
            return passed
        }
    }

    // MARK: macdoc pdf form-skeleton
    struct FormSkeletonCommand: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "form-skeleton",
            abstract: "從空白 PDF 表單產生 .tex 疊印骨架（bp、原點左上，每個印刷標籤一個欄位巨集與一行註解）。",
            discussion: """
            不給 --output 時骨架寫到 stdout，\\BlankForm 用空白表單的絕對路徑；給 --output 時寫成檔案
            （已存在時不覆寫）；空白表單在該檔所在資料夾底下時 \\BlankForm 用相對路徑，否則用絕對路徑。
            """
        )

        @Option(name: .long, help: "空白 PDF 表單。")
        var pdf: String

        @Option(name: .long, help: "要寫出的 .tex（預設：寫到 stdout）；已存在時不覆寫。")
        var output: String?

        mutating func run() throws {
            let form = try FormCommandSupport.inputURL(pdf)
            let tex = output.map(FormCommandSupport.absoluteURL)
            if let tex, FileManager.default.fileExists(atPath: tex.path) {
                throw ValidationError("輸出檔已存在，不覆寫：\(tex.path)")
            }
            let reference = tex.map { FormCommandSupport.relativePath(of: form, from: $0.deletingLastPathComponent()) } ?? form.path
            let skeleton = try FormCommandSupport.reportingErrors {
                // PDFKit logs debug lines on stderr while it reads the page's text.
                try FormCommandSupport.withStderrSilenced {
                    try FormSkeleton.generate(blankForm: form, reference: reference)
                }
            }
            guard let tex else {
                print(skeleton, terminator: "")
                return
            }
            try FormCommandSupport.reportingErrors {
                try FileManager.default.createDirectory(at: tex.deletingLastPathComponent(), withIntermediateDirectories: true)
                do {
                    // Refuses to replace a file created since the check above.
                    try Data(skeleton.utf8).write(to: tex, options: .withoutOverwriting)
                } catch CocoaError.fileWriteFileExists {
                    throw ValidationError("輸出檔已存在，不覆寫：\(tex.path)")
                }
            }
            let labels = skeleton.split(separator: "\n").filter { $0.hasPrefix("% \\at{") }.count
            FormCommandSupport.reportWritten(tex, note: "\(labels) 個標籤；\\BlankForm = \(reference)")
        }
    }

    // MARK: macdoc pdf form-fill
    struct FormFillCommand: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "form-fill",
            abstract: "編譯疊印層、1:1 蓋到空白表單副本上，並與原表逐像素比對（五項檢查）。",
            discussion: """
            空白表單取自 .tex 的 \\BlankForm（相對路徑以 .tex 所在資料夾為準）。原表不經過 TeX：
            疊印層以 xelatex 編兩次後，在 PDF 物件層級 1:1 疊到原表上（原表內容逐字複製，不重畫）。--page a4（預設）把接近 A4 的原表
            對齊左上校正成精確 A4（210×297 mm），不縮放；裁掉的邊條若有墨則拒絕。--page original 保留原表尺寸。
            疊印層的頁面必須與成品同尺寸（form-skeleton 依原表大小寫好），繪圖不能超出頁緣，也不能帶註解。--output 必須是檔案，
            不能是資料夾、符號連結、原表或 .tex；多頁、旋轉或帶註解（連結、表單欄位）的原表會被拒絕。
            五項檢查都是 0 才以 0 結束；即使檢查失敗，成品仍會寫出供檢視。
            """
        )

        @Argument(help: "疊印層 .tex。")
        var tex: String

        @Option(name: .long, help: "要寫出的成品 PDF 檔（預設：.tex 同名的 .pdf）。")
        var output: String?

        @Option(name: .long, help: "頁面尺寸：a4（預設）或 original。")
        var page: PageMode = .a4

        @Option(name: .long, help: "驗證用的算繪解析度（dpi）。")
        var dpi: Double = 144

        @Option(name: .long, help: "TeX 引擎名稱或路徑。")
        var engine: String = "xelatex"

        @Option(name: .long, help: "寫出差值產物的資料夾。")
        var diffDir: String?

        mutating func run() throws {
            let texURL = try FormCommandSupport.inputURL(tex)
            let outputURL = output.map(FormCommandSupport.absoluteURL) ?? texURL.deletingPathExtension().appendingPathExtension("pdf")
            let diffDirectory = diffDir.map(FormCommandSupport.absoluteURL)
            let result = try FormCommandSupport.reportingErrors {
                try FormFiller.fill(tex: texURL, output: outputURL, pageMode: page, dpi: dpi, engine: engine,
                                    diffDirectory: diffDirectory)
            }
            FormCommandSupport.reportWritten(result.output)
            if let diffDirectory { FormCommandSupport.reportWritten(diffDirectory) }
            print("Page: \(FormCommandSupport.size(result.pageSize)) (\(FormCommandSupport.classification(result.pageSize)))")
            print(String(format: "Changed pixels: %d at %.0f dpi", result.report.changedPixelCount, result.report.dpi))
            if !FormCommandSupport.printChecks(result.report.checks) { throw ExitCode.failure }
        }
    }
}
