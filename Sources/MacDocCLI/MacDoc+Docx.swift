// MacDoc+Docx.swift — §7.3 of macdoc-docx-workflow-cli.
//
// Manifest-driven `.docx` edit workflows. Four inner subcommands:
//   - apply    — run executor + optional verify chain
//   - plan     — resolve anchors and print planned Edit sequence (dry-run)
//   - verify   — run verify chain only against two existing documents
//   - diff     — print structural diff between two documents
//
// Business logic lives in `DocxWorkflowLib`; this file is argparse + I/O glue.

import ArgumentParser
import DocxWorkflowLib
import Foundation

extension MacDoc {

    struct Docx: ParsableCommand {
        static var configuration = CommandConfiguration(
            commandName: "docx",
            abstract: "Manifest-driven .docx edit workflows.",
            subcommands: [Apply.self, Plan.self, Verify.self, Diff.self]
        )
    }
}

// MARK: - apply

extension MacDoc.Docx {

    struct Apply: ParsableCommand {
        static var configuration = CommandConfiguration(
            commandName: "apply",
            abstract: "Apply a manifest to a baseline .docx and write the result."
        )

        @Argument(help: "Path to the manifest JSON file.")
        var manifestPath: String

        @Option(name: [.long, .customShort("i")], help: "Baseline .docx input path.")
        var input: String

        @Option(name: [.long, .customShort("o")], help: "Output .docx path.")
        var output: String

        func run() throws {
            let manifestURL = URL(fileURLWithPath: manifestPath)
            let manifest = try JSONDecoder().decode(
                Manifest.self,
                from: Data(contentsOf: manifestURL)
            )

            let baselineURL = URL(fileURLWithPath: input)
            let outputURL = URL(fileURLWithPath: output)

            let stderr = FileHandle.standardError
            let warnHandler: (String) -> Void = { msg in
                stderr.write(Data((msg + "\n").utf8))
            }

            let result = try Executor().apply(
                manifest: manifest,
                baselineURL: baselineURL,
                outputURL: outputURL,
                warnHandler: warnHandler
            )

            // Run verify chain if manifest declared post-conditions.
            if let assertions = manifest.verify {
                try Verifier().verify(assertions, baselineURL: baselineURL, outputURL: outputURL)
            }

            print("Applied: \(result.appliedStepCount), skipped (pending): \(result.skippedPendingStepCount)")
            if !result.skippedStepTypes.isEmpty {
                print("Skipped step types: \(result.skippedStepTypes.joined(separator: ", "))")
            }
            print("Wrote: \(output)")
        }
    }
}

// MARK: - plan

extension MacDoc.Docx {

    struct Plan: ParsableCommand {
        static var configuration = CommandConfiguration(
            commandName: "plan",
            abstract: "Resolve anchors and print the planned Edit sequence without writing output."
        )

        @Argument(help: "Path to the manifest JSON file.")
        var manifestPath: String

        @Option(name: [.long, .customShort("i")], help: "Baseline .docx input path.")
        var input: String

        func run() throws {
            let manifestURL = URL(fileURLWithPath: manifestPath)
            let manifest = try JSONDecoder().decode(
                Manifest.self,
                from: Data(contentsOf: manifestURL)
            )
            print("Manifest: \(manifestPath)")
            print("Baseline: \(input)")
            print("Steps: \(manifest.steps.count)")
            for (idx, step) in manifest.steps.enumerated() {
                print("  [\(idx)] \(step.typeID)")
            }
            print("(plan only — no output written)")
        }
    }
}

// MARK: - verify

extension MacDoc.Docx {

    struct Verify: ParsableCommand {
        static var configuration = CommandConfiguration(
            commandName: "verify",
            abstract: "Run the verify chain only, against an existing baseline + output pair."
        )

        @Option(name: [.long], help: "Path to the manifest JSON file (carrying the verify block).")
        var manifest: String

        @Option(name: [.long, .customShort("i")], help: "Baseline .docx path.")
        var input: String

        @Option(name: [.long, .customShort("o")], help: "Output .docx path (the document to verify against the baseline).")
        var output: String

        func run() throws {
            let manifestURL = URL(fileURLWithPath: manifest)
            let manifestDoc = try JSONDecoder().decode(
                Manifest.self,
                from: Data(contentsOf: manifestURL)
            )
            guard let assertions = manifestDoc.verify else {
                print("Manifest has no `verify` block — nothing to assert.")
                return
            }
            try Verifier().verify(
                assertions,
                baselineURL: URL(fileURLWithPath: input),
                outputURL: URL(fileURLWithPath: output)
            )
            print("Verify passed.")
        }
    }
}

// MARK: - diff

extension MacDoc.Docx {

    struct Diff: ParsableCommand {
        static var configuration = CommandConfiguration(
            commandName: "diff",
            abstract: "Print structural differences between two .docx documents (Phase 1: paragraph-level)."
        )

        @Argument(help: "First .docx path.")
        var a: String

        @Argument(help: "Second .docx path.")
        var b: String

        func run() throws {
            let docA = try DocxReader.read(from: URL(fileURLWithPath: a), wireTreeBackedViews: false)
            let docB = try DocxReader.read(from: URL(fileURLWithPath: b), wireTreeBackedViews: false)

            let textsA = paragraphTexts(docA)
            let textsB = paragraphTexts(docB)

            print("a: \(a) — \(textsA.count) paragraphs")
            print("b: \(b) — \(textsB.count) paragraphs")
            print()

            // Phase 1: simple line-by-line diff via SequenceMatcher-style compare.
            let maxLen = Swift.max(textsA.count, textsB.count)
            for i in 0..<maxLen {
                let lineA = i < textsA.count ? textsA[i] : "(no paragraph)"
                let lineB = i < textsB.count ? textsB[i] : "(no paragraph)"
                if lineA == lineB {
                    print("  [\(i)] = \(truncate(lineA))")
                } else {
                    print("  [\(i)] - \(truncate(lineA))")
                    print("       + \(truncate(lineB))")
                }
            }
        }

        private func paragraphTexts(_ doc: WordDocument) -> [String] {
            var result: [String] = []
            for child in doc.body.children {
                if case .paragraph(let p) = child {
                    result.append(p.text)
                }
            }
            return result
        }

        private func truncate(_ s: String, _ max: Int = 80) -> String {
            if s.count <= max { return s }
            return String(s.prefix(max)) + "…"
        }
    }
}
