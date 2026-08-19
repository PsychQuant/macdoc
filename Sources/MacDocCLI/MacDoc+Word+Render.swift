// MacDoc+Word+Render.swift
// Spectra change `script-pipeline-surface` tasks 2.1–2.4 —
// `mdocx-grammar` «Render command rebuilds a document from a script».
//
// The CLI half of the script pipeline. `word reverse` lifts a docx into an
// `.mdocx.swift` rebuild script; `word render` replays that script back
// into a docx. Both this command and che-word-mcp's `execute_script` call
// the SAME shared entry point (`scriptPipelineExecute` in OOXMLSwift's
// Transcode module), which is what makes the two faces agree by
// construction rather than by convention.
//
// The command is named `render` because `mdocx-grammar` already named it
// while specifying extension dispatch; the MCP face keeps `execute_script`
// because that name is part of a published tool schema.

import ArgumentParser
import Foundation
import OOXMLSwift

extension MacDoc.Word {
    struct Render: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "render",
            abstract: "執行 .mdocx.swift 腳本重建 docx")

        @Argument(help: "輸入的 .mdocx.swift（或 .mdocx）腳本")
        var input: String

        @Option(name: .customLong("to-docx"), help: "輸出的 .docx 路徑")
        var toDocx: String

        // Verification is opt-in: absence of a verdict must never be
        // readable as a passing one, so we only verify when the caller
        // names something to verify against.
        @Option(name: .customLong("verify-against"),
                help: "參考 .docx；提供時對重建的 XML part set 做 byte-equal 驗證")
        var verifyAgainst: String?

        @Flag(help: "覆寫既有的輸出檔案")
        var force = false

        func run() throws {
            let inputURL = try validatedInputURL(input)
            let outputURL = URL(fileURLWithPath: toDocx)

            guard !FileManager.default.fileExists(atPath: outputURL.path) || force else {
                throw ValidationError("輸出檔案已存在: \(toDocx)（使用 --force 覆寫）")
            }

            // The shared entry point pins the reference BEFORE writing, so a
            // missing reference is surfaced without a write side effect and
            // `--to-docx` == `--verify-against` compares against pre-write
            // bytes instead of this run's own output.
            let result: ScriptExecuteResult
            do {
                result = try scriptPipelineExecute(
                    scriptPath: inputURL.path,
                    outputPath: outputURL.path,
                    verifyAgainst: verifyAgainst)
            } catch let error as TranscodeError {
                throw ValidationError(Self.describe(error))
            } catch let error as ScriptPipelineError {
                throw ValidationError(error.errorDescription ?? "\(error)")
            }

            FileHandle.standardError.write(Data("已寫入: \(result.written)\n".utf8))

            guard let verified = result.verified else { return }
            if verified {
                FileHandle.standardError.write(Data("byte-equal 驗證通過\n".utf8))
            } else {
                throw ValidationError(
                    "byte-equal 驗證失敗，以下 part 與參考檔不符:\n"
                        + result.brokenParts.map { "  \($0)" }.joined(separator: "\n"))
            }
        }

        /// TranscodeError is not LocalizedError — without this the location
        /// information the transcoder worked to produce is thrown away.
        private static func describe(_ error: TranscodeError) -> String {
            switch error {
            case .unsupportedSyntax(let line, let column, let reason):
                return "腳本解析失敗（line \(line), column \(column)）: \(reason)"
            case .malformedRawOp(let line, let reason):
                return "raw op 解析失敗（line \(line)）: \(reason)"
            case .slotDesignationFailure(let name, let reason):
                return "slot「\(name)」無法建立: \(reason)"
            }
        }
    }
}
