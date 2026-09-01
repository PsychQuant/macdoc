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
                help: "參考 .docx；提供時對重建的 part set 做 byte-equal 驗證（含 binary part）")
        var verifyAgainst: String?

        @Flag(help: "覆寫既有的輸出檔案")
        var force = false

        func run() throws {
            let inputURL = try validatedInputURL(input)
            let outputURL = URL(fileURLWithPath: toDocx)

            // No overwrite check here on purpose. The gate lives in the
            // shared entry point, so the MCP face inherits it; a copy here
            // would rebuild exactly the defect that left that face
            // unprotected while this one had --force.
            //
            // The shared entry point also pins the reference BEFORE writing,
            // and stages the rebuild beside the output so nothing is
            // published until the verdict is known.
            let result: ScriptExecuteResult
            do {
                result = try scriptPipelineExecute(
                    scriptPath: inputURL.path,
                    outputPath: outputURL.path,
                    verifyAgainst: verifyAgainst,
                    overwrite: force)
            } catch let error as TranscodeError {
                throw ValidationError(Self.describe(error))
            } catch ScriptPipelineError.outputExists(let path) {
                // The library deliberately carries no advice about HOW to
                // permit overwriting, because the answer differs per face.
                // This is where the CLI's answer belongs.
                throw ValidationError("輸出檔案已存在: \(path)（使用 --force 覆寫）")
            } catch let error as ScriptPipelineError {
                throw ValidationError(error.errorDescription ?? "\(error)")
            }

            // Verdict BEFORE the announcement. Announcing the write first and
            // failing afterwards told the operator a document had been
            // written — over one that had in fact just been destroyed.
            if result.verified == false {
                throw ValidationError(
                    "byte-equal 驗證失敗，未寫出任何檔案。以下 part 與參考檔不符:\n"
                        + result.brokenParts.map { "  \($0)" }.joined(separator: "\n"))
            }
            if let written = result.written {
                // Unwrapped: interpolating the optional directly still
                // compiles and prints `Optional("…")` at the operator.
                FileHandle.standardError.write(Data("已寫入: \(written)\n".utf8))
            }
            if result.verified == true {
                // Name the scope. "byte-equal 驗證通過" on its own invites the
                // reader to `ls -la` the two files, find different sizes, and
                // doubt the tool — the comparison is per part, and the zip
                // container (entry order, compression, timestamps) never
                // enters it.
                //
                // Counting the reference is exact on this path, not an
                // approximation: compareParts walks the union of both part
                // sets, and a path present in only one side yields
                // .missingInRebuilt / .unexpectedInRebuilt — neither is
                // .equal, so it would have failed the verdict we just passed.
                // Union size therefore equals reference size here.
                var scope = "zip 容器大小可能不同"
                if let reference = verifyAgainst,
                   let count = try? RawPartChannel
                       .readAllParts(from: URL(fileURLWithPath: reference)).count {
                    scope = "\(count) 個 part 逐位元組相同；" + scope
                }
                FileHandle.standardError.write(
                    Data("byte-equal 驗證通過（\(scope)）\n".utf8))
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
