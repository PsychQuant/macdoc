// MacDoc+Word+Form.swift — `macdoc word form classify|apply` (macdoc#249,
// change docx-form-normalization).
//
// Form normalization runs on a rendered .docx, after `macdoc word render`:
// the script's byte-equal verification is about the template, and these
// operations are explicit follow-ups that make a filled form uniform. All
// edits are string-level edits of word/document.xml (DocxForm); every other
// part is copied unchanged and a failure leaves the output path untouched.

import ArgumentParser
import DocxForm
import Foundation

extension MacDoc.Word {
    struct Form: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "form",
            abstract: "表單整理：依段落類型分類，統一填寫欄格式",
            subcommands: [Classify.self, Apply.self]
        )
    }
}

/// Runtime failure of a form command: printed as `Error: <message>` without
/// the usage text, exit code 1.
/// A command failure. Messages quote names taken from the file (tag names,
/// zip entry paths), so they are sanitized like the classify preview.
struct FormCommandError: Error, CustomStringConvertible {
    let description: String

    init(description: String) {
        self.description = TerminalText.sanitize(description)
    }
}

/// Replaces every control character (Cc), the line and paragraph separators
/// and the bidirectional formatting characters with a space, so text from a
/// document can neither drive nor reorder the terminal.
enum TerminalText {
    static let bidiControls: Set<Unicode.Scalar> = [
        "\u{061C}", "\u{200E}", "\u{200F}", "\u{202A}", "\u{202B}", "\u{202C}", "\u{202D}", "\u{202E}",
        "\u{2066}", "\u{2067}", "\u{2068}", "\u{2069}",
    ]

    static func sanitize(_ text: String) -> String {
        let scalars = text.unicodeScalars.map { scalar -> Unicode.Scalar in
            switch scalar.properties.generalCategory {
            case .control, .lineSeparator, .paragraphSeparator: return " "
            default: return bidiControls.contains(scalar) ? " " : scalar
            }
        }
        return String(String.UnicodeScalarView(scalars))
    }
}

extension MacDoc.Word.Form {
    struct Classify: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "classify",
            abstract: "列出帶 w14:paraId 的段落與類型（list-checkbox / checkbox-line / table-field / body）"
        )

        @Argument(help: "輸入的 .docx 檔案")
        var input: String

        func run() throws {
            let inputURL = try validatedInputURL(input)
            do {
                let entries = try DocxPackage.read(from: inputURL)
                guard let document = entries.first(where: { $0.path == DocxPackage.documentPart }) else {
                    throw DocxPackageError.missingPart(DocxPackage.documentPart)
                }
                let numbering = entries.first { $0.path == DocxPackage.numberingPart }
                if let numbering, !FormClassifier.isReadableNumbering(Array(numbering.data)) {
                    FileHandle.standardError.write(Data(
                        "note: \(DocxPackage.numberingPart) 無法解析，略過 list-checkbox 判定\n".utf8))
                }
                let paragraphs = try FormClassifier.classify(documentXML: Array(document.data),
                                                             numberingXML: numbering.map { Array($0.data) })
                // A w14:paraId is eight hexadecimal digits. Any other value comes
                // from a damaged or crafted file; printing it could inject
                // terminal sequences or fake columns, so such rows are counted.
                var skipped = 0
                for paragraph in paragraphs {
                    guard Self.isParaId(paragraph.paraId) else { skipped += 1; continue }
                    print("\(paragraph.paraId)\t\(paragraph.kind.rawValue)\t\(Self.preview(paragraph.text))")
                }
                if skipped > 0 {
                    FileHandle.standardError.write(Data(
                        "note: 略過 \(skipped) 個 w14:paraId 不是 8 位十六進位的段落\n".utf8))
                }
            } catch let error as DocxPackageError {
                throw FormCommandError(description: error.description)
            } catch let error as XMLScanError {
                throw FormCommandError(description: FormError.malformedPart(error.description).description)
            }
        }

        /// True for exactly eight ASCII hexadecimal digits.
        static func isParaId(_ id: String) -> Bool {
            id.utf8.count == 8 && id.utf8.allSatisfy {
                (0x30...0x39).contains($0) || (0x41...0x46).contains($0) || (0x61...0x66).contains($0)
            }
        }

        /// First 30 characters with every control character (tab, line
        /// breaks, ESC and the rest of C0/C1), the line and paragraph
        /// separators and the bidirectional formatting characters replaced by
        /// a space, so document text cannot drive or reorder the terminal.
        static func preview(_ text: String) -> String {
            TerminalText.sanitize(String(text.prefix(30)))
        }
    }

    struct Apply: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "apply",
            abstract: "整理已填寫的表單：統一填寫欄、方框字型、清單勾選、插入、移除、截斷"
        )

        @Argument(help: "輸入的 .docx 檔案")
        var input: String

        @Option(name: .customLong("to-docx"), help: "輸出的 .docx 路徑")
        var toDocx: String

        @Flag(help: "覆寫既有的輸出檔案")
        var force = false

        @Option(name: .customLong("field"),
                help: ArgumentHelp("表格填寫欄（可重複）：統一字級、靠左、垂直置中，去掉樣式、縮排與同格空段落",
                                   valueName: "paraId"))
        var fields: [String] = []

        @Option(name: .customLong("field-size"),
                help: ArgumentHelp("填寫欄字級（pt，0.5 為單位）；省略時取指定欄位字級的眾數，同票取大",
                                   valueName: "pt"))
        var fieldSize: String?

        @Option(name: .customLong("checkbox-font"),
                help: ArgumentHelp("本文（word/document.xml）的方框字元（□ ■ ☐ ☑ ☒）改用同一字型，字級不變；頁首、頁尾、註腳不處理", valueName: "font"))
        var checkboxFont: String?

        @Option(name: .customLong("tick-list"),
                help: ArgumentHelp("勾選以方框為清單符號的段落（可重複）：拿掉清單編號，前面加 ■",
                                   valueName: "paraId"))
        var tickList: [String] = []

        @Option(name: .customLong("insert-after"),
                help: ArgumentHelp("在段落後插入一段文字，沿用錨點的段落與文字格式（可重複，同一錨點依序接續）；錨點帶分節符時，分節符移到最後插入的段落",
                                   valueName: "paraId=text"))
        var insertAfter: [String] = []

        @Option(name: .customLong("remove"),
                help: ArgumentHelp("移除段落（可重複）；帶分節符的段落、儲存格或文字方塊唯一的段落、刪掉後儲存格會以表格結尾的段落會拒絕（穿過內容控制項計算，同一格要刪的幾段合起來判斷），會拆開欄位或讓註解失去引用時也拒絕；另一半不在這次要刪的範圍裡的書籤等範圍標記留下",
                                   valueName: "paraId"))
        var remove: [String] = []

        @Option(name: .customLong("truncate-from"),
                help: ArgumentHelp("從本文的這一段刪到結尾；保留內容的最後一個區塊是自帶分節符的段落時沿用它，否則沿用被刪範圍第一個分節設定；會拆開欄位或讓註解失去引用時拒絕，另一半保留的書籤等範圍標記移到保留內容的結尾", valueName: "paraId"))
        var truncateFrom: String?

        func validate() throws {
            let plan = try makePlan()
            guard plan.hasOperations else {
                throw ValidationError(
                    "至少要指定一個操作：--field、--checkbox-font、--tick-list、--insert-after、--remove 或 --truncate-from")
            }
            if fieldSize != nil, fields.isEmpty {
                throw ValidationError("--field-size 需要搭配 --field")
            }
        }

        func makePlan() throws -> FormPlan {
            var insertions: [FormInsertion] = []
            for raw in insertAfter {
                let pieces = raw.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard pieces.count == 2, !pieces[0].isEmpty else {
                    throw ValidationError("無效的 --insert-after: \(raw)（格式為 <paraId>=<文字>）")
                }
                insertions.append(FormInsertion(anchor: String(pieces[0]), text: String(pieces[1])))
            }
            let size: FieldSize?
            do {
                size = try fieldSize.map { try FieldSize.parse(points: $0) }
            } catch let error as FormError {
                throw ValidationError(error.description)
            }
            return FormPlan(fields: fields, fieldSize: size, checkboxFont: checkboxFont, tickList: tickList,
                            insertions: insertions, removals: remove, truncateFrom: truncateFrom)
        }

        func run() throws {
            let inputURL = try validatedInputURL(input)
            let outputURL = URL(fileURLWithPath: toDocx)
            let plan = try makePlan()
            var outcome: FormResult?
            do {
                try DocxPackage.rewriteDocument(input: inputURL, output: outputURL, force: force) { document, _ in
                    let result = try plan.apply(toDocumentXML: Array(document))
                    outcome = result
                    return Data(result.documentXML)
                }
            } catch let error as FormError {
                throw FormCommandError(description: error.description)
            } catch let error as DocxPackageError {
                throw FormCommandError(description: error.description)
            } catch let error as XMLScanError {
                throw FormCommandError(description: FormError.malformedPart(error.description).description)
            }
            if let outcome {
                if let size = outcome.fieldSize, outcome.fieldSizeWasDerived {
                    FileHandle.standardError.write(Data(
                        "填寫欄字級：\(size.pointsDescription)（取指定欄位字級的眾數；可用 --field-size 指定）\n".utf8))
                }
                if outcome.skippedCheckboxRuns > 0 {
                    FileHandle.standardError.write(Data(
                        "note: 有 \(outcome.skippedCheckboxRuns) 個含方框字元的 run 未改字型（另含其他內容、需要拆開但帶格式修訂，或在原生核取方塊內容控制項裡）\n".utf8))
                }
                for skip in outcome.skippedCleanups {
                    FileHandle.standardError.write(Data(Self.cleanupNote(skip).utf8))
                }
            }
            FileHandle.standardError.write(Data("已寫入: \(toDocx)\n".utf8))
        }

        /// One stderr line per `--field` whose cell cleanup was skipped (#253).
        static func cleanupNote(_ skip: CleanupSkip) -> String {
            let names = skip.reasons.map { reason -> String in
                switch reason {
                case .nestedTable: return "巢狀表格（w:tbl）"
                case .contentControl: return "內容控制項（w:sdt）"
                case .customXML: return "自訂 XML（w:customXml）"
                }
            }
            return "note: --field \(TerminalText.sanitize(skip.paragraphId)) 所在的儲存格含"
                + names.joined(separator: "、") + "，依規格不清除同格的空段落\n"
        }
    }
}

/// `word reverse --slot` follow-up notes (macdoc#249): one stderr line per
/// slot whose kind needs a `word form apply` option, nothing for body slots.
enum SlotFollowUp {
    static func notes(for designations: [(name: String, paraId: String)], parts: [String: Data]) -> [String] {
        guard !designations.isEmpty, let document = parts[DocxPackage.documentPart] else { return [] }
        let numbering = parts[DocxPackage.numberingPart].map { Array($0) }
        guard let kinds = try? FormClassifier.kinds(of: designations.map(\.paraId),
                                                    documentXML: Array(document), numberingXML: numbering) else {
            return []
        }
        // Same degradation as classify, and said the same way: a list
        // checkbox slot would otherwise lose its note without a trace.
        let numberingNote = numbering.map { FormClassifier.isReadableNumbering($0) } == false
            ? ["note: \(DocxPackage.numberingPart) 無法解析，略過 list-checkbox 判定"] : []
        return numberingNote + designations.compactMap { slot in
            guard let kind = kinds[slot.paraId], let option = option(for: kind, paraId: slot.paraId) else { return nil }
            return "note: slot「\(slot.name)」（\(slot.paraId)）是 \(kind.rawValue)；render 之後可用 macdoc word form apply \(option) 整理格式"
        }
    }

    static func option(for kind: ParagraphKind, paraId: String) -> String? {
        switch kind {
        case .tableField: return "--field \(paraId)"
        case .checkboxLine: return "--checkbox-font <字型>"
        case .listCheckbox: return "--tick-list \(paraId)"
        case .body: return nil
        }
    }
}
