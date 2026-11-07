// FormKindHandlingTests.swift — one place for "paragraph kind → word form
// apply option" (macdoc#255): the `word reverse --slot` hints are built from
// `ParagraphKind.applyOption`, and the swiftify skill's kind table must agree
// with it row by row.

import Foundation
import XCTest
import DocxForm
@testable import MacDocCLI

final class FormKindHandlingTests: XCTestCase {
    func testEachKindNamesItsApplyOption() {
        XCTAssertEqual(ParagraphKind.tableField.applyOption, ApplyOption(flag: "--field", argument: .paraId))
        XCTAssertEqual(ParagraphKind.checkboxLine.applyOption, ApplyOption(flag: "--checkbox-font", argument: .placeholder("<字型>")))
        XCTAssertEqual(ParagraphKind.listCheckbox.applyOption, ApplyOption(flag: "--tick-list", argument: .paraId))
        XCTAssertNil(ParagraphKind.body.applyOption)
    }

    /// The hint strings are the ones `word reverse --slot` printed before the
    /// mapping existed; the output does not change.
    func testSlotHintsAreUnchanged() {
        let expected: [ParagraphKind: String?] = [
            .tableField: "--field 0000A001", .checkboxLine: "--checkbox-font <字型>",
            .listCheckbox: "--tick-list 0000A001", .body: nil,
        ]
        XCTAssertEqual(Set(expected.keys), Set(ParagraphKind.allCases))
        for (kind, hint) in expected {
            XCTAssertEqual(SlotFollowUp.option(for: kind, paraId: "0000A001"), hint, kind.rawValue)
        }
    }

    /// The swiftify skill's routing table (the one after 「依段落類型分流」):
    /// exactly one row per kind and no row for an unknown kind; a kind with an
    /// apply option names that option first, a kind without one names none of
    /// the kinds' tidy flags.
    func testSwiftifyKindTableMatchesTheMapping() throws {
        let url = CLITestHelper.repoRoot.appendingPathComponent("plugins/macdoc/skills/swiftify/SKILL.md")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return XCTFail("cannot read \(url.path)")
        }
        let lines = text.components(separatedBy: "\n")
        guard let intro = lines.firstIndex(where: { $0.contains("依段落類型分流") }),
              let header = lines[intro...].firstIndex(where: { $0.hasPrefix("| 類型 |") }),
              header + 1 < lines.count, lines[header + 1].hasPrefix("|--") else {
            return XCTFail("routing table (header and separator row) not found in \(url.lastPathComponent)")
        }
        var rows: [String: String] = [:]
        for line in lines[(header + 2)...].prefix(while: { $0.hasPrefix("|") }) {
            let cells = line.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            guard cells.count == 5, cells[1].hasPrefix("`"), cells[1].hasSuffix("`") else {
                XCTFail("malformed routing row: \(line)"); continue
            }
            let kind = String(cells[1].dropFirst().dropLast())
            XCTAssertNil(rows[kind], "duplicate row for \(kind)")
            XCTAssertNotNil(ParagraphKind(rawValue: kind), "row for unknown kind \(kind)")
            rows[kind] = cells[3]
        }
        for kind in ParagraphKind.allCases {
            guard let cell = rows[kind.rawValue] else { XCTFail("no row for \(kind.rawValue)"); continue }
            if let handling = kind.applyOption {
                XCTAssertTrue(cell.hasPrefix("`\(handling.usage(paraId: "<paraId>"))`"), "\(kind.rawValue): \(cell)")
            } else {
                // A kind without a tidy option names none of the kinds' tidy
                // flags (`body` may still mention `--insert-after`).
                for flag in ParagraphKind.allCases.compactMap({ $0.applyOption?.flag }) {
                    XCTAssertFalse(cell.contains("`\(flag)"), "\(kind.rawValue) has no apply option but names \(flag): \(cell)")
                }
            }
        }
    }
}
