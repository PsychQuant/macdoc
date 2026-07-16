import Foundation
import XCTest

/// Regression test for macdoc#133: the timeout path in CLITestHelper must
/// reap the child before reading terminationStatus, otherwise
/// `-[NSConcreteTask terminationStatus]` throws NSInvalidArgumentException
/// ("task still running") and takes down the whole test process.
///
/// Uses `/bin/sleep` (guaranteed to outlive a sub-second timeout) so the
/// terminate branch is exercised deterministically — independent of macdoc's
/// cold-start timing.
final class CLITestHelperTimeoutTests: XCTestCase {

    func testTimeoutPathReapsChildAndDoesNotCrash() throws {
        let result = try CLITestHelper.runProcess(
            executableURL: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["5"],
            currentDirectory: nil,
            timeout: 0.3)
        // The child was SIGTERM'd on timeout; reaching this line at all means
        // terminationStatus was read on a reaped process (no exception).
        XCTAssertNotEqual(result.exitCode, 0,
                          "a timed-out (terminated) process must not report success")
    }

    func testNormalPathStillReturnsCleanly() throws {
        let result = try CLITestHelper.runProcess(
            executableURL: URL(fileURLWithPath: "/bin/echo"),
            arguments: ["ok"],
            currentDirectory: nil,
            timeout: 10)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "ok")
    }
}
