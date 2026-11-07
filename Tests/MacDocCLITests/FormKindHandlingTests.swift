// FormKindHandlingTests.swift — one place for "paragraph kind → word form
// apply option" (macdoc#255): the `word reverse --slot` hints take it from
// `ParagraphKind.applyOption`, and the swiftify skill's kind table must list
// the same option for every kind.

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

    func testSlotHintsTakeTheOptionFromTheMapping() {
        for kind in ParagraphKind.allCases {
            XCTAssertEqual(SlotFollowUp.option(for: kind, paraId: "0000A001"),
                           kind.applyOption?.usage(paraId: "0000A001"), kind.rawValue)
        }
        XCTAssertEqual(ParagraphKind.tableField.applyOption?.usage(paraId: "0000A001"), "--field 0000A001")
        XCTAssertEqual(ParagraphKind.checkboxLine.applyOption?.usage(paraId: "0000A001"), "--checkbox-font <字型>")
    }

    /// The swiftify skill routes each kind to an option in a table. Every kind
    /// has a row, and a kind with an apply option names exactly that option
    /// first, so adding a kind or changing an option without the table fails here.
    func testSwiftifyKindTableMatchesTheMapping() throws {
        let url = CLITestHelper.repoRoot.appendingPathComponent("plugins/macdoc/skills/swiftify/SKILL.md")
        let text = try String(contentsOf: url, encoding: .utf8)
        var rows: [String: String] = [:]
        for line in text.split(separator: "\n") where line.hasPrefix("| `") {
            let cells = line.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            guard cells.count >= 4, cells[1].hasPrefix("`"), cells[1].hasSuffix("`") else { continue }
            rows[String(cells[1].dropFirst().dropLast())] = cells[3]
        }
        for kind in ParagraphKind.allCases {
            guard let option = rows[kind.rawValue] else { XCTFail("swiftify table has no row for \(kind.rawValue)"); continue }
            if let handling = kind.applyOption {
                XCTAssertTrue(option.hasPrefix("`\(handling.usage(paraId: "<paraId>"))`"), "\(kind.rawValue): \(option)")
            }
        }
    }
}
