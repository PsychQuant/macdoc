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
        let listed: Bool

        var testDescription: String { "(\(ext), \(target)) \(listed ? "listed" : "unlisted")" }
    }

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
        var listed = Set<String>()
        for route in routes {
            for ext in route.from {
                if !extensions.contains(ext) { extensions.append(ext) }
                listed.insert(ext + "→" + route.to)
            }
            if !targets.contains(route.to) { targets.append(route.to) }
        }
        extensions += vocabularyExtensions.filter { !extensions.contains($0) }
        targets += vocabularyTargets.filter { !targets.contains($0) }
        return extensions.flatMap { ext in
            targets.map { ProbePair(ext: ext, target: $0, listed: listed.contains(ext + "→" + $0)) }
        }
    }()

    @Test("every extension/target pair dispatches exactly as the overlay says", arguments: pairs)
    func probe(pair: ProbePair) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("macdoc-cli-spec-probe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let input = directory.appendingPathComponent("probe.\(pair.ext)")
        try Data().write(to: input)
        let output = directory.appendingPathComponent("out.\(pair.target)")

        // PATH without Homebrew / pip locations: the HTML → PDF route must
        // stop at "playwright not found" instead of launching Chromium.
        let result = try CLITestHelper.run(
            ["convert", "--to", pair.target, "--output", output.path, input.path],
            environment: ["PATH": "/usr/bin:/bin"]
        )

        let rejection = "不支援從 .\(pair.ext) 轉換到 \(pair.target)"
        if pair.listed {
            #expect(!result.stderr.contains("不支援從"),
                    "overlay lists \(pair.ext) → \(pair.target) but the binary rejects it: \(result.stderr)")
        } else {
            #expect(result.exitCode != 0)
            #expect(result.stderr.contains(rejection),
                    "the binary dispatches \(pair.ext) → \(pair.target) but the overlay does not list it: \(result.stderr)")
        }
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
    func examplePairs(ext: String, target: String, listed: Bool) {
        #expect(Self.pairs.contains(ProbePair(ext: ext, target: target, listed: listed)))
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
        #expect(Self.pairs.contains(ProbePair(ext: "pdf", target: "tex", listed: false)))
    }
}
