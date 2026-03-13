import Foundation
import XCTest
@testable import SRTToHTMLSwift

final class SRTConverterTests: XCTestCase {
    func testBasicConversion() throws {
        let url = try temporaryFile(named: "basic.srt", contents: """
        1
        00:00:00,000 --> 00:00:02,500
        Hello world
        """)

        let html = try SRTConverter().convertToString(input: url)

        XCTAssertTrue(html.contains("<!DOCTYPE html>"))
        XCTAssertTrue(html.contains("<div class=\"subtitle\" data-index=\"1\">"))
        XCTAssertTrue(html.contains("<div class=\"timestamp\">00:00:00,000 --> 00:00:02,500</div>") || html.contains("<div class=\"timestamp\">00:00:00,000 --&gt; 00:00:02,500</div>"))
        XCTAssertTrue(html.contains("<div class=\"text\">Hello world</div>"))
    }

    func testMultipleSubtitles() throws {
        let url = try temporaryFile(named: "multi.srt", contents: """
        1
        00:00:00,000 --> 00:00:02,500
        First line
        Second line

        2
        00:00:03,000 --> 00:00:04,000
        Another subtitle
        """)

        let html = try SRTConverter().convertToString(input: url)

        XCTAssertEqual(html.components(separatedBy: "<div class=\"subtitle\"").count - 1, 2)
        XCTAssertTrue(html.contains("First line<br />Second line"))
        XCTAssertTrue(html.contains("Another subtitle"))
    }

    func testEmptyInput() throws {
        let url = try temporaryFile(named: "empty.srt", contents: "")

        let html = try SRTConverter().convertToString(input: url)

        XCTAssertTrue(html.contains("<!DOCTYPE html>"))
        XCTAssertFalse(html.contains("<div class=\"subtitle\""))
    }

    private func temporaryFile(named name: String, contents: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent(name)
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }
}
