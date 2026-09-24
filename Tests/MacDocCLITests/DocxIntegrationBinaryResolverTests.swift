import Foundation
import XCTest

final class DocxIntegrationBinaryResolverTests: XCTestCase {
    private let cwd = URL(fileURLWithPath: "/tmp/idd-docx-resolver-root")

    func testResolvesToCwdRelativeDebugBinaryWhenPresent() {
        let expected = cwd.appendingPathComponent(".build/debug/macdoc")

        let result = DocxIntegrationBinaryResolver.resolve(
            cwd: cwd,
            fileExists: { $0 == expected.path }
        )

        XCTAssertEqual(result, expected)
    }

    func testReturnsNilWhenBinaryMissing() {
        let result = DocxIntegrationBinaryResolver.resolve(
            cwd: cwd,
            fileExists: { _ in false }
        )

        XCTAssertNil(result)
    }

    // Locks the design decision from PsychQuant/macdoc#192: this resolver
    // must NOT grow into a unified, MACDOC_TEST_BINARY-aware resolver.
    // Passing an override in `environment` must not change the result —
    // the resolver stays pinned to the cwd-relative debug binary.
    func testIgnoresMacdocTestBinaryEnvironmentOverride() {
        let expected = cwd.appendingPathComponent(".build/debug/macdoc")

        let result = DocxIntegrationBinaryResolver.resolve(
            cwd: cwd,
            environment: ["MACDOC_TEST_BINARY": "/somewhere/else/macdoc"],
            fileExists: { $0 == expected.path }
        )

        XCTAssertEqual(result, expected)
    }
}
