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
            abstract: "Apply a manifest to a baseline .docx and write the result through the certified transaction."
        )

        @Argument(help: "Path to the manifest JSON file.")
        var manifestPath: String

        @Option(name: [.long, .customShort("i")], help: "Baseline .docx input path.")
        var input: String

        @Option(name: [.long, .customShort("o")], help: "Output .docx path.")
        var output: String

        @Option(name: [.long], help: "Optional path to write the Layer 1 certification certificate (JSON), on success and on failure.")
        var certificate: String?

        // macdoc#137 Layer 1 (docx-mutation-certification-layer1): `apply`
        // commits its output only through `CertifiedTransaction`, never by
        // any other route. A gate/verify/baseline-changed/intent failure
        // leaves the output path exactly as it was; the failure kind and
        // (when there is one) the rejected-candidate path are reported on
        // stderr per the repo's error-and-output convention (Traditional
        // Chinese status/error text). This is presentation glue, not
        // business logic — the transaction itself lives in DocxWorkflowLib.
        func run() throws {
            let stderr = FileHandle.standardError
            let warnHandler: (String) -> Void = { msg in
                stderr.write(Data((msg + "\n").utf8))
            }

            // R2 review Finding 1 (CRITICAL): a certificate-write failure
            // must never overwrite the transaction's own success/failure
            // signal. `certificateWarnHandler` captures it separately so
            // the exit code and message below reflect the ACTUAL
            // transaction outcome, plus this warning when there is one.
            var certificateWriteWarning: String?
            let certificateWarnHandler: (String) -> Void = { msg in certificateWriteWarning = msg }

            do {
                // Manifest decoding and baseline/output URL construction are
                // inside this `do` block (R2 review L5): any failure here —
                // a missing manifest file, malformed JSON, an unreadable
                // baseline — is not a `CertificationError` (the transaction
                // never even started), but must still surface through the
                // repo's Traditional Chinese "錯誤：" convention rather than
                // ArgumentParser's default English top-level printer.
                let manifestURL = URL(fileURLWithPath: manifestPath)
                let manifest = try JSONDecoder().decode(
                    Manifest.self,
                    from: Data(contentsOf: manifestURL)
                )
                let baselineURL = URL(fileURLWithPath: input)
                let outputURL = URL(fileURLWithPath: output)
                let certificateURL = certificate.map { URL(fileURLWithPath: $0) }

                _ = try CertifiedTransaction().apply(
                    manifest: manifest,
                    baselineURL: baselineURL,
                    outputURL: outputURL,
                    certificateURL: certificateURL,
                    warnHandler: warnHandler,
                    certificateWarnHandler: certificateWarnHandler
                )
                stderr.write(Data("已寫入: \(output)\n".utf8))
            } catch let error as CertificationError {
                Self.reportCertificationFailure(error, to: stderr)
                if let certificateWriteWarning {
                    stderr.write(Data("警告：\(certificateWriteWarning)\n".utf8))
                }
                throw ExitCode.failure
            } catch {
                // L5（R2 review）：非 CertificationError 的失敗（例如
                // Executor 內既有的 reducer 錯誤、manifest／baseline 讀取
                // 失敗）維持繁體中文「錯誤：」前綴，不讓 ArgumentParser
                // 預設的英文頂層錯誤印出格式蓋過本 repo 的訊息慣例。這不
                // 修復任何底層錯誤本身（例如 set_bold 的 macdoc#232），
                // 只統一 CLI 呈現層的語言前綴。
                stderr.write(Data("錯誤：套用 manifest 時發生非預期錯誤：\(error)\n".utf8))
                throw ExitCode.failure
            }

            if let certificateWriteWarning {
                stderr.write(Data(
                    "警告：\(certificateWriteWarning)；輸出檔本身有效，但 --certificate 指定的檔案不存在或內容不可信，請確認路徑後重跑。\n".utf8
                ))
                throw ExitCode.failure
            }
        }

        private static func reportCertificationFailure(_ error: CertificationError, to stderr: FileHandle) {
            func writeLine(_ line: String) {
                stderr.write(Data((line + "\n").utf8))
            }
            func reportRejectedCandidate(_ certificate: CertificationCertificate) {
                if let rejected = certificate.rejectedCandidateURL {
                    writeLine("已保留候選檔（供診斷）: \(rejected)")
                }
            }
            switch error {
            case .intentUnavailable(let stepType):
                writeLine("錯誤：manifest 內的 step type「\(stepType)」不在允許變更 part 的封閉對照表中，交易已中止（未建立候選檔）。")
            case .gateFailed(let certificate):
                writeLine("錯誤：Layer 1 驗證失敗（package 完整性或位元組保留檢查未通過），輸出檔未變更：")
                for violation in certificate.layer1.violations {
                    writeLine("  - \(violation)")
                }
                reportRejectedCandidate(certificate)
            case .verifyFailed(let verifyError, let certificate):
                writeLine("錯誤：manifest 的 verify 斷言驗證失敗，輸出檔未變更：\(verifyError)")
                reportRejectedCandidate(certificate)
            case .baselineChanged(let certificate):
                writeLine("錯誤：baseline 檔案在交易過程中被改動，已中止（TOCTOU 防護），輸出檔未變更。")
                reportRejectedCandidate(certificate)
            case .outputPathIsDirectory(let path):
                writeLine("錯誤：輸出路徑「\(path)」已經是一個既有目錄，拒絕覆寫；未做任何寫入。")
            case .certificateDestinationInvalid(let path, let reason):
                writeLine("錯誤：--certificate 指定的路徑「\(path)」無效（\(reason)），交易未開始，輸出檔與 baseline 皆未變更。")
            }
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
