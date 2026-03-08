# Phase 2 Consolidation Pipeline Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add AI config system, mechanical LaTeX cleanup commands, and agent-based consolidation to macdoc's pdf-to-latex pipeline.

**Architecture:** Three layers — (1) AIConfig reads/writes `~/.config/macdoc/config.json` with auto-detection of installed CLI tools, (2) three mechanical LaTeX processors (normalize, env-check, compile-check) as pure functions in PDFToLaTeXCore, (3) a Consolidator that orchestrates mechanical + agent steps. All wired into `macdoc pdf` and `macdoc config ai` CLI subcommands.

**Tech Stack:** Swift 5.9+, macOS 14+, swift-argument-parser, PDFToLaTeXCore library, pdflatex CLI

---

## Task 1: AIConfig — Config File Model

**Files:**
- Create: `packages/pdf-to-latex-swift/Sources/PDFToLaTeXCore/AIConfig.swift`
- Test: `packages/pdf-to-latex-swift/Tests/PDFToLaTeXCoreTests/AIConfigTests.swift`

**Step 1: Write the failing test**

```swift
// AIConfigTests.swift
import XCTest
@testable import PDFToLaTeXCore

final class AIConfigTests: XCTestCase {
    func testDefaultConfig() {
        let config = AIConfig()
        XCTAssertEqual(config.available, [])
        XCTAssertEqual(config.transcription, "codex")
        XCTAssertEqual(config.agent, "claude")
    }

    func testEncodeDecodeCycle() throws {
        var config = AIConfig()
        config.available = ["codex", "claude"]
        config.transcription = "codex"
        config.agent = "claude"

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AIConfig.self, from: data)
        XCTAssertEqual(decoded.available, ["codex", "claude"])
        XCTAssertEqual(decoded.transcription, "codex")
        XCTAssertEqual(decoded.agent, "claude")
    }

    func testSaveAndLoad() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        let configURL = tmpDir.appendingPathComponent("config.json")

        var config = AIConfig()
        config.available = ["codex", "gemini"]
        config.transcription = "codex"
        config.agent = "gemini"

        try config.save(to: configURL)
        let loaded = try AIConfig.load(from: configURL)
        XCTAssertEqual(loaded.available, ["codex", "gemini"])
        XCTAssertEqual(loaded.agent, "gemini")
    }

    func testLoadMissingFileReturnsDefault() throws {
        let missing = URL(fileURLWithPath: "/tmp/nonexistent-\(UUID().uuidString).json")
        let config = try AIConfig.load(from: missing)
        XCTAssertEqual(config.transcription, "codex")
        XCTAssertEqual(config.agent, "claude")
    }

    func testDetectReturnsNonEmpty() {
        // detect() runs `which` — on any dev machine at least one tool should exist,
        // but we only check it doesn't crash
        let config = AIConfig.detect()
        XCTAssertNotNil(config)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd /Users/che/Developer/macdoc/packages/pdf-to-latex-swift && swift test --filter AIConfigTests 2>&1 | tail -5`
Expected: Compilation error — `AIConfig` not defined.

**Step 3: Write minimal implementation**

```swift
// AIConfig.swift
import Foundation

/// AI CLI 工具設定（codex / claude / gemini）。
/// 儲存在 ~/.config/macdoc/config.json。
public struct AIConfig: Codable, Sendable, Equatable {
    /// 本機偵測到的 CLI 工具名稱。
    public var available: [String]
    /// 預設用於 one-shot 轉寫的後端。
    public var transcription: String
    /// 預設用於 agentic consolidation 的後端。
    public var agent: String

    public init(
        available: [String] = [],
        transcription: String = "codex",
        agent: String = "claude"
    ) {
        self.available = available
        self.transcription = transcription
        self.agent = agent
    }

    // MARK: - File I/O

    /// 預設設定檔路徑。
    public static var defaultConfigURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/macdoc/config.json")
    }

    /// 從指定路徑載入設定。找不到檔案則回傳預設值。
    public static func load(from url: URL? = nil) throws -> AIConfig {
        let configURL = url ?? defaultConfigURL
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            return AIConfig()
        }
        let data = try Data(contentsOf: configURL)
        return try JSONDecoder().decode(AIConfig.self, from: data)
    }

    /// 儲存到指定路徑。自動建立父目錄。
    public func save(to url: URL? = nil) throws {
        let configURL = url ?? Self.defaultConfigURL
        let dir = configURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: configURL, options: .atomic)
    }

    // MARK: - Detection

    /// 偵測本機安裝了哪些 AI CLI 工具。
    public static func detect() -> AIConfig {
        let tools = ["codex", "claude", "gemini"]
        let found = tools.filter { isInstalled($0) }

        return AIConfig(
            available: found,
            transcription: found.first ?? "codex",
            agent: found.contains("claude") ? "claude" : (found.first ?? "claude")
        )
    }

    /// 檢查 CLI 工具是否已安裝（用 `which`）。
    private static func isInstalled(_ tool: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [tool]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
```

**Step 4: Run test to verify it passes**

Run: `cd /Users/che/Developer/macdoc/packages/pdf-to-latex-swift && swift test --filter AIConfigTests 2>&1 | tail -5`
Expected: All 5 tests PASS.

**Step 5: Commit**

```bash
cd /Users/che/Developer/macdoc
git add packages/pdf-to-latex-swift/Sources/PDFToLaTeXCore/AIConfig.swift \
      packages/pdf-to-latex-swift/Tests/PDFToLaTeXCoreTests/AIConfigTests.swift
git commit -m "feat: add AIConfig for detecting and persisting AI CLI tool preferences"
```

---

## Task 2: LaTeXNormalizer — Mechanical Cleanup

**Files:**
- Create: `packages/pdf-to-latex-swift/Sources/PDFToLaTeXCore/LaTeXNormalizer.swift`
- Test: `packages/pdf-to-latex-swift/Tests/PDFToLaTeXCoreTests/LaTeXNormalizerTests.swift`

**Step 1: Write the failing test**

```swift
// LaTeXNormalizerTests.swift
import XCTest
@testable import PDFToLaTeXCore

final class LaTeXNormalizerTests: XCTestCase {
    func testDocumentClassFix_articleToBook() {
        let input = "\\documentclass{article}\n\\begin{document}\n\\chapter{Intro}\n\\end{document}"
        let result = LaTeXNormalizer().normalize(input)
        XCTAssertTrue(result.contains("\\documentclass{book}"))
        XCTAssertFalse(result.contains("\\documentclass{article}"))
    }

    func testDocumentClassFix_noChapterKeepsArticle() {
        let input = "\\documentclass{article}\n\\begin{document}\n\\section{Intro}\n\\end{document}"
        let result = LaTeXNormalizer().normalize(input)
        XCTAssertTrue(result.contains("\\documentclass{article}"))
    }

    func testSymbolNormalization() {
        let input = "\\bm{x} and \\bm{\\beta}"
        let normalizer = LaTeXNormalizer(symbolRules: ["\\bm{": "\\boldsymbol{"])
        let result = normalizer.normalize(input)
        XCTAssertEqual(result, "\\boldsymbol{x} and \\boldsymbol{\\beta}")
    }

    func testCrossPageDedup() {
        let input = """
        Line A
        Line B
        Line C
        %% === Page 2 ===
        Line B
        Line C
        Line D
        """
        let result = LaTeXNormalizer().normalize(input)
        // "Line B" and "Line C" duplicated at page boundary should be removed once
        XCTAssertEqual(result.components(separatedBy: "Line B").count, 2) // appears once
        XCTAssertEqual(result.components(separatedBy: "Line C").count, 2) // appears once
        XCTAssertTrue(result.contains("Line D"))
    }

    func testStripPageMarkers() {
        let input = "Hello\n%% === Page 1 ===\nWorld\n%% === Page 2 ===\nEnd"
        let result = LaTeXNormalizer(stripPageMarkers: true).normalize(input)
        XCTAssertFalse(result.contains("%% === Page"))
        XCTAssertTrue(result.contains("Hello"))
        XCTAssertTrue(result.contains("World"))
    }

    func testKeepPageMarkersByDefault() {
        let input = "Hello\n%% === Page 1 ===\nWorld"
        let result = LaTeXNormalizer().normalize(input)
        XCTAssertTrue(result.contains("%% === Page"))
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd /Users/che/Developer/macdoc/packages/pdf-to-latex-swift && swift test --filter LaTeXNormalizerTests 2>&1 | tail -5`
Expected: Compilation error — `LaTeXNormalizer` not defined.

**Step 3: Write minimal implementation**

```swift
// LaTeXNormalizer.swift
import Foundation

/// 機械式 LaTeX 清理：修正 document class、符號替換、跨頁去重、移除頁面標記。
public struct LaTeXNormalizer: Sendable {
    /// 符號替換規則（key → value）。
    public let symbolRules: [String: String]
    /// 是否移除 %% === Page N === 標記。
    public let stripPageMarkers: Bool
    /// 跨頁去重時，比對每頁邊界的行數。
    public let dedupLineCount: Int

    private static let pageMarkerPattern = #"^%% === Page \d+ ===$"#

    public init(
        symbolRules: [String: String] = [:],
        stripPageMarkers: Bool = false,
        dedupLineCount: Int = 3
    ) {
        self.symbolRules = symbolRules
        self.stripPageMarkers = stripPageMarkers
        self.dedupLineCount = dedupLineCount
    }

    /// 執行所有正規化步驟，回傳處理後的完整 LaTeX 文字。
    public func normalize(_ source: String) -> String {
        var text = source
        text = fixDocumentClass(text)
        text = applySymbolRules(text)
        text = removeCrossPageDuplicates(text)
        if stripPageMarkers {
            text = removePageMarkers(text)
        }
        return text
    }

    // MARK: - Steps

    /// 若有 \chapter 但 documentclass 是 article，換成 book。
    private func fixDocumentClass(_ text: String) -> String {
        let hasChapter = text.contains("\\chapter{") || text.contains("\\chapter*{")
        guard hasChapter else { return text }
        return text.replacingOccurrences(
            of: "\\documentclass{article}",
            with: "\\documentclass{book}"
        ).replacingOccurrences(
            of: "\\documentclass[",
            with: { () -> String in
                // Handle documentclass with options: \documentclass[...]{article}
                // Only replace if it's article class
                let pattern = #"\\documentclass\[([^\]]*)\]\{article\}"#
                guard let regex = try? NSRegularExpression(pattern: pattern) else { return "\\documentclass[" }
                let range = NSRange(text.startIndex..., in: text)
                let replaced = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "\\\\documentclass[$1]{book}")
                return replaced.contains("\\documentclass[") ? "\\documentclass[" : "\\documentclass["
            }()
        )
    }

    /// 套用符號替換規則。
    private func applySymbolRules(_ text: String) -> String {
        var result = text
        for (from, to) in symbolRules {
            result = result.replacingOccurrences(of: from, with: to)
        }
        return result
    }

    /// 移除跨頁邊界重複的行（比對頁面標記前後 N 行）。
    private func removeCrossPageDuplicates(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        guard lines.count > 1 else { return text }

        let markerRegex = try! NSRegularExpression(pattern: Self.pageMarkerPattern)
        var result: [String] = []
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let isMarker = markerRegex.firstMatch(
                in: line, range: NSRange(line.startIndex..., in: line)
            ) != nil

            if isMarker && !result.isEmpty {
                // Look back dedupLineCount lines from result, look forward dedupLineCount lines after marker
                let tailCount = min(dedupLineCount, result.count)
                let tail = Array(result.suffix(tailCount))

                var afterMarker: [String] = []
                var j = i + 1
                while afterMarker.count < dedupLineCount && j < lines.count {
                    afterMarker.append(lines[j])
                    j += 1
                }

                // Find overlap: matching suffix of tail with prefix of afterMarker
                var overlap = 0
                for len in (1...min(tail.count, afterMarker.count)).reversed() {
                    if Array(tail.suffix(len)) == Array(afterMarker.prefix(len)) {
                        overlap = len
                        break
                    }
                }

                result.append(line) // keep the marker
                // Skip the overlapping lines after marker
                i += 1 + overlap
            } else {
                result.append(line)
                i += 1
            }
        }
        return result.joined(separator: "\n")
    }

    /// 移除 %% === Page N === 標記行。
    private func removePageMarkers(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        let markerRegex = try! NSRegularExpression(pattern: Self.pageMarkerPattern)
        let filtered = lines.filter { line in
            markerRegex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) == nil
        }
        return filtered.joined(separator: "\n")
    }
}
```

Note: The `fixDocumentClass` method above has a closure issue. A cleaner implementation:

```swift
private func fixDocumentClass(_ text: String) -> String {
    let hasChapter = text.contains("\\chapter{") || text.contains("\\chapter*{")
    guard hasChapter else { return text }
    // Simple case: \documentclass{article}
    var result = text.replacingOccurrences(of: "\\documentclass{article}", with: "\\documentclass{book}")
    // With options: \documentclass[...]{article}
    if let regex = try? NSRegularExpression(pattern: #"\\documentclass\[([^\]]*)\]\{article\}"#) {
        let range = NSRange(result.startIndex..., in: result)
        result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: "\\\\documentclass[$1]{book}")
    }
    return result
}
```

**Step 4: Run test to verify it passes**

Run: `cd /Users/che/Developer/macdoc/packages/pdf-to-latex-swift && swift test --filter LaTeXNormalizerTests 2>&1 | tail -5`
Expected: All 6 tests PASS.

**Step 5: Commit**

```bash
cd /Users/che/Developer/macdoc
git add packages/pdf-to-latex-swift/Sources/PDFToLaTeXCore/LaTeXNormalizer.swift \
      packages/pdf-to-latex-swift/Tests/PDFToLaTeXCoreTests/LaTeXNormalizerTests.swift
git commit -m "feat: add LaTeXNormalizer for mechanical cleanup (doc class, symbols, dedup)"
```

---

## Task 3: LaTeXEnvChecker — Environment Mismatch Detection

**Files:**
- Create: `packages/pdf-to-latex-swift/Sources/PDFToLaTeXCore/LaTeXEnvChecker.swift`
- Test: `packages/pdf-to-latex-swift/Tests/PDFToLaTeXCoreTests/LaTeXEnvCheckerTests.swift`

**Step 1: Write the failing test**

```swift
// LaTeXEnvCheckerTests.swift
import XCTest
@testable import PDFToLaTeXCore

final class LaTeXEnvCheckerTests: XCTestCase {
    func testMatchedEnvironments_noIssues() {
        let input = "\\begin{equation}\nx = 1\n\\end{equation}"
        let issues = LaTeXEnvChecker().check(input)
        XCTAssertTrue(issues.isEmpty)
    }

    func testUnclosedEnvironment() {
        let input = "\\begin{equation}\nx = 1"
        let issues = LaTeXEnvChecker().check(input)
        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues[0].kind, .unclosed)
        XCTAssertEqual(issues[0].environment, "equation")
    }

    func testExtraClosed() {
        let input = "x = 1\n\\end{equation}"
        let issues = LaTeXEnvChecker().check(input)
        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues[0].kind, .extraClose)
    }

    func testMismatch() {
        let input = "\\begin{equation}\nx = 1\n\\end{align}"
        let issues = LaTeXEnvChecker().check(input)
        XCTAssertFalse(issues.isEmpty)
    }

    func testAutoFix_unclosed() {
        let input = "\\begin{equation}\nx = 1"
        let fixed = LaTeXEnvChecker().fix(input)
        XCTAssertTrue(fixed.contains("\\end{equation}"))
    }

    func testAutoFix_extraClose() {
        let input = "x = 1\n\\end{equation}"
        let fixed = LaTeXEnvChecker().fix(input)
        XCTAssertFalse(fixed.contains("\\end{equation}"))
    }

    func testNestedEnvironments() {
        let input = """
        \\begin{theorem}
        \\begin{equation}
        x = 1
        \\end{equation}
        \\end{theorem}
        """
        let issues = LaTeXEnvChecker().check(input)
        XCTAssertTrue(issues.isEmpty)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd /Users/che/Developer/macdoc/packages/pdf-to-latex-swift && swift test --filter LaTeXEnvCheckerTests 2>&1 | tail -5`
Expected: Compilation error — `LaTeXEnvChecker` not defined.

**Step 3: Write minimal implementation**

```swift
// LaTeXEnvChecker.swift
import Foundation

/// LaTeX 環境（begin/end）配對檢查器。
public struct LaTeXEnvChecker: Sendable {
    public init() {}

    /// 環境問題的分類。
    public enum IssueKind: String, Codable, Sendable, Equatable {
        case unclosed    // \begin{X} 沒有對應的 \end{X}
        case extraClose  // \end{X} 沒有對應的 \begin{X}
        case mismatch    // \begin{X} 配到 \end{Y}
    }

    /// 一個環境配對問題。
    public struct Issue: Sendable, Equatable {
        public let kind: IssueKind
        public let environment: String
        public let line: Int       // 1-based line number
        public let description: String
    }

    // MARK: - Check

    /// 檢查 LaTeX 原始碼中的環境配對問題。
    public func check(_ source: String) -> [Issue] {
        let lines = source.components(separatedBy: "\n")
        var stack: [(env: String, line: Int)] = []
        var issues: [Issue] = []

        let beginRegex = try! NSRegularExpression(pattern: #"\\begin\{(\w+\*?)\}"#)
        let endRegex = try! NSRegularExpression(pattern: #"\\end\{(\w+\*?)\}"#)

        for (index, line) in lines.enumerated() {
            let lineNum = index + 1
            let nsLine = line as NSString
            let range = NSRange(location: 0, length: nsLine.length)

            // Process all \begin and \end in order of appearance
            var events: [(pos: Int, isBegin: Bool, env: String)] = []

            for match in beginRegex.matches(in: line, range: range) {
                let envRange = match.range(at: 1)
                let env = nsLine.substring(with: envRange)
                events.append((match.range.location, true, env))
            }
            for match in endRegex.matches(in: line, range: range) {
                let envRange = match.range(at: 1)
                let env = nsLine.substring(with: envRange)
                events.append((match.range.location, false, env))
            }

            events.sort { $0.pos < $1.pos }

            for event in events {
                if event.isBegin {
                    stack.append((event.env, lineNum))
                } else {
                    if stack.isEmpty {
                        issues.append(Issue(
                            kind: .extraClose,
                            environment: event.env,
                            line: lineNum,
                            description: "\\end{\(event.env)} at line \(lineNum) has no matching \\begin"
                        ))
                    } else if stack.last!.env != event.env {
                        let top = stack.removeLast()
                        issues.append(Issue(
                            kind: .mismatch,
                            environment: event.env,
                            line: lineNum,
                            description: "\\begin{\(top.env)} at line \(top.line) closed by \\end{\(event.env)} at line \(lineNum)"
                        ))
                    } else {
                        stack.removeLast()
                    }
                }
            }
        }

        // Remaining unclosed
        for item in stack.reversed() {
            issues.append(Issue(
                kind: .unclosed,
                environment: item.env,
                line: item.line,
                description: "\\begin{\(item.env)} at line \(item.line) is never closed"
            ))
        }

        return issues
    }

    // MARK: - Fix

    /// 自動修復環境配對問題。回傳修復後的原始碼。
    public func fix(_ source: String) -> String {
        var lines = source.components(separatedBy: "\n")
        let endRegex = try! NSRegularExpression(pattern: #"\\end\{(\w+\*?)\}"#)

        // Pass 1: Remove extra \end lines (those with no matching \begin)
        let issues = check(source)
        let extraCloseLines = Set(issues.filter { $0.kind == .extraClose }.map { $0.line })
        if !extraCloseLines.isEmpty {
            lines = lines.enumerated().compactMap { (index, line) in
                extraCloseLines.contains(index + 1) ? nil : line
            }
        }

        // Pass 2: Re-check for unclosed and append missing \end
        let remaining = lines.joined(separator: "\n")
        let remainingIssues = check(remaining)
        let unclosed = remainingIssues.filter { $0.kind == .unclosed }

        for issue in unclosed {
            lines.append("\\end{\(issue.environment)}")
        }

        return lines.joined(separator: "\n")
    }
}
```

**Step 4: Run test to verify it passes**

Run: `cd /Users/che/Developer/macdoc/packages/pdf-to-latex-swift && swift test --filter LaTeXEnvCheckerTests 2>&1 | tail -5`
Expected: All 7 tests PASS.

**Step 5: Commit**

```bash
cd /Users/che/Developer/macdoc
git add packages/pdf-to-latex-swift/Sources/PDFToLaTeXCore/LaTeXEnvChecker.swift \
      packages/pdf-to-latex-swift/Tests/PDFToLaTeXCoreTests/LaTeXEnvCheckerTests.swift
git commit -m "feat: add LaTeXEnvChecker for detecting and fixing environment mismatches"
```

---

## Task 4: TexCompileChecker — Compilation Error Parser

**Files:**
- Create: `packages/pdf-to-latex-swift/Sources/PDFToLaTeXCore/TexCompileChecker.swift`
- Test: `packages/pdf-to-latex-swift/Tests/PDFToLaTeXCoreTests/TexCompileCheckerTests.swift`

**Step 1: Write the failing test**

```swift
// TexCompileCheckerTests.swift
import XCTest
@testable import PDFToLaTeXCore

final class TexCompileCheckerTests: XCTestCase {
    func testParseUndefinedCommand() {
        let log = """
        ! Undefined control sequence.
        l.42 \\bm
                {x}
        """
        let errors = TexCompileChecker.parseLog(log)
        XCTAssertEqual(errors.count, 1)
        XCTAssertEqual(errors[0].category, .undefinedCommand)
        XCTAssertEqual(errors[0].line, 42)
    }

    func testParseMissingMath() {
        let log = """
        ! Missing $ inserted.
        <inserted text>
                        $
        l.100 Some text with x_i
        """
        let errors = TexCompileChecker.parseLog(log)
        XCTAssertEqual(errors.count, 1)
        XCTAssertEqual(errors[0].category, .missingMath)
    }

    func testParseMissingBrace() {
        let log = """
        ! Missing } inserted.
        l.55 \\textbf{hello
        """
        let errors = TexCompileChecker.parseLog(log)
        XCTAssertEqual(errors.count, 1)
        XCTAssertEqual(errors[0].category, .missingBrace)
    }

    func testParseEnvironmentError() {
        let log = """
        ! LaTeX Error: \\begin{equation} on input line 30 ended by \\end{align}.
        l.35 \\end{align}
        """
        let errors = TexCompileChecker.parseLog(log)
        XCTAssertEqual(errors.count, 1)
        XCTAssertEqual(errors[0].category, .environment)
    }

    func testParseMultipleErrors() {
        let log = """
        ! Undefined control sequence.
        l.10 \\foo
        ! Missing $ inserted.
        l.20 x_i
        """
        let errors = TexCompileChecker.parseLog(log)
        XCTAssertEqual(errors.count, 2)
    }

    func testReportEncodeDecode() throws {
        let report = CompileReport(
            success: false,
            errors: [CompileError(category: .missingMath, line: 100, message: "Missing $", rawLog: "...")],
            warnings: []
        )
        let data = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(CompileReport.self, from: data)
        XCTAssertEqual(decoded.errors.count, 1)
        XCTAssertEqual(decoded.errors[0].category, .missingMath)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd /Users/che/Developer/macdoc/packages/pdf-to-latex-swift && swift test --filter TexCompileCheckerTests 2>&1 | tail -5`
Expected: Compilation error — `TexCompileChecker` not defined.

**Step 3: Write minimal implementation**

```swift
// TexCompileChecker.swift
import Foundation

/// LaTeX 編譯錯誤分類。
public enum CompileErrorCategory: String, Codable, Sendable, Equatable {
    case undefinedCommand = "undefined_command"
    case missingMath = "missing_math"
    case missingBrace = "missing_brace"
    case environment = "environment"
    case other
}

/// 一個編譯錯誤。
public struct CompileError: Codable, Sendable, Equatable {
    public let category: CompileErrorCategory
    public let line: Int?
    public let message: String
    public let rawLog: String

    public init(category: CompileErrorCategory, line: Int?, message: String, rawLog: String) {
        self.category = category
        self.line = line
        self.message = message
        self.rawLog = rawLog
    }
}

/// 編譯報告。
public struct CompileReport: Codable, Sendable {
    public let success: Bool
    public let errors: [CompileError]
    public let warnings: [String]

    public init(success: Bool, errors: [CompileError], warnings: [String]) {
        self.success = success
        self.errors = errors
        self.warnings = warnings
    }
}

/// 執行 pdflatex 並解析 log，產生結構化錯誤報告。
public struct TexCompileChecker: Sendable {
    public init() {}

    /// 執行 pdflatex（nonstopmode），回傳報告。
    public func run(texFileURL: URL) throws -> CompileReport {
        let dir = texFileURL.deletingLastPathComponent()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.currentDirectoryURL = dir
        process.arguments = [
            "pdflatex",
            "-interaction=nonstopmode",
            "-file-line-error",
            texFileURL.lastPathComponent,
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        // Read .log file
        let logURL = texFileURL.deletingPathExtension().appendingPathExtension("log")
        let logContent: String
        if FileManager.default.fileExists(atPath: logURL.path) {
            logContent = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
        } else {
            logContent = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        }

        let errors = Self.parseLog(logContent)
        let warnings = Self.parseWarnings(logContent)

        return CompileReport(
            success: process.terminationStatus == 0 && errors.isEmpty,
            errors: errors,
            warnings: warnings
        )
    }

    /// 從 pdflatex log 內容解析錯誤（純函數，方便測試）。
    public static func parseLog(_ log: String) -> [CompileError] {
        let lines = log.components(separatedBy: "\n")
        var errors: [CompileError] = []
        let lineNumberRegex = try! NSRegularExpression(pattern: #"l\.(\d+)"#)

        var i = 0
        while i < lines.count {
            let line = lines[i]
            guard line.hasPrefix("!") else { i += 1; continue }

            let message = String(line.dropFirst(2)) // Remove "! "
            let category = categorize(message)

            // Look for line number in subsequent lines
            var lineNum: Int?
            var rawLines = [line]
            for j in (i+1)..<min(i+5, lines.count) {
                rawLines.append(lines[j])
                let nsLine = lines[j] as NSString
                if let match = lineNumberRegex.firstMatch(in: lines[j], range: NSRange(location: 0, length: nsLine.length)) {
                    let numStr = nsLine.substring(with: match.range(at: 1))
                    lineNum = Int(numStr)
                    break
                }
            }

            errors.append(CompileError(
                category: category,
                line: lineNum,
                message: message.trimmingCharacters(in: .whitespaces),
                rawLog: rawLines.joined(separator: "\n")
            ))
            i += 1
        }
        return errors
    }

    /// 從 log 解析警告。
    public static func parseWarnings(_ log: String) -> [String] {
        log.components(separatedBy: "\n")
            .filter { $0.contains("Warning:") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func categorize(_ message: String) -> CompileErrorCategory {
        if message.contains("Undefined control sequence") { return .undefinedCommand }
        if message.contains("Missing $ inserted") { return .missingMath }
        if message.contains("Missing } inserted") || message.contains("Missing { inserted") { return .missingBrace }
        if message.contains("\\begin{") && message.contains("\\end{") { return .environment }
        if message.contains("LaTeX Error") && message.contains("ended by") { return .environment }
        return .other
    }

    // MARK: - Report I/O

    /// 將報告寫成 JSON 檔。
    public func writeReport(_ report: CompileReport, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        try data.write(to: url, options: .atomic)
    }
}
```

**Step 4: Run test to verify it passes**

Run: `cd /Users/che/Developer/macdoc/packages/pdf-to-latex-swift && swift test --filter TexCompileCheckerTests 2>&1 | tail -5`
Expected: All 6 tests PASS.

**Step 5: Commit**

```bash
cd /Users/che/Developer/macdoc
git add packages/pdf-to-latex-swift/Sources/PDFToLaTeXCore/TexCompileChecker.swift \
      packages/pdf-to-latex-swift/Tests/PDFToLaTeXCoreTests/TexCompileCheckerTests.swift
git commit -m "feat: add TexCompileChecker for parsing pdflatex errors into structured reports"
```

---

## Task 5: Consolidator — Orchestration Engine

**Files:**
- Create: `packages/pdf-to-latex-swift/Sources/PDFToLaTeXCore/Consolidator.swift`
- Test: `packages/pdf-to-latex-swift/Tests/PDFToLaTeXCoreTests/ConsolidatorTests.swift`

**Step 1: Write the failing test**

```swift
// ConsolidatorTests.swift
import XCTest
@testable import PDFToLaTeXCore

final class ConsolidatorTests: XCTestCase {
    func testMechanicalStepsOnSimpleInput() throws {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let texURL = tmpDir.appendingPathComponent("accumulated.tex")
        let source = """
        \\documentclass{article}
        \\begin{document}
        \\chapter{Introduction}
        \\begin{equation}
        x = 1
        \\end{equation}
        \\end{document}
        """
        try source.write(to: texURL, atomically: true, encoding: .utf8)

        let consolidator = Consolidator()
        let result = try consolidator.runMechanicalSteps(texFileURL: texURL)

        // Should fix article → book because \chapter is present
        let fixedContent = try String(contentsOf: texURL, encoding: .utf8)
        XCTAssertTrue(fixedContent.contains("\\documentclass{book}"))
        XCTAssertTrue(result.normalizeApplied)
        XCTAssertTrue(result.envCheckApplied)
    }

    func testBuildAgentPromptContainsErrors() {
        let errors = [
            CompileError(category: .undefinedCommand, line: 42, message: "Undefined control sequence", rawLog: "..."),
            CompileError(category: .missingMath, line: 100, message: "Missing $", rawLog: "...")
        ]
        let prompt = Consolidator.buildAgentPrompt(errors: errors, texFilePath: "/tmp/test.tex")
        XCTAssertTrue(prompt.contains("Undefined control sequence"))
        XCTAssertTrue(prompt.contains("line 42"))
        XCTAssertTrue(prompt.contains("Missing $"))
        XCTAssertTrue(prompt.contains("/tmp/test.tex"))
        XCTAssertTrue(prompt.contains("Fix ONLY"))
    }

    func testAgentCommandForEachBackend() {
        let prompt = "Fix these errors"
        let dir = "/tmp/project"

        let codexCmd = Consolidator.agentCommand(backend: .codex, model: "gpt-5.4", prompt: prompt, projectDir: dir)
        XCTAssertEqual(codexCmd[0], "codex")

        let claudeCmd = Consolidator.agentCommand(backend: .claude, model: "claude-sonnet-4-6", prompt: prompt, projectDir: dir)
        XCTAssertEqual(claudeCmd[0], "claude")

        let geminiCmd = Consolidator.agentCommand(backend: .gemini, model: "gemini-3.1-pro-preview", prompt: prompt, projectDir: dir)
        XCTAssertEqual(geminiCmd[0], "gemini")
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd /Users/che/Developer/macdoc/packages/pdf-to-latex-swift && swift test --filter ConsolidatorTests 2>&1 | tail -5`
Expected: Compilation error — `Consolidator` not defined.

**Step 3: Write minimal implementation**

```swift
// Consolidator.swift
import Foundation

/// 機械步驟的執行結果摘要。
public struct MechanicalResult: Sendable {
    public let normalizeApplied: Bool
    public let envCheckApplied: Bool
    public let envIssuesFixed: Int
    public let compileErrors: [CompileError]
}

/// 整合 pipeline：機械清理 → 編譯檢查 → Agent 修正。
public struct Consolidator: Sendable {
    public let normalizer: LaTeXNormalizer
    public let envChecker: LaTeXEnvChecker
    public let maxAgentRounds: Int

    public init(
        normalizer: LaTeXNormalizer = LaTeXNormalizer(
            symbolRules: ["\\bm{": "\\boldsymbol{"],
            stripPageMarkers: false
        ),
        envChecker: LaTeXEnvChecker = LaTeXEnvChecker(),
        maxAgentRounds: Int = 3
    ) {
        self.normalizer = normalizer
        self.envChecker = envChecker
        self.maxAgentRounds = maxAgentRounds
    }

    // MARK: - Mechanical Steps

    /// 執行機械式清理步驟（normalize + env fix），直接修改檔案。
    public func runMechanicalSteps(texFileURL: URL) throws -> MechanicalResult {
        // Backup
        let backupURL = texFileURL.appendingPathExtension("bak")
        if FileManager.default.fileExists(atPath: texFileURL.path) {
            try? FileManager.default.copyItem(at: texFileURL, to: backupURL)
        }

        // Step 1: Normalize
        var source = try String(contentsOf: texFileURL, encoding: .utf8)
        let normalized = normalizer.normalize(source)
        let normalizeApplied = normalized != source
        source = normalized

        // Step 2: Env check + fix
        let issues = envChecker.check(source)
        if !issues.isEmpty {
            source = envChecker.fix(source)
        }

        // Write back
        try source.write(to: texFileURL, atomically: true, encoding: .utf8)

        // Step 3: Compile check (only if pdflatex is available)
        var compileErrors: [CompileError] = []
        if Self.isPdflatexAvailable() {
            let checker = TexCompileChecker()
            let report = try checker.run(texFileURL: texFileURL)
            compileErrors = report.errors

            // Write report
            let reportURL = texFileURL.deletingLastPathComponent()
                .appendingPathComponent("compile-report.json")
            try checker.writeReport(report, to: reportURL)
        }

        return MechanicalResult(
            normalizeApplied: normalizeApplied,
            envCheckApplied: !issues.isEmpty,
            envIssuesFixed: issues.count,
            compileErrors: compileErrors
        )
    }

    // MARK: - Full Pipeline (mechanical + agent)

    /// 完整 pipeline：機械清理 → 如有錯誤，呼叫 agent 修正 → 重新編譯，最多 maxAgentRounds 輪。
    public func run(
        texFileURL: URL,
        backend: TranscriptionBackend,
        model: String,
        dryRun: Bool = false
    ) throws -> CompileReport {
        // Mechanical steps
        let mechanical = try runMechanicalSteps(texFileURL: texFileURL)

        if dryRun {
            return CompileReport(
                success: mechanical.compileErrors.isEmpty,
                errors: mechanical.compileErrors,
                warnings: []
            )
        }

        var currentErrors = mechanical.compileErrors
        var finalReport = CompileReport(success: currentErrors.isEmpty, errors: currentErrors, warnings: [])

        // Agent loop
        for round in 1...maxAgentRounds {
            guard !currentErrors.isEmpty else { break }

            let prompt = Self.buildAgentPrompt(errors: currentErrors, texFilePath: texFileURL.path)
            let command = Self.agentCommand(
                backend: backend, model: model, prompt: prompt,
                projectDir: texFileURL.deletingLastPathComponent().path
            )

            // Run agent
            try Self.runProcess(command, cwd: texFileURL.deletingLastPathComponent())

            // Re-check
            let checker = TexCompileChecker()
            finalReport = try checker.run(texFileURL: texFileURL)
            currentErrors = finalReport.errors

            let reportURL = texFileURL.deletingLastPathComponent()
                .appendingPathComponent("compile-report.json")
            try checker.writeReport(finalReport, to: reportURL)

            if finalReport.success { break }
        }

        return finalReport
    }

    // MARK: - Agent Prompt & Command (public for testing)

    /// 建構 agent prompt：列出所有錯誤，要求只修正列出的問題。
    public static func buildAgentPrompt(errors: [CompileError], texFilePath: String) -> String {
        var lines = [
            "You are fixing LaTeX compilation errors in: \(texFilePath)",
            "",
            "Fix ONLY the listed errors. Do not rewrite, restructure, or re-format the document.",
            "Do not change any content that compiles correctly.",
            "",
            "Errors to fix (\(errors.count) total):",
            ""
        ]
        for (i, error) in errors.enumerated() {
            lines.append("  \(i+1). [\(error.category.rawValue)] line \(error.line ?? 0): \(error.message)")
        }
        return lines.joined(separator: "\n")
    }

    /// 根據 backend 產生對應的 CLI command 陣列。
    public static func agentCommand(
        backend: TranscriptionBackend,
        model: String,
        prompt: String,
        projectDir: String
    ) -> [String] {
        switch backend {
        case .codex:
            return [
                "codex", "exec",
                "-C", projectDir,
                "-s", "full",
                "-m", model,
                "-p", prompt,
            ]
        case .claude:
            return [
                "claude",
                "-p", prompt,
                "--allowedTools", "Read,Write,Bash",
            ]
        case .gemini:
            return [
                "gemini", prompt,
            ]
        }
    }

    // MARK: - Helpers

    private static func isPdflatexAvailable() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["pdflatex"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch { return false }
    }

    @discardableResult
    private static func runProcess(_ args: [String], cwd: URL) throws -> String {
        guard let executable = args.first else { throw PDFToLaTeXError.cliNotFound("empty command") }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.currentDirectoryURL = cwd
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}
```

**Step 4: Run test to verify it passes**

Run: `cd /Users/che/Developer/macdoc/packages/pdf-to-latex-swift && swift test --filter ConsolidatorTests 2>&1 | tail -5`
Expected: All 3 tests PASS.

**Step 5: Commit**

```bash
cd /Users/che/Developer/macdoc
git add packages/pdf-to-latex-swift/Sources/PDFToLaTeXCore/Consolidator.swift \
      packages/pdf-to-latex-swift/Tests/PDFToLaTeXCoreTests/ConsolidatorTests.swift
git commit -m "feat: add Consolidator orchestrating mechanical cleanup and agent error fixes"
```

---

## Task 6: CLI Commands — Normalize, FixEnvs, CompileCheck, Consolidate

**Files:**
- Modify: `Sources/MacDocCLI/MacDoc+PDF.swift` — add 4 new subcommands
- Modify: `Sources/MacDocCLI/MacDoc.swift` — add Config subcommand group

**Step 1: Write the CLI commands**

Add to `MacDoc+PDF.swift` subcommands array:
```swift
Normalize.self,
FixEnvs.self,
CompileCheck.self,
Consolidate.self,
```

Then add the 4 structs inside `extension MacDoc.PDF { ... }`:

```swift
// MARK: macdoc pdf normalize
struct Normalize: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "normalize",
        abstract: "機械式清理 accumulated.tex（document class、符號、跨頁去重）。"
    )

    @Option(name: .long, help: "專案資料夾。")
    var project: String = "."

    @Flag(name: .long, help: "移除頁面標記 (%% === Page N ===)。")
    var stripMarkers: Bool = false

    mutating func run() throws {
        let root = Support.absoluteURL(from: project, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        let texURL = root.appendingPathComponent("accumulated.tex")
        guard FileManager.default.fileExists(atPath: texURL.path) else {
            throw ValidationError("找不到 accumulated.tex: \(texURL.path)")
        }

        let source = try String(contentsOf: texURL, encoding: .utf8)
        let normalizer = LaTeXNormalizer(
            symbolRules: ["\\bm{": "\\boldsymbol{"],
            stripPageMarkers: stripMarkers
        )

        // Backup
        let backupURL = texURL.appendingPathExtension("bak")
        try source.write(to: backupURL, atomically: true, encoding: .utf8)

        let result = normalizer.normalize(source)
        try result.write(to: texURL, atomically: true, encoding: .utf8)
        print("normalize 完成。備份: \(backupURL.path)")
    }
}

// MARK: macdoc pdf fix-envs
struct FixEnvs: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "fix-envs",
        abstract: "檢查 LaTeX 環境配對（\\begin/\\end），可選自動修復。"
    )

    @Option(name: .long, help: "專案資料夾。")
    var project: String = "."

    @Flag(name: .long, help: "自動修復問題。")
    var fix: Bool = false

    mutating func run() throws {
        let root = Support.absoluteURL(from: project, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        let texURL = root.appendingPathComponent("accumulated.tex")
        guard FileManager.default.fileExists(atPath: texURL.path) else {
            throw ValidationError("找不到 accumulated.tex: \(texURL.path)")
        }

        let source = try String(contentsOf: texURL, encoding: .utf8)
        let checker = LaTeXEnvChecker()
        let issues = checker.check(source)

        if issues.isEmpty {
            print("沒有環境配對問題。")
            return
        }

        for issue in issues {
            print("[\(issue.kind.rawValue)] line \(issue.line): \(issue.description)")
        }
        print("共 \(issues.count) 個問題。")

        if fix {
            let fixed = checker.fix(source)
            try fixed.write(to: texURL, atomically: true, encoding: .utf8)
            print("已自動修復。")
        }
    }
}

// MARK: macdoc pdf compile-check
struct CompileCheck: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "compile-check",
        abstract: "執行 pdflatex 編譯並輸出結構化錯誤報告。"
    )

    @Option(name: .long, help: "專案資料夾。")
    var project: String = "."

    @Option(name: .long, help: "TeX 檔案名稱。")
    var file: String = "accumulated.tex"

    mutating func run() throws {
        let root = Support.absoluteURL(from: project, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        let texURL = root.appendingPathComponent(file)
        guard FileManager.default.fileExists(atPath: texURL.path) else {
            throw ValidationError("找不到 \(file): \(texURL.path)")
        }

        let checker = TexCompileChecker()
        let report = try checker.run(texFileURL: texURL)
        let reportURL = root.appendingPathComponent("compile-report.json")
        try checker.writeReport(report, to: reportURL)

        if report.success {
            print("編譯成功！")
        } else {
            print("編譯失敗，\(report.errors.count) 個錯誤：")
            for error in report.errors {
                print("  [\(error.category.rawValue)] line \(error.line ?? 0): \(error.message)")
            }
        }
        print("報告: \(reportURL.path)")
    }
}

// MARK: macdoc pdf consolidate
struct Consolidate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "consolidate",
        abstract: "整合 pipeline：機械清理 → Agent 修正剩餘錯誤。"
    )

    @Option(name: .long, help: "專案資料夾。")
    var project: String = "."

    @Option(name: .long, help: "Agent 後端 (codex|claude|gemini)。")
    var agent: String?

    @Option(name: .long, help: "Agent 模型。")
    var model: String?

    @Flag(name: .long, help: "只跑機械步驟，不呼叫 agent。")
    var dryRun: Bool = false

    mutating func run() throws {
        let root = Support.absoluteURL(from: project, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        let texURL = root.appendingPathComponent("accumulated.tex")
        guard FileManager.default.fileExists(atPath: texURL.path) else {
            throw ValidationError("找不到 accumulated.tex: \(texURL.path)")
        }

        let aiConfig = try AIConfig.load()
        let backend = agent.flatMap { TranscriptionBackend(rawValue: $0) }
            ?? TranscriptionBackend(rawValue: aiConfig.agent) ?? .claude
        let resolvedModel = model ?? backend.defaultModel

        let consolidator = Consolidator()
        let report = try consolidator.run(
            texFileURL: texURL,
            backend: backend,
            model: resolvedModel,
            dryRun: dryRun
        )

        if report.success {
            print("Consolidation 完成！")
        } else {
            print("仍有 \(report.errors.count) 個未解決的錯誤。")
            for error in report.errors {
                print("  [\(error.category.rawValue)] line \(error.line ?? 0): \(error.message)")
            }
        }
    }
}
```

**Step 2: Add Config.AI subcommands to MacDoc.swift**

Add `Config.self` to subcommands in `MacDoc`:

```swift
// In MacDoc.swift, add to subcommands:
subcommands: [Word.self, PDF.self, Config.self]
```

Then add the Config extension:

```swift
// MARK: - Config 子命令
extension MacDoc {
    struct Config: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "config",
            abstract: "管理 macdoc 設定",
            subcommands: [AI.self]
        )

        struct AI: AsyncParsableCommand {
            static let configuration = CommandConfiguration(
                commandName: "ai",
                abstract: "AI CLI 工具設定",
                subcommands: [Detect.self, List.self, Set.self]
            )

            struct Detect: AsyncParsableCommand {
                static let configuration = CommandConfiguration(
                    commandName: "detect",
                    abstract: "自動偵測已安裝的 AI CLI 工具。"
                )
                mutating func run() throws {
                    let config = AIConfig.detect()
                    try config.save()
                    print("偵測到的工具: \(config.available.joined(separator: ", "))")
                    print("轉寫預設: \(config.transcription)")
                    print("Agent 預設: \(config.agent)")
                    print("設定已儲存到: \(AIConfig.defaultConfigURL.path)")
                }
            }

            struct List: AsyncParsableCommand {
                static let configuration = CommandConfiguration(
                    commandName: "list",
                    abstract: "顯示目前的 AI 設定。"
                )
                mutating func run() throws {
                    let config = try AIConfig.load()
                    print("可用工具: \(config.available.isEmpty ? "(未偵測)" : config.available.joined(separator: ", "))")
                    print("轉寫預設: \(config.transcription)")
                    print("Agent 預設: \(config.agent)")
                }
            }

            struct Set: AsyncParsableCommand {
                static let configuration = CommandConfiguration(
                    commandName: "set",
                    abstract: "設定 AI 偏好（如 agent claude）。"
                )

                @Argument(help: "要設定的 key（transcription 或 agent）。")
                var key: String

                @Argument(help: "值（codex、claude 或 gemini）。")
                var value: String

                mutating func run() throws {
                    var config = try AIConfig.load()
                    switch key {
                    case "transcription": config.transcription = value
                    case "agent": config.agent = value
                    default: throw ValidationError("未知的 key: \(key)。可用: transcription, agent")
                    }
                    try config.save()
                    print("已設定 \(key) = \(value)")
                }
            }
        }
    }
}
```

**Step 3: Build and verify**

Run: `cd /Users/che/Developer/macdoc && swift build 2>&1 | tail -10`
Expected: Build succeeds.

**Step 4: Smoke test CLI**

Run: `cd /Users/che/Developer/macdoc && swift run macdoc config ai detect`
Run: `cd /Users/che/Developer/macdoc && swift run macdoc pdf --help` (should show new subcommands)

**Step 5: Commit**

```bash
cd /Users/che/Developer/macdoc
git add Sources/MacDocCLI/MacDoc.swift Sources/MacDocCLI/MacDoc+PDF.swift
git commit -m "feat: add CLI commands for normalize, fix-envs, compile-check, consolidate, and config ai"
```

---

## Task 7: Integration Test — Full Pipeline on Hansen

**Files:**
- No new files. Run existing pipeline on the accumulated.tex we already have.

**Step 1: Run normalize on hansen project**

Run:
```bash
cd /Users/che/Developer/macdoc && swift run macdoc pdf normalize \
  --project /Users/che/Library/CloudStorage/Dropbox/che_workspace/teaching/2026_Winston/econometrics/references/hansen-2014/hansen-econometrics
```

Expected: Prints "normalize 完成" and creates `accumulated.tex.bak`.

**Step 2: Run fix-envs (report mode)**

Run:
```bash
cd /Users/che/Developer/macdoc && swift run macdoc pdf fix-envs \
  --project /path/to/hansen-econometrics
```

Expected: Lists any environment issues found.

**Step 3: Run compile-check**

Run:
```bash
cd /Users/che/Developer/macdoc && swift run macdoc pdf compile-check \
  --project /path/to/hansen-econometrics
```

Expected: Creates `compile-report.json` with categorized errors.

**Step 4: Run consolidate --dry-run**

Run:
```bash
cd /Users/che/Developer/macdoc && swift run macdoc pdf consolidate \
  --project /path/to/hansen-econometrics --dry-run
```

Expected: Runs mechanical steps, prints error summary, does NOT invoke agent.

**Step 5: Commit test results (if any fixes needed)**

```bash
git add -A && git commit -m "test: verify Phase 2 consolidation pipeline on hansen-econometrics"
```

---

## Summary

| Task | Component | New Files | Tests |
|------|-----------|-----------|-------|
| 1 | AIConfig | AIConfig.swift | 5 tests |
| 2 | LaTeXNormalizer | LaTeXNormalizer.swift | 6 tests |
| 3 | LaTeXEnvChecker | LaTeXEnvChecker.swift | 7 tests |
| 4 | TexCompileChecker | TexCompileChecker.swift | 6 tests |
| 5 | Consolidator | Consolidator.swift | 3 tests |
| 6 | CLI Commands | MacDoc.swift, MacDoc+PDF.swift (modify) | build + smoke |
| 7 | Integration | — | end-to-end on hansen |

Total: 5 new core files, 2 modified CLI files, 27+ unit tests, 1 integration test.
