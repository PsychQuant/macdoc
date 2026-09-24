import Foundation
import XCTest

final class CLITestHelperBinaryPathTests: XCTestCase {
    private let root = URL(fileURLWithPath: "/tmp/idd-test-root")
    private let debugPath = "/tmp/idd-test-root/.build/debug/macdoc"
    private let releasePath = "/tmp/idd-test-root/.build/release/macdoc"

    func testBinaryPathUsesActualTestBuildConfiguration() throws {
        let variable = "MACDOC_TEST_BINARY"
        let originalValue = getenv(variable).map { String(cString: $0) }
        unsetenv(variable)
        defer {
            if let originalValue {
                setenv(variable, originalValue, 1)
            } else {
                unsetenv(variable)
            }
        }

        #if DEBUG
        let expectedPath = CLITestHelper.repoRoot
            .appendingPathComponent(".build/debug/macdoc").path
        #else
        let expectedPath = CLITestHelper.repoRoot
            .appendingPathComponent(".build/release/macdoc").path
        #endif

        if FileManager.default.isExecutableFile(atPath: expectedPath) {
            XCTAssertEqual(try CLITestHelper.binaryPath, expectedPath)
        } else {
            XCTAssertThrowsError(try CLITestHelper.binaryPath) {
                XCTAssertEqual($0 as? BinarySelectionError, .unavailable(expectedPath))
            }
        }
    }

    func testDebugDoesNotPreferRelease() throws {
        let available = Set([debugPath, releasePath])

        let result = try resolve(configuration: "debug", available: available)

        XCTAssertEqual(result.path, debugPath)
    }

    func testReleaseDoesNotPreferDebug() throws {
        let available = Set([debugPath, releasePath])

        let result = try resolve(configuration: "release", available: available)

        XCTAssertEqual(result.path, releasePath)
    }

    func testMissingDebugDoesNotFallBackToRelease() {
        XCTAssertThrowsError(try resolve(configuration: "debug", available: [releasePath])) {
            XCTAssertEqual($0 as? BinarySelectionError, .unavailable(debugPath))
        }
    }

    func testMissingBothConfigurationsThrowsUnavailable() {
        XCTAssertThrowsError(try resolve(configuration: "debug", available: [])) {
            XCTAssertEqual($0 as? BinarySelectionError, .unavailable(debugPath))
        }
    }

    func testExecutableAbsoluteOverrideTakesPriority() throws {
        let override = "/tmp/custom/macdoc"

        let result = try resolve(
            configuration: "debug",
            environment: ["MACDOC_TEST_BINARY": override],
            available: [debugPath, override]
        )

        XCTAssertEqual(result.path, override)
    }

    func testUnavailableOverrideDoesNotFallBack() {
        let override = "/tmp/missing/macdoc"

        XCTAssertThrowsError(try resolve(
            configuration: "debug",
            environment: ["MACDOC_TEST_BINARY": override],
            available: [debugPath]
        )) {
            XCTAssertEqual($0 as? BinarySelectionError, .unavailable(override))
        }
    }

    func testEmptyOverrideIsInvalid() {
        XCTAssertThrowsError(try resolve(
            configuration: "debug",
            environment: ["MACDOC_TEST_BINARY": ""],
            available: [debugPath]
        )) {
            XCTAssertEqual($0 as? BinarySelectionError, .invalidOverride(""))
        }
    }

    func testRelativeOverrideIsInvalid() {
        let override = ".build/debug/macdoc"

        XCTAssertThrowsError(try resolve(
            configuration: "debug",
            environment: ["MACDOC_TEST_BINARY": override],
            available: [debugPath]
        )) {
            XCTAssertEqual($0 as? BinarySelectionError, .invalidOverride(override))
        }
    }

    // MARK: - Directory override (PsychQuant/macdoc#192)
    //
    // The tests above all exercise `resolveBinaryURL` through the `resolve`
    // stub, which injects `isExecutable` as `available.contains` — a Set
    // membership check that has no notion of "is this a directory". That
    // stub can never catch a regression in the *production* `isExecutable`
    // closure wired up in `CLITestHelper.binaryPath` (line 57 as of this
    // writing), which was `FileManager.default.isExecutableFile(atPath:)`
    // verbatim. That API returns `true` for a directory with the execute
    // bit set — true for nearly every directory, since that bit is what
    // makes a directory `cd`-able. So a `MACDOC_TEST_BINARY` override that
    // points at a directory used to sail past the `guard isExecutable(...)`
    // check and only fail much later, inside `Process.run()`, with an
    // unhelpful low-level error. This test calls the real `binaryPath`
    // getter (not the stub) to close that gap.
    func testBinaryPathThrowsUnavailableWhenOverrideIsDirectory() throws {
        let variable = "MACDOC_TEST_BINARY"
        let originalValue = getenv(variable).map { String(cString: $0) }
        let directory = CLITestHelper.repoRoot.path
        setenv(variable, directory, 1)
        defer {
            if let originalValue {
                setenv(variable, originalValue, 1)
            } else {
                unsetenv(variable)
            }
        }

        XCTAssertThrowsError(try CLITestHelper.binaryPath) {
            XCTAssertEqual($0 as? BinarySelectionError, .unavailable(directory))
        }
    }

    // MARK: - Error message clarity (PsychQuant/macdoc#192 Expected #2)

    func testUnavailableDescriptionNamesDirectoryExplicitly() {
        let directory = CLITestHelper.repoRoot.path

        let description = String(describing: BinarySelectionError.unavailable(directory))

        XCTAssertTrue(
            description.contains("目錄"),
            "指向目錄的 unavailable 錯誤描述應明確指出這是目錄，而不是只重複路徑本身。實際訊息: \(description)"
        )
    }

    func testUnavailableDescriptionNamesMissingPathExplicitly() {
        let missing = "/tmp/macdoc-test-does-not-exist-\(UUID().uuidString)/macdoc"

        let description = String(describing: BinarySelectionError.unavailable(missing))

        XCTAssertTrue(
            description.contains("不存在"),
            "指向不存在路徑的 unavailable 錯誤描述應提示檔案不存在。實際訊息: \(description)"
        )
    }

    private func resolve(
        configuration: String,
        environment: [String: String] = [:],
        available: Set<String>
    ) throws -> URL {
        try CLITestHelper.resolveBinaryURL(
            repoRoot: root,
            configuration: configuration,
            environment: environment,
            isExecutable: available.contains
        )
    }
}
