import ArgumentParser
import Foundation
import CommonConverterSwift
import WordToMDSwift
import WordToHTML
import HTMLToMD
import HTMLToWord
import MDToHTML
import MDToWord
import SRTToHTML
import PDFToMD
import PDFToDOCX
import TeXToDOCX
import BibAPAToHTML
import BibAPAToJSON
import BibAPAToMD
import MarkerWordConverter
import NoteToHTML
import NoteToPDF

// MARK: - Convert 子命令（textutil-compatible 統一入口）
extension MacDoc {
    struct Convert: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "convert",
            abstract: "Convert documents between formats (textutil-compatible)"
        )

        @Option(name: .long, help: "Target format (md, html, docx, pdf, json, marker)")
        var to: String

        @Option(name: .long, help: "Output file path (or directory for marker)")
        var output: String?

        @Flag(name: .long, help: "Force output to stdout")
        var stdout: Bool = false

        @Option(name: .long, help: "CSS style: minimal|web (bib), dark|light (srt)")
        var css: CSSStyle = .web

        @Flag(name: .long, help: "Treat soft breaks as hard line breaks")
        var hardBreaks: Bool = false

        @Flag(name: .long, help: "Output full HTML document instead of fragment")
        var full: Bool = false

        @Flag(name: .long, help: "Include YAML frontmatter metadata")
        var frontmatter: Bool = false

        @Flag(name: .long, help: "Preserve <u>/<sup>/<sub>/<mark> as raw HTML in Markdown")
        var htmlExtensions: Bool = false

        @Argument(help: "Input file")
        var input: String

        mutating func run() async throws {
            let inputURL = try validatedInputURL(input)

            let ext = inputURL.pathExtension.lowercased()
            let target = to.lowercased()

            switch (ext, target) {
            case ("docx", "md"):
                try convertWordToMD(inputURL: inputURL)

            case ("docx", "html"):
                try convertWordToHTML(inputURL: inputURL)

            case ("docx", "marker"):
                try await convertWordToMarker(inputURL: inputURL)

            case ("html", "md"), ("htm", "md"):
                try convertHTMLToMD(inputURL: inputURL)

            case ("html", "pdf"), ("htm", "pdf"):
                try convertHTMLToPDF(inputURL: inputURL)

            case ("html", "docx"), ("htm", "docx"):
                try convertHTMLToWord(inputURL: inputURL)

            case ("md", "html"), ("markdown", "html"):
                try convertMDToHTML(inputURL: inputURL)

            case ("md", "docx"), ("markdown", "docx"):
                try convertMDToWord(inputURL: inputURL)

            case ("srt", "html"):
                try convertSRTToHTML(inputURL: inputURL)

            case ("bib", "html"):
                try convertBibToHTML(inputURL: inputURL)

            case ("bib", "md"):
                try convertBibToMD(inputURL: inputURL)

            case ("bib", "json"):
                try convertBibToJSON(inputURL: inputURL)

            case ("pdf", "md"):
                try convertPDFToMD(inputURL: inputURL)

            case ("pdf", "docx"):
                try convertPDFToWord(inputURL: inputURL)

            case ("tex", "docx"):
                try convertTeXToWord(inputURL: inputURL)

            case ("note", "html"), ("ntb", "html"):
                try rejectUnsupportedNotabilityGeneration(inputURL: inputURL)
                try convertNoteToHTML(inputURL: inputURL)

            case ("note", "pdf"), ("ntb", "pdf"):
                try rejectUnsupportedNotabilityGeneration(inputURL: inputURL)
                try convertNoteToPDF(inputURL: inputURL)

            default:
                throw ValidationError(
                    "不支援從 .\(ext) 轉換到 \(target)"
                )
            }
        }

        // MARK: - Word → Markdown

        private func convertWordToMD(inputURL: URL) throws {
            let options = ConversionOptions(
                includeFrontmatter: frontmatter,
                hardLineBreaks: hardBreaks,
                tableStyle: .pipe,
                headingStyle: .atx
            )

            let converter = WordConverter()
            if let outputPath = resolveOutputPath() {
                try converter.convertToFile(input: inputURL, output: URL(fileURLWithPath: outputPath), options: options)
            } else {
                try converter.convertToStdout(input: inputURL, options: options)
            }
        }

        // MARK: - Word → HTML

        private func convertWordToHTML(inputURL: URL) throws {
            var options = ConversionOptions.default
            options.includeFrontmatter = frontmatter

            let converter = WordHTMLConverter()
            if let outputPath = resolveOutputPath() {
                try converter.convertToFile(input: inputURL, output: URL(fileURLWithPath: outputPath), options: options)
            } else {
                try converter.convertToStdout(input: inputURL, options: options)
            }
        }

        // MARK: - Word → Marker

        private func convertWordToMarker(inputURL: URL) async throws {
            guard !stdout else {
                throw ValidationError("marker 是目錄結構，不支援 stdout 輸出")
            }

            let options = ConversionOptions(
                includeFrontmatter: frontmatter,
                hardLineBreaks: hardBreaks,
                tableStyle: .pipe,
                headingStyle: .atx
            )

            let outputDir: URL
            if let outputPath = output {
                outputDir = URL(fileURLWithPath: outputPath)
            } else {
                let inputDir = inputURL.deletingLastPathComponent()
                let baseName = inputURL.deletingPathExtension().lastPathComponent
                outputDir = inputDir.appendingPathComponent("\(baseName)_output")
            }

            let converter = MarkerWordConverter()
            let result = try await converter.convert(
                input: inputURL,
                outputDirectory: outputDir,
                options: options
            )

            FileHandle.standardError.write(Data("已寫入: \(outputDir.path)\n".utf8))
            FileHandle.standardError.write(Data("  Markdown: \(result.markdownURL.path)\n".utf8))
            FileHandle.standardError.write(Data("  Metadata: \(result.metadataURL.path)\n".utf8))
            FileHandle.standardError.write(Data("  Images:   \(result.imagesDirectory.path)\n".utf8))
        }

        // MARK: - HTML → Markdown

        private func convertHTMLToMD(inputURL: URL) throws {
            let options = ConversionOptions(
                includeFrontmatter: frontmatter,
                hardLineBreaks: hardBreaks,
                tableStyle: .pipe,
                headingStyle: .atx,
                useHTMLExtensions: htmlExtensions
            )

            let converter = HTMLConverter()
            if let outputPath = resolveOutputPath() {
                try converter.convertToFile(input: inputURL, output: URL(fileURLWithPath: outputPath), options: options)
            } else {
                try converter.convertToStdout(input: inputURL, options: options)
            }
        }

        // MARK: - HTML → Word

        private func convertHTMLToWord(inputURL: URL) throws {
            let outputURL = try resolveDocxOutputURL(inputURL: inputURL)
            try HTMLToWordConverter().convertToFile(input: inputURL, output: outputURL)
            FileHandle.standardError.write(Data("已寫入: \(outputURL.path)\n".utf8))
        }

        // MARK: - HTML → PDF

        private func convertHTMLToPDF(inputURL: URL) throws {
            let outputURL = try resolveBinaryOutputURL(inputURL: inputURL, ext: "pdf")

            // 檢查 playwright 是否可用
            guard isCommandAvailable("playwright") else {
                throw ValidationError(
                    "需要 playwright CLI：pip install playwright && playwright install chromium"
                )
            }

            // absoluteString 自動處理 percent-encoding（空格、中文等）
            let fileURL = inputURL.absoluteString

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [
                "playwright", "pdf",
                fileURL,
                outputURL.path,
                "--paper-format", "A4",
            ]

            let stderrPipe = Pipe()
            process.standardOutput = FileHandle.nullDevice
            process.standardError = stderrPipe

            try process.run()

            // 先讀 pipe 再 wait，避免 pipe buffer 滿造成 deadlock
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            let stderrOutput = String(data: stderrData, encoding: .utf8) ?? ""

            guard process.terminationStatus == 0 else {
                throw ValidationError(
                    "playwright pdf 失敗（exit \(process.terminationStatus)）：\(stderrOutput)"
                )
            }

            FileHandle.standardError.write(Data("已寫入: \(outputURL.path)\n".utf8))
        }

        /// 檢查外部命令是否可用
        private func isCommandAvailable(_ command: String) -> Bool {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["which", command]
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
                return process.terminationStatus == 0
            } catch {
                return false
            }
        }

        // MARK: - Markdown → HTML

        private func convertMDToHTML(inputURL: URL) throws {
            let htmlOptions = HTMLOptions(fullDocument: full)
            let converter = MarkdownConverter()
            let result = try converter.convert(input: inputURL, options: htmlOptions)
            try writeStringOutput(result, to: resolveOutputPath())
        }

        // MARK: - Markdown → Word

        private func convertMDToWord(inputURL: URL) throws {
            var options = ConversionOptions.default
            options.hardLineBreaks = hardBreaks

            let outputURL = try resolveDocxOutputURL(inputURL: inputURL)
            try MarkdownToWordConverter().convertToFile(input: inputURL, output: outputURL, options: options)
            FileHandle.standardError.write(Data("已寫入: \(outputURL.path)\n".utf8))
        }

        // MARK: - SRT → HTML

        private func convertSRTToHTML(inputURL: URL) throws {
            if css != .dark && css != .light {
                throw ValidationError("SRT → HTML 的 --css 只支援 dark 或 light")
            }

            let converter = SRTConverter()

            if full {
                let cssString = css == .light ? SRTCSS.light : SRTCSS.dark
                let html = try converter.convertFull(input: inputURL, css: cssString)
                try writeStringOutput(html, to: resolveOutputPath())
            } else {
                let options = ConversionOptions.default
                if let outputPath = resolveOutputPath() {
                    try converter.convertToFile(input: inputURL, output: URL(fileURLWithPath: outputPath), options: options)
                } else {
                    try converter.convertToStdout(input: inputURL, options: options)
                }
            }
        }

        // MARK: - Bib → HTML

        private func convertBibToHTML(inputURL: URL) throws {
            if css != .minimal && css != .web {
                throw ValidationError("Bib → HTML 的 --css 只支援 minimal 或 web")
            }

            let entries = try loadBibEntries(from: inputURL)
            let cssString = css == .minimal ? APACSS.minimal : APACSS.web

            let html: String
            if full {
                let body = BibToAPAHTMLFormatter.formatReferenceList(entries)
                html = """
                <!DOCTYPE html>
                <html lang="en">
                <head>
                <meta charset="UTF-8">
                <meta name="viewport" content="width=device-width, initial-scale=1.0">
                <title>APA 7 References</title>
                <style>
                \(cssString)
                </style>
                </head>
                <body>
                <div class="apa-reference-list">
                \(body)
                </div>
                </body>
                </html>
                """
            } else {
                html = BibToAPAHTMLFormatter.formatReferenceListWithCSS(entries, css: cssString)
            }

            try writeStringOutput(html, to: resolveOutputPath())
        }

        // MARK: - Bib → Markdown

        private func convertBibToMD(inputURL: URL) throws {
            let entries = try loadBibEntries(from: inputURL)
            let md = BibToAPAFormatter.formatReferenceList(entries)
            try writeStringOutput(md, to: resolveOutputPath())
        }

        // MARK: - Bib → JSON

        private func convertBibToJSON(inputURL: URL) throws {
            let entries = try loadBibEntries(from: inputURL)
            let json = try BibToAPAJSONFormatter.formatJSON(entries, prettyPrint: true)
            try writeStringOutput(json, to: resolveOutputPath())
        }

        // MARK: - PDF → Markdown

        private func convertPDFToMD(inputURL: URL) throws {
            let options = ConversionOptions(
                includeFrontmatter: frontmatter,
                hardLineBreaks: hardBreaks,
                tableStyle: .pipe,
                headingStyle: .atx
            )

            let converter = PDFToMD.PDFConverter()
            if let outputPath = resolveOutputPath() {
                try converter.convertToFile(input: inputURL, output: URL(fileURLWithPath: outputPath), options: options)
            } else {
                try converter.convertToStdout(input: inputURL, options: options)
            }
        }

        // MARK: - PDF → Word

        private func convertPDFToWord(inputURL: URL) throws {
            var options = ConversionOptions.default
            options.hardLineBreaks = hardBreaks

            let outputURL = try resolveDocxOutputURL(inputURL: inputURL)
            try PDFToDOCXConverter().convertToFile(input: inputURL, output: outputURL, options: options)
            FileHandle.standardError.write(Data("已寫入: \(outputURL.path)\n".utf8))
        }

        // MARK: - TeX → Word

        private func convertTeXToWord(inputURL: URL) throws {
            let outputURL = try resolveDocxOutputURL(inputURL: inputURL)
            try TeXToDOCXConverter().convertToFile(input: inputURL, output: outputURL)
            FileHandle.standardError.write(Data("已寫入: \(outputURL.path)\n".utf8))
        }

        // MARK: - Note → HTML

        private func rejectUnsupportedNotabilityGeneration(inputURL: URL) throws {
            guard NotabilityContainerDetector.classify(at: inputURL) == .modernFlatBuffers else {
                return
            }
            throw ValidationError(NotabilityContainerDetector.modernContainerDiagnostic)
        }

        private func convertNoteToHTML(inputURL: URL) throws {
            if css != .dark && css != .light {
                throw ValidationError("Note → HTML 的 --css 只支援 dark 或 light")
            }

            let converter = NoteConverter()
            let theme: NoteConverter.Theme = css == .dark ? .dark : .light

            if stdout {
                // --stdout: 完全內嵌（base64），單一 HTML 輸出到 stdout
                if full {
                    let html = try converter.convertFull(input: inputURL, theme: theme)
                    print(html)
                } else {
                    let options = ConversionOptions.default
                    try converter.convertToStdout(input: inputURL, options: options)
                }
            } else {
                // 預設：資料夾輸出（index.html + media/）(#65)
                let outputDir: URL
                if let outputPath = output {
                    outputDir = URL(fileURLWithPath: outputPath)
                } else {
                    outputDir = inputURL.deletingPathExtension()
                }
                try converter.convertToDirectory(input: inputURL, outputDir: outputDir, theme: theme)
                FileHandle.standardError.write(Data("已寫入: \(outputDir.path)/\n".utf8))
            }
        }

        private func convertNoteToPDF(inputURL: URL) throws {
            let converter = NoteToPDFConverter()
            let pdfData = try converter.convert(input: inputURL)

            let outputURL: URL
            if let outputPath = output {
                outputURL = URL(fileURLWithPath: outputPath)
            } else {
                outputURL = inputURL.deletingPathExtension().appendingPathExtension("pdf")
            }

            try pdfData.write(to: outputURL)
            FileHandle.standardError.write(Data("已寫入: \(outputURL.path)\n".utf8))
        }

        // MARK: - Helpers

        /// Resolve the output path: --stdout forces nil (stdout), overriding --output.
        /// If neither is specified, defaults to stdout.
        private func resolveOutputPath() -> String? {
            if stdout { return nil }
            return output
        }

        /// Resolve the output path with auto-generated fallback.
        /// --stdout forces stdout; --output uses specified path;
        /// otherwise auto-generates same name with target extension in same directory.
        private func resolveOutputPath(inputURL: URL, ext: String) -> String? {
            if stdout { return nil }
            if let outputPath = output { return outputPath }
            return inputURL.deletingPathExtension().appendingPathExtension(ext).path
        }

        /// Resolve the output URL for binary formats (docx, pdf).
        /// --stdout is not supported; without --output, auto-generates same name with target extension.
        private func resolveBinaryOutputURL(inputURL: URL, ext: String) throws -> URL {
            if stdout {
                throw ValidationError("\(ext) 是二進位格式，不支援 stdout 輸出")
            }
            if let outputPath = output {
                return URL(fileURLWithPath: outputPath)
            }
            return inputURL.deletingPathExtension().appendingPathExtension(ext)
        }

        /// Convenience for docx output (backward compat).
        private func resolveDocxOutputURL(inputURL: URL) throws -> URL {
            try resolveBinaryOutputURL(inputURL: inputURL, ext: "docx")
        }

        private func loadBibEntries(from inputURL: URL) throws -> [BibEntry] {
            let bibFile = try BibParser.parse(filePath: inputURL.path)
            return bibFile.entries
        }
    }
}
