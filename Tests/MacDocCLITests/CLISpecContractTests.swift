import Testing
import Foundation
import CLISpec

/// Contract tests of `cli-spec.yaml` against the real built `macdoc` binary
/// and the real overlay (Spectra change `cli-spec-yaml`; PsychQuant/macdoc#72).
/// Each test pins a scenario of the `cli-spec` spec.
struct CLISpecContractTests {

    func command(_ path: String) throws -> CLISpecDocument.Command {
        let document = try CLISpecHarness.document()
        return try #require(document.commands.first { $0.path == path }, "no command \(path)")
    }

    func option(_ name: String, of path: String) throws -> CLISpecDocument.Argument {
        let command = try command(path)
        return try #require(command.options.first { $0.names.contains(name) }, "no option \(name) on \(path)")
    }

    // MARK: - Header and root

    @Test("header lines identify the file as generated")
    func header() throws {
        let lines = try CLISpecHarness.generate().components(separatedBy: "\n")
        #expect(lines[0] == "# cli-spec.yaml — macdoc CLI specification (schema_version 1)")
        #expect(lines[1].hasPrefix("# ") && lines[1].contains("GENERATED FILE") && lines[1].contains("make cli-spec"))
        #expect(lines[2].hasPrefix("# ") && lines[2].contains("Sources/MacDocCLI"))
        #expect(lines[3] == "# Project metadata overlay: Sources/CLISpec/MacDocCLIMetadata.swift")
        #expect(lines[4].hasPrefix("# ") && lines[4].contains("PsychQuant/macdoc#72"))
        #expect(lines[5] == "schema_version: 1")
    }

    @Test("root command: tool block and subcommands without the builtin help")
    func root() throws {
        let document = try CLISpecHarness.document()
        let versionOutput = try CLISpecHarness.inputs().versionOutput
        #expect(document.tool.name == "macdoc")
        #expect(document.tool.version == versionOutput.trimmingCharacters(in: .whitespacesAndNewlines))
        #expect(document.tool.version.isEmpty == false)
        #expect(document.commands.first?.path == "macdoc")
        #expect(document.commands.first?.subcommands == ["convert", "pdf", "bib", "config", "ocr", "docx", "word"])
        #expect(!document.commands.contains { $0.path == "macdoc help" })
    }

    @Test("builtin --help, -h, -help and --version flags are absent everywhere")
    func builtinsAbsent() throws {
        let document = try CLISpecHarness.document()
        let names = document.commands.flatMap { $0.options + $0.flags }.flatMap(\.names)
        for builtin in ["--help", "-h", "-help", "--version"] {
            #expect(!names.contains(builtin), "\(builtin) should be normalized away")
        }
    }

    @Test("commands are listed in depth-first declaration order")
    func commandOrder() throws {
        let paths = try CLISpecHarness.document().commands.map(\.path)
        #expect(Array(paths.prefix(8)) == [
            "macdoc", "macdoc convert", "macdoc pdf", "macdoc pdf init", "macdoc pdf segment",
            "macdoc pdf render", "macdoc pdf ocr", "macdoc pdf blocks",
        ])
        #expect(try command("macdoc pdf").defaultSubcommand == "status")
    }

    // MARK: - convert

    @Test("convert --to and --css render exactly as the spec example")
    func convertOptionsYAML() throws {
        let yaml = try CLISpecHarness.generate()
        #expect(yaml.contains("""
              - names: ["--to"]
                value_name: to
                required: true
                help: "Target format (md, html, docx, pdf, json, marker, tokens)"

        """))
        #expect(yaml.contains("""
              - names: ["--css"]
                value_name: css
                required: false
                default: web
                values: [minimal, web, dark, light]
                help: "CSS style: minimal|web (bib), dark|light (srt)"

        """))
    }

    @Test("convert declares --to first, --profile values, flags and the input positional")
    func convertSurface() throws {
        let convert = try command("macdoc convert")
        #expect(convert.options.first?.names == ["--to"])
        #expect(try option("--profile", of: "macdoc convert").values == ["inherit", "official"])
        #expect(try option("--math", of: "macdoc convert").values == ["literal", "omath"])
        #expect(convert.flags.map(\.names) == [
            ["--allow-network"], ["--stdout"], ["--hard-breaks"], ["--full"], ["--frontmatter"], ["--html-extensions"],
        ])
        #expect(convert.flags.allSatisfy { !$0.required })
        #expect(convert.arguments.map(\.name) == ["input"])
        #expect(convert.arguments.first?.required == true)
    }

    // MARK: - pdf ocr

    @Test("pdf ocr is a nested path with its defaults and dependencies")
    func pdfOCR() throws {
        let ocr = try command("macdoc pdf ocr")
        #expect(try option("--mode", of: "macdoc pdf ocr").defaultValue == "local")
        #expect(try option("--host", of: "macdoc pdf ocr").defaultValue == "localhost:11434")
        #expect(try option("--page-dpi", of: "macdoc pdf ocr").defaultValue == "200.0")
        #expect(try option("--model", of: "macdoc pdf ocr").defaultValue == "EZCon/GLM-OCR-8bit-mlx")
        #expect(ocr.flags.map(\.names) == [["--with-pdfkit"]])
        #expect(ocr.project?.status == .active)
        #expect(ocr.project?.dependencies == ["huggingface", "ollama"])
    }

    @Test("deprecated pdf block pipeline points to pdf ocr")
    func deprecatedPDFCommands() throws {
        for path in ["macdoc pdf blocks", "macdoc pdf transcribe", "macdoc pdf transcribe-pages", "macdoc pdf resume"] {
            let project = try #require(try command(path).project, "\(path) has no overlay entry")
            #expect(project.status == .deprecated, "\(path)")
            #expect(project.replacement == "macdoc pdf ocr", "\(path)")
        }
    }

    // MARK: - word reverse / word render

    @Test("word reverse: input, --to-mdocx, flags and repeatable --slot")
    func wordReverse() throws {
        let reverse = try command("macdoc word reverse")
        #expect(reverse.arguments.map(\.name) == ["input"])
        #expect(reverse.arguments.first?.required == true)
        #expect(try option("--to-mdocx", of: "macdoc word reverse").required == false)
        #expect(reverse.flags.map(\.names) == [["--from-oplog"], ["--force"], ["--coverage"], ["--paragraphs-only"]])
        let slot = try option("--slot", of: "macdoc word reverse")
        #expect(slot.valueName == "name=paraId")
        #expect(slot.repeating)
        #expect(try CLISpecHarness.generate().contains("        value_name: \"name=paraId\"\n"))
    }

    @Test("word render: required --to-docx, optional profile options, --force flag")
    func wordRender() throws {
        let render = try command("macdoc word render")
        #expect(render.arguments.map(\.name) == ["input"])
        #expect(render.arguments.first?.required == true)
        #expect(render.options.map(\.names) == [["--to-docx"], ["--profile"], ["--document-config"], ["--verify-against"]])
        #expect(render.options.map(\.required) == [true, false, false, false])
        #expect(try option("--profile", of: "macdoc word render").values == ["inherit", "official"])
        #expect(render.flags.map(\.names) == [["--force"]])
        #expect(render.flags.first?.required == false)
    }

    // MARK: - config document

    @Test("config document subtree")
    func configDocument() throws {
        #expect(try command("macdoc config document").subcommands == ["show", "set-default", "import-official"])
        let setDefault = try command("macdoc config document set-default")
        #expect(setDefault.arguments.map(\.name) == ["profile"])
        #expect(setDefault.arguments.first?.required == true)
        #expect(setDefault.arguments.first?.values == ["inherit", "official"])
        #expect(setDefault.options.map(\.names) == [["--config"]])
        let importOfficial = try command("macdoc config document import-official")
        #expect(importOfficial.options.map(\.names) == [["--template"], ["--config"]])
        #expect(importOfficial.project?.dependencies == ["microsoft-word"])
    }

    // MARK: - Removed top-level ocr shim

    @Test("top-level ocr shim: hidden catch-all positional, removed status")
    func ocrShim() throws {
        let shim = try command("macdoc ocr")
        let ignored = try #require(shim.arguments.first)
        #expect(shim.arguments.count == 1)
        #expect(ignored.name == "ignored")
        #expect(ignored.repeating)
        #expect(ignored.parsing == "all_unrecognized")
        #expect(ignored.hidden)
        #expect(ignored.required == false)
        #expect(shim.options.isEmpty && shim.flags.isEmpty)
        let project = try #require(shim.project)
        #expect(project.status == .removed)
        #expect(project.replacement?.contains("bestocr") == true)
        #expect(project.replacement?.contains("https://github.com/PsychQuant/bestOCR") == true)
    }

    // MARK: - Names, overlaps, dependencies

    @Test("names are ordered long-first and repeating options are marked")
    func namesAndRepeating() throws {
        #expect(try option("--output", of: "macdoc bib to-html").names == ["--output", "-o"])
        #expect(try option("--key", of: "macdoc bib to-html").repeating)
        #expect(try option("--input", of: "macdoc docx apply").names == ["--input", "-i"])
    }

    @Test("overlapping PDF paths are documented as separate paths")
    func pdfOverlap() throws {
        let document = try CLISpecHarness.document()
        let overlap = try #require(document.overlaps.first { $0.paths.contains { $0.command == "macdoc pdf ocr" } })
        #expect(overlap.paths.contains { $0.command == "macdoc convert" && $0.usage == "macdoc convert --to md file.pdf" })
        #expect(overlap.paths.contains { $0.command == "macdoc ocr" })
        let notes = overlap.paths.map(\.note).joined(separator: " ")
        #expect(notes.contains("PDFKit"))
        #expect(notes.contains("GLM-OCR"))
        #expect(notes.contains("#145"))
    }

    @Test("dependency used_by is derived and never empty")
    func dependencyUsage() throws {
        let document = try CLISpecHarness.document()
        let playwright = try #require(document.externalDependencies.first { $0.dependency.id == "playwright" })
        #expect(playwright.usedBy == ["HTML → PDF"])
        #expect(document.externalDependencies.allSatisfy { !$0.usedBy.isEmpty })
        let tex = try #require(document.externalDependencies.first { $0.dependency.id == "tex" })
        #expect(tex.usedBy == ["macdoc pdf assemble", "macdoc pdf compile-check", "macdoc pdf consolidate"])
    }

    @Test("routes whose styles exclude the --css default say so, and no overlay prose quotes a default value")
    func cssDefaultNotes() throws {
        let document = try CLISpecHarness.document()
        let cssDefault = try #require(try option("--css", of: "macdoc convert").defaultValue)
        for conversion in document.conversions where conversion.options.contains("--css") {
            let rejectsDefault = !conversion.styles.contains(cssDefault)
            let noted = conversion.notes.contains { $0.contains("rejects the option's default") }
            #expect(rejectsDefault == noted,
                    "\(conversion.label): --css default \(cssDefault) rejected=\(rejectsDefault) but note present=\(noted)")
        }
        // Defaults are derived from ArgumentParser; prose restating them would drift silently.
        let prose = document.commands.compactMap(\.project).flatMap(\.notes)
            + document.conversions.flatMap(\.notes)
            + document.externalDependencies.map(\.dependency.purpose)
            + document.overlaps.flatMap(\.paths).map(\.note)
        for text in prose {
            #expect(!text.contains("(default)") && !text.contains("defaults to") && !text.contains("default localhost"),
                    "overlay prose restates a default: \(text)")
        }
    }

    @Test("selected conversions match the spec example table")
    func selectedConversions() throws {
        let conversions = try CLISpecHarness.document().conversions
        func conversion(_ label: String) throws -> CLISpecMetadata.Conversion {
            try #require(conversions.first { $0.label == label }, "no conversion \(label)")
        }
        let word = try conversion("Word → Markdown")
        #expect(word.command == "macdoc convert" && word.from == ["docx"] && word.to == "md")
        #expect(word.output == .stdoutOrFile && word.options == ["--frontmatter", "--hard-breaks"])
        let htmlPDF = try conversion("HTML → PDF")
        #expect(htmlPDF.from == ["html", "htm"] && htmlPDF.to == "pdf" && htmlPDF.output == .file)
        #expect(htmlPDF.dependencies == ["playwright"] && htmlPDF.options.isEmpty)
        let srt = try conversion("SRT → HTML")
        #expect(srt.options == ["--full", "--css"] && srt.styles == ["dark", "light"])
        let note = try conversion("舊版 Note → HTML")
        #expect(note.from == ["note", "ntb"] && note.output == .directoryOrStdout && note.styles == ["dark", "light"])
        let latex = try conversion("PDF → LaTeX")
        #expect(latex.command == "macdoc pdf" && latex.to == "tex" && latex.output == .directory)
        let tokens = try conversion("UTF-8 text → Token count")
        #expect(tokens.from == ["*"] && tokens.to == "tokens" && tokens.dependencies == ["anthropic-api"])
        #expect(tokens.options == ["--model", "--allow-network"])
        // Output behavior is expressed by `output`, never by listing these.
        #expect(conversions.allSatisfy { !$0.options.contains("--output") && !$0.options.contains("--stdout") })
    }
}
