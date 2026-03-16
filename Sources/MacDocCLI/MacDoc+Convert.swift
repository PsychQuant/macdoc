import ArgumentParser
import Foundation
import CommonConverterSwift
import WordToMDSwift
import HTMLToMD
import MDToHTML
import SRTToHTML
import BibAPAToHTML
import BibAPAToJSON
import BibAPAToMD

// MARK: - Convert 子命令（textutil-compatible 統一入口）
extension MacDoc {
    struct Convert: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "convert",
            abstract: "Convert documents between formats (textutil-compatible)"
        )

        @Option(name: .long, help: "Target format (md, html, json)")
        var to: String

        @Option(name: .long, help: "Output file path")
        var output: String?

        @Flag(name: .long, help: "Force output to stdout")
        var stdout: Bool = false

        @Option(name: .long, help: "CSS style: minimal|web (bib), dark|light (srt)")
        var css: CSSStyle = .web

        @Flag(name: .long, help: "Treat soft breaks as hard line breaks")
        var hardBreaks: Bool = false

        @Flag(name: .long, help: "Output full HTML document instead of fragment")
        var full: Bool = false

        @Argument(help: "Input file")
        var input: String

        mutating func run() throws {
            let inputURL = try validatedInputURL(input)

            let ext = inputURL.pathExtension.lowercased()
            let target = to.lowercased()

            switch (ext, target) {
            case ("docx", "md"):
                try convertWordToMD(inputURL: inputURL)

            case ("html", "md"), ("htm", "md"):
                try convertHTMLToMD(inputURL: inputURL)

            case ("md", "html"), ("markdown", "html"):
                try convertMDToHTML(inputURL: inputURL)

            case ("srt", "html"):
                try convertSRTToHTML(inputURL: inputURL)

            case ("bib", "html"):
                try convertBibToHTML(inputURL: inputURL)

            case ("bib", "md"):
                try convertBibToMD(inputURL: inputURL)

            case ("bib", "json"):
                try convertBibToJSON(inputURL: inputURL)

            default:
                throw ValidationError(
                    "Conversion from .\(ext) to \(target) is not supported."
                )
            }
        }

        // MARK: - Word → Markdown

        private func convertWordToMD(inputURL: URL) throws {
            let options = ConversionOptions(
                includeFrontmatter: false,
                hardLineBreaks: hardBreaks,
                tableStyle: .pipe,
                headingStyle: .atx
            )

            let converter = WordConverter()
            if let outputPath = resolveOutputPath() {
                let outputURL = URL(fileURLWithPath: outputPath)
                try converter.convertToFile(input: inputURL, output: outputURL, options: options)
            } else {
                try converter.convertToStdout(input: inputURL, options: options)
            }
        }

        // MARK: - HTML → Markdown

        private func convertHTMLToMD(inputURL: URL) throws {
            let options = ConversionOptions(
                includeFrontmatter: false,
                hardLineBreaks: hardBreaks,
                tableStyle: .pipe,
                headingStyle: .atx
            )

            let converter = HTMLConverter()
            if let outputPath = resolveOutputPath() {
                let outputURL = URL(fileURLWithPath: outputPath)
                try converter.convertToFile(input: inputURL, output: outputURL, options: options)
            } else {
                try converter.convertToStdout(input: inputURL, options: options)
            }
        }

        // MARK: - Markdown → HTML

        private func convertMDToHTML(inputURL: URL) throws {
            let htmlOptions = HTMLOptions(fullDocument: full)
            let converter = MarkdownConverter()
            let result = try converter.convert(input: inputURL, options: htmlOptions)

            if let outputPath = resolveOutputPath() {
                let outputURL = URL(fileURLWithPath: outputPath)
                try result.write(to: outputURL, atomically: true, encoding: .utf8)
                FileHandle.standardError.write(
                    Data("Written to: \(outputURL.path)\n".utf8)
                )
            } else {
                print(result)
            }
        }

        // MARK: - SRT → HTML

        private func convertSRTToHTML(inputURL: URL) throws {
            let converter = SRTConverter()

            if full {
                let cssString = css == .light ? SRTCSS.light : SRTCSS.dark
                let html = try converter.convertFull(input: inputURL, css: cssString)
                try writeStringOutput(html, to: resolveOutputPath())
            } else {
                let options = ConversionOptions.default
                if let outputPath = resolveOutputPath() {
                    let outputURL = URL(fileURLWithPath: outputPath)
                    try converter.convertToFile(input: inputURL, output: outputURL, options: options)
                } else {
                    try converter.convertToStdout(input: inputURL, options: options)
                }
            }
        }

        // MARK: - Bib → HTML

        private func convertBibToHTML(inputURL: URL) throws {
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

            try writeBibOutput(html)
        }

        // MARK: - Bib → Markdown

        private func convertBibToMD(inputURL: URL) throws {
            let entries = try loadBibEntries(from: inputURL)
            let md = BibToAPAFormatter.formatReferenceList(entries)
            try writeBibOutput(md)
        }

        // MARK: - Bib → JSON

        private func convertBibToJSON(inputURL: URL) throws {
            let entries = try loadBibEntries(from: inputURL)
            let json = try BibToAPAJSONFormatter.formatJSON(entries, prettyPrint: true)
            try writeBibOutput(json)
        }

        // MARK: - Helpers

        /// Resolve the output path: --stdout forces nil (stdout), overriding --output.
        /// If neither is specified, defaults to stdout.
        private func resolveOutputPath() -> String? {
            if stdout { return nil }
            return output
        }

        private func loadBibEntries(from inputURL: URL) throws -> [BibEntry] {
            let bibFile = try BibParser.parse(filePath: inputURL.path)
            return bibFile.entries
        }

        private func writeBibOutput(_ content: String) throws {
            if let outputPath = resolveOutputPath() {
                let outputURL = URL(fileURLWithPath: outputPath)
                try content.write(to: outputURL, atomically: true, encoding: .utf8)
                FileHandle.standardError.write(
                    Data("Written to: \(outputURL.path)\n".utf8)
                )
            } else {
                print(content)
            }
        }
    }
}
