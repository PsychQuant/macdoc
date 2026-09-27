import Foundation
import XCTest

/// PsychQuant/macdoc#190 — tests, sources and scripts must not reference a
/// file through the author's home directory.
///
/// #186 removed a test that read a fixture from a personal folder outside the
/// repository; the path itself stays in the Git history (commit `d181090`),
/// and the owner chose not to rewrite 249 commits and 28 tags for it (#190,
/// option B). This test keeps the tree from acquiring a new one: a path like
/// that fails on every other machine, and it publishes the author's folder
/// layout. Use a fixture inside the repository, a generated fixture, or an
/// environment-gated directory (e.g. `MACDOC_TEMPLATE_DIR`) instead.
final class HostAbsolutePathGuardTests: XCTestCase {
    /// Built from parts so this file does not match its own pattern.
    private static let homeRoots = ["Us" + "ers", "ho" + "me"]
    private static let scannedDirectories = ["Tests", "Sources", "scripts"]
    private static let scannedExtensions: Set<String> = [
        "swift", "sh", "py", "yaml", "yml", "json", "md", "txt",
    ]

    func testNoHomeDirectoryAbsolutePathsInTestsSourcesOrScripts() throws {
        let root = try Self.repositoryRoot()
        let roots = Self.homeRoots.joined(separator: "|")
        // `/<root>/<name>/`, where <name> is a real account name rather than a
        // placeholder such as `<user>`.
        let pattern = try NSRegularExpression(pattern: "/(?:\(roots))/[A-Za-z0-9._-]+/")

        var offenders: [String] = []
        for directory in Self.scannedDirectories {
            let base = root.appendingPathComponent(directory)
            guard let files = FileManager.default.enumerator(
                at: base, includingPropertiesForKeys: [.isRegularFileKey]
            ) else { continue }
            for case let file as URL in files where Self.scannedExtensions.contains(file.pathExtension) {
                guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
                for (index, line) in text.components(separatedBy: "\n").enumerated() {
                    let range = NSRange(line.startIndex..., in: line)
                    if pattern.firstMatch(in: line, range: range) != nil {
                        let relative = file.path.replacingOccurrences(of: root.path + "/", with: "")
                        offenders.append("\(relative):\(index + 1)")
                    }
                }
            }
        }

        XCTAssertTrue(
            offenders.isEmpty,
            "home-directory absolute paths found (use an in-repo or env-gated fixture instead):\n"
                + offenders.joined(separator: "\n")
        )
    }

    private static func repositoryRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.pathComponents.count > 1 {
            url.deleteLastPathComponent()
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
                return url
            }
        }
        // Fail rather than skip: a guard that silently skips is not a guard.
        throw NSError(
            domain: "HostAbsolutePathGuardTests", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Package.swift not found above \(#filePath)"]
        )
    }
}
