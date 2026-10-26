import CoreGraphics
import CoreText
import Foundation
import Testing

/// CLI tests for `macdoc pdf visual-diff`, `form-skeleton`, `form-fill` and
/// the page-geometry section of `macdoc pdf compare` (PsychQuant/macdoc#240).
/// Every PDF is synthesized here with CoreGraphics; no real form is used.
final class PDFFormCommandTests {

    /// Directories this test created; removed when the test finishes.
    private var created: [URL] = []

    deinit {
        for dir in created { try? FileManager.default.removeItem(at: dir) }
    }

    func directory() throws -> URL {
        let dir = try Self.makeDirectory()
        created.append(dir)
        return dir
    }

    enum Item {
        case line(CGPoint, CGPoint)
        case text(String, CGPoint, CGFloat, String)
        case fill(CGRect)
    }

    static let a4 = CGSize(width: 210 / 25.4 * 72, height: 297 / 25.4 * 72)
    static let nearA4 = CGSize(width: 596, height: 843)
    static let form: [Item] = [
        .line(CGPoint(x: 100, y: 100), CGPoint(x: 300, y: 100)),
        .text("甲", CGPoint(x: 150, y: 300), 12, "PingFang TC"),
    ]

    static let xelatexAvailable: Bool = {
        let path = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        return (path + ["/Library/TeX/texbin", "/opt/homebrew/bin", "/usr/local/bin"])
            .contains { FileManager.default.isExecutableFile(atPath: "\($0)/xelatex") }
    }()

    static func makeDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("macdoc-pdf-form-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @discardableResult
    static func pdf(_ pages: [(CGSize, [Item])], at url: URL) throws -> URL {
        let consumer = try #require(CGDataConsumer(url: url as CFURL))
        let context = try #require(CGContext(consumer: consumer, mediaBox: nil, nil))
        for (size, items) in pages {
            var box = CGRect(origin: .zero, size: size)
            context.beginPage(mediaBox: &box)
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.setStrokeColor(CGColor(gray: 0, alpha: 1))
            for item in items {
                switch item {
                case let .line(a, b):
                    context.setLineWidth(1)
                    context.move(to: CGPoint(x: a.x, y: size.height - a.y))
                    context.addLine(to: CGPoint(x: b.x, y: size.height - b.y))
                    context.strokePath()
                case let .fill(rect):
                    context.fill(CGRect(x: rect.minX, y: size.height - rect.maxY, width: rect.width, height: rect.height))
                case let .text(string, at, pointSize, fontName):
                    let font = CTFontCreateWithName(fontName as CFString, pointSize, nil)
                    let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: [
                        NSAttributedString.Key(kCTFontAttributeName as String): font,
                        NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
                    ]))
                    context.textPosition = CGPoint(x: at.x, y: size.height - at.y)
                    CTLineDraw(line, context)
                }
            }
            context.endPage()
        }
        context.closePDF()
        return url
    }

    static func overlayTeX(_ placement: String) -> String {
        """
        \\documentclass{article}
        \\usepackage[a4paper,margin=0pt]{geometry}
        \\usepackage{tikz}
        \\usetikzlibrary{calc}
        \\pagestyle{empty}
        \\newcommand{\\BlankForm}{blank.pdf}
        \\newcommand{\\at}[3]{\\node[anchor=base west,inner sep=0pt,font=\\fontsize{#3}{#3}\\selectfont] at ($(current page.north west)+(#1 bp,-#2 bp)$)}
        \\begin{document}
        \\null
        \\begin{tikzpicture}[remember picture,overlay]
        \(placement)
        \\end{tikzpicture}
        \\end{document}
        """
    }

    // MARK: visual-diff

    @Test("visual-diff of identical PDFs exits 0")
    func visualDiffIdentical() throws {
        let dir = try directory()
        let a = try Self.pdf([(Self.a4, Self.form)], at: dir.appendingPathComponent("a.pdf"))
        let b = try Self.pdf([(Self.a4, Self.form)], at: dir.appendingPathComponent("b.pdf"))
        let result = try CLITestHelper.run(["pdf", "visual-diff", "--original", a.path, "--reproduced", b.path])
        #expect(result.exitCode == 0, "stderr: \(result.stderr)")
        #expect(result.stdout.contains("Changed pixels: 0"))
        #expect(result.stdout.contains("✓ identical"))
    }

    @Test("visual-diff reports overlay ink on original ink with its band and exits non-zero")
    func visualDiffOverlap() throws {
        let dir = try directory()
        let typed = Item.text("42", CGPoint(x: 148, y: 300), 12, "Helvetica")
        let original = try Self.pdf([(Self.nearA4, Self.form)], at: dir.appendingPathComponent("original.pdf"))
        let output = try Self.pdf([(Self.a4, Self.form + [typed])], at: dir.appendingPathComponent("output.pdf"))
        let overlay = try Self.pdf([(Self.a4, [typed])], at: dir.appendingPathComponent("overlay.pdf"))
        let result = try CLITestHelper.run(["pdf", "visual-diff", "--original", original.path, "--reproduced", output.path,
                                            "--overlay", overlay.path])
        #expect(result.exitCode != 0)
        #expect(result.stdout.contains("✗ overlayInkOnOriginalInk"))
        #expect(result.stdout.contains("✓ differenceOutsideOverlay: 0 px"))
        #expect(result.stdout.contains("    y "))
    }

    @Test("visual-diff writes the four diff artifacts")
    func visualDiffArtifacts() throws {
        let dir = try directory()
        let a = try Self.pdf([(Self.a4, [])], at: dir.appendingPathComponent("a.pdf"))
        let b = try Self.pdf([(Self.a4, [.fill(CGRect(x: 10, y: 10, width: 5, height: 5))])], at: dir.appendingPathComponent("b.pdf"))
        let diffDir = dir.appendingPathComponent("diff")
        let result = try CLITestHelper.run(["pdf", "visual-diff", "--original", a.path, "--reproduced", b.path, "--diff-dir", diffDir.path])
        #expect(result.exitCode != 0)
        for name in ["diff_signed.png", "diff_abs.png", "diff.bin", "report.json"] {
            #expect(FileManager.default.fileExists(atPath: diffDir.appendingPathComponent(name).path), "\(name)")
        }
    }

    @Test("visual-diff fails a preserved region that changed")
    func visualDiffPreserved() throws {
        let dir = try directory()
        let a = try Self.pdf([(Self.a4, [])], at: dir.appendingPathComponent("a.pdf"))
        let b = try Self.pdf([(Self.a4, [.fill(CGRect(x: 100, y: 100, width: 2, height: 2))])], at: dir.appendingPathComponent("b.pdf"))
        let failing = try CLITestHelper.run(["pdf", "visual-diff", "--original", a.path, "--reproduced", b.path,
                                             "--preserve", "50,50,150,150"])
        #expect(failing.exitCode != 0)
        #expect(failing.stdout.contains("✗ preserved region 0"))
        let passing = try CLITestHelper.run(["pdf", "visual-diff", "--original", a.path, "--reproduced", b.path,
                                             "--preserve", "300,300,400,400"])
        #expect(passing.exitCode == 0, "stdout: \(passing.stdout)")
    }

    @Test("visual-diff rejects a malformed --preserve")
    func visualDiffBadRect() throws {
        let dir = try directory()
        let a = try Self.pdf([(Self.a4, [])], at: dir.appendingPathComponent("a.pdf"))
        let result = try CLITestHelper.run(["pdf", "visual-diff", "--original", a.path, "--reproduced", a.path, "--preserve", "1,2,3"])
        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("--preserve"))
    }

    @Test("visual-diff fails the identity check when the page sizes differ")
    func visualDiffSizeMismatch() throws {
        let dir = try directory()
        let a = try Self.pdf([(Self.nearA4, [])], at: dir.appendingPathComponent("a.pdf"))
        let b = try Self.pdf([(Self.a4, [])], at: dir.appendingPathComponent("b.pdf"))
        let result = try CLITestHelper.run(["pdf", "visual-diff", "--original", a.path, "--reproduced", b.path])
        #expect(result.exitCode != 0)
        #expect(result.stdout.contains("✗ identical"))
        #expect(result.stdout.contains("page sizes differ"))
    }

    @Test("visual-diff rejects a --preserve with a non-finite number")
    func visualDiffInfiniteRect() throws {
        let dir = try directory()
        let a = try Self.pdf([(Self.a4, [])], at: dir.appendingPathComponent("a.pdf"))
        let result = try CLITestHelper.run(["pdf", "visual-diff", "--original", a.path, "--reproduced", a.path, "--preserve", "0,0,inf,100"])
        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("--preserve"))
    }

    @Test("visual-diff fails a preserved region that reaches beyond the page")
    func visualDiffRegionBeyondPage() throws {
        let dir = try directory()
        let a = try Self.pdf([(Self.a4, [])], at: dir.appendingPathComponent("a.pdf"))
        let result = try CLITestHelper.run(["pdf", "visual-diff", "--original", a.path, "--reproduced", a.path, "--preserve", "500,800,700,900"])
        #expect(result.exitCode != 0)
        #expect(result.stdout.contains("✗ preserved region 0"))
        #expect(result.stdout.contains("outside the compared area"))
    }

    @Test("visual-diff says how many bands it did not print")
    func visualDiffBandsTruncated() throws {
        let dir = try directory()
        let marks = (0..<12).map { Item.fill(CGRect(x: 100, y: 100 + Double($0) * 20, width: 2, height: 2)) }
        let original = try Self.pdf([(Self.a4, [])], at: dir.appendingPathComponent("original.pdf"))
        let output = try Self.pdf([(Self.a4, marks)], at: dir.appendingPathComponent("output.pdf"))
        let overlay = try Self.pdf([(Self.a4, [])], at: dir.appendingPathComponent("overlay.pdf"))
        let result = try CLITestHelper.run(["pdf", "visual-diff", "--original", original.path, "--reproduced", output.path,
                                            "--overlay", overlay.path])
        #expect(result.exitCode != 0)
        #expect(result.stdout.contains("    … 2 more bands"))
    }

    // MARK: form-skeleton

    @Test("form-skeleton reports only the written file on stderr when it succeeds")
    func formSkeletonQuiet() throws {
        let dir = try directory()
        try Self.pdf([(Self.nearA4, Self.form)], at: dir.appendingPathComponent("blank.pdf"))
        let result = try CLITestHelper.run(["pdf", "form-skeleton", "--pdf", dir.appendingPathComponent("blank.pdf").path,
                                            "--output", dir.appendingPathComponent("filled.tex").path])
        #expect(result.exitCode == 0)
        let lines = result.stderr.split(separator: "\n")
        #expect(lines.count == 1 && lines[0].hasPrefix("已寫入: "), "stderr: \(result.stderr)")
    }

    @Test("form-skeleton writes a skeleton and refuses to overwrite it")
    func formSkeleton() throws {
        let dir = try directory()
        try Self.pdf([(Self.nearA4, [.text("甲      乙      丙", CGPoint(x: 150, y: 300), 12, "PingFang TC")])],
                     at: dir.appendingPathComponent("blank.pdf"))
        let tex = dir.appendingPathComponent("filled.tex")
        let first = try CLITestHelper.run(["pdf", "form-skeleton", "--pdf", dir.appendingPathComponent("blank.pdf").path,
                                           "--output", tex.path])
        #expect(first.exitCode == 0, "stderr: \(first.stderr)")
        let content = try String(contentsOf: tex, encoding: .utf8)
        #expect(content.contains("\\newcommand{\\BlankForm}{blank.pdf}"))
        #expect(content.split(separator: "\n").filter { $0.hasPrefix("% \\at{") }.count == 3)

        let second = try CLITestHelper.run(["pdf", "form-skeleton", "--pdf", dir.appendingPathComponent("blank.pdf").path,
                                            "--output", tex.path])
        #expect(second.exitCode != 0)
        #expect(try String(contentsOf: tex, encoding: .utf8) == content)
    }

    // MARK: form-fill

    @Test("form-fill on a clean overlay reports the output and five zero checks", .enabled(if: xelatexAvailable, "xelatex not found"))
    func formFillClean() throws {
        let dir = try directory()
        try Self.pdf([(Self.nearA4, Self.form)], at: dir.appendingPathComponent("blank.pdf"))
        let tex = dir.appendingPathComponent("filled.tex")
        try Self.overlayTeX("\\at{123}{310}{12}{42};").write(to: tex, atomically: true, encoding: .utf8)
        let result = try CLITestHelper.run(["pdf", "form-fill", tex.path], timeout: 120)
        #expect(result.exitCode == 0, "stdout: \(result.stdout)\nstderr: \(result.stderr)")
        #expect(result.stderr.contains("已寫入: \(dir.appendingPathComponent("filled.pdf").path)"))
        #expect(result.stdout.contains("exactA4"))
        for check in ["differenceOutsideOverlay", "originalMadeLighter", "overlayInkOnOriginalInk", "inkInCroppedStrip",
                      "overlayMissingFromOutput"] {
            #expect(result.stdout.contains("✓ \(check): 0 px"), "\(check)")
        }
    }

    @Test("form-fill exits non-zero when typed text touches the form", .enabled(if: xelatexAvailable, "xelatex not found"))
    func formFillCollision() throws {
        let dir = try directory()
        try Self.pdf([(Self.nearA4, Self.form)], at: dir.appendingPathComponent("blank.pdf"))
        let tex = dir.appendingPathComponent("filled.tex")
        try Self.overlayTeX("\\at{148}{300}{12}{42};").write(to: tex, atomically: true, encoding: .utf8)
        let result = try CLITestHelper.run(["pdf", "form-fill", tex.path], timeout: 120)
        #expect(result.exitCode != 0)
        #expect(result.stdout.contains("✗ overlayInkOnOriginalInk"))
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("filled.pdf").path))
    }

    @Test("form-fill refuses an overlay with a link and writes nothing", .enabled(if: xelatexAvailable, "xelatex not found"))
    func formFillAnnotatedOverlay() throws {
        let dir = try directory()
        try Self.pdf([(Self.nearA4, Self.form)], at: dir.appendingPathComponent("blank.pdf"))
        let tex = dir.appendingPathComponent("filled.tex")
        let source = Self.overlayTeX("\\at{148}{100}{12}{\\href{https://example.org}{X}};")
            .replacingOccurrences(of: "\\pagestyle{empty}", with: "\\usepackage{hyperref}\n\\pagestyle{empty}")
        try source.write(to: tex, atomically: true, encoding: .utf8)
        let result = try CLITestHelper.run(["pdf", "form-fill", tex.path], timeout: 120)
        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("錯誤：疊印層帶有 1 個註解"), "stderr: \(result.stderr)")
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("filled.pdf").path))
    }

    @Test("form-fill refuses an overlay it cannot place and writes nothing", .enabled(if: xelatexAvailable, "xelatex not found"))
    func formFillUnverifiableOverlay() throws {
        let dir = try directory()
        try Self.pdf([(Self.nearA4, Self.form)], at: dir.appendingPathComponent("blank.pdf"))
        let tex = dir.appendingPathComponent("filled.tex")
        try Self.overlayTeX("\\at{148}{100}{12}{\\special{pdf:content /Nope Do}X};").write(to: tex, atomically: true, encoding: .utf8)
        let result = try CLITestHelper.run(["pdf", "form-fill", tex.path], timeout: 120)
        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("錯誤：疊印層有 1 處無法定位"), "stderr: \(result.stderr)")
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("filled.pdf").path))
    }

    @Test("form-fill refuses a default output that is the blank form itself and leaves it untouched")
    func formFillDefaultOutputIsBlankForm() throws {
        let dir = try directory()
        let blank = try Self.pdf([(Self.nearA4, Self.form)], at: dir.appendingPathComponent("form.pdf"))
        let tex = dir.appendingPathComponent("form.tex")
        try Self.overlayTeX("\\at{123}{310}{12}{42};").replacingOccurrences(of: "{blank.pdf}", with: "{form.pdf}")
            .write(to: tex, atomically: true, encoding: .utf8)
        let before = try Data(contentsOf: blank)
        let result = try CLITestHelper.run(["pdf", "form-fill", tex.path], timeout: 120)
        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("不能把成品寫在空白表單上"))
        #expect(try Data(contentsOf: blank) == before)
    }

    @Test("form-fill refuses an --output that is the .tex itself")
    func formFillOutputIsTeX() throws {
        let dir = try directory()
        try Self.pdf([(Self.nearA4, Self.form)], at: dir.appendingPathComponent("blank.pdf"))
        let tex = dir.appendingPathComponent("filled.tex")
        try Self.overlayTeX("").write(to: tex, atomically: true, encoding: .utf8)
        let before = try Data(contentsOf: tex)
        let result = try CLITestHelper.run(["pdf", "form-fill", tex.path, "--output", tex.path], timeout: 120)
        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("不能把成品寫在.tex 原始檔上"))
        #expect(try Data(contentsOf: tex) == before)
    }

    @Test("form-fill refuses a directory as --output and leaves it as it was")
    func formFillOutputIsDirectory() throws {
        let dir = try directory()
        try Self.pdf([(Self.nearA4, Self.form)], at: dir.appendingPathComponent("blank.pdf"))
        let tex = dir.appendingPathComponent("filled.tex")
        try Self.overlayTeX("").write(to: tex, atomically: true, encoding: .utf8)
        let before = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
        let result = try CLITestHelper.run(["pdf", "form-fill", tex.path, "--output", dir.path], timeout: 120)
        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("不是一般檔案"))
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted() == before)
    }

    @Test("form-fill reports a bad resolution in Chinese and writes nothing")
    func formFillBadResolution() throws {
        let dir = try directory()
        try Self.pdf([(Self.nearA4, Self.form)], at: dir.appendingPathComponent("blank.pdf"))
        let tex = dir.appendingPathComponent("filled.tex")
        try Self.overlayTeX("").write(to: tex, atomically: true, encoding: .utf8)
        let result = try CLITestHelper.run(["pdf", "form-fill", tex.path, "--dpi", "0"], timeout: 120)
        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("錯誤：解析度必須介於 1 到 2400 dpi"))
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("filled.pdf").path))
    }

    @Test("visual-diff fails the fifth check when the typed text is missing from the reproduced page")
    func visualDiffMissingOverlay() throws {
        let dir = try directory()
        let typed = Item.text("42", CGPoint(x: 123, y: 310), 12, "Helvetica")
        let original = try Self.pdf([(Self.nearA4, Self.form)], at: dir.appendingPathComponent("original.pdf"))
        let reproduced = try Self.pdf([(Self.a4, Self.form)], at: dir.appendingPathComponent("reproduced.pdf"))
        let overlay = try Self.pdf([(Self.a4, [typed])], at: dir.appendingPathComponent("overlay.pdf"))
        let result = try CLITestHelper.run(["pdf", "visual-diff", "--original", original.path, "--reproduced", reproduced.path,
                                            "--overlay", overlay.path])
        #expect(result.exitCode != 0)
        #expect(result.stdout.contains("✗ overlayMissingFromOutput"))
    }

    @Test("a missing input is reported the way every macdoc command reports it")
    func missingInput() throws {
        let result = try CLITestHelper.run(["pdf", "visual-diff", "--original", "/nonexistent/a.pdf", "--reproduced", "/nonexistent/b.pdf"])
        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("找不到輸入檔案"))
    }

    @Test("visual-diff refuses a --diff-dir whose artifacts would replace an input")
    func visualDiffArtifactCollision() throws {
        let dir = try directory()
        let original = try Self.pdf([(Self.a4, [])], at: dir.appendingPathComponent("report.json"))
        let reproduced = try Self.pdf([(Self.a4, [])], at: dir.appendingPathComponent("b.pdf"))
        let before = try Data(contentsOf: original)
        let result = try CLITestHelper.run(["pdf", "visual-diff", "--original", original.path, "--reproduced", reproduced.path,
                                            "--diff-dir", dir.path])
        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("會蓋掉原始 PDF"))
        #expect(try Data(contentsOf: original) == before)
    }

    @Test("visual-diff prints two different sizes that differ only past two decimals")
    func visualDiffDistinctSizes() throws {
        let dir = try directory()
        let a = try Self.pdf([(Self.a4, [])], at: dir.appendingPathComponent("a.pdf"))
        let b = try Self.pdf([(CGSize(width: 595.28, height: 841.89), [])], at: dir.appendingPathComponent("b.pdf"))
        let result = try CLITestHelper.run(["pdf", "visual-diff", "--original", a.path, "--reproduced", b.path])
        #expect(result.exitCode != 0)
        let line = try #require(result.stdout.split(separator: "\n").first { $0.contains("page sizes differ") })
        let sizes = try #require(line.range(of: "(")).upperBound
        let parts = line[sizes...].split(separator: ")").first?.components(separatedBy: " vs ") ?? []
        #expect(parts.count == 2 && parts[0] != parts[1], "\(line)")
    }

    @Test("form-skeleton without --output writes the skeleton to stdout with an absolute blank-form path")
    func formSkeletonStdout() throws {
        let dir = try directory()
        let blank = try Self.pdf([(Self.nearA4, Self.form)], at: dir.appendingPathComponent("blank.pdf"))
        let result = try CLITestHelper.run(["pdf", "form-skeleton", "--pdf", blank.path])
        #expect(result.exitCode == 0, "stderr: \(result.stderr)")
        #expect(result.stdout.contains("\\documentclass{article}"))
        #expect(result.stdout.contains("\\newcommand{\\BlankForm}{\(blank.path)}"))
        #expect(result.stderr.isEmpty, "stderr: \(result.stderr)")
    }

    @Test("form-skeleton reports a write failure in Chinese")
    func formSkeletonWriteFailure() throws {
        let dir = try directory()
        let blank = try Self.pdf([(Self.nearA4, Self.form)], at: dir.appendingPathComponent("blank.pdf"))
        let file = dir.appendingPathComponent("plain-file")
        try Data().write(to: file)
        let result = try CLITestHelper.run(["pdf", "form-skeleton", "--pdf", blank.path,
                                            "--output", file.appendingPathComponent("sub/filled.tex").path])
        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("錯誤：無法讀寫檔案"), "stderr: \(result.stderr)")
    }

    @Test("form-fill classifies a landscape A4 page as A4, like compare", .enabled(if: xelatexAvailable, "xelatex not found"))
    func formFillLandscape() throws {
        let dir = try directory()
        let landscape = CGSize(width: Self.a4.height, height: Self.a4.width)
        let blank = try Self.pdf([(landscape, [])], at: dir.appendingPathComponent("blank.pdf"))
        let tex = dir.appendingPathComponent("filled.tex")
        let skeleton = try CLITestHelper.run(["pdf", "form-skeleton", "--pdf", blank.path, "--output", tex.path])
        #expect(skeleton.exitCode == 0, "stderr: \(skeleton.stderr)")
        let result = try CLITestHelper.run(["pdf", "form-fill", tex.path, "--page", "original"], timeout: 120)
        #expect(result.exitCode == 0, "stdout: \(result.stdout)\nstderr: \(result.stderr)")
        #expect(result.stdout.contains("(exactA4, landscape)"))
    }

    @Test("form-fill refuses a --diff-dir whose report.json is the --output")
    func formFillArtifactIsOutput() throws {
        let dir = try directory()
        try Self.pdf([(Self.nearA4, Self.form)], at: dir.appendingPathComponent("blank.pdf"))
        let tex = dir.appendingPathComponent("filled.tex")
        try Self.overlayTeX("").write(to: tex, atomically: true, encoding: .utf8)
        let diff = dir.appendingPathComponent("diff")
        let result = try CLITestHelper.run(["pdf", "form-fill", tex.path, "--output", diff.appendingPathComponent("Report.json").path,
                                            "--diff-dir", diff.path], timeout: 120)
        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("會蓋掉成品"), "stderr: \(result.stderr)")
    }

    @Test("visual-diff rejects a --preserve with an empty field")
    func visualDiffEmptyField() throws {
        let dir = try directory()
        let a = try Self.pdf([(Self.a4, [])], at: dir.appendingPathComponent("a.pdf"))
        let result = try CLITestHelper.run(["pdf", "visual-diff", "--original", a.path, "--reproduced", a.path, "--preserve", "1,,2,3,4"])
        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("--preserve"))
    }

    // MARK: compare geometry

    @Test("visual-diff reports a failed artifact write in Chinese, without system text")
    func visualDiffArtifactWriteFailure() throws {
        let dir = try directory()
        let a = try Self.pdf([(Self.a4, Self.form)], at: dir.appendingPathComponent("a.pdf"))
        let b = try Self.pdf([(Self.a4, Self.form)], at: dir.appendingPathComponent("b.pdf"))
        let blocker = dir.appendingPathComponent("not-a-directory")
        try Data("x".utf8).write(to: blocker)
        let result = try CLITestHelper.run(["pdf", "visual-diff", "--original", a.path, "--reproduced", b.path,
                                            "--diff-dir", blocker.path])
        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("錯誤：無法寫出差值產物：\(blocker.path)（"), "stderr: \(result.stderr)")
        #expect(!result.stderr.contains("couldn"))
        #expect(!result.stderr.contains("原因不明"))
    }

    @Test("visual-diff fails a preserved region just past the page edge")
    func visualDiffPreserveJustPastEdge() throws {
        let dir = try directory()
        let a = try Self.pdf([(Self.a4, Self.form)], at: dir.appendingPathComponent("a.pdf"))
        let b = try Self.pdf([(Self.a4, Self.form)], at: dir.appendingPathComponent("b.pdf"))
        let result = try CLITestHelper.run(["pdf", "visual-diff", "--original", a.path, "--reproduced", b.path,
                                            "--preserve", "595.3,10,595.4,20"])
        #expect(result.exitCode != 0, "stdout: \(result.stdout)")
    }

    @Test("compare prints the page-geometry section with mismatched pages")
    func compareGeometry() throws {
        let dir = try directory()
        let text: [Item] = [.text("Chapter 1 sample text", CGPoint(x: 72, y: 72), 12, "Helvetica")]
        let original = try Self.pdf([(Self.nearA4, text), (Self.nearA4, text), (Self.nearA4, text)],
                                    at: dir.appendingPathComponent("original.pdf"))
        let reproduced = try Self.pdf([(Self.nearA4, text), (Self.nearA4, text), (CGSize(width: 612, height: 792), text)],
                                      at: dir.appendingPathComponent("reproduced.pdf"))
        let result = try CLITestHelper.run(["pdf", "compare", "--original", original.path, "--reproduced", reproduced.path], timeout: 60)
        #expect(result.exitCode == 0, "stderr: \(result.stderr)")
        #expect(result.stdout.contains("PAGE GEOMETRY"))
        #expect(result.stdout.contains("612.00 × 792.00 bp  other"))
        #expect(result.stdout.contains("Pages whose size differs: 3"))
    }

    @Test("visual-diff reports an unusable resolution in Chinese instead of stopping", arguments: ["-inf", "nan", "-1e300"])
    func visualDiffUnusableResolution(dpi: String) throws {
        let dir = try directory()
        let a = try Self.pdf([(Self.a4, Self.form)], at: dir.appendingPathComponent("a.pdf"))
        let result = try CLITestHelper.run(["pdf", "visual-diff", "--original", a.path, "--reproduced", a.path, "--dpi=\(dpi)"])
        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("錯誤：解析度必須介於 1 到 2400 dpi"), "exit \(result.exitCode), stderr: \(result.stderr)")
    }

    /// A blank form drawing an image whose data lives in another file (/F):
    /// its objects cannot be copied, so it cannot be stamped.
    static func externalStreamForm(at url: URL) throws {
        let objects = [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595.2756 841.8898] /Contents 4 0 R "
                + "/Resources << /XObject << /Im0 5 0 R >> >> >>",
            "<< /Length 27 >>\nstream\n0 0 0 rg 100 100 20 20 re f\nendstream",
            "<< /Type /XObject /Subtype /Image /Width 1 /Height 1 /BitsPerComponent 8 /ColorSpace /DeviceGray "
                + "/F (elsewhere.bin) /Length 0 >>\nstream\n\nendstream",
        ]
        var pdf = "%PDF-1.4\n"
        var offsets: [Int] = []
        for (i, body) in objects.enumerated() {
            offsets.append(pdf.utf8.count)
            pdf += "\(i + 1) 0 obj\n\(body)\nendobj\n"
        }
        let xref = pdf.utf8.count
        pdf += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for offset in offsets { pdf += String(format: "%010d 00000 n \n", offset) }
        pdf += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        try Data(pdf.utf8).write(to: url)
    }

    @Test("form-fill words a refused stamp's reason in Chinese", .enabled(if: xelatexAvailable, "xelatex not found"))
    func formFillUnstampableInChinese() throws {
        let dir = try directory()
        try Self.externalStreamForm(at: dir.appendingPathComponent("blank.pdf"))
        let tex = dir.appendingPathComponent("filled.tex")
        try Self.overlayTeX("").write(to: tex, atomically: true, encoding: .utf8)
        let result = try CLITestHelper.run(["pdf", "form-fill", tex.path], timeout: 120)
        #expect(result.exitCode != 0)
        #expect(result.stderr.contains("（有資料存放在外部檔案的串流）"), "stderr: \(result.stderr)")
        #expect(!result.stderr.contains("external"))
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("filled.pdf").path))
    }
}
