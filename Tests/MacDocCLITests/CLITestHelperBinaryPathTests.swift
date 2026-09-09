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

        XCTAssertEqual(try CLITestHelper.binaryPath, expectedPath)
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
