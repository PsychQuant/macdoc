// Project metadata overlay for cli-spec.yaml (PsychQuant/macdoc#72).
//
// Only facts ArgumentParser cannot express belong here: command status and
// replacements, conversion routes (the `convert` route table is a Swift
// `switch` and cannot be introspected), overlapping paths, and external
// dependencies. Everything else — paths, arguments, options, flags,
// defaults, help text — is derived from the binary's declarations.
//
// Editing rules:
// - Every command path, option name, CSS style and dependency id used here is
//   validated against the derived surface when the spec is generated
//   (CLISpecBuilder); a stale reference fails `make cli-spec` and the drift
//   test by name.
// - `conversions` must match the binary's dispatch (CLISpecRouteProbeTests)
//   and CONVERSIONS.md's "Converter Details" labels
//   (CLISpecConversionsDocTests). Add a route here, in MacDoc+Convert.swift
//   and in CONVERSIONS.md together.
// - After any edit run `make cli-spec` and commit the regenerated file.

public enum MacDocCLIMetadata {

    public static let overlay = CLISpecMetadata(
        provenance: CLISpecMetadata.Provenance(
            authority: "ArgumentParser declarations in Sources/MacDocCLI (code-first)",
            overlay: "Sources/CLISpec/MacDocCLIMetadata.swift",
            regenerate: "make cli-spec",
            contract: "openspec change cli-spec-yaml, capability cli-spec (PsychQuant/macdoc#72)"
        ),
        commands: commands,
        conversions: conversions,
        overlaps: overlaps,
        externalDependencies: externalDependencies
    )

    // MARK: - Commands

    static let commands: [CLISpecMetadata.CommandInfo] = [
        CLISpecMetadata.CommandInfo(
            path: "macdoc convert",
            status: .active,
            notes: [
                "The input format is detected from the file extension; `conversions` lists every route with its route-specific options.",
                "Output handling is per route: see `output` on each entry of `conversions`.",
            ],
            docs: [".claude/rules/cli-design/convert-entry-point.md", "CONVERSIONS.md"]
        ),
        CLISpecMetadata.CommandInfo(
            path: "macdoc pdf ocr",
            status: .active,
            dependencies: ["huggingface", "ollama"],
            notes: [
                "Whole-page GLM-OCR for the PDF → LaTeX project pipeline; results are written into the project folder, not printed as Markdown.",
                "--mode local runs MLX and downloads the --model repository from Hugging Face on first use; it needs mlx.metallib beside the binary (make release).",
                "--mode ollama sends page images to the Ollama server at --host.",
                "#218: --host and --model have no static default; when omitted, priority is the matching `macdoc config ocr` setting, then a built-in fallback. --host also resolves a `config ocr add-host` profile name to its address. --mode is unaffected by any of this: its own declared default still applies when omitted, and `config ocr set-backend`'s setting is never read — using Ollama still requires passing --mode ollama yourself (see that command's own abstract for why).",
                "--config points at an alternate settings file instead of ~/.config/macdoc/config.json, same flag as `macdoc config ocr`.",
            ]
        ),
        CLISpecMetadata.CommandInfo(
            path: "macdoc pdf blocks",
            status: .deprecated,
            replacement: "macdoc pdf ocr",
            notes: ["Block-level Vision OCR, superseded by whole-page GLM-OCR."]
        ),
        CLISpecMetadata.CommandInfo(
            path: "macdoc pdf transcribe",
            status: .deprecated,
            replacement: "macdoc pdf ocr",
            dependencies: ["ai-cli"],
            notes: ["Block-level AI transcription, superseded by whole-page GLM-OCR."]
        ),
        CLISpecMetadata.CommandInfo(
            path: "macdoc pdf transcribe-pages",
            status: .deprecated,
            replacement: "macdoc pdf ocr",
            dependencies: ["ai-cli"],
            notes: ["Page-level AI transcription, superseded by whole-page GLM-OCR."]
        ),
        CLISpecMetadata.CommandInfo(
            path: "macdoc pdf resume",
            status: .deprecated,
            replacement: "macdoc pdf ocr",
            dependencies: ["ai-cli"],
            notes: ["Resumes the deprecated block transcription from its checkpoint."]
        ),
        CLISpecMetadata.CommandInfo(
            path: "macdoc pdf assemble",
            status: .active,
            dependencies: ["tex"],
            notes: ["Compiles the assembled main TeX file with latexmk unless --skip-compile is given."]
        ),
        CLISpecMetadata.CommandInfo(
            path: "macdoc pdf compile-check",
            status: .active,
            dependencies: ["tex"],
            notes: ["Runs pdflatex on accumulated.tex and writes compile-report.json into the project."]
        ),
        CLISpecMetadata.CommandInfo(
            path: "macdoc pdf consolidate",
            status: .active,
            dependencies: ["tex", "ai-cli"],
            notes: ["Runs the mechanical clean-up, then hands remaining compile errors to the AI CLI chosen by --agent or `macdoc config ai`; --dry-run skips the agent."]
        ),
        CLISpecMetadata.CommandInfo(
            path: "macdoc bib",
            status: .active,
            notes: ["`macdoc convert --to html|md|json file.bib` converts a whole file; these subcommands add repeatable --key filtering and `list`."]
        ),
        CLISpecMetadata.CommandInfo(
            path: "macdoc config ocr",
            status: .active,
            notes: [
                "Stores Ollama host profiles, the OCR model and the OCR backend in the macdoc config file.",
                "#218: `macdoc pdf ocr` reads the host profiles and the OCR model as fallbacks for its own --host/--model when those flags are omitted (priority: explicit flag > this setting > pdf ocr's built-in default). The OCR backend setting is stored but still not read by any command — see `macdoc config ocr set-backend`'s own abstract for why.",
            ]
        ),
        CLISpecMetadata.CommandInfo(
            path: "macdoc config document import-official",
            status: .active,
            dependencies: ["microsoft-word"],
            notes: ["Without --template it reads Normal.dotm from Microsoft Word's Office group container for the current account."]
        ),
        CLISpecMetadata.CommandInfo(
            path: "macdoc ocr",
            status: .removed,
            replacement: "bestocr (https://github.com/PsychQuant/bestOCR)",
            notes: [
                "Deprecation shim (#145): accepts and ignores any arguments, prints migration guidance to stderr and exits with status 2.",
                "General-purpose OCR belongs to bestOCR; page-level OCR inside the PDF → LaTeX pipeline is `macdoc pdf ocr`.",
            ]
        ),
        CLISpecMetadata.CommandInfo(
            path: "macdoc word",
            status: .active,
            docs: ["docs/swift-as-document-source.md", "openspec/specs/mdocx-grammar/spec.md"]
        ),
    ]

    // MARK: - Conversions (labels = CONVERSIONS.md "Converter Details" rows)

    private static let convert = "macdoc convert"
    private static let docxProfileOptions = ["--profile", "--document-config"]

    static let conversions: [CLISpecMetadata.Conversion] = [
        CLISpecMetadata.Conversion(
            label: "Word → Markdown", command: convert, from: ["docx"], to: "md",
            converter: "word-to-md-swift", output: .stdoutOrFile,
            options: ["--frontmatter", "--hard-breaks"]
        ),
        CLISpecMetadata.Conversion(
            label: "Word → HTML", command: convert, from: ["docx"], to: "html",
            converter: "word-to-html-swift", output: .stdoutOrFile,
            options: ["--frontmatter"]
        ),
        CLISpecMetadata.Conversion(
            label: "Word → Marker", command: convert, from: ["docx"], to: "marker",
            converter: "marker-word-converter-swift", output: .directory,
            options: ["--frontmatter", "--hard-breaks"],
            notes: ["Writes Markdown, _meta.json and images/ into --output, or <input-stem>_output/ beside the input; --stdout is rejected."]
        ),
        CLISpecMetadata.Conversion(
            label: "HTML → Markdown", command: convert, from: ["html", "htm"], to: "md",
            converter: "html-to-md-swift", output: .stdoutOrFile,
            options: ["--frontmatter", "--hard-breaks", "--html-extensions"]
        ),
        CLISpecMetadata.Conversion(
            label: "HTML → PDF", command: convert, from: ["html", "htm"], to: "pdf",
            converter: "playwright", output: .file,
            dependencies: ["playwright"],
            notes: ["Runs `playwright pdf` with A4 paper; without playwright on PATH it fails with an install hint."]
        ),
        CLISpecMetadata.Conversion(
            label: "HTML → Word", command: convert, from: ["html", "htm"], to: "docx",
            converter: "html-to-word-swift", output: .file,
            options: docxProfileOptions
        ),
        CLISpecMetadata.Conversion(
            label: "Markdown → HTML", command: convert, from: ["md", "markdown"], to: "html",
            converter: "md-to-html-swift", output: .stdoutOrFile,
            options: ["--full"]
        ),
        CLISpecMetadata.Conversion(
            label: "Markdown → Word", command: convert, from: ["md", "markdown"], to: "docx",
            converter: "md-to-word-swift", output: .file,
            options: ["--hard-breaks", "--math"] + docxProfileOptions,
            notes: ["--math omath turns $…$ formulas into native Word OMath; --math literal keeps them as text."]
        ),
        CLISpecMetadata.Conversion(
            label: "SRT → HTML", command: convert, from: ["srt"], to: "html",
            converter: "srt-to-html-swift", output: .stdoutOrFile,
            options: ["--full", "--css"], styles: ["dark", "light"],
            notes: [
                "This route accepts only --css dark or --css light. --css has no built-in default (#216); when it is omitted this route falls back to dark.",
                "Speaker labels (`Speaker 1:` or `[Speaker 1]`) become speaker badges.",
            ]
        ),
        CLISpecMetadata.Conversion(
            label: "BibLaTeX → APA HTML", command: convert, from: ["bib"], to: "html",
            converter: "bib-apa-to-html-swift", output: .stdoutOrFile,
            options: ["--full", "--css"], styles: ["minimal", "web"],
            notes: ["--css has no built-in default (#216); when it is omitted this route falls back to web."]
        ),
        CLISpecMetadata.Conversion(
            label: "BibLaTeX → APA Markdown", command: convert, from: ["bib"], to: "md",
            converter: "bib-apa-to-md-swift", output: .stdoutOrFile
        ),
        CLISpecMetadata.Conversion(
            label: "BibLaTeX → APA JSON", command: convert, from: ["bib"], to: "json",
            converter: "bib-apa-to-json-swift", output: .stdoutOrFile
        ),
        CLISpecMetadata.Conversion(
            label: "PDF → Markdown", command: convert, from: ["pdf"], to: "md",
            converter: "pdf-to-md-swift", output: .stdoutOrFile,
            options: ["--frontmatter", "--hard-breaks"],
            notes: ["Reads the embedded text layer with PDFKit (no OCR)."]
        ),
        CLISpecMetadata.Conversion(
            label: "PDF → DOCX", command: convert, from: ["pdf"], to: "docx",
            converter: "pdf-to-docx-swift", output: .file,
            options: ["--hard-breaks"] + docxProfileOptions,
            notes: ["Reads the embedded text layer with PDFKit (no OCR)."]
        ),
        CLISpecMetadata.Conversion(
            label: "PDF → LaTeX", command: "macdoc pdf", from: ["pdf"], to: "tex",
            converter: "pdf-to-latex-swift", output: .directory,
            notes: ["Multi-step project pipeline, not a `convert` route: init → render → ocr → chapters → assemble, then normalize → fix-envs → compile-check → consolidate."]
        ),
        CLISpecMetadata.Conversion(
            label: "LaTeX → Word", command: convert, from: ["tex"], to: "docx",
            converter: "tex-to-docx-swift", output: .file,
            options: docxProfileOptions
        ),
        CLISpecMetadata.Conversion(
            label: "舊版 Note → HTML", command: convert, from: ["note", "ntb"], to: "html",
            converter: "note-to-html-swift", output: .directoryOrStdout,
            options: ["--full", "--css"], styles: ["dark", "light"],
            notes: [
                "Legacy plist-based .note only; modern FlatBuffers .ntb containers are recognized and rejected.",
                "Writes <input-stem>/ with index.html and media/ (or --output); --stdout prints one self-contained HTML, with --full for a complete document.",
                "This route accepts only --css dark or --css light. --css has no built-in default (#216); when it is omitted this route falls back to dark.",
            ]
        ),
        CLISpecMetadata.Conversion(
            label: "舊版 Note → PDF", command: convert, from: ["note", "ntb"], to: "pdf",
            converter: "note-to-pdf-swift", output: .file,
            notes: ["Legacy plist-based .note only; modern FlatBuffers .ntb containers are recognized and rejected."]
        ),
        CLISpecMetadata.Conversion(
            label: "UTF-8 text → Token count", command: convert, from: ["*"], to: "tokens",
            converter: "token-counter-swift", output: .stdoutOrFile,
            options: ["--model", "--allow-network"],
            dependencies: ["anthropic-api"],
            notes: [
                "Measurement route: any extension, strict UTF-8, at most 1,000,000 bytes.",
                "gpt-4o counts offline; claude-sonnet-4-6 sends the whole file to Anthropic and needs --allow-network and ANTHROPIC_API_KEY.",
            ]
        ),
    ]

    // MARK: - Overlapping paths

    static let overlaps: [CLISpecMetadata.Overlap] = [
        CLISpecMetadata.Overlap(topic: "PDF text, OCR and LaTeX", paths: [
            CLISpecMetadata.OverlapPath(
                command: "macdoc convert",
                usage: "macdoc convert --to md file.pdf",
                note: "Reads the PDF's embedded text layer with PDFKit plus heading/list heuristics; no OCR, so scanned pages yield no text. `--to docx` does the same into Word."
            ),
            CLISpecMetadata.OverlapPath(
                command: "macdoc pdf ocr",
                usage: "macdoc pdf ocr --project <dir>",
                note: "Page-image GLM-OCR (local MLX or Ollama) inside the PDF → LaTeX project pipeline; results feed `pdf chapters` and `pdf assemble`."
            ),
            CLISpecMetadata.OverlapPath(
                command: "macdoc ocr",
                usage: "macdoc ocr <input>",
                note: "Removed shim (#145): exits with status 2 and points to bestocr, which owns general-purpose OCR."
            ),
            CLISpecMetadata.OverlapPath(
                command: "macdoc config ocr",
                usage: "macdoc config ocr list",
                note: "Edits OCR host and model settings that feed `pdf ocr`'s --host/--model when those flags are omitted (#218); the backend setting is still not read by any command."
            ),
        ]),
        CLISpecMetadata.Overlap(topic: "BibLaTeX to APA 7", paths: [
            CLISpecMetadata.OverlapPath(
                command: "macdoc convert",
                usage: "macdoc convert --to html file.bib",
                note: "Whole file to APA 7 HTML, Markdown or JSON; HTML takes --full and --css minimal|web."
            ),
            CLISpecMetadata.OverlapPath(
                command: "macdoc bib to-html",
                usage: "macdoc bib to-html file.bib --key smith2020",
                note: "Same renderers with repeatable --key filtering and -o; `bib to-md` and `bib to-json` likewise, `bib list` prints entry keys."
            ),
        ]),
        CLISpecMetadata.Overlap(topic: "Word documents and .mdocx scripts", paths: [
            CLISpecMetadata.OverlapPath(
                command: "macdoc convert",
                usage: "macdoc convert --to md file.docx",
                note: "Readable Markdown export; lossy by design."
            ),
            CLISpecMetadata.OverlapPath(
                command: "macdoc word reverse",
                usage: "macdoc word reverse file.docx --to-mdocx out.mdocx.swift",
                note: "Full-fidelity .mdocx.swift script; `macdoc word render` rebuilds the .docx from it."
            ),
            CLISpecMetadata.OverlapPath(
                command: "macdoc docx apply",
                usage: "macdoc docx apply manifest.json -i base.docx -o out.docx",
                note: "Manifest-driven edits of an existing .docx."
            ),
        ]),
    ]

    // MARK: - External dependencies

    static let externalDependencies: [CLISpecMetadata.ExternalDependency] = [
        CLISpecMetadata.ExternalDependency(
            id: "playwright", kind: .cli,
            purpose: "Renders HTML to PDF through Chromium (`playwright pdf`).",
            install: "pip install playwright && playwright install chromium"
        ),
        CLISpecMetadata.ExternalDependency(
            id: "tex", kind: .cli,
            purpose: "latexmk and pdflatex from a TeX distribution compile the assembled or accumulated LaTeX.",
            install: "MacTeX or TeX Live"
        ),
        CLISpecMetadata.ExternalDependency(
            id: "ai-cli", kind: .cli,
            purpose: "codex, claude or gemini CLI, delegated for block/page transcription and compile-error repair.",
            install: "Install at least one; `macdoc config ai detect` records what is available."
        ),
        CLISpecMetadata.ExternalDependency(
            id: "ollama", kind: .networkService,
            purpose: "Serves the glm-ocr model over HTTP for `pdf ocr --mode ollama` at the address given by --host.",
            install: "Install Ollama and pull the glm-ocr model."
        ),
        CLISpecMetadata.ExternalDependency(
            id: "huggingface", kind: .networkService,
            purpose: "Hugging Face Hub, from which `pdf ocr --mode local` downloads the MLX model named by --model on first use."
        ),
        CLISpecMetadata.ExternalDependency(
            id: "anthropic-api", kind: .networkService,
            purpose: "Anthropic token counting for `--to tokens --model claude-sonnet-4-6`; needs --allow-network and ANTHROPIC_API_KEY."
        ),
        CLISpecMetadata.ExternalDependency(
            id: "microsoft-word", kind: .application,
            purpose: "Provides the Normal.dotm template that `config document import-official` reads when --template is omitted."
        ),
    ]
}
