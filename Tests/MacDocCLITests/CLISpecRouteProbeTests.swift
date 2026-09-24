import Testing
import Foundation
import CLISpec

/// Checks the overlay's `macdoc convert` conversions against what the binary's
/// route `switch` actually dispatches (Spectra change `cli-spec-yaml`,
/// requirement "Convert routes match the binary's dispatch";
/// PsychQuant/macdoc#72). The route table is not introspectable, so this is
/// the test that keeps the overlay honest in both directions: a listed pair
/// the binary rejects, and a dispatched pair the overlay forgot.
struct CLISpecRouteProbeTests {

    struct ProbePair: Sendable, Hashable, CustomTestStringConvertible {
        let ext: String
        let target: String
        /// Label of the overlay conversion that lists this pair; `nil` when unlisted.
        let label: String?
        /// `--css` value passed so a styled route clears its own style check.
        let style: String?

        var listed: Bool { label != nil }
        var testDescription: String { "(\(ext), \(target)) \(label ?? "unlisted")" }
    }

    /// Listed routes that cannot succeed in the probe environment, with the
    /// diagnostic only that route's own implementation prints. Every other
    /// listed route must succeed and produce its output. This is a closed
    /// list: HTML → PDF needs playwright, which the probe keeps off PATH.
    static let inRouteDiagnostics: [String: String] = [
        "HTML → PDF": "需要 playwright CLI",
    ]

    /// Fixed probe vocabulary, unioned with the overlay's extensions and
    /// targets. It holds every source extension and target the overlay used
    /// when it was last updated — so dropping a route from the overlay while
    /// the binary still dispatches it fails the probe — plus candidate
    /// formats, so a new `switch` case for one of them fails too.
    static let vocabularyExtensions = [
        "docx", "html", "htm", "md", "markdown", "srt", "bib", "pdf", "tex", "note", "ntb",
        "txt", "rtf", "odt", "epub", "pptx", "xlsx", "csv", "typ", "ipynb", "mdocx",
    ]
    static let vocabularyTargets = [
        "md", "html", "marker", "pdf", "docx", "json",
        "txt", "rtf", "epub", "tex", "pptx", "srt",
    ]

    /// E × T over the `macdoc convert` conversions whose sources are concrete
    /// extensions (the `"*"` tokens route is covered by TokenCountCommandTests).
    static let pairs: [ProbePair] = {
        let routes = MacDocCLIMetadata.overlay.conversions.filter {
            $0.command == "macdoc convert" && !$0.from.contains("*")
        }
        var extensions: [String] = []
        var targets: [String] = []
        for route in routes {
            for ext in route.from where !extensions.contains(ext) {
                extensions.append(ext)
            }
            if !targets.contains(route.to) { targets.append(route.to) }
        }
        extensions += vocabularyExtensions.filter { !extensions.contains($0) }
        targets += vocabularyTargets.filter { !targets.contains($0) }
        return extensions.flatMap { ext in
            targets.map { target in
                let route = routes.first { $0.to == target && $0.from.contains(ext) }
                return ProbePair(ext: ext, target: target, label: route?.label, style: route?.styles.first)
            }
        }
    }()

    /// Real input bytes per source extension, generated once into a private
    /// directory. Listed routes run on these so they clear every validation
    /// and reach their converter; unlisted pairs run on empty files, because
    /// dispatch rejects them before reading the input.
    static let fixtures: [String: Data] = {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("macdoc-cli-spec-fixtures-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        func read(_ path: String) -> Data? { FileManager.default.contents(atPath: path) }

        let docx = directory.appendingPathComponent("fixture.docx")
        FixtureManager.createMinimalDocx(at: docx)
        let pdf = directory.appendingPathComponent("fixture.pdf")
        FixtureManager.createMinimalPDF(at: pdf)
        let note = directory.appendingPathComponent("fixture.note")
        try? NoteFixtureGenerator.generate(at: note)

        var data: [String: Data] = [:]
        data["docx"] = read(docx.path)
        data["pdf"] = read(pdf.path)
        data["note"] = read(note.path)
        data["ntb"] = data["note"]   // a legacy container is accepted under either extension
        // Text fixtures are written atomically by FixtureManager, so reading them is race-free.
        data["html"] = read(FixtureManager.htmlFile())
        data["htm"] = data["html"]
        data["md"] = read(FixtureManager.markdownFile())
        data["markdown"] = data["md"]
        data["srt"] = read(FixtureManager.srtFile())
        data["bib"] = read(FixtureManager.bibFile())
        data["tex"] = read(FixtureManager.texFile())
        return data
    }()

    @Test("every extension/target pair dispatches exactly as the overlay says", arguments: pairs)
    func probe(pair: ProbePair) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("macdoc-cli-spec-probe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = directory.appendingPathComponent("probe.\(pair.ext)")
        let content: Data
        if pair.listed {
            content = try #require(Self.fixtures[pair.ext], "no probe fixture for .\(pair.ext)")
            #expect(!content.isEmpty, "empty probe fixture for .\(pair.ext)")
        } else {
            content = Data()
        }
        try content.write(to: input)
        let output = directory.appendingPathComponent("out.\(pair.target)")

        var arguments = ["convert", "--to", pair.target, "--output", output.path]
        if let style = pair.style { arguments += ["--css", style] }
        arguments.append(input.path)

        // PATH without Homebrew / pip locations: the HTML → PDF route must
        // stop at "playwright not found" instead of launching Chromium.
        let result = try CLITestHelper.run(arguments, environment: ["PATH": "/usr/bin:/bin"])

        guard let label = pair.label else {
            #expect(result.exitCode != 0)
            #expect(result.stderr.contains("不支援從 .\(pair.ext) 轉換到 \(pair.target)"),
                    "the binary dispatches \(pair.ext) → \(pair.target) but the overlay does not list it: \(result.stderr)")
            return
        }

        if let diagnostic = Self.inRouteDiagnostics[label] {
            #expect(result.exitCode != 0)
            #expect(result.stderr.contains(diagnostic),
                    "\(label): expected the route's own diagnostic 「\(diagnostic)」, got: \(result.stderr)")
            return
        }
        #expect(result.exitCode == 0, "\(label) did not succeed on a valid fixture: \(result.stderr)")
        #expect(Self.hasOutput(at: output), "\(label) produced no output at \(output.path): \(result.stderr)")
    }

    /// A non-empty file, or a directory with at least one entry.
    static func hasOutput(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return false }
        if isDirectory.boolValue {
            return !((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []).isEmpty
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        return size > 0
    }

    @Test("the in-route diagnostics table only names listed conversions")
    func diagnosticsTableIsClosed() {
        let labels = Set(MacDocCLIMetadata.overlay.conversions.map(\.label))
        #expect(Set(Self.inRouteDiagnostics.keys).isSubset(of: labels))
    }

    @Test("the probe covers the spec's example pairs with the expected classification", arguments: [
        ("docx", "md", true),
        ("htm", "pdf", true),
        ("ntb", "pdf", true),
        ("srt", "md", false),
        ("tex", "html", false),
        ("bib", "docx", false),
        ("pdf", "tex", false),
        ("txt", "md", false),
    ])
    func examplePairs(ext: String, target: String, listed: Bool) throws {
        let pair = try #require(Self.pairs.first { $0.ext == ext && $0.target == target })
        #expect(pair.listed == listed)
    }

    @Test("the probe space is the full cross product and covers the overlay")
    func probeSpace() {
        let extensions = Set(Self.pairs.map(\.ext))
        let targets = Set(Self.pairs.map(\.target))
        #expect(extensions == Set(Self.vocabularyExtensions))
        #expect(targets == Set(Self.vocabularyTargets))
        #expect(Self.pairs.count == extensions.count * targets.count)
        #expect(Self.pairs.filter(\.listed).count == 24)
        // `tex` is a target only through the `macdoc pdf` pipeline, never `convert`.
        #expect(Self.pairs.first { $0.ext == "pdf" && $0.target == "tex" }?.listed == false)
        // Styled routes get a style they accept.
        #expect(Self.pairs.first { $0.ext == "srt" && $0.target == "html" }?.style == "dark")
    }
}
